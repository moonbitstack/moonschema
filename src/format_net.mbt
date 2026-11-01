// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The formats that name a host or an address: the two IP literals, the two
// hostnames, and the two mailboxes.
//
// A hostname is a name in the DNS as IDNA2008 defines it, and the tables that
// decide which code points a label may hold are generated from RFC 5892 into
// `idna_classes.mbt`. The mapping, the normalisation and the Punycode are
// moonurl's: a U-label and its A-label are one name written two ways, and this
// asks the same library that writes them which is which.

///|
/// Which of the two spellings a format names: the ASCII one every resolver in
/// the world reads, or the international one that carries its own script.
priv enum Reach {
  Ascii
  International
}

///|
/// Whether a code point is in a table of inclusive ranges, by bisection.
fn in_ranges(ranges : Array[Int32], code : Int32) -> Bool {
  let mut low = 0
  let mut high = ranges.length() / 2 - 1
  while low <= high {
    let middle = (low + high) / 2
    let start = ranges[middle * 2]
    let end = ranges[middle * 2 + 1]
    if code < start {
      high = middle - 1
    } else if code > end {
      low = middle + 1
    } else {
      return true
    }
  }
  false
}

///|
fn in_span(code : Int32, low : Int32, high : Int32) -> Bool {
  code >= low && code <= high
}

///|
fn hex_value(code : Int32) -> Int32 {
  if code >= 0x30 && code <= 0x39 {
    code - 0x30
  } else if code >= 0x41 && code <= 0x46 {
    code - 0x41 + 10
  } else if code >= 0x61 && code <= 0x66 {
    code - 0x61 + 10
  } else {
    -1
  }
}

///|
/// An RFC 2673 dotted quad, as RFC 3986 §3.2.2 narrowed it: four decimal
/// octets, each 0 to 255, and no leading zero — a `010` is an octal spelling
/// some parsers honour, so it is not read here at all.
fn is_ipv4(text : String) -> Bool {
  let view = text[:]
  let mut i = 0
  for part = 0; part < 4; part = part + 1 {
    let start = i
    let mut value = 0
    while i < view.length() && digit_at(view, i) >= 0 {
      value = value * 10 + digit_at(view, i)
      i = i + 1
    }
    let width = i - start
    guard width > 0 && width <= 3 else { return false }
    guard value <= 255 else { return false }
    guard width == 1 || view[start] != '0' else { return false }
    if part < 3 {
      guard i < view.length() && view[i] == '.' else { return false }
      i = i + 1
    }
  }
  i == view.length()
}

///|
/// An RFC 4291 address: up to eight groups of one to four hexadecimal digits,
/// and at most one `::` standing for the groups left out.
fn is_ipv6(text : String) -> Bool {
  let view = text[:]
  let n = view.length()
  guard n > 0 else { return false }
  let mut i = 0
  let mut groups = 0
  let mut gap = false
  // A leading `::` is the elision, and `::` alone is the address of zeros.
  if view[0] == ':' {
    guard n > 1 && view[1] == ':' else { return false }
    gap = true
    i = 2
    if i == n {
      return true
    }
  }
  while i < n {
    let start = i
    let mut width = 0
    while i < n && hex_value(view[i].to_int()) >= 0 {
      i = i + 1
      width = width + 1
    }
    guard width > 0 else { return false }
    if i < n && view[i] == '.' {
      // What was read as hexadecimal is the first octet of an embedded IPv4
      // address, which stands for the last two groups.
      guard is_ipv4(view[start:].to_owned()) else { return false }
      groups = groups + 2
      i = n
      break
    }
    guard width <= 4 else { return false }
    groups = groups + 1
    if i == n {
      break
    }
    guard view[i] == ':' else { return false }
    if i + 1 < n && view[i + 1] == ':' {
      guard !gap else { return false }
      gap = true
      i = i + 2
      if i == n {
        break
      }
    } else {
      i = i + 1
      guard i < n else { return false }
    }
  }
  // The elision stands for at least one group, so it cannot be there when all
  // eight are written out.
  if gap {
    groups < 8
  } else {
    groups == 8
  }
}

///|
/// Whether every code point is ASCII, which `hostname` and `email` are and
/// their IDN twins are not.
fn is_ascii(text : String) -> Bool {
  for c in text {
    if c.to_int() > 0x7F {
      return false
    }
  }
  true
}

