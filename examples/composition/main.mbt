// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// Schemas built out of other schemas: the applicators, the branches they
// choose, and the properties left over at the end. Run it with
// `moon run examples/composition`.

///|
fn main raise {
  // `allOf` applies every branch and reports every branch that refused, so a
  // value can fail twice for two different reasons.
  let summed = @moonschema.Schema::new(
    @json.parse(
      (
        #|{
        #|  "allOf": [
        #|    { "type": "integer" },
        #|    { "minimum": 1 },
        #|    { "maximum": 10 }
        #|  ]
        #|}
      ),
    ),
  )
  println("allOf — an integer from 1 to 10:")
  for instance in [Json::number(5.0), Json::number(0.0), Json::number(11.0)] {
    println("  \{instance.stringify()}  ->  \{summed.valid(instance)}")
    for fault in summed.faults(instance) {
      println("      " + fault.to_string())
    }
  }

  // `anyOf` passes when one branch does, and a branch that failed is not a
  // fault of the instance: only every branch failing is. So the answer is one
  // fault, not the reasons of each branch.
  let either = @moonschema.Schema::new(
    @json.parse(
      (
        #|{ "anyOf": [ { "type": "string" }, { "type": "integer" } ] }
      ),
    ),
  )
  println("\nanyOf — a string or an integer:")
  for instance in [Json::string("x"), Json::boolean(true)] {
    println("  \{instance.stringify()}  ->  \{either.valid(instance)}")
    for fault in either.faults(instance) {
      println("      " + fault.to_string())
    }
  }

  // `oneOf` wants exactly one branch. Two branches matching is its own fault,
  // and the message says how many did.
  let exactly = @moonschema.Schema::new(
    @json.parse(
      (
        #|{ "oneOf": [ { "type": "integer" }, { "minimum": 0 } ] }
      ),
    ),
  )
  println("\noneOf — an integer, or a number from 0 up:")
  for instance in [Json::number(-2.0), Json::number(3.0)] {
    println("  \{instance.stringify()}  ->  \{exactly.valid(instance)}")
    for fault in exactly.faults(instance) {
      println("      " + fault.to_string())
    }
  }

  // `if` never fails on its own: it picks the branch, and the reasons come from
  // whichever branch it picked.
  let shipping = @moonschema.Schema::new(
    @json.parse(
      (
        #|{
        #|  "type": "object",
        #|  "properties": { "country": { "type": "string" }, "postcode": { "type": "string" } },
        #|  "if": { "properties": { "country": { "const": "US" } } },
        #|  "then": { "properties": { "postcode": { "pattern": "^[0-9]{5}$" } } },
        #|  "else": { "properties": { "postcode": { "minLength": 3 } } }
        #|}
      ),
    ),
  )
  println(
    "\nif / then / else — a US postcode is five digits, any other is at least three characters:",
  )
  for
    text in [
      "{\"country\": \"US\", \"postcode\": \"94107\"}", "{\"country\": \"US\", \"postcode\": \"9410\"}",
      "{\"country\": \"NL\", \"postcode\": \"10\"}",
    ] {
    let instance = @json.parse(text)
    println("  \{text}")
    println("      -> \{shipping.valid(instance)}")
    for fault in shipping.faults(instance) {
      println("      " + fault.to_string())
    }
  }

  // `unevaluatedProperties` reads what every other keyword in the same schema
  // left untouched — including the branches of an `allOf`, which is what makes
  // it the way to close a composed object. Nothing evaluated `email`, so it is
  // the one that fails.
  let closed = @moonschema.Schema::new(
    @json.parse(
      (
        #|{
        #|  "allOf": [
        #|    { "properties": { "name": { "type": "string" } } },
        #|    { "properties": { "age": { "type": "integer", "minimum": 0 } } }
        #|  ],
        #|  "unevaluatedProperties": false
        #|}
      ),
    ),
  )
  println(
    "\nunevaluatedProperties — name and age are known, nothing else is:",
  )
  for
    text in [
      "{\"name\": \"Ada\", \"age\": 36}", "{\"name\": \"Ada\", \"email\": \"a@b.test\"}",
    ] {
    let instance = @json.parse(text)
    println("  \{text}  ->  \{closed.valid(instance)}")
    for fault in closed.faults(instance) {
      println("      " + fault.to_string())
    }
  }

  // `patternProperties` and `additionalProperties` divide the same object up:
  // a name one of the patterns matched belongs to it, and only the rest is
  // "additional".
  let headers = @moonschema.Schema::new(
    @json.parse(
      (
        #|{
        #|  "type": "object",
        #|  "patternProperties": { "^x-": { "type": "string" } },
        #|  "additionalProperties": { "type": "integer" }
        #|}
      ),
    ),
  )
  println("\npatternProperties then additionalProperties:")
  for
    text in [
      "{\"x-trace\": \"abc\", \"retries\": 3}", "{\"x-trace\": 1, \"retries\": \"three\"}",
    ] {
    let instance = @json.parse(text)
    println("  \{text}  ->  \{headers.valid(instance)}")
    for fault in headers.faults(instance) {
      println("      " + fault.to_string())
    }
  }
}
