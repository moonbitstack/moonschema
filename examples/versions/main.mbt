// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// One document, five readings: the places where the versions actually differ.
// Run it with `moon run examples/versions`.

///|
fn main raise {
  // `exclusiveMaximum` was a boolean beside `maximum` through draft-04, and a
  // number of its own from draft-06. A document holding the flag means "ten is
  // out of bounds" at draft-04, and at every later version the flag is not a
  // number, asserts nothing, and ten is allowed.
  let flag = @json.parse("{ \"maximum\": 10, \"exclusiveMaximum\": true }")
  println("maximum 10, exclusiveMaximum true — is ten allowed?")
  for draft in [@moonschema.Draft::Draft4, Draft6, Draft7, Draft2019, Draft2020] {
    let schema = @moonschema.Schema::new(flag, draft~)
    println("  \{draft}  \{schema.valid(Json::number(10.0))}")
  }

  // A list of schemas for the leading items was `items` before 2020-12, and is
  // `prefixItems` after it. Read at the other version the keyword is not one
  // that version has, so it asserts nothing — and the item goes unchecked.
  // This is why a document should say which version wrote it.
  let spellings = [
    ("items      ", "{\"items\": [{\"type\": \"string\"}]}"),
    ("prefixItems", "{\"prefixItems\": [{\"type\": \"string\"}]}"),
  ]
  println("\nthe first item should be a string; here it is 2:")
  for pair in spellings {
    let (label, text) = pair
    for draft in [@moonschema.Draft::Draft2019, Draft2020] {
      let schema = @moonschema.Schema::new(@json.parse(text), draft~)
      println(
        "  \{label} at \{draft}:  [2] is \{schema.valid(@json.parse("[2]"))}",
      )
    }
  }

  // `dependencies` was split in 2019-09 into `dependentRequired` for the names
  // and `dependentSchemas` for the schemas. A document that writes the new pair
  // is a document from 2019-09 or later; at draft-07 both names are unknown.
  let needs = @json.parse("{ \"dependentRequired\": { \"a\": [\"b\"] } }")
  println("\ndependentRequired — a needs b — for the instance {\"a\": 1}:")
  for draft in [@moonschema.Draft::Draft7, Draft2019, Draft2020] {
    let schema = @moonschema.Schema::new(needs, draft~)
    println("  \{draft}  \{schema.valid(@json.parse("{\"a\": 1}"))}")
  }

  // A document that names a version is read at the version it names, whatever
  // the `draft` argument says: the document is the more specific of the two.
  let named = @json.parse(
    (
      #|{ "$schema": "http://json-schema.org/draft-04/schema#",
      #|  "maximum": 10, "exclusiveMaximum": true }
    ),
  )
  let strict = @moonschema.Schema::new(
    named,
    draft=@moonschema.Draft::Draft2020,
  )
  println(
    "\nnamed draft-04, asked for 2020-12 — ten is \{strict.valid(Json::number(10.0))}",
  )
}