///|
/// An RFC 1123 host name: labels of letters, digits and hyphens, joined by dots,
/// none of them empty, longer than 63, or beginning or ending with a hyphen.
///
/// An `xn--` label is an A-label, and an A-label is only a host name if what it
/// stands for is one: it has to decode to a label IDNA2008 permits, and encode
/// back to itself, because two spellings of one name is one name too many.
fn is_hostname(text : String) -> Bool {
  guard is_ascii(text) else { return false }
  labels_ok(text, Ascii)
}

///|
/// An RFC 5890 internationalised host name: the same name, written in whatever
/// script its owner writes it in, with the A-labels every other resolver sees.
fn is_idn_hostname(text : String) -> Bool {
  let outcome = @idna.to_ascii(text, options=@idna.strict)
  guard outcome.is_ok() else { return false }
  guard labels_ok(outcome.name, International) else { return false }
  // The mapping rewrites a name it can read, so an A-label that was not
  // canonical comes back canonical and would be waved through. It was written
  // wrong, and a name is not one because the reader could repair it.
  input_a_labels_ok(text)
}

///|
/// Every A-label as it was written, before any mapping: a label spelled `xn--`
/// has to decode and encode back to itself.
fn input_a_labels_ok(text : String) -> Bool {
  let out : Array[String] = []
  let piece = StringBuilder()
  for c in text {
    // The four dots IDNA treats as separators.
    if c == '.' || c == '\u{3002}' || c == '\u{FF0E}' || c == '\u{FF61}' {
      out.push(piece.to_string())
      piece.reset()
    } else {
      piece.write_char(c)
    }
  }
  out.push(piece.to_string())
  for label in out {
    let lower = lower(label)
    if lower.length() > 4 && lower[0:4].to_owned() == "xn--" {
      // The body is case-insensitive, and a Punycode body in capitals still
      // decodes; what has to hold is that it decodes to what it says.
      guard a_label_ok(lower) else { return false }
    }
  }
  true
}

///|
/// The labels of a name, each checked on its own and the whole measured as the
/// DNS measures it.
fn labels_ok(text : String, reach : Reach) -> Bool {
  guard text.length() > 0 && text.length() <= 253 else { return false }
  let labels = split_labels(text)
  guard labels.length() > 0 else { return false }
  for label in labels {
    guard label.length() > 0 && label.length() <= 63 else { return false }
    if reach is Ascii {
      for c in label {
        let code = c.to_int()
        let alnum = (code >= 0x30 && code <= 0x39) ||
          (code >= 0x41 && code <= 0x5A) ||
          (code >= 0x61 && code <= 0x7A)
        guard alnum || code == 0x2D else { return false }
      }
      guard label[0] != '-' && label[label.length() - 1] != '-' else {
        return false
      }
    }
    // The ACE prefix is read without regard to case, and the body below it is
    // Punycode, which has none either.
    let spelled = lower(label)
    if spelled.length() > 4 && spelled[0:4].to_owned() == "xn--" {
      guard a_label_ok(spelled) else { return false }
    }
  }
  true
}

///|
fn split_labels(text : String) -> Array[String] {
  let out : Array[String] = []
  let piece = StringBuilder()
  for c in text {
    if c == '.' {
      out.push(piece.to_string())
      piece.reset()
    } else {
      piece.write_char(c)
    }
  }
  out.push(piece.to_string())
  out
}

///|
/// An A-label: `xn--` and a Punycode body that decodes to a label IDNA2008
/// permits, and that encodes back to the label it came from.
fn a_label_ok(label : String) -> Bool {
  let body = label[4:].to_owned()
  let decoded = @idna.decode(body) catch { _ => return false }
  // A label whose A-label form is all ASCII has no A-label form at all.
  guard !is_ascii(decoded) else { return false }
  guard u_label_ok(decoded) else { return false }
  // `xn---9uc` and its kind decode, but not to themselves.
  @idna.encode(decoded) == body
}

///|
/// Whether a U-label is one IDNA2008 permits: every code point allowed, and
/// every contextual one where the standard says it may sit.
fn u_label_ok(label : String) -> Bool {
  let points : Array[Int32] = []
  for c in label {
    points.push(c.to_int())
  }
  guard points.length() > 0 && points.length() <= 63 else { return false }
  for point in points {
    guard in_ranges(idna_allowed, point) else { return false }
  }
  // A combining mark needs something to combine with, and a label does not
  // begin with one.
  guard !in_ranges(idna_marks, points[0]) else { return false }
  // The third and fourth characters may not both be a hyphen: that is how an
  // A-label announces itself, and a U-label that looks like one is a confusion
  // the standard refuses (RFC 5891 §4.2.3.1).
  if points.length() >= 4 && points[2] == 0x2D && points[3] == 0x2D {
    return false
  }
  contextj_ok(points) && contexto_ok(points)
}

