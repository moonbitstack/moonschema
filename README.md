# moonschema

JSON Schema validation for MoonBit. It validates; it does not parse JSON — a
caller hands in a `Json` tree, which [`moonjson`](https://github.com/moonbitstack/moonjson)
reads.

> **Status: the repository is set up, the validator is not written yet.** What is
> here is the version model, the specification and the official test suite as
> submodules, and the plan. See the tracking list with the project.

```moonbit
@moonschema.Draft::of("https://json-schema.org/draft/2020-12/schema")  // Some(2020-12)
@moonschema.draft                                                      // the preset: 2020-12
```

Run `moon run examples/tour` for what is there today.

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

## What it will be measured against

The [official test suite](https://github.com/json-schema-org/JSON-Schema-Test-Suite)
is the `suite/` submodule and the acceptance gate — **every case, not a
selection**:

| Version | Groups | Cases |
|:--:|:--:|:--:|
| draft-04 | 199 | 1009 |
| draft-06 | 277 | 1354 |
| draft-07 | 322 | 1832 |
| 2019-09 | 449 | 2285 |
| 2020-12 | 462 | 2329 |
| **total** | **1709** | **8809** |

A case that is skipped will say in the code why, and this README will say how
many. The [specification](https://github.com/json-schema-org/json-schema-spec)
is the `spec/` submodule; there is no official reference implementation, so the
implementations read for comparison are named in the tracking list.

```bash
git submodule update --init --recursive
```

Neither submodule ships in the package: `.moonignore` excludes them, because a
consumer installing this wants the validator and not the paperwork.

## What it will not do

**Fetch a remote `$ref`.** A validator should not open sockets. There will be a
seam for resolving references; the caller feeds it.

**Assert `format` by default.** The specification makes `format` an annotation
unless a caller asks otherwise, and so will this.

**Hyper-schema.** That is a different specification.

**Compile schemas to code.** Interpretation first; if it measures slow, that is
the time to argue about it.

## Install

```bash
moon add moonbitstack/moonschema
```

## Licence

Apache-2.0.
