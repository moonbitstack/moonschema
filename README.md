<div align="center">

<h1>moonschema</h1>

<p><b>JSON Schema validation for MoonBit.</b><br>
A schema is read, an instance is walked against it, and the answer says where —<br>
in the instance, and in the schema. Six versions of the specification, one validator, no sockets.</p>

<p>
<a href="https://moonbitstack.github.io/moonschema/">Home</a> ·
<a href="https://moonbitstack.github.io/moonschema/guide.html">Guide</a> ·
<a href="https://moonbitstack.github.io/moonschema/api.html">API</a> ·
<a href="https://moonbitstack.github.io/moonschema/showcase.html">Showcase</a> ·
<a href="https://mooncakes.io/docs/moonbitstack/moonschema">mooncakes</a>
</p>

</div>

```bash
moon add moonbitstack/moonschema
```

```moonbit
fn main raise {
  let schema = @moonschema.Schema::new(
    @json.loads(
      (
        #|{ "type": "object",
        #|  "properties": { "port": { "type": "integer", "minimum": 1 } },
        #|  "required": ["port"] }
      ),
    ),
  )
  assert_eq(schema.valid(@json.loads("{\"port\": 8080}")), true)
  let faults = schema.faults(@json.loads("{\"port\": 0}"))
  assert_eq(faults.length(), 1)
  assert_eq(
    faults[0].to_string(),
    "/port: below the minimum (minimum at /properties/port/minimum)",
  )
}
```

## What it answers

`Schema::new` reads the document once. After that, `valid` is the flag output, `faults` is the
flat list of reasons, and `report` is any of the four formats the specification defines.

<table>
<tr><th>Call</th><th>Answers</th></tr>
<tr><td><code>Schema::new(document)</code></td><td>a schema, read at the version it names; raises <code>Refused</code> when it cannot be read</td></tr>
<tr><td><code>schema.valid(instance)</code></td><td><code>Bool</code> — whether the instance conforms, and nothing else</td></tr>
<tr><td><code>schema.faults(instance)</code></td><td><code>Array[Fault]</code> — every reason it did not, empty when it did</td></tr>
<tr><td><code>schema.report(instance, output=…)</code></td><td><code>Report</code> — the four formats of §12, and <code>to_json()</code> to write one</td></tr>
<tr><td><code>Schema::new(doc, draft=…)</code></td><td>the version to read a document that names none</td></tr>
<tr><td><code>Schema::new(doc, remotes=…)</code></td><td>the documents a <code>$ref</code> may reach, by URI</td></tr>
<tr><td><code>Schema::new(doc, format=true)</code></td><td>make <code>format</code> assert, or <code>false</code> to leave it an annotation</td></tr>
<tr><td><code>Schema::new(doc, registry=…)</code></td><td>the vocabularies from outside this library a document may ask for</td></tr>
</table>

### A fault

Four fields, so a message can point at both ends of a refusal.

<table>
<tr><th>Field</th><th>Holds</th></tr>
<tr><td><code>at</code></td><td>where in the instance, as a JSON Pointer (RFC 6901); empty for the instance itself</td></tr>
<tr><td><code>schema_at</code></td><td>where in the schema the keyword sits, following the walk it took</td></tr>
<tr><td><code>keyword</code></td><td>the keyword that refused it — <code>minimum</code>, <code>required</code>, <code>$ref</code></td></tr>
<tr><td><code>message</code></td><td>what that keyword had to say, in one clause</td></tr>
</table>

## Four ways to say it

§12 of the specification names four output formats, and `report` is all four: the same walk, said
with more or less of itself. `Report::to_json` writes the object §12.4 describes.

<table>
<tr><th>Format</th><th>Says</th></tr>
<tr><td><code>Flag</code></td><td>whether it validated, and nothing else</td></tr>
<tr><td><code>Basic</code></td><td>a flat list, one entry per keyword, each with both locations</td></tr>
<tr><td><code>Detailed</code></td><td>a tree, with the places several reasons share kept and a single reason pulled up to its parent</td></tr>
<tr><td><code>Verbose</code></td><td>the whole tree, annotations and passes included</td></tr>
</table>