///|
/// RFC 5892 Appendix A: a join control follows a virama, and a zero width
/// non-joiner may also sit between two letters that a joining script would join.
fn contextj_ok(points : Array[Int32]) -> Bool {
  for index, point in points {
    if in_ranges(idna_contextj, point) {
      let virama = index > 0 && in_ranges(idna_virama, points[index - 1])
      if point == 0x200D {
        // A zero width joiner has no second chance.
        guard virama else { return false }
      } else {
        guard virama || joined_across(points, index) else { return false }
      }
    }
  }
  true
}

///|
/// Whether the letters around a zero width non-joiner are ones it may separate.
fn joined_across(points : Array[Int32], index : Int32) -> Bool {
  let mut left = index - 1
  while left >= 0 && in_ranges(idna_join_transparent, points[left]) {
    left = left - 1
  }
  guard left >= 0 && in_ranges(idna_join_left, points[left]) else {
    return false
  }
  let mut right = index + 1
  while right < points.length() &&
        in_ranges(idna_join_transparent, points[right]) {
    right = right + 1
  }
  guard right < points.length() else { return false }
  in_ranges(idna_join_right, points[right])
}

///|
/// RFC 5892 §2's contextual rules: the code points whose meaning depends on
/// their neighbours, and the neighbours they need.
fn contexto_ok(points : Array[Int32]) -> Bool {
  let mut japanese = false
  let mut arabic_indic = false
  let mut extended_arabic = false
  for point in points {
    // The scripts, not the blocks: the middle dot sits in the Katakana block
    // and belongs to no script, so counting it would let a label of nothing but
    // a middle dot vouch for itself.
    if is_japanese(point) {
      japanese = true
    }
    if in_span(point, 0x660, 0x669) {
      arabic_indic = true
    }
    if in_span(point, 0x6F0, 0x6F9) {
      extended_arabic = true
    }
  }
  // The two Arabic-Indic digit blocks are one numbering, and a label in both is
  // a label in neither.
  guard !(arabic_indic && extended_arabic) else { return false }
  for index, point in points {
    match point {
      0xB7 =>
        // A middle dot stands between two `l`s, which is the Catalan spelling.
        if index == 0 ||
          index + 1 >= points.length() ||
          points[index - 1] != 0x6C ||
          points[index + 1] != 0x6C {
          return false
        }
      0x375 =>
        // A Greek keraia takes a Greek letter after it.
        if index + 1 >= points.length() || !is_greek(points[index + 1]) {
          return false
        }
      0x5F3 | 0x5F4 =>
        // A Hebrew geresh or gershayim takes a Hebrew letter before it.
        if index == 0 || !is_hebrew(points[index - 1]) {
          return false
        }
      0x30FB => if !japanese { return false }
      _ => ()
    }
  }
  true
}

///|
/// Hiragana, Katakana or Han, which is what a Katakana middle dot needs beside
/// it to be a word rather than a dot.
fn is_japanese(point : Int32) -> Bool {
  in_span(point, 0x3041, 0x3096) ||
  in_span(point, 0x309D, 0x309F) ||
  in_span(point, 0x30A1, 0x30FA) ||
  in_span(point, 0x30FD, 0x30FF) ||
  in_span(point, 0x31F0, 0x31FF) ||
  in_span(point, 0xFF66, 0xFF9D) ||
  point == 0x3005 ||
  point == 0x3007 ||
  in_span(point, 0x3021, 0x3029) ||
  in_span(point, 0x3038, 0x303B) ||
  in_span(point, 0x3400, 0x4DBF) ||
  in_span(point, 0x4E00, 0x9FFF) ||
  in_span(point, 0xF900, 0xFAFF) ||
  in_span(point, 0x20000, 0x2FA1F)
}

///|
fn is_greek(point : Int32) -> Bool {
  in_span(point, 0x370, 0x3FF) || in_span(point, 0x1F00, 0x1FFF)
}

///|
fn is_hebrew(point : Int32) -> Bool {
  in_span(point, 0x590, 0x5FF) || in_span(point, 0xFB1D, 0xFB4F)
}

