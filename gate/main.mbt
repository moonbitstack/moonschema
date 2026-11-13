// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Where the suite is, relative to this module.
let suite : String = "suite"

///|
/// One reading of the suite, at one version.
///
/// The required cases of each version are six of these; the rest are the parts
/// the specification calls optional or leaves as a proposal, run because this
/// library claims them.
struct Run {
  /// The directory under `tests/` the cases are in.
  directory : String
  /// One file of that directory, when the run is a single file rather than the
  /// whole directory.
  file : String?
  /// The version the cases are read at.
  draft : @moonschema.Draft
  /// Whether these cases call for `format` to assert. The suite asks a runner to
  /// turn it on for `optional/format`, and the parts about annotation run with
  /// it off; `None` is the document's own dialect deciding, which is what the
  /// vocabulary cases are about.
  format : Bool?
}

///|
/// Every reading the gate performs.
let runs : Array[Run] = [
  { directory: "draft4", file: None, draft: Draft4, format: None, },
  { directory: "draft6", file: None, draft: Draft6, format: None, },
  { directory: "draft7", file: None, draft: Draft7, format: None, },
  { directory: "draft2019-09", file: None, draft: Draft2019, format: None, },
  { directory: "draft2020-12", file: None, draft: Draft2020, format: None, },
  { directory: "v1", file: None, draft: V1, format: None, },
  {
    directory: "v1/proposals/propertyDependencies",
    file: None,
    draft: V1,
    format: None,
  },
  {
    directory: "draft4/optional/format",
    file: None,
    draft: Draft4,
    format: Some(true),
  },
  {
    directory: "draft6/optional/format",
    file: None,
    draft: Draft6,
    format: Some(true),
  },
  {
    directory: "draft7/optional/format",
    file: None,
    draft: Draft7,
    format: Some(true),
  },
  {
    directory: "draft2019-09/optional/format",
    file: None,
    draft: Draft2019,
    format: Some(true),
  },
  {
    directory: "draft2020-12/optional/format",
    file: None,
    draft: Draft2020,
    format: Some(true),
  },
  { directory: "v1/format", file: None, draft: V1, format: Some(true), },
  // The assertion vocabulary a metaschema may declare, which turns the keyword
  // on with nobody asking.
  {
    directory: "draft2020-12/optional",
    file: Some("format-assertion.json"),
    draft: Draft2020,
    format: None,
  },
  // And the keyword read as an annotation, which is what a caller who turns the
  // assertion off gets.
  {
    directory: "v1/optional",
    file: Some("format-annotation.json"),
    draft: V1,
    format: Some(false),
  },
]

///|
/// The output-test directories, each with the version whose formats it checks.
let output_runs : Array[(String, @moonschema.Draft)] = [
  ("draft2019-09", Draft2019),
  ("draft2020-12", Draft2020),
]

///|
/// The cases that do not pass, and why.
///
/// None. Every case of every run passes, and the gate fails if that stops being
/// true — or if one named here starts passing, because then this list would be
/// describing something that is no longer so.
let known : Array[String] = []

///|
/// What one run came to.
struct Tally {
  mut passed : Int32
  mut failed : Int32
  first : Array[String]
}

///|
/// Run every case of every run and print what passed.
///
/// A case that fails says which file, group and case it was, because a count
/// that only goes up says nothing about which rule went wrong.
fn main {
  let remotes = load_remotes()
  let mut total = 0
  let mut wrong = 0
  for run in runs {
    let tally = measure(run, remotes)
    total = total + tally.passed + tally.failed
    wrong = wrong + tally.failed
    println(
      label(run).pad_start(40, ' ') +
      ": " +
      tally.passed.to_string() +
      " passed, " +
      tally.failed.to_string() +
      " failed",
    )
    for line in tally.first {
      println("    " + line)
    }
  }
  for outputs in output_runs {
    let tally = measure_outputs(outputs.0, outputs.1, remotes)
    total = total + tally.passed + tally.failed
    wrong = wrong + tally.failed
    println(
      ("outputs: " + outputs.0).pad_start(40, ' ') +
      ": " +
      tally.passed.to_string() +
      " passed, " +
      tally.failed.to_string() +
      " failed",
    )
    for line in tally.first {
      println("    " + line)
    }
  }
  let differential = measure_differential()
  total = total + differential.passed + differential.failed
  wrong = wrong + differential.failed
  println(
    "differential, against two other implementations".pad_start(40, ' ') +
    ": " +
    differential.passed.to_string() +
    " passed, " +
    differential.failed.to_string() +
    " failed",
  )
  for line in differential.first {
    println("    " + line)
  }
  println(
    "total: " +
    (total - wrong).to_string() +
    " of " +
    total.to_string() +
    " cases",
  )
  // The gate is the suite, so the suite decides.
  if wrong != known.length() {
    abort(
      "the suite says " +
      wrong.to_string() +
      " cases fail, and " +
      known.length().to_string() +
      " are known to",
    )
  }
}

