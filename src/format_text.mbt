// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The formats that name a place inside a document or a value of a fixed shape:
// the two JSON Pointers (RFC 6901 and the relative form), the UUID (RFC 4122)
// and the regular expression (ECMA-262).

///|
/// A JSON Pointer: the empty string, which points at the whole document, or a
/// run of `/`-prefixed tokens in which `~` may only appear as `~0` or `~1`.
///
/// Everything else is a token character, including the control characters a
/// URI could never carry: a pointer is not a URI, and a pointer that arrived
/// inside one is percent-coded before it gets here.
fn is_json_pointer(text : String) -> Bool {
  let view = text[:]
  if view.length() == 0 {
    return true
  }
  guard view[0] == '/' else { return false }
  let mut i = 0
  while i < view.length() {
    if view[i] == '~' {
      guard i + 1 < view.length() else { return false }
      guard view[i + 1] == '0' || view[i + 1] == '1' else { return false }
      i = i + 2
      continue
    }
    i = i + 1
  }
  true
}

///|
/// A relative JSON Pointer: a non-negative integer, then either `#` — the
/// whole document above this one — or a JSON Pointer.
///
/// No leading zero, because `01/a` is a number nobody writes.
fn is_relative_json_pointer(text : String) -> Bool {
  let view = text[:]
  let mut i = 0
  while i < view.length() && digit_at(view, i) >= 0 {
    i = i + 1
  }
  guard i > 0 else { return false }
  guard i == 1 || view[0] != '0' else { return false }
  if i == view.length() {
    return true
  }
  if view[i] == '#' {
    // `#` is the whole reference and takes nothing after it.
    return i + 1 == view.length()
  }
  is_json_pointer(view[i:].to_owned())
}

///|
/// A UUID in its canonical textual form: five groups of hexadecimal digits,
/// 8-4-4-4-12, joined by hyphens. Either case, and no braces and no `urn:`
/// — those are other formats' business.
fn is_uuid(text : String) -> Bool {
  guard text.length() == 36 else { return false }
  for index in [8, 13, 18, 23] {
    guard text[index] == '-' else { return false }
  }
  for i = 0; i < 36; i = i + 1 {
    if i == 8 || i == 13 || i == 18 || i == 23 {
      continue
    }
    guard hex_value(text[i].to_int()) >= 0 else { return false }
  }
  true
}

///|
/// An ECMA-262 regular expression, which is the dialect `pattern` is read in
/// (§6.3.3): one reading of a pattern, so that a schema cannot mean one thing
/// to `pattern` and another to `format: regex`.
fn is_regex(text : String) -> Bool {
  let _ = @moonregex.compile(
    text,
    flags=@moonregex.unicode,
    dialect=@moonregex.ecma262,
  ) catch {
    _ => return false
  }
  groups_are_ecma(text)
}

///|
/// Whether every `(?` in a pattern introduces a group form ECMA-262 has.
///
/// The grammar has five — `(?:`, `(?=`, `(?!`, `(?<=`, `(?<!` — and a named
/// capture, `(?<name>`. A reader that accepts more than those accepts a pattern
/// written for another dialect and then matches it differently, which is the one
/// failure a `pattern` must not have.
fn groups_are_ecma(text : String) -> Bool {
  let points : Array[Int32] = []
  for c in text {
    points.push(c.to_int())
  }
  let mut i = 0
  let mut in_class = false
  while i < points.length() {
    let code = points[i]
    if code == 0x5C {
      // An escape, including `\(`, which is not a group.
      i = i + 2
      continue
    }
    if in_class {
      if code == 0x5D {
        in_class = false
      }
      i = i + 1
      continue
    }
    if code == 0x5B {
      in_class = true
      i = i + 1
      continue
    }
    if code == 0x28 && i + 1 < points.length() && points[i + 1] == 0x3F {
      guard i + 2 < points.length() else { return false }
      let next = points[i + 2]
      let assertion = next == 0x3A || next == 0x3D || next == 0x21
      if !assertion {
        guard next == 0x3C && i + 3 < points.length() else { return false }
        // `(?<=` and `(?<!` look behind, and `(?<name>` names a capture.
        let after = points[i + 3]
        if after != 0x3D && after != 0x21 {
          guard is_name_start(after) else { return false }
        }
      }
    }
    i = i + 1
  }
  true
}

///|
fn is_name_start(code : Int32) -> Bool {
  (code >= 0x41 && code <= 0x5A) ||
  (code >= 0x61 && code <= 0x7A) ||
  code == 0x5F ||
  code == 0x24
}