///|
/// An RFC 5321 mailbox: `local@domain`, where the local part is a dot-separated
/// run of atoms or one quoted string, and the domain is a host name or an
/// address literal.
///
/// `reach` is the difference between `email` and `idn-email`: RFC 6531 widened
/// the local part to UTF-8 and left everything else alone.
fn is_email(text : String, reach : Reach) -> Bool {
  let view = text[:]
  let n = view.length()
  let at = match local_end(view, reach) {
    Some(found) => found
    None => return false
  }
  guard at < n && view[at] == '@' else { return false }
  let domain = view[at + 1:].to_owned()
  guard domain.length() > 0 else { return false }
  if domain[0] == '[' {
    guard domain[domain.length() - 1] == ']' else { return false }
    return is_address_literal(domain[1:domain.length() - 1].to_owned())
  }
  if reach is Ascii {
    is_hostname(domain)
  } else {
    is_idn_hostname(domain)
  }
}

///|
/// Where the local part ends, which is the `@` that separates it from the
/// domain — and not one inside a quoted string.
fn local_end(text : StringView, reach : Reach) -> Int32? {
  let n = text.length()
  guard n > 0 else { return None }
  if text[0] == '"' {
    return quoted_end(text, reach)
  }
  // A dot-atom: atoms joined by single dots, and no dot at either end.
  let mut i = 0
  while i < n {
    let start = i
    while i < n && is_atext(text[i].to_int(), reach) {
      i = i + 1
    }
    guard i > start else { return None }
    if i < n && text[i] == '.' {
      i = i + 1
      guard i < n else { return None }
    } else {
      break
    }
  }
  Some(i)
}

///|
/// The `@` that ends a quoted local part, the closing quote being part of it.
fn quoted_end(text : StringView, reach : Reach) -> Int32? {
  let n = text.length()
  let mut i = 1
  while i < n {
    let c = text[i]
    if c == '"' {
      return Some(i + 1)
    }
    if c == '\\' {
      // A quoted pair: the backslash and whatever it protects.
      guard i + 1 < n else { return None }
      guard quoted_pair_ok(text[i + 1].to_int(), reach) else { return None }
      i = i + 2
      continue
    }
    guard qtext_ok(c.to_int(), reach) else { return None }
    i = i + 1
  }
  None
}

///|
/// An RFC 5321 atom character, widened to UTF-8 by RFC 6531 when the format is
/// the international one.
fn is_atext(code : Int32, reach : Reach) -> Bool {
  if code > 0x7F {
    return reach is International
  }
  let alnum = (code >= 0x30 && code <= 0x39) ||
    (code >= 0x41 && code <= 0x5A) ||
    (code >= 0x61 && code <= 0x7A)
  if alnum {
    return true
  }
  match code {
    0x21
    | 0x23
    | 0x24
    | 0x25
    | 0x26
    | 0x27
    | 0x2A
    | 0x2B
    | 0x2D
    | 0x2F
    | 0x3D
    | 0x3F
    | 0x5E
    | 0x5F
    | 0x60
    | 0x7B
    | 0x7C
    | 0x7D
    | 0x7E => true
    _ => false
  }
}

///|
/// What may stand inside a quoted string: printable ASCII except the quote and
/// the backslash, which are the two the quoting exists for.
fn qtext_ok(code : Int32, reach : Reach) -> Bool {
  if code > 0x7F {
    return reach is International
  }
  (code >= 0x20 && code <= 0x21) ||
  (code >= 0x23 && code <= 0x5B) ||
  (code >= 0x5D && code <= 0x7E)
}

///|
fn quoted_pair_ok(code : Int32, reach : Reach) -> Bool {
  if code > 0x7F {
    return reach is International
  }
  (code >= 0x20 && code <= 0x7E) || code == 0x09
}

///|
/// The inside of an RFC 5321 address literal: an IPv4 address, or `IPv6:` and
/// one. Nothing else, which is what rules out `[1.2.3]` and the narrative forms
/// the standard once allowed.
fn is_address_literal(inner : String) -> Bool {
  if inner.length() >= 5 && lower(inner[0:5].to_owned()) == "ipv6:" {
    return is_ipv6(inner[5:].to_owned())
  }
  is_ipv4(inner)
}

///|
fn lower(text : String) -> String {
  let out = StringBuilder()
  for c in text {
    let code = c.to_int()
    if code >= 0x41 && code <= 0x5A {
      out.write_char((code + 0x20).unsafe_to_char())
    } else {
      out.write_char(c)
    }
  }
  out.to_string()
}