///|
fn label(run : Run) -> String {
  match run.file {
    Some(file) => run.directory + "/" + file
    None => run.directory
  }
}

///|
/// Every case of one run, run.
fn measure(run : Run, remotes : Map[String, Json]) -> Tally {
  let tally = { passed: 0, failed: 0, first: [], }
  let root = suite + "/tests/" + run.directory
  let files = match run.file {
    Some(file) => [file]
    None =>
      (@fs.read_dir(root) catch {
        _ => {
          tally.first.push("no such directory: " + root)
          return tally
        }
      }).to_owned()
  }
  files.sort()
  for file in files {
    // A subdirectory is `optional/` or `proposals/`, and each of those is a run
    // of its own: what is here is the files that hold cases.
    if !file.has_suffix(".json") {
      continue
    }
    let text = @fs.read_file_to_string(root + "/" + file) catch {
      _ => continue
    }
    let groups = @json.loads(text) catch {
      _ => {
        tally.first.push(file + ": unreadable")
        continue
      }
    }
    guard groups is Array(all) else { continue }
    for group in all {
      guard group is Object(fields) else { continue }
      let title = text_of(fields.get("description"))
      let schema = match fields.get("schema") {
        Some(found) => found
        None => continue
      }
      let cases = match fields.get("tests") {
        Some(Array(found)) => found
        _ => continue
      }
      let validator = build(run, schema, remotes) catch {
        error => {
          for _ in cases {
            tally.failed = tally.failed + 1
          }
          if tally.first.length() < 80 {
            tally.first.push(
              file + " / " + title + ": schema refused: " + error.to_string(),
            )
          }
          continue
        }
      }
      for instance in cases {
        guard instance is Object(one) else { continue }
        let wanted = one.get("valid") is Some(True)
        let data = match one.get("data") {
          Some(found) => found
          None => Json::null()
        }
        let got = validator.valid(data)
        if got == wanted {
          tally.passed = tally.passed + 1
        } else {
          tally.failed = tally.failed + 1
          if tally.first.length() < 80 {
            tally.first.push(
              file +
              " / " +
              title +
              " / " +
              text_of(one.get("description")) +
              ": " +
              debug_text(data) +
              " wanted " +
              wanted.to_string() +
              ", got " +
              got.to_string(),
            )
          }
        }
      }
    }
  }
  tally
}

///|
/// The schema of one case group, read the way its run asks for.
fn build(
  run : Run,
  schema : Json,
  remotes : Map[String, Json],
) -> @moonschema.Schema raise @moonschema.Refused {
  match run.format {
    Some(wanted) =>
      @moonschema.Schema::new(schema, draft=run.draft, remotes~, format=wanted)
    None => @moonschema.Schema::new(schema, draft=run.draft, remotes~)
  }
}

