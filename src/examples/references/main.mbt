// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// References: how one document reaches another part of itself, and how it
// reaches a document that is not itself. Run it with
// `moon run examples/references`.

///|
fn main raise {
  // A `$defs` entry and a `$ref` to it. The fault names the place in the
  // instance and the place in the schema, so a message can point at both.
  let order = @moonschema.Schema::new(
    @json.parse(
      (
        #|{
        #|  "$defs": { "port": { "type": "integer", "minimum": 1, "maximum": 65535 } },
        #|  "type": "object",
        #|  "properties": { "port": { "$ref": "#/$defs/port" } },
        #|  "required": ["port"]
        #|}
      ),
    ),
  )
  for
    instance in [
      @json.parse("{\"port\": 8080}"),
      @json.parse("{\"port\": 70000}"),
    ] {
    println("\{instance.stringify()}  ->  \{order.valid(instance)}")
    for fault in order.faults(instance) {
      println("    " + fault.to_string())
    }
  }

  // `$id` gives a subschema a URI of its own, and a reference inside it
  // resolves against that URI rather than against the document's. "money" is a
  // relative name, so it lands at https://example.test/money — beside the
  // document, not inside it.
  let nested = @moonschema.Schema::new(
    @json.parse(
      (
        #|{
        #|  "$id": "https://example.test/order",
        #|  "$defs": {
        #|    "money": {
        #|      "$id": "money",
        #|      "type": "object",
        #|      "properties": { "cents": { "type": "integer" } },
        #|      "required": ["cents"]
        #|    }
        #|  },
        #|  "type": "object",
        #|  "properties": { "total": { "$ref": "money" } }
        #|}
      ),
    ),
  )
  println("\nnested resource:")
  for
    text in [
      "{\"total\": {\"cents\": 1250}}", "{\"total\": {\"cents\": \"12.50\"}}",
    ] {
    let instance = @json.parse(text)
    println("  \{text}  ->  \{nested.valid(instance)}")
    for fault in nested.faults(instance) {
      println("      " + fault.to_string())
    }
  }

  // An `$anchor` names a place inside a document by a plain word, which is
  // what a reference written by hand usually wants.
  let anchored = @moonschema.Schema::new(
    @json.parse(
      (
        #|{
        #|  "$id": "https://example.test/customer",
        #|  "$defs": { "name": { "$anchor": "name", "type": "string", "minLength": 1 } },
        #|  "properties": { "name": { "$ref": "#name" } }
        #|}
      ),
    ),
  )
  println("\nanchor:")
  for text in ["{\"name\": \"Ada\"}", "{\"name\": \"\"}"] {
    let instance = @json.parse(text)
    println("  \{text}  ->  \{anchored.valid(instance)}")
    for fault in anchored.faults(instance) {
      println("      " + fault.to_string())
    }
  }

  // A reference to a document outside this one resolves only when the caller
  // hands that document over: this opens no sockets, so what is not fed to it
  // does not exist. Nothing is fetched, and a reference that lands nowhere is a
  // fault rather than a silent pass.
  let remote = @json.parse("{ \"$ref\": \"https://example.test/int\" }")
  let alone = @moonschema.Schema::new(remote)
  println("\nwith nothing fed to it:")
  println("  1  ->  \{alone.valid(Json::number(1.0))}")
  for fault in alone.faults(Json::number(1.0)) {
    println("      " + fault.to_string())
  }
  let fed = @moonschema.Schema::new(remote, remotes={
    "https://example.test/int": @json.parse(
      "{ \"type\": \"integer\", \"minimum\": 0 }",
    ),
  })
  println("\nwith the document fed in:")
  for instance in [Json::number(1.0), Json::number(-1.0)] {
    println("  \{instance.stringify()}  ->  \{fed.valid(instance)}")
    for fault in fed.faults(instance) {
      println("      " + fault.to_string())
    }
  }
}
