// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The keywords whose work does not fit on one line: what they answer, and what
// the version they belong to does with them elsewhere.

///|
/// A schema from its JSON text, at a version of the caller's choosing.
fn at(text : String, draft~ : @moonschema.Draft) -> @moonschema.Schema raise {
  @moonschema.Schema::new(@json.parse(text), draft~)
}

///|
test "propertyDependencies picks the subschema by a property's value" {
  let document =
    #|{ "$defs": {
    #|    "card": { "required": ["cardNumber"] },
    #|    "bank": { "required": ["account"] } },
    #|  "propertyDependencies": {
    #|    "kind": {
    #|      "card": { "$ref": "#/$defs/card" },
    #|      "bank": { "$ref": "#/$defs/bank" } } } }
  let schema = at(document, draft=V1)
  assert_eq(
    schema.valid(@json.parse("{\"kind\": \"card\", \"cardNumber\": 1}")),
    true,
  )
  assert_eq(
    schema.valid(@json.parse("{\"kind\": \"card\", \"account\": 1}")),
    false,
  )
  assert_eq(
    schema.valid(@json.parse("{\"kind\": \"bank\", \"account\": 1}")),
    true,
  )
  assert_eq(
    schema.valid(@json.parse("{\"kind\": \"bank\", \"cardNumber\": 1}")),
    false,
  )
  // A value nobody depends on, and an instance without the property at all.
  assert_eq(schema.valid(@json.parse("{\"kind\": \"cash\"}")), true)
  assert_eq(schema.valid(@json.parse("{}")), true)
  // A value that is not a string is not a key into the inner object.
  assert_eq(schema.valid(@json.parse("{\"kind\": 1}")), true)
  let faults = schema.faults(
    @json.parse("{\"kind\": \"card\", \"account\": 1}"),
  )
  assert_eq(faults[0].keyword, "required")
  // The walk, not the target: it went through the keyword and through `$ref`.
  assert_eq(
    faults[0].schema_at,
    "/propertyDependencies/kind/card/$ref/required",
  )
}

///|
test "propertyDependencies is v1's alone" {
  let document =
    #|{ "propertyDependencies": { "kind": { "card": { "required": ["cardNumber"] } } } }
  for draft in [@moonschema.Draft::Draft2019, @moonschema.Draft::Draft2020] {
    let schema = at(document, draft~)
    assert_eq(schema.valid(@json.parse("{\"kind\": \"card\"}")), true)
  }
}

///|
test "propertyDependencies leaves what it evaluated to unevaluatedProperties" {
  let schema = at(
    (
      #|{ "properties": { "kind": true },
      #|  "propertyDependencies": { "kind": { "card": { "properties": { "number": { "type": "integer" } } } } },
      #|  "unevaluatedProperties": false }
    ),
    draft=V1,
  )
  assert_eq(
    schema.valid(@json.parse("{\"kind\": \"card\", \"number\": 1}")),
    true,
  )
  assert_eq(
    schema.valid(@json.parse("{\"kind\": \"card\", \"extra\": 1}")),
    false,
  )
}
