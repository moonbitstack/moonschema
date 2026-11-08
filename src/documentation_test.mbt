// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// What the README and the skill say, run as it is written: the blocks those two
// show are compiled by `scripts/check_snippets.py`, and the values they claim are
// pinned here. A change to a message or to an output shape has to come with a
// change to the prose that promises it.

///|
/// A keyword and a vocabulary, so that the documented extension point is run
/// rather than described. Its own types, because a reader's copy of the example
/// is a copy: nothing here is exported, and the names are the example's alone.
struct EvenNumber {}

///|
pub impl @moonschema.Keyword for EvenNumber with fn name(_self) {
  "x-even"
}

///|
pub impl @moonschema.Keyword for EvenNumber with fn judge(
  _self,
  value,
  instance,
  site,
) {
  ignore(site)
  match (value, instance) {
    (True, Number(number, ..)) =>
      if number == (number / 2.0).floor() * 2.0 {
        Accept
      } else {
        Refuse(why="odd")
      }
    _ => Accept
  }
}

///|
pub extend EvenNumber with @moonschema.Keyword::{name, judge}

///|
struct EvenVocabulary {}

///|
pub impl @moonschema.Vocabulary for EvenVocabulary with fn uri(_self) {
  "https://example.test/vocab/even"
}

///|
pub impl @moonschema.Vocabulary for EvenVocabulary with fn keywords(_self) {
  let even : &@moonschema.Keyword = EvenNumber::{ }
  [even]
}

///|
pub extend EvenVocabulary with @moonschema.Vocabulary::{uri, keywords}

///|
test "the quick start says true and one fault" {
  let schema = @moonschema.Schema::new(
    @json.parse(
      (
        #|{ "type": "object",
        #|  "properties": { "port": { "type": "integer", "minimum": 1 } },
        #|  "required": ["port"] }
      ),
    ),
  )
  assert_eq(schema.valid(@json.parse("{\"port\": 8080}")), true)
  let faults = schema.faults(@json.parse("{\"port\": 0}"))
  assert_eq(faults.length(), 1)
  assert_eq(
    faults[0].to_string(),
    "/port: below the minimum (minimum at /properties/port/minimum)",
  )
}

///|
test "the basic format is the object the README prints" {
  let schema = @moonschema.Schema::new(@json.parse("{ \"type\": \"integer\" }"))
  let report = schema.report(
    @json.parse("\"seven\""),
    output=@moonschema.Output::Basic,
  )
  assert_eq(
    report.to_json().stringify(indent=2),
    "{\n  \"valid\": false,\n  \"errors\": [\n    {\n      \"valid\": false,\n      \"keywordLocation\": \"/type\",\n      \"instanceLocation\": \"\",\n      \"error\": \"not of type integer\"\n    }\n  ]\n}",
  )
}

///|
test "format is an annotation until it is asked to assert" {
  let lenient = @moonschema.Schema::new(@json.parse("{ \"format\": \"ipv4\" }"))
  assert_eq(lenient.valid(@json.parse("\"not-an-ipv4\"")), true)
  let strict = @moonschema.Schema::new(
    @json.parse("{ \"format\": \"ipv4\" }"),
    format=true,
  )
  assert_eq(strict.valid(@json.parse("\"not-an-ipv4\"")), false)
  assert_eq(strict.valid(@json.parse("\"10.0.0.1\"")), true)
}

///|
test "a reference resolves when its document is handed over" {
  let remote = @json.parse("{ \"$ref\": \"https://example.test/int\" }")
  let alone = @moonschema.Schema::new(remote)
  assert_eq(
    alone.faults(Json::number(1.0))[0].to_string(),
    "the instance: reference resolves to nothing ($ref at /$ref)",
  )
  let fed = @moonschema.Schema::new(remote, remotes={
    "https://example.test/int": @json.parse("{ \"type\": \"integer\" }"),
  })
  assert_eq(fed.valid(Json::number(1.0)), true)
}

///|
test "the reference resolves to nothing is a fault, not a pass" {
  let alone = @moonschema.Schema::new(
    @json.parse("{ \"$ref\": \"https://example.test/int\" }"),
  )
  assert_eq(
    alone.faults(Json::number(1.0))[0].to_string(),
    "the instance: reference resolves to nothing ($ref at /$ref)",
  )
}

///|
test "the keywords the guide prints name themselves" {
  // `dependentRequired` says which property is missing; the property that pulled
  // it in is part of the instance, not a step of the schema's path.
  let dependency = @moonschema.Schema::new(
    @json.parse(
      (
        #|{ "properties": { "id": { "type": "string" },
        #|    "rev": { "type": "string" } },
        #|  "dependentRequired": { "id": ["rev"] } }
      ),
    ),
  )
  assert_eq(
    dependency.faults(@json.parse("{\"id\": \"a\"}"))[0].to_string(),
    "the instance: missing rev (dependentRequired at /dependentRequired)",
  )
  let closed = @moonschema.Schema::new(
    @json.parse("{ \"unevaluatedProperties\": false }"),
  )
  assert_eq(
    closed.faults(@json.parse("{\"email\": \"a@b\"}"))[0].to_string(),
    "/email: no instance validates against false (unevaluatedProperties at /unevaluatedProperties)",
  )
}

///|
test "the documented keyword asserts once its vocabulary is in force" {
  let metaschema = @json.parse(
    (
      #|{ "$id": "https://example.test/meta",
      #|  "$schema": "https://json-schema.org/draft/2020-12/schema",
      #|  "$vocabulary": {
      #|    "https://json-schema.org/draft/2020-12/vocab/validation": true,
      #|    "https://example.test/vocab/even": true } }
    ),
  )
  let remotes = { "https://example.test/meta": metaschema }
  let registry = @moonschema.Registry::new()
  registry.add(EvenVocabulary::{ })
  let schema = @moonschema.Schema::new(
    @json.parse(
      (
        #|{ "$schema": "https://example.test/meta",
        #|  "type": "integer", "x-even": true }
      ),
    ),
    remotes~,
    registry~,
  )
  assert_eq(schema.valid(@json.parse("4")), true)
  assert_eq(
    schema.faults(@json.parse("5"))[0].to_string(),
    "the instance: odd (x-even at /x-even)",
  )
}
