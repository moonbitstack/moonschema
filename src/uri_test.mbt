// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// RFC 3986 §5 is a table of eleven cases, and a validator that gets one of them
// wrong resolves a reference to a document nobody named. These are the shapes a
// schema actually writes, each reached through `$ref` so that the answer is the
// one a caller sees.

///|
test "a relative reference is merged onto the base's directory" {
  // `c.json` beside `b.json` is `.../dir/c.json`, not `.../c.json`.
  let references = @json.loads(
    (
      #|{ "$id": "http://example.test/dir/root.json",
      #|  "$ref": "other.json" }
    ),
  )
  let remotes = {
    "http://example.test/dir/other.json": @json.loads(
      "{ \"type\": \"integer\" }",
    ),
  }
  let schema = @moonschema.Schema::new(references, remotes~)
  assert_eq(schema.valid(@json.loads("1")), true)
  assert_eq(schema.valid(@json.loads("\"x\"")), false)
}

///|
test "dot segments are taken out before the reference is looked up" {
  let references = @json.loads(
    (
      #|{ "$id": "http://example.test/dir/root.json",
      #|  "$ref": "../lib/int.json" }
    ),
  )
  let remotes = {
    "http://example.test/lib/int.json": @json.loads("{ \"type\": \"integer\" }"),
  }
  let schema = @moonschema.Schema::new(references, remotes~)
  assert_eq(schema.valid(@json.loads("1")), true)
  assert_eq(schema.valid(@json.loads("\"x\"")), false)
}

///|
test "a network-path reference takes the base's scheme" {
  let references = @json.loads(
    (
      #|{ "$id": "https://a.test/dir/root.json",
      #|  "$ref": "//b.test/int.json" }
    ),
  )
  let remotes = {
    "https://b.test/int.json": @json.loads("{ \"type\": \"integer\" }"),
  }
  let schema = @moonschema.Schema::new(references, remotes~)
  assert_eq(schema.valid(@json.loads("1")), true)
}

///|
test "an absolute reference stands on its own" {
  let references = @json.loads(
    (
      #|{ "$id": "https://a.test/dir/root.json",
      #|  "$ref": "http://b.test/int.json" }
    ),
  )
  let remotes = {
    "http://b.test/int.json": @json.loads("{ \"type\": \"integer\" }"),
  }
  let schema = @moonschema.Schema::new(references, remotes~)
  assert_eq(schema.valid(@json.loads("1")), true)
}

///|
test "a fragment resolves inside the document it is in" {
  let schema = @moonschema.Schema::new(
    @json.loads(
      (
        #|{ "$id": "http://example.test/root.json",
        #|  "$defs": { "int": { "type": "integer" } },
        #|  "$ref": "#/$defs/int" }
      ),
    ),
  )
  assert_eq(schema.valid(@json.loads("1")), true)
  assert_eq(schema.valid(@json.loads("\"x\"")), false)
}

///|
test "a fragment with its slash percent-encoded is still a pointer" {
  let schema = @moonschema.Schema::new(
    @json.loads(
      (
        #|{ "properties": { "a name": { "type": "integer" } },
        #|  "$ref": "#/properties/a%20name" }
      ),
    ),
  )
  assert_eq(schema.valid(@json.loads("1")), true)
  assert_eq(schema.valid(@json.loads("\"x\"")), false)
}

///|
test "an anchor names a place without a pointer" {
  let schema = @moonschema.Schema::new(
    @json.loads(
      (
        #|{ "$defs": { "int": { "$anchor": "count", "type": "integer" } },
        #|  "$ref": "#count" }
      ),
    ),
  )
  assert_eq(schema.valid(@json.loads("1")), true)
  assert_eq(schema.valid(@json.loads("\"x\"")), false)
}

///|
test "a pointer's escapes are undone in the order that keeps a name whole" {
  // `~1` is a slash in a name and `~0` a tilde; undoing them the other way
  // round turns one name into two.
  let schema = @moonschema.Schema::new(
    @json.loads(
      (
        #|{ "properties": { "a/b": { "type": "integer" }, "c~d": { "type": "integer" } },
        #|  "allOf": [
        #|    { "$ref": "#/properties/a~1b" },
        #|    { "$ref": "#/properties/c~0d" }
        #|  ] }
      ),
    ),
  )
  assert_eq(schema.valid(@json.loads("1")), true)
  assert_eq(schema.valid(@json.loads("\"x\"")), false)
}
