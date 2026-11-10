// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// A fault's keyword is not a second opinion about which keyword refused an
// instance: it is read from the end of the path the fault reports. These tests
// hold every keyword to that, so the two cannot drift apart — the drift that once
// let a `dependentRequired` fault name the property it was about.

///|
/// The last step of a JSON Pointer, unescaped (RFC 6901).
///
/// Written here rather than taken from the package, so that the test compares two
/// readings of the same path instead of one reading with itself.
fn tail(pointer : String) -> String {
  let text = pointer[:]
  let mut start = 0
  for i = 0; i < text.length(); i = i + 1 {
    if text[i] == '/' {
      start = i + 1
    }
  }
  let raw = text[start:].to_owned()
  let mut out = ""
  let mut i = 0
  while i < raw.length() {
    if raw[i] == '~' && i + 1 < raw.length() {
      match raw[i + 1] {
        '0' => {
          out = out + "~"
          i = i + 2
        }
        '1' => {
          out = out + "/"
          i = i + 2
        }
        _ => {
          out = out + "~"
          i = i + 1
        }
      }
    } else {
      out = out + raw[i:i + 1].to_owned()
      i = i + 1
    }
  }
  out
}

///|
test "every keyword a fault can name is the end of its own path" {
  // One row per keyword the library asserts with: the schema, the instance that
  // breaks it, and the keyword the fault has to name. Where a keyword hands the
  // instance on — `allOf`, `properties` — the fault is the one underneath it.
  let rows : Array[(String, String, String)] = [
    ("{ \"type\": \"integer\" }", "\"x\"", "type"),
    ("{ \"type\": [\"integer\", \"null\"] }", "\"x\"", "type"),
    ("{ \"enum\": [1, 2] }", "3", "enum"),
    ("{ \"const\": 1 }", "2", "const"),
    ("{ \"multipleOf\": 2 }", "3", "multipleOf"),
    ("{ \"maximum\": 10 }", "11", "maximum"),
    ("{ \"minimum\": 10 }", "9", "minimum"),
    ("{ \"exclusiveMaximum\": 10 }", "10", "exclusiveMaximum"),
    ("{ \"exclusiveMinimum\": 10 }", "10", "exclusiveMinimum"),
    ("{ \"maxLength\": 2 }", "\"abc\"", "maxLength"),
    ("{ \"minLength\": 2 }", "\"a\"", "minLength"),
    ("{ \"pattern\": \"^a$\" }", "\"b\"", "pattern"),
    ("{ \"maxItems\": 1 }", "[1, 2]", "maxItems"),
    ("{ \"minItems\": 2 }", "[1]", "minItems"),
    ("{ \"uniqueItems\": true }", "[1, 1]", "uniqueItems"),
    ("{ \"contains\": { \"type\": \"integer\" } }", "[\"a\"]", "contains"),
    (
      "{ \"contains\": { \"type\": \"integer\" }, \"minContains\": 2 }", "[1]", "contains",
    ),
    (
      "{ \"contains\": { \"type\": \"integer\" }, \"maxContains\": 1 }", "[1, 2]",
      "contains",
    ),
    ("{ \"maxProperties\": 1 }", "{\"a\": 1, \"b\": 2}", "maxProperties"),
    ("{ \"minProperties\": 2 }", "{\"a\": 1}", "minProperties"),
    ("{ \"required\": [\"a\"] }", "{}", "required"),
    (
      "{ \"dependentRequired\": { \"a\": [\"b\"] } }", "{\"a\": 1}", "dependentRequired",
    ),
    (
      "{ \"dependentSchemas\": { \"a\": { \"required\": [\"b\"] } } }", "{\"a\": 1}",
      "required",
    ),
    (
      "{ \"properties\": { \"a\": { \"type\": \"integer\" } } }", "{\"a\": \"x\"}",
      "type",
    ),
    (
      "{ \"patternProperties\": { \"^x\": { \"type\": \"integer\" } } }", "{\"xa\": \"x\"}",
      "type",
    ),
    (
      "{ \"additionalProperties\": false }", "{\"a\": 1}", "additionalProperties",
    ),
    ("{ \"propertyNames\": { \"pattern\": \"^a$\" } }", "{\"b\": 1}", "pattern"),
    ("{ \"allOf\": [{ \"type\": \"integer\" }] }", "\"x\"", "type"),
    ("{ \"anyOf\": [{ \"type\": \"integer\" }] }", "\"x\"", "anyOf"),
    ("{ \"oneOf\": [{ \"type\": \"integer\" }] }", "\"x\"", "oneOf"),
    (
      "{ \"oneOf\": [{ \"type\": \"integer\" }, { \"type\": \"number\" }] }", "1",
      "oneOf",
    ),
    ("{ \"not\": { \"type\": \"integer\" } }", "1", "not"),
    (
      "{ \"if\": { \"type\": \"integer\" }, \"then\": { \"minimum\": 10 } }", "1",
      "minimum",
    ),
    (
      "{ \"if\": { \"type\": \"integer\" }, \"else\": { \"maxLength\": 1 } }", "\"abc\"",
      "maxLength",
    ),
    (
      "{ \"properties\": true, \"unevaluatedProperties\": false }", "{\"a\": 1}",
      "unevaluatedProperties",
    ),
    (
      "{ \"prefixItems\": true, \"unevaluatedItems\": false }", "[1]", "unevaluatedItems",
    ),
    ("{ \"$ref\": \"#/$defs/x\" }", "1", "$ref"),
    ("{ \"$dynamicRef\": \"#nope\" }", "1", "$dynamicRef"),
    ("false", "1", ""),
  ]
  for row in rows {
    let (text, instance, keyword) = row
    let faults = @moonschema.Schema::new(@json.parse(text)).faults(
      @json.parse(instance),
    )
    assert_eq(faults.length() > 0, true)
    for fault in faults {
      assert_eq(fault.keyword, tail(fault.schema_at))
    }
    assert_eq(faults[0].keyword, keyword)
  }
}

///|
test "the keyword a fault names is the end of the walk, not the end of a branch" {
  // The walk goes through `$ref` and through `properties`; the keyword that
  // refused the value is `minimum`, three steps after the route began.
  let schema = @moonschema.Schema::new(
    @json.parse(
      (
        #|{ "$defs": { "port": { "type": "integer", "minimum": 1 } },
        #|  "properties": { "port": { "$ref": "#/$defs/port" } } }
      ),
    ),
  )
  let faults = schema.faults(@json.parse("{\"port\": 0}"))
  assert_eq(faults.length(), 1)
  assert_eq(faults[0].keyword, "minimum")
  assert_eq(faults[0].schema_at, "/properties/port/$ref/minimum")
  assert_eq(faults[0].at, "/port")
}

///|
test "a property name with a pointer's punctuation is escaped in the path" {
  let schema = @moonschema.Schema::new(
    @json.parse(
      (
        #|{ "properties": {
        #|    "a/b": { "type": "integer" },
        #|    "m~n": { "required": ["x"] } } }
      ),
    ),
  )
  let slash = schema.faults(@json.parse("{\"a/b\": \"x\"}"))
  assert_eq(slash[0].keyword, "type")
  assert_eq(slash[0].schema_at, "/properties/a~1b/type")
  let tilde = schema.faults(@json.parse("{\"m~n\": {}}"))
  assert_eq(tilde[0].keyword, "required")
  assert_eq(tilde[0].schema_at, "/properties/m~0n/required")
}