```moonbit
let schema = @moonschema.Schema::new(@json.loads("{ \"type\": \"integer\" }"))
let report = schema.report(@json.loads("\"seven\""), output=@moonschema.Output::Basic)
assert_eq(
  report.to_json().stringify(indent=2),
  #|{
  #|  "valid": false,
  #|  "errors": [
  #|    {
  #|      "valid": false,
  #|      "keywordLocation": "/type",
  #|      "instanceLocation": "",
  #|      "error": "not of type integer"
  #|    }
  #|  ]
  #|},
)
```

An output unit carries two pointers that are one pointer until a reference is crossed:
`keywordLocation` is the *evaluation path* and goes through `$ref`, while
`absoluteKeywordLocation` is the *schema location* — the resource's own URI and a pointer into
it — and does not.

## `format`

`format` names a shape for a string: `date-time`, `email`, `ipv4`, `uri`, `uuid`, `regex` and a
dozen more, each read against the RFC that defines it. Before v1 the specification makes the
keyword an annotation, so it says nothing about validity unless you ask:

```moonbit
let schema = @moonschema.Schema::new(
  @json.loads("{ \"format\": \"ipv4\" }"),
  format=true,
)
assert_eq(schema.valid(@json.loads("\"not-an-ipv4\"")), false)
assert_eq(schema.valid(@json.loads("\"10.0.0.1\"")), true)
```

The argument is optional, and leaving it out lets the document answer: an annotation unless its
dialect's metaschema declares the format-assertion vocabulary, and an assertion throughout v1,
which made assertion the requirement. A call is more specific than a dialect, which is more
specific than a version.

<table>
<tr><th>Group</th><th>Names</th></tr>
<tr><td>Time</td><td><code>date</code>, <code>time</code>, <code>date-time</code>, <code>duration</code></td></tr>
<tr><td>Hosts</td><td><code>hostname</code>, <code>idn-hostname</code>, <code>ipv4</code>, <code>ipv6</code></td></tr>
<tr><td>Mail</td><td><code>email</code>, <code>idn-email</code></td></tr>
<tr><td>Resources</td><td><code>uri</code>, <code>uri-reference</code>, <code>iri</code>, <code>iri-reference</code>, <code>uri-template</code></td></tr>
<tr><td>Values</td><td><code>uuid</code>, <code>json-pointer</code>, <code>relative-json-pointer</code>, <code>regex</code></td></tr>
</table>

## Versions

A document is read at the version it names in `$schema`. The `draft` argument is the fallback for a
document that names nothing; it never overrides one that does. A `$schema` this does not know is
refused, not guessed at.

<table>
<tr><th>Value</th><th><code>$schema</code></th><th>Version</th></tr>
<tr><td><code>Draft4</code></td><td><code>json-schema.org/draft-04/schema#</code></td><td>draft-04 (2013)</td></tr>
<tr><td><code>Draft6</code></td><td><code>json-schema.org/draft-06/schema#</code></td><td>draft-06 (2017)</td></tr>
<tr><td><code>Draft7</code></td><td><code>json-schema.org/draft-07/schema#</code></td><td>draft-07 (2018)</td></tr>
<tr><td><code>Draft2019</code></td><td><code>json-schema.org/draft/2019-09/schema</code></td><td>2019-09</td></tr>
<tr><td><code>Draft2020</code></td><td><code>json-schema.org/draft/2020-12/schema</code></td><td>2020-12 — the preset</td></tr>
<tr><td><code>V1</code></td><td><code>json-schema.org/v1</code></td><td>v1 (2026), or <code>…/v1/2026</code> for the release</td></tr>
</table>

Both `http` and `https` spellings are accepted, with or without the trailing `#`.
`Draft::of(uri)` reads one back; `Draft::uri()` prints the one a version writes.

