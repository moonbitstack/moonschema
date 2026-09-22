# moonschema

JSON Schema validation for MoonBit. It validates; it does not parse JSON — a
caller hands in a `Json` tree, which [`moonjson`](https://github.com/moonbitstack/moonjson)
reads.

```moonbit
let schema = @moonschema.Schema::new(document)   // `document` is a Json tree
schema.valid(instance)                           // the flag output: yes or no
schema.faults(instance)                          // the basic output: every reason

// A reference to another document reaches what the caller hands it, and nothing
// else: this opens no sockets.
@moonschema.Schema::new(document, remotes={ "https://example.test/int": other })
```

Run `moon run examples/tour` for a worked example.

## What it passes

Every required case of the official suite, for all five versions:

| Version | Cases | Passing |
|:--:|:--:|:--:|
| draft-04 | 618 | **618** |
| draft-06 | 841 | **841** |
| draft-07 | 929 | **929** |
| 2019-09 | 1261 | **1261** |
| 2020-12 | 1301 | **1301** |
| **total** | **4950** | **4950** |

Nothing is skipped and nothing is excused: the gate fails if a single case stops
passing, and it fails just as loudly if a case listed as known-failing starts
passing, because the list would then be describing something that is no longer
so. The list is empty.

The counts are the cases the suite calls required. The `optional/` directory —
`format` assertions, big numbers beyond a double, non-BMP text — is not run, by
the same reading of the specification that makes `format` an annotation.

## Versions

Five released versions, all of them still in use:

| Value | Version | Why it is here |
|:--:|:--:|:--|
| `Draft4` | draft-04 (2013) | What OpenAPI 3.0 profiles, and what much Java and Python tooling still emits |
| `Draft6` | draft-06 (2017) | `$id` replaces `id`; `exclusiveMinimum` becomes a number |
| `Draft7` | draft-07 (2018) | The most widely deployed version |
| `Draft2019` | 2019-09 | Vocabularies, `$defs`, `$recursiveRef`, `unevaluatedProperties` |
| `Draft2020` | 2020-12 | `$dynamicRef`, `prefixItems` — and what OpenAPI 3.1 **is** |

`draft-03` is not here and will not be: it predates the `$` keywords and nothing
has been written against it since 2010. The next release arrives as another
value of this enum and a keyword table, not as a second validator.

**A document is read at the version it names.** `$schema` wins over the `draft`
argument, which wins over the preset — the same "more specific wins" rule the
rest of this family publishes. A `$schema` URI this does not know answers `None`
rather than a guess: a document written against something else is not a document
to read at a version of our choosing.

Both `http` and `https` spellings are accepted, with or without the trailing
`#`, because both are found in the wild.

## What it is measured against

The [official test suite](https://github.com/json-schema-org/JSON-Schema-Test-Suite)
is the `suite/` submodule and the acceptance gate — **every required case, not a
selection**. It is run by the `gate/` module, which reads the suite off disk,
feeds the validator the remote documents the suite refers to, and fails unless
the result is exactly the table above. The library itself reads no files: the
gate is where the caller lives.

```bash
git submodule update --init --recursive
cd gate && moon run . --target native
```

The [specification](https://github.com/json-schema-org/json-schema-spec) is the
`spec/` submodule. Neither submodule, and not the gate, ships in the package:
`.moonignore` excludes them, because a consumer installing this wants the
validator and not the paperwork.

## What it will not do

**Fetch a remote `$ref`.** A validator should not open sockets. The seam is
`remotes`: a map from URI to document, which the caller fills from wherever it
keeps them. What is not handed over does not resolve, and a reference that
resolves to nothing is a fault rather than a silent pass.

**Assert `format`.** The specification makes `format` an annotation unless a
caller asks otherwise, and this does not offer the otherwise yet.

**Hyper-schema.** That is a different specification.

**Compile schemas to code.** Interpretation first; if it measures slow, that is
the time to argue about it.

## Install

```bash
moon add moonbitstack/moonschema
```

## Licence

Apache-2.0.
