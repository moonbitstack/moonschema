// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The formats that name a resource: `uri`, `uri-reference` and their
// internationalised twins (RFC 3986 and RFC 3987), and `uri-template`
// (RFC 6570).
//
// moonurl reads a reference into its five components — the scheme, the
// authority, the path, the query and the fragment — including the bracket
// around an IP literal and the one `@` that divides a userinfo from a host.
// What is left for a format to say is whether the characters in each component
// are ones the grammar allows, which is a different question from where the
// components end, and is the one an assertion is asked.

///|
/// Whether `text` is a URI: an absolute one, so a scheme is required.
fn is_uri(text : String, reach : Reach) -> Bool {
  match check_reference(text, reach) {
    Some(absolute) => absolute
    None => false
  }
}

///|
/// Whether `text` is a URI reference: a URI, or a relative reference, or the
/// empty string, which is the reference to this very document.
fn is_uri_reference(text : String, reach : Reach) -> Bool {
  check_reference(text, reach) is Some(_)
}

///|
/// The reference read and checked, answering whether it named a scheme.
///
/// `None` is not a reference at all; `Some(false)` is a relative one.
fn check_reference(text : String, reach : Reach) -> Bool? {
  let url = @moonurl.Url::decode(text) catch { _ => return None }
  let absolute = url.scheme is Some(_)
  if !absolute {
    // A relative reference's first path segment may not hold a colon: that is
    // how a reader tells `1:b` from a scheme, and `./this:that` from a mistake.
    let head = first_segment(url.path)
    if head.contains(":") {
      return None
    }
  }
  match url.userinfo {
    Some(info) => if !component_ok(info, Userinfo, reach) { return None }
    None => ()
  }
  match url.host {
    Some(host) => if !host_ok(host, reach) { return None }
    None => ()
  }
  if !component_ok(url.path, Path, reach) {
    return None
  }
  match url.query {
    Some(query) => if !component_ok(query, Query, reach) { return None }
    None => ()
  }
  match url.fragment {
    Some(fragment) =>
      if !component_ok(fragment, Fragment, reach) {
        return None
      }
    None => ()
  }
  Some(absolute)
}

///|
fn first_segment(path : String) -> String {
  for i = 0; i < path.length(); i = i + 1 {
    if path[i] == '/' {
      return path[0:i].to_owned()
    }
  }
  path
}

///|
/// Which component a run of characters is in, because each allows a different
/// set: a sub-delimiter belongs in a path and not in a host.
priv enum Part {
  Userinfo
  Host
  Path
  Query
  Fragment
}

///|
/// Whether every character in a component is one the grammar gives it, and
/// every `%` introduces two hexadecimal digits.
fn component_ok(text : String, part : Part, reach : Reach) -> Bool {
  // Code points, not code units: a supplementary-plane character is one
  // character to the grammar and two to a reader that counts units.
  let points : Array[Int32] = []
  for c in text {
    points.push(c.to_int())
  }
  let mut i = 0
  while i < points.length() {
    let code = points[i]
    if code == 0x25 {
      guard i + 2 < points.length() else { return false }
      guard hex_value(points[i + 1]) >= 0 && hex_value(points[i + 2]) >= 0 else {
        return false
      }
      i = i + 3
      continue
    }
    if code > 0x7F {
      // RFC 3987 puts a range of non-ASCII into each component and forbids the
      // rest; RFC 3986 has no non-ASCII at all. The private planes belong to a
      // path, a query and a fragment, and to no host.
      guard reach is International &&
        (is_ucschar(code) || (wide_private(part) && is_iprivate(code))) else {
        return false
      }
    } else {
      let allowed = match part {
        Userinfo => is_unreserved(code) || is_sub_delim(code) || code == 0x3A
        Host => is_unreserved(code) || is_sub_delim(code)
        Path => is_pchar(code) || code == 0x2F
        Query | Fragment => is_pchar(code) || code == 0x2F || code == 0x3F
      }
      guard allowed else { return false }
    }
    i = i + 1
  }
  true
}

