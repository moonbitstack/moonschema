// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// `format`: when it asserts, and what each name it knows answers. The suite is
// the gate for the names; what is here is the switch, which the suite only
// exercises from the other side of a metaschema.

///|
fn reads(
  text : String,
  draft? : @moonschema.Draft,
  format? : Bool,
) -> @moonschema.Schema raise {
  @moonschema.Schema::new(@json.parse(text), draft?, format?)
}

///|
test "an annotation says nothing about validity unless it is asked to" {
  let document = "{ \"format\": \"ipv4\" }"
  let quiet = reads(document)
  assert_eq(quiet.valid(@json.parse("\"not-an-ipv4\"")), true)
  let loud = reads(document, format=true)
  assert_eq(loud.valid(@json.parse("\"not-an-ipv4\"")), false)
  assert_eq(loud.valid(@json.parse("\"127.0.0.1\"")), true)
  let faults = loud.faults(@json.parse("\"not-an-ipv4\""))
  assert_eq(faults[0].keyword, "format")
  assert_eq(faults[0].message, "not a valid ipv4")
}

///|
test "a metaschema that declares the assertion vocabulary turns it on" {
  let metaschema = @json.parse(
    (
      #|{ "$id": "https://example.test/meta",
      #|  "$schema": "https://json-schema.org/draft/2020-12/schema",
      #|  "$vocabulary": {
      #|    "https://json-schema.org/draft/2020-12/vocab/core": true,
      #|    "https://json-schema.org/draft/2020-12/vocab/format-assertion": true } }
    ),
  )
  let remotes = { "https://example.test/meta": metaschema }
  let asserting = @moonschema.Schema::new(
    @json.parse(
      (
        #|{ "$schema": "https://example.test/meta", "format": "ipv4" }
      ),
    ),
    remotes~,
  )
  assert_eq(asserting.valid(@json.parse("\"not-an-ipv4\"")), false)
  // The caller can still turn it off: what a call says outranks what a dialect
  // says, which outranks what the version says.
  let off = @moonschema.Schema::new(
    @json.parse(
      (
        #|{ "$schema": "https://example.test/meta", "format": "ipv4" }
      ),
    ),
    remotes~,
    format=false,
  )
  assert_eq(off.valid(@json.parse("\"not-an-ipv4\"")), true)
}

///|
test "v1 asserts without being asked, and refuses a format it cannot read" {
  let schema = reads(
    (
      #|{ "$schema": "https://json-schema.org/v1", "format": "ipv4" }
    ),
  )
  assert_eq(schema.valid(@json.parse("\"not-an-ipv4\"")), false)
  // The specification makes an unsupported format a schema not to process at
  // all, rather than a keyword to pass over.
  let refused = try {
    reads(
      (
        #|{ "$schema": "https://json-schema.org/v1", "format": "x-made-up" }
      ),
    )
    |> ignore
    ""
  } catch {
    @moonschema.Broken(at~, why~) => at + ": " + why
    _ => "wrong error"
  }
  assert_eq(refused, "/format: no such format: x-made-up")
  // An earlier version passes over it: there, `format` is an annotation, and an
  // annotation nobody understands annotates nothing.
  let older = reads(
    "{ \"format\": \"x-made-up\" }",
    draft=@moonschema.Draft::Draft2020,
    format=true,
  )
  assert_eq(older.valid(@json.parse("\"anything\"")), true)
}

///|
test "a time is not a leap second where a time has no date to say which" {
  // RFC 9557, which v1 reads `time` against, dropped the leap second from a
  // bare time; `date-time` still has a date to place it.
  let v1 = @moonschema.Draft::V1
  assert_eq(
    reads("{ \"format\": \"time\" }", draft=v1).valid(
      @json.parse("\"23:59:60Z\""),
    ),
    false,
  )
  assert_eq(
    reads("{ \"format\": \"date-time\" }", draft=v1).valid(
      @json.parse("\"1998-12-31T23:59:60Z\""),
    ),
    true,
  )
  assert_eq(
    reads("{ \"format\": \"time\" }", draft=@moonschema.Draft::Draft2020).valid(
      @json.parse("\"23:59:60Z\""),
    ),
    true,
  )
}

///|
test "each name answers the shape it names" {
  let cases : Array[(String, String, Bool)] = [
    // (format, instance, valid)
    ("date", "\"2020-02-29\"", true),
    ("date", "\"2021-02-29\"", false),
    ("time", "\"08:30:06+00:20\"", true),
    ("time", "\"12:00:00\"", false),
    ("date-time", "\"1963-06-19t08:30:06.283185z\"", true),
    ("duration", "\"P1Y2M3DT4H5M6S\"", true),
    ("duration", "\"P1Y2D\"", false),
    ("email", "\"joe.bloggs@example.com\"", true),
    ("email", "\"te..st@example.com\"", false),
    ("hostname", "\"host-name.example.com\"", true),
    ("hostname", "\"-hostname\"", false),
    ("idn-hostname", "\"실례.테스트\"", true),
    ("ipv4", "\"192.168.0.1\"", true),
    ("ipv4", "\"192.168.0.256\"", false),
    ("ipv6", "\"2001:db8::1\"", true),
    ("ipv6", "\"1::2::3\"", false),
    ("uri", "\"urn:oasis:names:specification:docbook:dtd:xml:4.1.2\"", true),
    ("uri", "\"/abc\"", false),
    ("uri-reference", "\"/abc\"", true),
    ("uuid", "\"2EB8AA08-AA98-11EA-B4AA-73B441D16380\"", true),
    ("uuid", "\"{2eb8aa08-aa98-11ea-b4aa-73b441d16380}\"", false),
    ("json-pointer", "\"/foo/bar~0/baz~1/%a\"", true),
    ("json-pointer", "\"/foo/bar~\"", false),
    ("relative-json-pointer", "\"2/0/baz/1/zip\"", true),
    ("relative-json-pointer", "\"01/a\"", false),
    ("regex", "\"([abc])+\\\\s+$\"", true),
    ("regex", "\"^(abc]\"", false),
    ("uri-template", "\"{+var}/a'b\"", true),
    ("uri-template", "\"{v:01}\"", false),
  ]
  for case in cases {
    let (name, instance, want) = case
    let schema = reads(
      "{ \"format\": \"" + name + "\" }",
      draft=@moonschema.Draft::Draft2020,
      format=true,
    )
    let got = schema.valid(@json.parse(instance))
    if got != want {
      fail("format " + name + " read " + instance + " as " + got.to_string())
    }
  }
}

///|
test "a format answers about strings and nothing else" {
  // §7.2.1: a format applies to the instance types it names, and every format
  // here names strings, so every other type passes.
  let schema = reads("{ \"format\": \"ipv4\" }", format=true)
  for instance in ["12", "13.7", "{}", "[]", "false", "null"] {
    assert_eq(schema.valid(@json.parse(instance)), true)
  }
}
