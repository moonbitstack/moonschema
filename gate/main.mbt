// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Where the suite is, relative to this module.
let suite : String = "../suite"

///|
/// The five versions, each with the directory the suite keeps it in.
let versions : Array[(String, @moonschema.Draft)] = [
  ("draft4", Draft4),
  ("draft6", Draft6),
  ("draft7", Draft7),
  ("draft2019-09", Draft2019),
  ("draft2020-12", Draft2020),
]

///|
/// The cases that do not pass, and why.
///
/// None. Every required case of every version passes, and the gate fails if
/// that stops being true — or if one named here starts passing, because then
/// this list would be describing something that is no longer so.
let known : Array[String] = []

///|
/// What one version's run came to.
struct Tally {
  mut passed : Int
  mut failed : Int
  first : Array[String]
}

///|
/// Run every case of every version and print what passed.
///
/// A case that fails says which file, group and case it was, because a count
/// that only goes up says nothing about which rule went wrong.
fn main {
  let remotes = load_remotes()
  let mut total = 0
  let mut wrong = 0
  for version in versions {
    let (directory, draft) = version
    let tally = measure(directory, draft, remotes)
    total = total + tally.passed + tally.failed
    wrong = wrong + tally.failed
    println(
      directory.pad_start(13, ' ') +
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
/// Every file of one version, run.
fn measure(
  directory : String,
  draft : @moonschema.Draft,
  remotes : Map[String, Json],
) -> Tally {
  let tally = { passed: 0, failed: 0, first: [] }
  let root = suite + "/tests/" + directory
  let files = @fs.read_dir(root) catch {
    _ => {
      tally.first.push("no such directory: " + root)
      return tally
    }
  }
  files.sort()
  for file in files {
    // `optional/` is a directory, and what is in it are the cases the
    // specification itself calls optional.
    if !file.has_suffix(".json") {
      continue
    }
    let text = @fs.read_file_to_string(root + "/" + file) catch { _ => continue }
    let groups = @json.parse(text) catch {
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
      let validator = @moonschema.Schema::new(schema, draft~, remotes~) catch {
        error => {
          for _ in cases {
            tally.failed = tally.failed + 1
          }
          if tally.first.length() < 60 {
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
          if tally.first.length() < 60 {
            tally.first.push(
              file +
              " / " +
              title +
              " / " +
              text_of(one.get("description")) +
              ": wanted " +
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
/// The documents a `$ref` in the suite reaches, under the URIs it reaches them
/// by. The suite serves `remotes/` at `http://localhost:1234/`.
fn load_remotes() -> Map[String, Json] {
  let remotes : Map[String, Json] = Map::Map([])
  gather(suite + "/remotes", "http://localhost:1234", remotes)
  // The metaschemas, which a schema is entitled to reference and which the
  // validator itself does not carry: a caller feeds it what it may reach, and
  // here the caller is this harness. They are the published documents, kept in
  // `meta/` because they are frozen and fetching them would be I/O in a test.
  for name in meta_documents {
    let text = @fs.read_file_to_string("meta/" + name.1) catch { _ => continue }
    match (@json.parse(text) catch { _ => continue }) {
      document => remotes[name.0] = document
    }
  }
  remotes
}

///|
/// Each metaschema, by the URI a schema references it as.
let meta_documents : Array[(String, String)] = [
  ("http://json-schema.org/draft-04/schema", "draft-04.json"),
  ("http://json-schema.org/draft-06/schema", "draft-06.json"),
  ("http://json-schema.org/draft-07/schema", "draft-07.json"),
  ("https://json-schema.org/draft/2019-09/schema", "2019-09.json"),
  ("https://json-schema.org/draft/2019-09/meta/core", "2019-09-core.json"),
  (
    "https://json-schema.org/draft/2019-09/meta/applicator",
    "2019-09-applicator.json",
  ),
  (
    "https://json-schema.org/draft/2019-09/meta/validation",
    "2019-09-validation.json",
  ),
  (
    "https://json-schema.org/draft/2019-09/meta/meta-data",
    "2019-09-meta-data.json",
  ),
  ("https://json-schema.org/draft/2019-09/meta/format", "2019-09-format.json"),
  ("https://json-schema.org/draft/2019-09/meta/content", "2019-09-content.json"),
  ("https://json-schema.org/draft/2020-12/schema", "2020-12.json"),
  ("https://json-schema.org/draft/2020-12/meta/core", "2020-12-core.json"),
  (
    "https://json-schema.org/draft/2020-12/meta/applicator",
    "2020-12-applicator.json",
  ),
  (
    "https://json-schema.org/draft/2020-12/meta/validation",
    "2020-12-validation.json",
  ),
  (
    "https://json-schema.org/draft/2020-12/meta/meta-data",
    "2020-12-meta-data.json",
  ),
  (
    "https://json-schema.org/draft/2020-12/meta/format-annotation",
    "2020-12-format-annotation.json",
  ),
  ("https://json-schema.org/draft/2020-12/meta/content", "2020-12-content.json"),
  (
    "https://json-schema.org/draft/2020-12/meta/unevaluated",
    "2020-12-unevaluated.json",
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
      match (@json.parse(text) catch { _ => continue }) {
        document => remotes[uri] = document
      }
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