v1 is 2020-12 with three differences: `format` asserts without being asked, `propertyDependencies`
joins the applicators — one property's value chooses the subschema the whole instance is then
validated against — and `$dynamicRef` drops the rule that it first had to resolve to a
`$dynamicAnchor` of the same name.

## References

A `$ref` is resolved with the RFC 3986 rules a browser uses for a relative link, against the base
URI in effect — the document's `$id`, or the one a surrounding subschema gave it. `$anchor` names a
place inside a document by a plain word.

A reference to another document resolves only when that document is handed over. Nothing is
fetched: a validator that opens sockets is a validator that blocks, retries and fails. What is not
handed over does not resolve, and a reference that lands nowhere is a fault rather than a silent
pass.

```moonbit
let remote = @json.loads("{ \"$ref\": \"https://example.test/int\" }")
let schema = @moonschema.Schema::new(
  remote,
  remotes={
    "https://example.test/int": @json.loads("{ \"type\": \"integer\" }"),
  },
)
assert_eq(schema.valid(Json::number(1.0)), true)
```

## Your own keywords

A vocabulary outside this library plugs in without a change here: a `Keyword` asserts or
annotates, a `Vocabulary` holds a set of them under a URI, and a `Registry` offers them to a
document. The document's own metaschema decides which are in force — named with `true` they
assert, with `false` they annotate and assert nothing, and named with `true` and held by nobody the
document is refused rather than half-read.

```moonbit
struct Even {}

pub impl @moonschema.Keyword for Even with fn name(_self) {
  "x-even"
}

pub impl @moonschema.Keyword for Even with fn judge(_self, value, instance, site) {
  ignore(site)
  match (value, instance) {
    (True, Number(number, ..)) =>
      if number == (number / 2.0).floor() * 2.0 {
        Accept
      } else {
        Refuse(why="odd")
      }
    _ => Accept
  }
}

pub extend Even with @moonschema.Keyword::{name, judge}

struct Counting {}

pub impl @moonschema.Vocabulary for Counting with fn uri(_self) {
  "https://example.test/vocab/even"
}

pub impl @moonschema.Vocabulary for Counting with fn keywords(_self) {
  let even : &@moonschema.Keyword = Even::{  }
  [even]
}

pub extend Counting with @moonschema.Vocabulary::{uri, keywords}
```

A keyword sees the instance, the keyword's value, and where both sit; it does not apply subschemas.
A name a built-in keyword already answers to cannot be taken, and two vocabularies cannot claim one
name: the second registration is refused rather than resolved in someone's favour.

What puts the vocabulary in force is the document's own metaschema, handed over like any other
document:

```moonbit
let metaschema = @json.loads(
  (
    #|{ "$id": "https://example.test/meta",
    #|  "$schema": "https://json-schema.org/draft/2020-12/schema",
    #|  "$vocabulary": {
    #|    "https://json-schema.org/draft/2020-12/vocab/validation": true,
    #|    "https://example.test/vocab/even": true } }
  ),
)
let remotes = { "https://example.test/meta": metaschema }
let registry = @moonschema.Registry::new()
registry.add(Counting::{  })
let schema = @moonschema.Schema::new(
  @json.loads(
    (
      #|{ "$schema": "https://example.test/meta",
      #|  "type": "integer", "x-even": true }
    ),
  ),
  remotes~,
  registry~,
)
assert_eq(schema.valid(@json.loads("4")), true)
assert_eq(
  schema.faults(@json.loads("5"))[0].to_string(),
  "the instance: odd (x-even at /x-even)",
)
```

## What it will not do

- **Fetch a remote `$ref`.** The seam is `remotes`; the caller fills it from wherever they keep them.
- **Validate a schema against its metaschema.** A schema is read for what it says, not checked for
  whether it should have said it. `$schema` picks the version; the rest is the schema author's.
- **Hyper-schema.** Links and media types are a different specification.
- **Compile schemas to code.** Interpretation first; a measurement is the time to argue about it.

## Conformance

