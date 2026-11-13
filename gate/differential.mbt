// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The differential run: the same documents and instances judged by two other
// implementations, replayed here.
//
// A validator has no wire format to exchange with another one, so what stands in
// for interoperability is agreement — same schema, same instance, same verdict.
// The cases come from `differential/vectors.json`, which
// `scripts/gen_differential_vectors.py` writes from Ajv and python-jsonschema and
// keeps only where those two agree. The file is committed, so the run here needs
// neither node nor Python: it needs the verdicts and this library.

///|
/// The name of the vector file, relative to this module.
let vectors : String = "differential/vectors.json"

///|
/// Every kept case of the differential file, run.
///
/// The file states how many cases it holds, and a run that reads a different
/// number fails: a vector file cut short by a bad edit would otherwise pass by
/// having nothing left to disagree with.
fn measure_differential() -> Tally {
  let tally = { passed: 0, failed: 0, first: [], }
  let text = @fs.read_file_to_string(vectors) catch {
    _ => {
      tally.first.push("no such file: " + vectors)
      return tally
    }
  }
  let document = @json.loads(text) catch {
    _ => {
      tally.first.push(vectors + ": unreadable")
      return tally
    }
  }
  guard document is Object(fields) else {
    tally.first.push(vectors + ": not an object")
    return tally
  }
  let cases = match fields.get("cases") {
    Some(Array(kept)) => kept
    _ => {
      tally.first.push(vectors + ": no cases")
      return tally
    }
  }
  let stated = match fields.get("kept") {
    Some(Number(count, ..)) => count.to_int()
    _ => -1
  }
  if stated != cases.length() {
    tally.first.push(
      "the file states " +
      stated.to_string() +
      " cases and holds " +
      cases.length().to_string(),
    )
    return tally
  }
  // The count is kept as the loop runs rather than read off the array at the
  // end: a loop that visits fewer cases than the file states is the failure this
  // guard exists for, and an array that was never cut cannot see it.
  let mut seen = 0
  for entry in cases {
    seen = seen + 1
    guard entry is Object(one) else {
      tally.failed = tally.failed + 1
      continue
    }
    let schema = match one.get("schema") {
      Some(found) => found
      None => {
        tally.failed = tally.failed + 1
        continue
      }
    }
    let data = match one.get("data") {
      Some(found) => found
      None => Json::null()
    }
    let wanted = one.get("valid") is Some(True)
    let draft = match draft_of(schema) {
      Some(found) => found
      None => {
        tally.failed = tally.failed + 1
        if tally.first.length() < 80 {
          tally.first.push(debug_text(schema) + ": no version this reads")
        }
        continue
      }
    }
    // The references judged `format` as an annotation, which is the default
    // everywhere before v1; saying so keeps a future default from moving the
    // verdicts under the vectors.
    let validator = @moonschema.Schema::new(schema, draft~, format=false) catch {
      error => {
        tally.failed = tally.failed + 1
        if tally.first.length() < 80 {
          tally.first.push(
            debug_text(schema) + ": refused: " + error.to_string(),
          )
        }
        continue
      }
    }
    let got = validator.valid(data)
    if got == wanted {
      tally.passed = tally.passed + 1
    } else {
      tally.failed = tally.failed + 1
      if tally.first.length() < 80 {
        tally.first.push(
          debug_text(schema) +
          " / " +
          debug_text(data) +
          ": the references say " +
          wanted.to_string() +
          ", got " +
          got.to_string(),
        )
      }
    }
  }
  if seen != stated {
    tally.failed = tally.failed + 1
    tally.first.push(
      "the file states " +
      stated.to_string() +
      " cases and " +
      seen.to_string() +
      " were run",
    )
  }
  tally
}

///|
/// The version a case's own `$schema` names.
fn draft_of(schema : Json) -> @moonschema.Draft? {
  match schema {
    Object(members) =>
      match members.get("$schema") {
        Some(String(uri)) => @moonschema.Draft::of(uri[:])
        _ => None
      }
    _ => None
  }
}
