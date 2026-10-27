// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The official suite is the gate and it lives in the `gate/` module, which reads
// it off disk. What is here is what the suite does not cover: the shape of this
// library's own API — what `Schema::new` reads, what a fault says, and that the
// version a document names is the version it is read at.

///|
/// A schema from its JSON text, which is how a caller has one.
fn schema(
  text : String,
  draft? : @moonschema.Draft,
) -> @moonschema.Schema raise {
  @moonschema.Schema::new(@json.parse(text), draft?)
}

///|
test "an instance validates, or says why not" {
  let person = schema(
    (
      #|{ "type": "object",
      #|  "properties": { "name": { "type": "string", "minLength": 1 } },
      #|  "required": ["name"] }
    ),
  )
  assert_eq(person.valid(@json.parse("{\"name\": \"Leo\"}")), true)
  assert_eq(person.faults(@json.parse("{\"name\": \"Leo\"}")), [])
  // The basic output: where in the instance, which keyword, and where that was.
  let faults = person.faults(@json.parse("{\"name\": \"\"}"))
  assert_eq(faults.length(), 1)
  assert_eq(faults[0].at, "/name")
  assert_eq(faults[0].keyword, "minLength")
  assert_eq(faults[0].schema_at, "/properties/name/minLength")
  assert_eq(
    faults[0].to_string(),
    "/name: shorter than allowed (minLength at /properties/name/minLength)",
  )
  // A missing member is a fault of the object, not of the member.
  let missing = person.faults(@json.parse("{}"))
  assert_eq(missing[0].at, "")
  assert_eq(missing[0].keyword, "required")
}

///|
test "every reason is collected, not just the first" {
  let strict = schema(
    (
      #|{ "type": "object",
      #|  "properties": { "a": { "type": "integer" }, "b": { "type": "integer" } },
      #|  "required": ["c"] }
    ),
  )
  let faults = strict.faults(@json.parse("{\"a\": \"x\", \"b\": true}"))
  assert_eq(faults.length(), 3)
  // `valid` answers the same question and stops at the first reason.
  assert_eq(strict.valid(@json.parse("{\"a\": \"x\", \"b\": true}")), false)
}

///|
test "the version a document names is the version it is read at" {
  // `exclusiveMaximum` is a flag on `maximum` in draft-04 and a number after it.
  let old = schema(
    (
      #|{ "$schema": "http://json-schema.org/draft-04/schema#",
      #|  "maximum": 10, "exclusiveMaximum": true }
    ),
    draft=Draft2020,
  )
  assert_eq(old.valid(@json.parse("10")), false)
  assert_eq(old.valid(@json.parse("9")), true)
  // The same document read at 2020-12 means something else entirely: the flag
  // is not a number, so it asserts nothing and ten is allowed.
  let modern = schema(
    (
      #|{ "$schema": "https://json-schema.org/draft/2020-12/schema",
      #|  "maximum": 10, "exclusiveMaximum": true }
    ),
  )
  assert_eq(modern.valid(@json.parse("10")), true)
}

///|
test "a version nobody knows is refused, not guessed at" {
  let refused = try {
    schema("{ \"$schema\": \"https://example.test/schema\" }") |> ignore
    ""
  } catch {
    @moonschema.Unknown(uri) => uri
    _ => "wrong error"
  }
  assert_eq(refused, "https://example.test/schema")
}

///|
test "a reference reaches another document only when it is handed one" {
  let document = @json.parse("{ \"$ref\": \"https://example.test/int\" }")
  let alone = @moonschema.Schema::new(document)
  // Nothing was fed, so the reference resolves to nothing and refuses.
  assert_eq(alone.valid(@json.parse("1")), false)
  assert_eq(alone.faults(@json.parse("1"))[0].keyword, "$ref")
  let remotes = {
    "https://example.test/int": @json.parse("{ \"type\": \"integer\" }"),
  }
  let fed = @moonschema.Schema::new(document, remotes~)
  assert_eq(fed.valid(@json.parse("1")), true)
  assert_eq(fed.valid(@json.parse("\"x\"")), false)
}

///|
test "a boolean is a schema" {
  assert_eq(
    @moonschema.Schema::new(Json::boolean(true)).valid(Json::null()),
    true,
  )
  assert_eq(
    @moonschema.Schema::new(Json::boolean(false)).valid(Json::null()),
    false,
  )
}

///|
test "the shorthand classes a pattern is written with" {
  // ECMA-262 spells them `\d`, `\w` and `\s`; the engine underneath wants the
  // POSIX names, so a pattern is rewritten before it is read.
  let digits = schema("{ \"pattern\": \"^\\\\d+$\" }")
  assert_eq(digits.valid(Json::string("123")), true)
  assert_eq(digits.valid(Json::string("12a")), false)
  let word = schema("{ \"pattern\": \"^\\\\w+$\" }")
  assert_eq(word.valid(Json::string("a_1")), true)
  assert_eq(word.valid(Json::string("a-1")), false)
  let spaced = schema("{ \"pattern\": \"a\\\\sb\" }")
  assert_eq(spaced.valid(Json::string("a b")), true)
  assert_eq(spaced.valid(Json::string("ab")), false)
  // Negated, and inside a class beside other members.
  let mixed = schema("{ \"pattern\": \"^[\\\\d-]+$\" }")
  assert_eq(mixed.valid(Json::string("1-2")), true)
  let other = schema("{ \"pattern\": \"^\\\\D+$\" }")
  assert_eq(other.valid(Json::string("abc")), true)
  assert_eq(other.valid(Json::string("a1c")), false)
}

///|
test "a property escape is the category it names" {
  // The engine underneath has no Unicode properties, and its `[[:alpha:]]` is
  // ASCII, so the ranges of the category are carried here and spliced in.
  let letters = schema("{ \"pattern\": \"^\\\\p{Letter}+$\" }")
  assert_eq(letters.valid(Json::string("Hello")), true)
  assert_eq(letters.valid(Json::string("\u{03C0}")), true)
  assert_eq(letters.valid(Json::string("123")), false)
  // The short name, the long name and the `General_Category=` spelling are one.
  for name in ["Lu", "Uppercase_Letter", "General_Category=Lu"] {
    let upper = schema("{ \"pattern\": \"^\\\\p{" + name + "}+$\" }")
    assert_eq(upper.valid(Json::string("AB")), true)
    assert_eq(upper.valid(Json::string("ab")), false)
  }
  // Negated, and beside another member of a class.
  let other = schema("{ \"pattern\": \"^\\\\P{Letter}+$\" }")
  assert_eq(other.valid(Json::string("123")), true)
  assert_eq(other.valid(Json::string("abc")), false)
  let mixed = schema("{ \"pattern\": \"^[\\\\p{Nd}-]+$\" }")
  assert_eq(mixed.valid(Json::string("1-2")), true)
  assert_eq(mixed.valid(Json::string("a")), false)
}

///|
test "a property this does not know refuses rather than admits" {
  // A script is a property too, but not one of the categories carried here. The
  // pattern is left as it was written and the engine refuses it, which keeps a
  // schema's mistake from passing every instance.
  let script = schema("{ \"pattern\": \"^\\\\p{Script=Han}+$\" }")
  assert_eq(script.valid(Json::string("\u{6C49}")), false)
  assert_eq(script.valid(Json::string("abc")), false)
}