///|
/// The documents a `$ref` in the suite reaches, under the URIs it reaches them
/// by. The suite serves `remotes/` at `http://localhost:1234/`.
fn load_remotes() -> Map[String, Json] {
  let remotes : Map[String, Json] = Map::Map([])
  gather(suite + "/remotes", "http://localhost:1234", remotes)
  // The metaschemas, which a schema is entitled to reference and which the
  // validator itself does not carry: a caller feeds it what it may reach, and
  // here the caller is this harness. They are the published documents, kept in
  // `meta/` because they are frozen and fetching them would be I/O in a test.
  let missing : Array[String] = []
  for name in meta_documents {
    let text = @fs.read_file_to_string("meta/" + name.1) catch {
      _ => {
        missing.push(name.1)
        continue
      }
    }
    match (@json.loads(text) catch { _ => continue }) {
      document => remotes[name.0] = document
    }
  }
  // A document the harness means to feed and cannot find would make the cases
  // that reach it pass for the wrong reason, so it is a failure of the harness
  // rather than a quietly absent remote.
  if missing.length() > 0 {
    abort("no such metaschema in meta/: " + missing.join(", "))
  }
  // The schemas that say what an output has to look like, which the output tests
  // reference by the URI each publishes under.
  for published in output_schemas {
    let path = suite + "/output-tests/" + published.1
    let text = @fs.read_file_to_string(path) catch { _ => continue }
    match (@json.loads(text) catch { _ => continue }) {
      document => remotes[published.0] = document
    }
  }
  remotes
}

///|
/// Each published output schema, by the URI a case references it as.
let output_schemas : Array[(String, String)] = [
  (
    "https://json-schema.org/draft/2019-09/output/schema", "draft2019-09/output-schema.json",
  ),
  (
    "https://json-schema.org/draft/2020-12/output/schema", "draft2020-12/output-schema.json",
  ),
]

///|
/// Each metaschema, by the URI a schema references it as.
let meta_documents : Array[(String, String)] = [
  ("http://json-schema.org/draft-04/schema", "draft-04/schema.json"),
  ("http://json-schema.org/draft-06/schema", "draft-06/schema.json"),
  ("http://json-schema.org/draft-07/schema", "draft-07/schema.json"),
  ("https://json-schema.org/draft/2019-09/schema", "2019-09/schema.json"),
  ("https://json-schema.org/draft/2019-09/meta/core", "2019-09/core.json"),
  (
    "https://json-schema.org/draft/2019-09/meta/applicator", "2019-09/applicator.json",
  ),
  (
    "https://json-schema.org/draft/2019-09/meta/validation", "2019-09/validation.json",
  ),
  (
    "https://json-schema.org/draft/2019-09/meta/meta-data", "2019-09/meta-data.json",
  ),
  ("https://json-schema.org/draft/2019-09/meta/format", "2019-09/format.json"),
  ("https://json-schema.org/draft/2019-09/meta/content", "2019-09/content.json"),
  ("https://json-schema.org/draft/2020-12/schema", "2020-12/schema.json"),
  ("https://json-schema.org/draft/2020-12/meta/core", "2020-12/core.json"),
  (
    "https://json-schema.org/draft/2020-12/meta/applicator", "2020-12/applicator.json",
  ),
  (
    "https://json-schema.org/draft/2020-12/meta/validation", "2020-12/validation.json",
  ),
  (
    "https://json-schema.org/draft/2020-12/meta/meta-data", "2020-12/meta-data.json",
  ),
  (
    "https://json-schema.org/draft/2020-12/meta/format-annotation", "2020-12/format-annotation.json",
  ),
  (
    "https://json-schema.org/draft/2020-12/meta/format-assertion", "2020-12/format-assertion.json",
  ),
  ("https://json-schema.org/draft/2020-12/meta/content", "2020-12/content.json"),
  (
    "https://json-schema.org/draft/2020-12/meta/unevaluated", "2020-12/unevaluated.json",
  ),
]

///|
/// Read one directory of remote documents into `remotes`, and its directories.
fn gather(
  directory : String,
  prefix : String,
  remotes : Map[String, Json],
) -> Unit {
  let entries = @fs.read_dir(directory) catch { _ => return }
  for entry in entries {
    let path = directory + "/" + entry
    let uri = prefix + "/" + entry
    let folder = (@fs.is_dir(path) : Bool) catch { _ => false }
    if folder {
      gather(path, uri, remotes)
    } else if entry.has_suffix(".json") {
      let text = @fs.read_file_to_string(path) catch { _ => continue }
      match (@json.loads(text) catch { _ => continue }) {
        document => remotes[uri] = document
      }
    }
  }
}

///|
/// The instance a case turned on, so that a failure names what it was about.
fn debug_text(value : Json) -> String {
  let out = StringBuilder()
  write_json(value, out)
  out.to_string()
}