///|
/// Whether a host is a reg-name, an IPv4 address or an IP literal.
///
/// moonurl hands back an IP literal without its brackets, which leaves the
/// colon as the only sign that there were any — and an unbracketed host cannot
/// hold one, since it would have been read as the port.
fn host_ok(host : String, reach : Reach) -> Bool {
  if host.contains(":") {
    return is_ipv6(host)
  }
  if host.length() > 0 && (host[0] == 'v' || host[0] == 'V') {
    if is_ipvfuture(host) {
      return true
    }
  }
  component_ok(host, Host, reach)
}

///|
/// An IPvFuture literal: `v`, hexadecimal, `.`, and the characters a URI may
/// carry (RFC 3986 §3.2.2).
fn is_ipvfuture(text : String) -> Bool {
  let view = text[:]
  guard view.length() > 3 else { return false }
  let mut i = 1
  let mut digits = 0
  while i < view.length() && hex_value(view[i].to_int()) >= 0 {
    i = i + 1
    digits = digits + 1
  }
  guard digits > 0 && i < view.length() && view[i] == '.' else { return false }
  for j = i + 1; j < view.length(); j = j + 1 {
    let code = view[j].to_int()
    guard is_unreserved(code) || is_sub_delim(code) || code == 0x3A else {
      return false
    }
  }
  true
}

///|
/// Which components RFC 3987 lets a private-use character into.
fn wide_private(part : Part) -> Bool {
  match part {
    Userinfo | Host => false
    Path | Query | Fragment => true
  }
}

///|
fn is_unreserved(code : Int32) -> Bool {
  (code >= 0x41 && code <= 0x5A) ||
  (code >= 0x61 && code <= 0x7A) ||
  (code >= 0x30 && code <= 0x39) ||
  code == 0x2D ||
  code == 0x2E ||
  code == 0x5F ||
  code == 0x7E
}

///|
fn is_sub_delim(code : Int32) -> Bool {
  code == 0x21 ||
  code == 0x24 ||
  code == 0x26 ||
  code == 0x27 ||
  code == 0x28 ||
  code == 0x29 ||
  code == 0x2A ||
  code == 0x2B ||
  code == 0x2C ||
  code == 0x3B ||
  code == 0x3D
}

///|
fn is_pchar(code : Int32) -> Bool {
  is_unreserved(code) || is_sub_delim(code) || code == 0x3A || code == 0x40
}

///|
/// RFC 3987 §2.2's `ucschar`: the non-ASCII a URI may carry once it becomes an
/// identifier rather than a locator. The private ranges are not here — they
/// belong to `iprivate`, which a host may not hold.
fn is_ucschar(code : Int32) -> Bool {
  (code >= 0xA0 && code <= 0xD7FF) ||
  (code >= 0xF900 && code <= 0xFDCF) ||
  (code >= 0xFDF0 && code <= 0xFFEF) ||
  (code >= 0x10000 && code <= 0x1FFFD) ||
  (code >= 0x20000 && code <= 0x2FFFD) ||
  (code >= 0x30000 && code <= 0x3FFFD) ||
  (code >= 0x40000 && code <= 0x4FFFD) ||
  (code >= 0x50000 && code <= 0x5FFFD) ||
  (code >= 0x60000 && code <= 0x6FFFD) ||
  (code >= 0x70000 && code <= 0x7FFFD) ||
  (code >= 0x80000 && code <= 0x8FFFD) ||
  (code >= 0x90000 && code <= 0x9FFFD) ||
  (code >= 0xA0000 && code <= 0xAFFFD) ||
  (code >= 0xB0000 && code <= 0xBFFFD) ||
  (code >= 0xC0000 && code <= 0xCFFFD) ||
  (code >= 0xD0000 && code <= 0xDFFFD) ||
  (code >= 0xE1000 && code <= 0xEFFFD)
}

///|
/// An RFC 6570 template is read by moonurl, which is the same library that
/// expands one: the syntax of a template and the meaning of its expressions
/// are one grammar, and splitting them across two readings is how the two come
/// to disagree.
fn is_uri_template(text : String) -> Bool {
  let points : Array[Int32] = []
  for c in text {
    points.push(c.to_int())
  }
  let mut i = 0
  while i < points.length() {
    if points[i] == 0x7B {
      guard template_expression(points, i) is Some(after) else { return false }
      i = after
    } else {
      guard template_literal(points, i) is Some(after) else { return false }
      i = after
    }
  }
  true
}

