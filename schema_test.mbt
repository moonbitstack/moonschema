// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Every version names itself and reads back as itself.
test "a version round-trips through its URI" {
  for d in [@moonschema.Draft::Draft4, Draft6, Draft7, Draft2019, Draft2020] {
    assert_eq(@moonschema.Draft::of(d.uri()[:]), Some(d))
  }
}

///|
/// Both spellings are found in the wild, and a trailing `#` is optional. A
/// validator that only accepts the one the specification prints would refuse
/// half the documents written against it.
test "both spellings of a version URI are accepted" {
  let cases = [
    ("http://json-schema.org/draft-07/schema#", @moonschema.Draft::Draft7),
    ("http://json-schema.org/draft-07/schema", Draft7),
    ("https://json-schema.org/draft-07/schema#", Draft7),
    ("https://json-schema.org/draft-07/schema", Draft7),
    ("http://json-schema.org/draft-04/schema#", Draft4),
    ("https://json-schema.org/draft-04/schema", Draft4),
    ("https://json-schema.org/draft/2019-09/schema", Draft2019),
    ("http://json-schema.org/draft/2019-09/schema#", Draft2019),
    ("https://json-schema.org/draft/2020-12/schema", Draft2020),
    ("https://json-schema.org/draft/2020-12/schema#", Draft2020),
  ]
  for case in cases {
    let (uri, want) = case
    assert_eq(@moonschema.Draft::of(uri[:]), Some(want))
  }
}

///|
/// A URI this does not know is `None`, not a guess.
///
/// A document written against something else is not a document to read at a
/// version of our choosing — that is how a schema silently means something
/// other than what it says.
test "an unknown version is not guessed at" {
  for
    uri in [
      "https://example.test/schema", "http://json-schema.org/draft-03/schema#", "http://json-schema.org/draft-05/schema#",
      "https://json-schema.org/draft/2021-01/schema", "", "#", "json-schema.org",
    ] {
    assert_eq(@moonschema.Draft::of(uri[:]), None)
  }
}

///|
/// The presets, and where they come from.
test "the presets are the current release" {
  assert_eq(@moonschema.draft, @moonschema.Draft::Draft2020)
  assert_eq(
    @moonschema.draft.uri(),
    "https://json-schema.org/draft/2020-12/schema",
  )
  // `Flag` because the common case is a guard that wants a yes or a no.
  assert_eq(@moonschema.output, @moonschema.Output::Flag)
}

///|
/// The names are the specification's own, so a message about a document says
/// what the document says.
test "a version and an output format print as the specification names them" {
  assert_eq(@moonschema.Draft::Draft4.to_string(), "draft-04")
  assert_eq(@moonschema.Draft::Draft6.to_string(), "draft-06")
  assert_eq(@moonschema.Draft::Draft7.to_string(), "draft-07")
  assert_eq(@moonschema.Draft::Draft2019.to_string(), "2019-09")
  assert_eq(@moonschema.Draft::Draft2020.to_string(), "2020-12")
  assert_eq(@moonschema.Output::Flag.to_string(), "flag")
  assert_eq(@moonschema.Output::Basic.to_string(), "basic")
  assert_eq(@moonschema.Output::Detailed.to_string(), "detailed")
  assert_eq(@moonschema.Output::Verbose.to_string(), "verbose")
}
