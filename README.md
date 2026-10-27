<div align="center">

<h1>moonschema</h1>

<p><b>JSON Schema validation for MoonBit.</b><br>
A schema is read, an instance is walked against it, and the answer says where —<br>
in the instance, and in the schema. Five versions of the specification, one validator, no sockets.</p>

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
    @json.parse(
      (
        #|{ "type": "object",
        #|  "properties": { "port": { "type": "integer", "minimum": 1 } },
        #|  "required": ["port"] }
      ),
    ),
  )
  println(schema.valid(@json.parse("{\"port\": 8080}")))
  for fault in schema.faults(@json.parse("{\"port\": 0}")) {
    println(fault.to_string())
  }
}
```

```
true
/port: below the minimum (minimum at /properties/port/minimum)
```

## What it answers

`Schema::new` reads the document once. After that, `valid` is the flag output and `faults` is the
basic output — every reason, not just the first.

<table>
<tr><th>Call</th><th>Answers</th></tr>
<tr><td><code>Schema::new(document)</code></td><td>a schema, read at the version it names; raises <code>Refused</code> when it cannot be read</td></tr>
<tr><td><code>schema.valid(instance)</code></td><td><code>Bool</code> — whether the instance conforms, and nothing else</td></tr>
<tr><td><code>schema.faults(instance)</code></td><td><code>Array[Fault]</code> — every reason it did not, empty when it did</td></tr>
<tr><td><code>Schema::new(doc, draft=…)</code></td><td>the version to read a document that names none</td></tr>
<tr><td><code>Schema::new(doc, remotes=…)</code></td><td>the documents a <code>$ref</code> may reach, by URI</td></tr>
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
</table>

Both `http` and `https` spellings are accepted, with or without the trailing `#`.
`Draft::of(uri)` reads one back; `Draft::uri()` prints the one a version writes.

## References

A `$ref` is resolved with the RFC 3986 rules a browser uses for a relative link, against the base
URI in effect — the document's `$id`, or the one a surrounding subschema gave it. `$anchor` names a
place inside a document by a plain word.

A reference to another document resolves only when that document is handed over. Nothing is
fetched: a validator that opens sockets is a validator that blocks, retries and fails. What is not
handed over does not resolve, and a reference that lands nowhere is a fault rather than a silent
pass.

```moonbit
let remote = @json.parse("{ \"$ref\": \"https://example.test/int\" }")
let schema = @moonschema.Schema::new(
  remote,
  remotes={
    "https://example.test/int": @json.parse("{ \"type\": \"integer\" }"),
  },
)
println(schema.valid(Json::number(1.0)))   // true
```

## What it will not do

- **Fetch a remote `$ref`.** The seam is `remotes`; the caller fills it from wherever they keep them.
- **Assert `format`.** The specification makes it an annotation unless a caller asks otherwise, and
  this does not offer the otherwise yet.
- **Hyper-schema.** Links and media types are a different specification.
- **Compile schemas to code.** Interpretation first; a measurement is the time to argue about it.

## Examples

The first four are programs with their output, run with `moon run examples/<name>`. The last is
the library the documentation site compiles to JavaScript, built with
`moon build --target js --release examples/web`.

<table>
<tr><th>Example</th><th>Shows</th></tr>
<tr><td><code>tour</code></td><td>a schema, three instances, and the faults they earn</td></tr>
<tr><td><code>versions</code></td><td>one document read at each of the five, and where they differ</td></tr>
<tr><td><code>references</code></td><td><code>$defs</code>, <code>$id</code>, <code>$anchor</code>, and a document handed in</td></tr>
<tr><td><code>composition</code></td><td><code>allOf</code>, <code>oneOf</code>, <code>if</code>/<code>then</code>/<code>else</code>, and what is left over</td></tr>
<tr><td><code>web</code></td><td>the engine the documentation site runs in the browser</td></tr>
</table>

## Licence

Apache-2.0.
