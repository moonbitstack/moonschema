// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
fn main {
  // A document says which version it is written against, and it is read at the
  // version it says — whatever the preset is.
  for
    uri in [
      "http://json-schema.org/draft-04/schema#", "http://json-schema.org/draft-06/schema#",
      "http://json-schema.org/draft-07/schema#", "https://json-schema.org/draft/2019-09/schema",
      "https://json-schema.org/draft/2020-12/schema", "https://example.test/schema",
    ] {
    let named = match @moonschema.Draft::of(uri[:]) {
      Some(d) => d.to_string()
      None => "not a version this knows"
    }
    println("\{uri}  ->  \{named}")
  }

  // Every version names itself, and reads back as itself.
  for d in [@moonschema.Draft::Draft4, Draft6, Draft7, Draft2019, Draft2020] {
    let back = @moonschema.Draft::of(d.uri()[:])
    println("\{d} -> \{d.uri()} -> \{back is Some(_)}")
  }

  // A document that names none is read at the preset: the current release, and
  // the one OpenAPI 3.1 is defined against.
  println("preset version: \{@moonschema.draft}")
  println("preset output:  \{@moonschema.output}")
}