///|
fn write_json(value : Json, out : StringBuilder) -> Unit {
  match value {
    Null => out.write_string("null")
    True => out.write_string("true")
    False => out.write_string("false")
    Number(number, ..) => out.write_string(number.to_string())
    String(text) => {
      out.write_char('"')
      out.write_string(text)
      out.write_char('"')
    }
    Array(items) => {
      out.write_char('[')
      for index, item in items {
        if index > 0 {
          out.write_char(',')
        }
        write_json(item, out)
      }
      out.write_char(']')
    }
    Object(fields) => {
      out.write_char('{')
      let mut more = false
      for name, held in fields {
        if more {
          out.write_char(',')
        }
        more = true
        out.write_string("\"" + name + "\":")
        write_json(held, out)
      }
      out.write_char('}')
    }
  }
}

///|
fn text_of(value : Json?) -> String {
  match value {
    Some(String(text)) => text
    _ => "?"
  }
}

///|
/// The output tests: for each case, produce the report in the format the case
/// names and validate it against the schema the case gives.
///
/// The schema in the case is a schema, so the check is the same validator
/// reading a different document — and the `$ref` it opens with,
/// `/draft/2020-12/output/schema`, resolves against the case's own `$id` into the
/// published output schema, which this harness feeds in as a remote.
fn measure_outputs(
  directory : String,
  draft : @moonschema.Draft,
  remotes : Map[String, Json],
) -> Tally {
  let tally = { passed: 0, failed: 0, first: [], }
  let root = suite + "/output-tests/" + directory + "/content"
  let files = (@fs.read_dir(root) catch {
    _ => {
      tally.first.push("no such directory: " + root)
      return tally
    }
  }).to_owned()
  files.sort()
  for file in files {
    if !file.has_suffix(".json") {
      continue
    }
    let text = @fs.read_file_to_string(root + "/" + file) catch {
      _ => continue
    }
    let groups = @json.loads(text) catch {
      _ => {
        tally.first.push(file + ": unreadable")
        continue
      }
    }
    guard groups is Array(all) else { continue }
    for group in all {
      guard group is Object(fields) else { continue }
      let title = text_of(fields.get("description"))
      let schema = match fields.get("schema") {
        Some(found) => found
        None => continue
      }
      let cases = match fields.get("tests") {
        Some(Array(found)) => found
        _ => continue
      }
      let validator = @moonschema.Schema::new(schema, draft~) catch {
        error => {
          tally.first.push(
            file + " / " + title + ": schema refused: " + error.to_string(),
          )
          continue
        }
      }
      for instance in cases {
        guard instance is Object(one) else { continue }
        let data = match one.get("data") {
          Some(found) => found
          None => Json::null()
        }
        let wanted = match one.get("output") {
          Some(Object(found)) => found
          _ => continue
        }
        for name, expectation in wanted {
          let format = match output_of(name) {
            Some(found) => found
            None => continue
          }
          let report = validator.report(data, output=format)
          let produced = report.to_json()
          let check = @moonschema.Schema::new(
            expectation,
            draft~,
            remotes~,
            format=true,
          ) catch {
            error => {
              tally.failed = tally.failed + 1
              tally.first.push(
                file +
                " / " +
                title +
                ": output schema refused: " +
                error.to_string(),
              )
              continue
            }
          }
          if check.valid(produced) {
            tally.passed = tally.passed + 1
          } else {
            tally.failed = tally.failed + 1
            if tally.first.length() < 80 {
              tally.first.push(
                file +
                " / " +
                title +
                " / " +
                text_of(one.get("description")) +
                " / " +
                name +
                ": " +
                debug_text(produced) +
                " was refused: " +
                check
                .faults(produced)
                .map(fn(fault) { fault.to_string() })
                .join("; "),
              )
            }
          }
        }
      }
    }
  }
  tally
}

///|
/// The name a case writes a format by.
fn output_of(name : String) -> @moonschema.Output? {
  match name {
    "flag" => Some(Flag)
    "basic" => Some(Basic)
    "detailed" => Some(Detailed)
    "verbose" => Some(Verbose)
    _ => None
  }
}