The specification has no reference implementation, so it publishes cases instead: one suite covering
every keyword at every version, written by the people who wrote the other validators. All of it runs
here — the required cases at each of the six versions, the optional `format` sets, the output-format
cases, and the v1 proposals.

A suite is not the whole question, though: it says whether the answers are right, not whether another
validator would have given them. So a second run replays a fixed corpus against this library and
against two mature implementations — Ajv and python-jsonschema — keeping only the cases where those
two agree with each other, so that the corpus is somebody else's opinion and not this library's.

The table is the gate's own output, put into this page by a script so that a count here cannot go
stale:

<!-- conformance:begin -->
<table>
<tr><th>Set</th><th>Cases</th><th>Failed</th></tr>
<tr><td><code>draft4</code></td><td>618</td><td>0</td></tr>
<tr><td><code>draft6</code></td><td>841</td><td>0</td></tr>
<tr><td><code>draft7</code></td><td>929</td><td>0</td></tr>
<tr><td><code>draft2019-09</code></td><td>1,261</td><td>0</td></tr>
<tr><td><code>draft2020-12</code></td><td>1,301</td><td>0</td></tr>
<tr><td><code>v1</code></td><td>1,135</td><td>0</td></tr>
<tr><td><code>v1/proposals/propertyDependencies</code></td><td>38</td><td>0</td></tr>
<tr><td><code>draft4/optional/format</code></td><td>291</td><td>0</td></tr>
<tr><td><code>draft6/optional/format</code></td><td>407</td><td>0</td></tr>
<tr><td><code>draft7/optional/format</code></td><td>785</td><td>0</td></tr>
<tr><td><code>draft2019-09/optional/format</code></td><td>866</td><td>0</td></tr>
<tr><td><code>draft2020-12/optional/format</code></td><td>866</td><td>0</td></tr>
<tr><td><code>v1/format</code></td><td>860</td><td>0</td></tr>
<tr><td><code>draft2020-12/optional/format-assertion.json</code></td><td>4</td><td>0</td></tr>
<tr><td><code>v1/optional/format-annotation.json</code></td><td>133</td><td>0</td></tr>
<tr><td><code>outputs: draft2019-09</code></td><td>4</td><td>0</td></tr>
<tr><td><code>outputs: draft2020-12</code></td><td>4</td><td>0</td></tr>
<tr><td><code>differential, against two other implementations</code></td><td>676</td><td>0</td></tr>
<tr><td><b>Total</b></td><td><b>11,019</b></td><td><b>0</b></td></tr>
</table>
<!-- conformance:end -->

No case fails. One construct is read differently on purpose: `multipleOf` with a divisor that is not a
binary fraction. Both references refuse `0.3` against `{"multipleOf": 0.1}`, because `0.3 / 0.1` is
`2.9999999999999996` in binary floating point. The suite requires `0.0075` to be a multiple of
`0.0001`, which can only hold if the division is the decimal one the document wrote, so this library
allows the remainder the representation leaves behind and takes the suite's side.

## Examples

Each is a program with its real output, run with `moon run src/examples/<name>`. The last is the
library the documentation site compiles to JavaScript, built with
`moon build --target js --release src/examples/web`.

<table>
<tr><th>Example</th><th>Shows</th></tr>
<tr><td><code>tour</code></td><td>a schema, three instances, and the faults they earn</td></tr>
<tr><td><code>versions</code></td><td>one document read at each of the six, and where they differ</td></tr>
<tr><td><code>references</code></td><td><code>$defs</code>, <code>$id</code>, <code>$anchor</code>, and a document handed in</td></tr>
<tr><td><code>composition</code></td><td><code>allOf</code>, <code>oneOf</code>, <code>if</code>/<code>then</code>/<code>else</code>, and what is left over</td></tr>
<tr><td><code>formats</code></td><td>one failure in all four output formats</td></tr>
<tr><td><code>vocabularies</code></td><td>a keyword from outside, put in force by a metaschema</td></tr>
<tr><td><code>web</code></td><td>the engine the documentation site runs in the browser</td></tr>
</table>

## Licence

Apache-2.0.
