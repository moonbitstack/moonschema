---
name: moonschema
description: "Validate a JSON document against a JSON Schema in MoonBit, draft-04 through v1, with the four output formats of the specification, format assertion, and vocabularies defined outside the library. Use it to answer whether an instance conforms, and to say where it does not."
---

# moonschema

`moon add moonbitstack/moonschema`. One package, `@moonschema`, and `moonbitlang/core/json` for the
`Json` values it reads and writes.

```moonbit
import {
  "moonbitstack/moonschema",
  "moonbitlang/core/json",
}
```

A schema is a `Json` tree: this package does not parse JSON, and it opens no sockets.

## Ask whether an instance conforms

`Schema::new` reads the document once and raises `Refused` when it cannot. `valid` answers yes or
no; `faults` answers with the reasons, each carrying a pointer into the instance and one into the
schema.

```moonbit
let schema = @moonschema.Schema::new(
  @json.loads("{ \"type\": \"object\", \"required\": [\"id\"] }"),
)
assert_eq(schema.valid(@json.loads("{\"id\": 1}")), true)
assert_eq(
  schema.faults(@json.loads("{}"))[0].to_string(),
  "the instance: missing id (required at /required)",
)
```

## Say why, in one of the four formats

`report` produces the `flag`, `basic`, `detailed` and `verbose` formats of §12 by one walk;
`Report::to_json` writes the object §12.4 describes, which is the one to send over a wire.
`schema.faults` returns the basic format flattened, and is what a message to a person usually
starts from.

```moonbit
let person = @moonschema.Schema::new(
  @json.loads("{ \"type\": \"object\", \"required\": [\"id\"] }"),
)
let report = person.report(@json.loads("{}"), output=@moonschema.Output::Basic)
assert_eq(report.valid, false)
assert_eq(report.units[0].keyword_at, "/required")
assert_eq(report.units[0].at, "")
```

## Hand over the documents a `$ref` may reach

Nothing is fetched. A reference to another document resolves only when the caller passes that
document in `remotes`, keyed by the URI the reference names; one that lands nowhere is a fault.

```moonbit
let remote = @json.loads("{ \"$ref\": \"https://example.test/int\" }")
let fed = @moonschema.Schema::new(
  remote,
  remotes={
    "https://example.test/int": @json.loads("{ \"type\": \"integer\" }"),
  },
)
assert_eq(fed.valid(Json::number(2.0)), true)
```

## Rules that catch people out

- **A document's `$schema` beats the `draft` argument.** `draft` is the fallback for a document that
  names no version; a `$schema` nobody here knows raises `Refused` rather than being guessed at.
- **`format` is an annotation before v1.** Turn it into an assertion with `format=true`, which
  outranks the dialect, or let the dialect's metaschema declare the format-assertion vocabulary. v1
  asserts it unasked.
- **`valid` stops at the first refusal; `faults` keeps every reason.** Asking for both pays for both.
- **`schema_at` is the route the walk took, not where the keyword is defined.** A fault reached
  through a reference reports `/properties/port/$ref/maximum`, and `absolute_at` on an output unit is
  the one that names the resource.
- **A fault's `keyword` is the last step of its `schema_at`, unescaped.** Read either one and you have
  the other: `/properties/port/$ref/maximum` is `maximum`, and a property named `a/b` appears in the
  path as `a~1b`. Nothing else has to be consulted to say which keyword refused an instance.
- **A vocabulary from outside must be registered and asked for.** `Registry::add` refuses a name a
  built-in keyword answers to or one another vocabulary already claimed, and a document whose
  metaschema requires a vocabulary nobody holds raises `Refused` instead of half-reading.
- **`unevaluatedProperties` and `unevaluatedItems` see annotations from branches that succeeded.**
  A schema that puts a failing `anyOf` branch's annotations to work will refuse more than expected;
  that is the specification, not an omission here.
