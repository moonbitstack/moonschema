// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// A keyword this library has never heard of, defined outside it and put in force
// by the document's own metaschema. Run it with
// `moon run src/examples/vocabularies`.

///|
/// `x-units`: a number is a whole number of units, and the keyword says how many
/// decimal places a unit has — so `2` admits `1.25` and refuses `1.234`.
struct Units {}

///|
/// Ten to the power of a small non-negative integer.
fn scale_of(places : Double) -> Double {
  let mut scale = 1.0
  for _ in 0..<places.to_int() {
    scale = scale * 10.0
  }
  scale
}

///|
pub impl @moonschema.Keyword for Units with fn name(_self) {
  "x-units"
}

///|
pub impl @moonschema.Keyword for Units with fn judge(
  _self,
  value,
  instance,
  site,
) {
  ignore(site)
  match (value, instance) {
    (Number(places, ..), Number(number, ..)) => {
      let scaled = number * scale_of(places)
      // A binary float carries a little error: 1.234 is 1233.9999999999998 in
      // thousandths, and refusing that would be an artefact of the arithmetic.
      let nearest = scaled.round()
      let slack = if scaled.abs() > 1.0 { scaled.abs() } else { 1.0 }
      if (scaled - nearest).abs() <= 1.0e-9 * slack {
        Accept
      } else {
        Refuse(why="not a whole number of units")
      }
    }
    _ => Accept
  }
}

///|
pub extend Units with @moonschema.Keyword::{name, judge}

///|
/// The vocabulary that holds it.
struct Measures {}

///|
pub impl @moonschema.Vocabulary for Measures with fn uri(_self) {
  "https://example.test/vocab/measures"
}

///|
pub impl @moonschema.Vocabulary for Measures with fn keywords(_self) {
  let units : &@moonschema.Keyword = Units::{ }
  [units]
}

///|
pub extend Measures with @moonschema.Vocabulary::{uri, keywords}

///|
fn main raise {
  // A metaschema is a document like any other: this one says it is written
  // against 2020-12 and that it wants the measures vocabulary.
  let metaschema = @json.loads(
    (
      #|{ "$id": "https://example.test/meta",
      #|  "$schema": "https://json-schema.org/draft/2020-12/schema",
      #|  "$vocabulary": {
      #|    "https://json-schema.org/draft/2020-12/vocab/validation": true,
      #|    "https://example.test/vocab/measures": true } }
    ),
  )
  let remotes = { "https://example.test/meta": metaschema }
  let registry = @moonschema.Registry::new()
  registry.add(Measures::{ })

  let document = @json.loads(
    (
      #|{ "$schema": "https://example.test/meta",
      #|  "type": "number", "x-units": 2 }
    ),
  )
  let schema = @moonschema.Schema::new(document, remotes~, registry~)
  // Three places is a whole number of hundredths; 1.234 is not.
  for text in ["1.25", "1.234"] {
    let instance = @json.loads(text)
    println("\{text}  \{schema.valid(instance)}")
    for fault in schema.faults(instance) {
      println("  " + fault.to_string())
    }
  }

  // Without the vocabulary, the same document is one this cannot read: it asks
  // for something required and nobody holds it.
  let alone = try {
    @moonschema.Schema::new(document, remotes~) |> ignore
    "read"
  } catch {
    @moonschema.Broken(at~, why~) => at + ": " + why
    _ => "refused"
  }
  println("\nwithout the vocabulary: \{alone}")
}
