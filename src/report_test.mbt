// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The four output formats, read against the examples §12.4 works out in full:
// the polygon schema for `flag`, `basic` and `detailed`, and the smaller one for
// `verbose`. What the specification leaves to the implementation is the wording
// of an error, so that is the one thing these do not pin.

///|
/// The schema and instance §12.4 uses for the first three formats.
fn polygon() -> (@moonschema.Schema, Json) raise {
  let schema = @moonschema.Schema::new(
    @json.parse(
      (
        #|{ "$id": "https://example.com/polygon",
        #|  "$schema": "https://json-schema.org/draft/2020-12/schema",
        #|  "$defs": {
        #|    "point": {
        #|      "type": "object",
        #|      "properties": {
        #|        "x": { "type": "number" },
        #|        "y": { "type": "number" } },
        #|      "additionalProperties": false,
        #|      "required": [ "x", "y" ] } },
        #|  "type": "array",
        #|  "items": { "$ref": "#/$defs/point" },
        #|  "minItems": 3 }
      ),
    ),
  )
  let instance = @json.parse(
    (
      #|[ { "x": 2.5, "y": 1.3 },
      #|  { "x": 1, "z": 6.7 } ]
    ),
  )
  (schema, instance)
}

///|
/// One report as JSON text, with the keys in a fixed order so that a test can
/// read it.
fn text(report : @moonschema.Report) -> String {
  report.to_json().stringify(indent=2)
}

///|
/// The unit at `path`, which is how a test names one result among several.
fn find(
  units : Array[@moonschema.OutputUnit],
  path : String,
) -> @moonschema.OutputUnit? {
  let found = units.search_by(fn(unit) { unit.keyword_at == path })
  match found {
    Some(index) => Some(units[index])
    None => None
  }
}

///|
test "flag says whether it validated and nothing else" {
  let (schema, instance) = polygon()
  assert_eq(
    text(schema.report(instance, output=@moonschema.Output::Flag)),
    "{\n  \"valid\": false\n}",
  )
  let passing = schema.report(
    @json.parse("[]"),
    output=@moonschema.Output::Flag,
  )
  assert_eq(text(passing), "{\n  \"valid\": false\n}")
}

///|
test "basic is a flat list, and the schema location is dereferenced" {
  let (schema, instance) = polygon()
  let report = schema.report(instance, output=@moonschema.Output::Basic)
  assert_false(report.valid)
  // Flat: no unit carries a nested result.
  for unit in report.units {
    assert_eq(unit.children.length(), 0)
  }
  // The `$ref` is in the evaluation path and not in the schema location, which
  // is the whole difference between the two pointers.
  match find(report.units, "/items/$ref/required") {
    Some(unit) => {
      assert_eq(unit.at, "/1")
      assert_eq(
        unit.absolute_at,
        Some("https://example.com/polygon#/$defs/point/required"),
      )
      assert_eq(unit.error, Some("missing y"))
    }
    None => fail("no unit for the missing property")
  }
  // A branch says only that something under it failed.
  match find(report.units, "/items/$ref") {
    Some(unit) => assert_eq(unit.error, Some("a subschema had errors"))
    None => fail("no unit for the reference")
  }
}

///|
test "detailed keeps the places several reasons share, and nothing else" {
  let (schema, instance) = polygon()
  let report = schema.report(instance, output=@moonschema.Output::Detailed)
  assert_eq(
    text(report),
    (
      #|{
      #|  "valid": false,
      #|  "errors": [
      #|    {
      #|      "valid": false,
      #|      "keywordLocation": "/items/$ref",
      #|      "absoluteKeywordLocation": "https://example.com/polygon#/$defs/point",
      #|      "instanceLocation": "/1",
      #|      "error": "a subschema had errors",
      #|      "errors": [
      #|        {
      #|          "valid": false,
      #|          "keywordLocation": "/items/$ref/additionalProperties",
      #|          "absoluteKeywordLocation": "https://example.com/polygon#/$defs/point/additionalProperties",
      #|          "instanceLocation": "/1/z",
      #|          "error": "no instance validates against false"
      #|        },
      #|        {
      #|          "valid": false,
      #|          "keywordLocation": "/items/$ref/required",
      #|          "absoluteKeywordLocation": "https://example.com/polygon#/$defs/point/required",
      #|          "instanceLocation": "/1",
      #|          "error": "missing y"
      #|        }
      #|      ]
      #|    },
      #|    {
      #|      "valid": false,
      #|      "keywordLocation": "/minItems",
      #|      "absoluteKeywordLocation": "https://example.com/polygon#/minItems",
      #|      "instanceLocation": "",
      #|      "error": "fewer items than allowed"
      #|    }
      #|  ]
      #|}
    ),
  )
}

///|
test "verbose keeps what passed as well as what failed" {
  // §12.4.4's smaller example: a schema with no `$id`, so there is no location
  // to dereference and none is given.
  let schema = @moonschema.Schema::new(
    @json.parse(
      (
        #|{ "type": "object",
        #|  "properties": { "validProp": true },
        #|  "additionalProperties": false }
      ),
    ),
  )
  let report = schema.report(
    @json.parse("{ \"validProp\": 5, \"disallowedProp\": \"value\" }"),
    output=@moonschema.Output::Verbose,
  )
  assert_eq(
    text(report),
    (
      #|{
      #|  "valid": false,
      #|  "errors": [
      #|    {
      #|      "valid": false,
      #|      "keywordLocation": "/additionalProperties",
      #|      "instanceLocation": "",
      #|      "errors": [
      #|        {
      #|          "valid": false,
      #|          "keywordLocation": "/additionalProperties",
      #|          "instanceLocation": "/disallowedProp",
      #|          "error": "no instance validates against false"
      #|        }
      #|      ]
      #|    },
      #|    {
      #|      "valid": true,
      #|      "keywordLocation": "/properties",
      #|      "instanceLocation": ""
      #|    },
      #|    {
      #|      "valid": true,
      #|      "keywordLocation": "/type",
      #|      "instanceLocation": ""
      #|    }
      #|  ]
      #|}
    ),
  )
}

///|
test "a validation that held reports its annotations" {
  let schema = @moonschema.Schema::new(@json.parse("{ \"readOnly\": true }"))
  let report = schema.report(@json.parse("1"), output=@moonschema.Output::Basic)
  assert_eq(
    text(report),
    (
      #|{
      #|  "valid": true,
      #|  "annotations": [
      #|    {
      #|      "valid": true,
      #|      "keywordLocation": "/readOnly",
      #|      "instanceLocation": "",
      #|      "annotation": true
      #|    }
      #|  ]
      #|}
    ),
  )
}

///|
test "the flag output is the cheapest, and says the same thing" {
  let schema = @moonschema.Schema::new(
    @json.parse("{ \"type\": \"integer\", \"minimum\": 1 }"),
  )
  assert_eq(schema.report(@json.parse("7")).valid, true)
  assert_eq(schema.report(@json.parse("0")).valid, false)
  assert_eq(schema.report(@json.parse("0")).units.length(), 0)
  assert_eq(@moonschema.output, @moonschema.Output::Flag)
}
