// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The keywords whose work does not fit on one line: what they answer, and what
// the version they belong to does with them elsewhere.

///|
/// A schema from its JSON text, at a version of the caller's choosing.
fn at(text : String, draft~ : @moonschema.Draft) -> @moonschema.Schema raise {
  @moonschema.Schema::new(@json.loads(text), draft~)
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
    schema.valid(@json.loads("{\"kind\": \"card\", \"cardNumber\": 1}")),
    true,
  )
  assert_eq(
    schema.valid(@json.loads("{\"kind\": \"card\", \"account\": 1}")),
    false,
  )
  assert_eq(
    schema.valid(@json.loads("{\"kind\": \"bank\", \"account\": 1}")),
    true,
  )
  assert_eq(
    schema.valid(@json.loads("{\"kind\": \"bank\", \"cardNumber\": 1}")),
    false,
  )
  // A value nobody depends on, and an instance without the property at all.
  assert_eq(schema.valid(@json.loads("{\"kind\": \"cash\"}")), true)
  assert_eq(schema.valid(@json.loads("{}")), true)
  // A value that is not a string is not a key into the inner object.
  assert_eq(schema.valid(@json.loads("{\"kind\": 1}")), true)
  let faults = schema.faults(
    @json.loads("{\"kind\": \"card\", \"account\": 1}"),
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
    assert_eq(schema.valid(@json.loads("{\"kind\": \"card\"}")), true)
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
    schema.valid(@json.loads("{\"kind\": \"card\", \"number\": 1}")),
    true,
  )
  assert_eq(
    schema.valid(@json.loads("{\"kind\": \"card\", \"extra\": 1}")),
    false,
  )
}

///|
test "a decimal multiple stays a multiple when binary division says otherwise" {
  // `0.3 / 0.1` is `2.9999999999999996` in binary floating point, and both Ajv
  // and python-jsonschema refuse this instance because of it. The specification's
  // own suite requires `0.0075` to be a multiple of `0.0001`, which can only hold
  // if the division is read as the decimal one the document wrote, so the
  // remainder the representation leaves behind is allowed for here.
  let tenth = at("{ \"multipleOf\": 0.1 }", draft=@moonschema.Draft::Draft2020)
  assert_eq(tenth.valid(@json.loads("0.3")), true)
  assert_eq(tenth.valid(@json.loads("0.35")), false)
  let small = at(
    "{ \"multipleOf\": 0.0001 }",
    draft=@moonschema.Draft::Draft2020,
  )
  assert_eq(small.valid(@json.loads("0.0075")), true)
}

///|
test "contains is not a keyword in draft-04" {
  let text = "{\"contains\": {\"const\": 1}}"
  assert_eq(at(text, draft=Draft4).valid(@json.loads("[2]")), true)
  // draft-06 brought it in.
  assert_eq(at(text, draft=Draft6).valid(@json.loads("[2]")), false)
}

///|
test "minContains and maxContains are not keywords before 2019-09" {
  let text = "{\"contains\": {\"const\": 1}, \"minContains\": 2, \"maxContains\": 2}"
  // draft-07 reads `contains` alone: one match is enough, and three are not too many.
  assert_eq(at(text, draft=Draft7).valid(@json.loads("[1]")), true)
  assert_eq(at(text, draft=Draft7).valid(@json.loads("[1, 1, 1]")), true)
  assert_eq(at(text, draft=Draft2019).valid(@json.loads("[1]")), false)
  assert_eq(at(text, draft=Draft2019).valid(@json.loads("[1, 1, 1]")), false)
}

///|
test "dependencies is not a keyword from 2019-09" {
  let text = "{\"dependencies\": {\"a\": [\"b\"]}}"
  assert_eq(at(text, draft=Draft7).valid(@json.loads("{\"a\": 1}")), false)
  // 2019-09 split it into `dependentRequired` and `dependentSchemas`.
  assert_eq(at(text, draft=Draft2019).valid(@json.loads("{\"a\": 1}")), true)
  assert_eq(at(text, draft=Draft2020).valid(@json.loads("{\"a\": 1}")), true)
}
