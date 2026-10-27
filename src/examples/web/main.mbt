// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The engine the documentation site runs in the browser: one call in, one JSON
// document out. It exists so that the page in `docs/` validates with the same
// code the package ships, rather than with a description of it.

///|
/// Validate `instance` against `schema` — both JSON text — at the version
/// `draft` names, and answer the result as a JSON document.
///
/// The answer is `{ status, side, draft, valid, faults, error }`. `status` is
/// `"ok"` when a validation happened, `"json"` when one of the two texts is not
/// JSON, and `"refused"` when the schema names a version this does not know.
/// `side` says which of the two texts that was.
pub fn check(schema : String, instance : String, draft : String) -> String {
  let document = @json.parse(schema[:]) catch {
    error => return fault_of("json", "schema", error.to_string())
  }
  let value = @json.parse(instance[:]) catch {
    error => return fault_of("json", "instance", error.to_string())
  }
  // The version is named by its `$schema` URI, which is also the value the
  // page's menu carries: unknown means the preset, exactly as `Schema::new`
  // treats a document that names nothing.
  let version = match @moonschema.Draft::of(draft[:]) {
    Some(named) => named
    None => @moonschema.draft
  }
  // A document that names a version is read at the version it names, so that is
  // the one to report: the menu is only what a silent document falls back to.
  let effective = match document {
    Object(members) =>
      match members.get("$schema") {
        Some(String(uri)) =>
          match @moonschema.Draft::of(uri[:]) {
            Some(named) => named
            None => version
          }
        _ => version
      }
    _ => version
  }
  let read = Ok(@moonschema.Schema::new(document, draft=version)) catch {
    error => Err(error)
  }
  match read {
    Ok(ready) => {
      let faults = ready.faults(value)
      let listed = StringBuilder()
      let mut written = false
      for fault in faults {
        if written {
          listed.write_string(",")
        }
        written = true
        listed.write_string(
          "{\"at\":" +
          quote(fault.at) +
          ",\"schemaAt\":" +
          quote(fault.schema_at) +
          ",\"keyword\":" +
          quote(fault.keyword) +
          ",\"message\":" +
          quote(fault.message) +
          "}",
        )
      }
      "{\"status\":\"ok\",\"side\":\"\",\"draft\":" +
      quote(effective.to_string()) +
      ",\"valid\":" +
      (faults.length() == 0).to_string() +
      ",\"faults\":[" +
      listed.to_string() +
      "],\"error\":\"\"}"
    }
    Err(error) =>
      "{\"status\":\"refused\",\"side\":\"schema\",\"draft\":" +
      quote(effective.to_string()) +
      ",\"valid\":false,\"faults\":[],\"error\":" +
      quote(error.to_string()) +
      "}"
  }
}

///|
/// The answer for a request that never reached a validation.
fn fault_of(status : String, side : String, message : String) -> String {
  "{\"status\":" +
  quote(status) +
  ",\"side\":" +
  quote(side) +
  ",\"draft\":\"\",\"valid\":false,\"faults\":[],\"error\":" +
  quote(message) +
  "}"
}

///|
/// A string as a JSON string literal, quotes included.
///
/// Only what JSON requires is escaped: the two characters a string cannot hold
/// raw and the control characters, which are written as `\uXXXX`. Everything
/// else — CJK, emoji — travels as it is, because JSON is UTF-8.
fn quote(text : String) -> String {
  let out = StringBuilder()
  out.write_char('"')
  for c in text {
    let code = c.to_int()
    if c == '"' {
      out.write_string("\\\"")
    } else if c == '\\' {
      out.write_string("\\\\")
    } else if code < 0x20 {
      out.write_string("\\u00")
      out.write_char(hex((code >> 4) & 0xF))
      out.write_char(hex(code & 0xF))
    } else {
      out.write_char(c)
    }
  }
  out.write_char('"')
  out.to_string()
}

///|
/// One hexadecimal digit, in the case JSON spells escapes in.
fn hex(value : Int32) -> Char {
  if value < 10 {
    (0x30 + value).unsafe_to_char()
  } else {
    (0x61 + value - 10).unsafe_to_char()
  }
}
