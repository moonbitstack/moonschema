// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The four output formats on one schema and one instance: the same walk, said
// four ways. Run it with `moon run src/examples/formats`.

///|
fn main raise {
  let schema = @moonschema.Schema::new(
    @json.parse(
      (
        #|{ "$id": "https://example.test/point",
        #|  "type": "object",
        #|  "properties": {
        #|    "x": { "type": "number", "format": "integer" },
        #|    "label": { "type": "string", "minLength": 2 } },
        #|  "required": ["x"] }
      ),
    ),
  )
  let instance = @json.parse("{ \"x\": 1.5, \"label\": \"a\" }")

  // `flag` is the boolean and nothing else, which is what a guard wants.
  let flag = schema.report(instance, output=@moonschema.Output::Flag)
  println("flag\n" + flag.to_json().stringify(indent=2))

  // `basic` is the same reasons as a flat list: one entry per keyword, each
  // with the place in the instance and the place in the schema.
  let basic = schema.report(instance, output=@moonschema.Output::Basic)
  println("\nbasic\n" + basic.to_json().stringify(indent=2))

  // `detailed` keeps the places several reasons share and drops the rest.
  let detailed = schema.report(instance, output=@moonschema.Output::Detailed)
  println("\ndetailed\n" + detailed.to_json().stringify(indent=2))

  // `verbose` keeps what passed as well, annotations included.
  let verbose = schema.report(instance, output=@moonschema.Output::Verbose)
  println("\nverbose\n" + verbose.to_json().stringify(indent=2))
}