///|
/// One literal character, or a percent-coded one, and where it ends.
///
/// The grammar's set, with the apostrophe the suite keeps: `!!!` — RFC 6570 §2
/// says a literal is anything a URI may carry, and the ABNF's list leaves `'`
/// out of a range it otherwise covers.
fn template_literal(points : Array[Int32], from : Int32) -> Int32? {
  let code = points[from]
  if code == 0x25 {
    guard from + 2 < points.length() else { return None }
    guard hex_value(points[from + 1]) >= 0 && hex_value(points[from + 2]) >= 0 else {
      return None
    }
    return Some(from + 3)
  }
  let allowed = (code >= 0x41 && code <= 0x5A) ||
    (code >= 0x61 && code <= 0x7A) ||
    (code >= 0x30 && code <= 0x39) ||
    code == 0x21 ||
    (code >= 0x23 && code <= 0x24) ||
    (code >= 0x26 && code <= 0x27) ||
    (code >= 0x28 && code <= 0x3B) ||
    code == 0x3D ||
    (code >= 0x3F && code <= 0x5B) ||
    code == 0x5D ||
    code == 0x5F ||
    code == 0x7E ||
    (code >= 0xA0 && is_ucschar(code)) ||
    is_iprivate(code)
  if allowed {
    Some(from + 1)
  } else {
    None
  }
}

///|
/// `{` operator? variable-list `}`, and where it ends.
fn template_expression(points : Array[Int32], from : Int32) -> Int32? {
  let mut i = from + 1
  guard i < points.length() else { return None }
  match points[i] {
    // The seven operators of RFC 6570 §2.2.
    0x2B | 0x23 | 0x2E | 0x2F | 0x3B | 0x3F | 0x26 => i = i + 1
    _ => ()
  }
  let mut specs = 0
  while true {
    i = match template_varspec(points, i) {
      Some(after) => after
      None => return None
    }
    specs = specs + 1
    if i < points.length() && points[i] == 0x2C {
      i = i + 1
    } else {
      break
    }
  }
  ignore(specs)
  guard i < points.length() && points[i] == 0x7D else { return None }
  Some(i + 1)
}

///|
/// One `varspec`: a name of name characters, then an optional prefix or an
/// explosion.
fn template_varspec(points : Array[Int32], from : Int32) -> Int32? {
  let mut i = from
  let mut letters = 0
  while i < points.length() {
    let code = points[i]
    if is_varchar(code) {
      i = i + 1
      letters = letters + 1
      continue
    }
    if code == 0x25 {
      // A percent-coded name character.
      guard i + 2 < points.length() &&
        hex_value(points[i + 1]) >= 0 &&
        hex_value(points[i + 2]) >= 0 else {
        return None
      }
      i = i + 3
      letters = letters + 1
      continue
    }
    if code == 0x2E {
      // A dot joins two name characters, and needs one after it: `a..b` is not
      // a name, and neither is `a.`.
      i = i + 1
      guard i < points.length() && is_varchar(points[i]) else { return None }
      continue
    }
    break
  }
  guard letters > 0 else { return None }
  if i < points.length() && points[i] == 0x3A {
    // A prefix length: one to four digits, and no leading zero.
    i = i + 1
    guard i < points.length() else { return None }
    let first = points[i]
    guard first >= 0x31 && first <= 0x39 else { return None }
    let mut digits = 1
    i = i + 1
    while i < points.length() &&
          digits < 4 &&
          points[i] >= 0x30 &&
          points[i] <= 0x39 {
      i = i + 1
      digits = digits + 1
    }
    return Some(i)
  }
  if i < points.length() && points[i] == 0x2A {
    return Some(i + 1)
  }
  Some(i)
}

///|
fn is_varchar(code : Int32) -> Bool {
  (code >= 0x41 && code <= 0x5A) ||
  (code >= 0x61 && code <= 0x7A) ||
  (code >= 0x30 && code <= 0x39) ||
  code == 0x5F
}

///|
/// RFC 3987 §2.2's `iprivate`, which a template literal may carry and a path
/// may not.
fn is_iprivate(code : Int32) -> Bool {
  (code >= 0xE000 && code <= 0xF8FF) ||
  (code >= 0xF0000 && code <= 0xFFFFD) ||
  (code >= 0x100000 && code <= 0x10FFFD)
}
