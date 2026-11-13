// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The seam, used the way a caller outside this library would use it: a keyword,
// a vocabulary, and a metaschema that puts the two in force.

///|
/// A keyword that says an instance is even, when the keyword's value is `true`.
struct Even {}

///|
pub impl @moonschema.Keyword for Even with fn name(_self) {
  "x-even"
}

///|
pub impl @moonschema.Keyword for Even with fn judge(
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
pub extend Even with @moonschema.Keyword::{name, judge}

///|
/// A keyword that says nothing about validity and contributes its value, which
/// is what a vocabulary the metaschema marks `false` may still do.
struct Tagged {}

///|
pub impl @moonschema.Keyword for Tagged with fn name(_self) {
  "x-tagged"
}

///|
pub impl @moonschema.Keyword for Tagged with fn judge(
  _self,
  value,
  instance,
  site,
) {
  ignore(instance)
  ignore(site)
  Annotate(annotation=value)
}

///|
pub extend Tagged with @moonschema.Keyword::{name, judge}

///|
/// The vocabulary that holds them, under the URI a metaschema names.
struct Counting {}

///|
pub impl @moonschema.Vocabulary for Counting with fn uri(_self) {
  "https://example.test/vocab/counting"
}

///|
pub impl @moonschema.Vocabulary for Counting with fn keywords(_self) {
  let even : &@moonschema.Keyword = Even::{ }
  let tagged : &@moonschema.Keyword = Tagged::{ }
  [even, tagged]
}

///|
pub extend Counting with @moonschema.Vocabulary::{uri, keywords}

///|
/// A registry holding it.
fn counting() -> @moonschema.Registry raise {
  let registry = @moonschema.Registry::new()
  registry.add(Counting::{ })
  registry
}

///|
/// A metaschema that declares the vocabulary, with `wanted` beside it.
fn declaring(wanted : Bool) -> Json raise {
  let flag = if wanted { "true" } else { "false" }
  @json.loads(
    (
      #|{ "$id": "https://example.test/meta",
      #|  "$schema": "https://json-schema.org/draft/2020-12/schema",
      #|  "$vocabulary": {
      #|    "https://json-schema.org/draft/2020-12/vocab/validation": true,
      #|    "https://example.test/vocab/counting":
    ) +
    flag +
    "}}",
  )
}

///|
test "a keyword from a vocabulary in force asserts" {
  let remotes = { "https://example.test/meta": declaring(true) }
  let schema = @moonschema.Schema::new(
    @json.loads(
      (
        #|{ "$schema": "https://example.test/meta", "x-even": true }
      ),
    ),
    remotes~,
    registry=counting(),
  )
  assert_eq(schema.valid(@json.loads("4")), true)
  assert_eq(schema.valid(@json.loads("5")), false)
  let faults = schema.faults(@json.loads("5"))
  assert_eq(faults[0].keyword, "x-even")
  assert_eq(faults[0].message, "odd")
  // A reader with no such vocabulary reads the document only because the
  // metaschema calls the vocabulary optional; calling it required is what makes
  // the document one this cannot read.
  let optional = { "https://example.test/meta": declaring(false) }
  let plain = @moonschema.Schema::new(
    @json.loads(
      "{ \"$schema\": \"https://example.test/meta\", \"x-even\": true }",
    ),
    remotes=optional,
  )
  assert_eq(plain.valid(@json.loads("5")), true)
}

///|
test "a vocabulary declared optional annotates and asserts nothing" {
  let remotes = { "https://example.test/meta": declaring(false) }
  let schema = @moonschema.Schema::new(
    @json.loads(
      (
        #|{ "$schema": "https://example.test/meta", "x-even": true, "x-tagged": "here" }
      ),
    ),
    remotes~,
    registry=counting(),
  )
  assert_eq(schema.valid(@json.loads("5")), true)
  let report = schema.report(@json.loads("5"), output=@moonschema.Output::Basic)
  let tagged = report.units.search_by(fn(unit) {
    unit.keyword_at == "/x-tagged"
  })
  match tagged {
    Some(index) =>
      assert_eq(report.units[index].annotation, Some(Json::string("here")))
    None => fail("no annotation for the keyword")
  }
}

///|
test "a vocabulary the document requires and nobody holds is refused" {
  let document = @json.loads(
    (
      #|{ "$schema": "https://example.test/meta" }
    ),
  )
  let remotes = { "https://example.test/meta": declaring(true) }
  let refused = try {
    @moonschema.Schema::new(document, remotes~) |> ignore
    ""
  } catch {
    @moonschema.Broken(at~, why~) => at + ": " + why
    _ => "wrong error"
  }
  assert_eq(
    refused, ": no such vocabulary: https://example.test/vocab/counting",
  )
}

///|
test "a name a built-in keyword answers to cannot be taken" {
  let registry = @moonschema.Registry::new()
  let clash = try {
    registry.add(Rules::{ }) |> ignore
    ""
  } catch {
    @moonschema.Broken(at~, why~) => at + ": " + why
    _ => "wrong error"
  }
  assert_eq(clash, "minimum: a keyword of that name is already answered for")
}

///|
/// A vocabulary that tries to take `minimum`.
struct Rules {}

///|
pub impl @moonschema.Vocabulary for Rules with fn uri(_self) {
  "https://example.test/vocab/rules"
}

///|
pub impl @moonschema.Vocabulary for Rules with fn keywords(_self) {
  let minimum : &@moonschema.Keyword = Minimum::{ }
  [minimum]
}

///|
pub extend Rules with @moonschema.Vocabulary::{uri, keywords}

///|
/// The keyword that tries.
struct Minimum {}

///|
pub impl @moonschema.Keyword for Minimum with fn name(_self) {
  "minimum"
}

///|
pub impl @moonschema.Keyword for Minimum with fn judge(
  _self,
  value,
  instance,
  site,
) {
  ignore(value)
  ignore(instance)
  ignore(site)
  Accept
}

///|
pub extend Minimum with @moonschema.Keyword::{name, judge}
