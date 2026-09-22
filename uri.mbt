// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The two addressing schemes a schema is written in: the URI references `$id`,
// `$ref` and `$anchor` carry (RFC 3986 §5, the reference resolution a validator
// needs and no more), and the JSON Pointer a fragment beginning with `/` is
// (RFC 6901). Both are here because both are addressing, and neither is JSON.

///|
/// A reference split into the part that names a document and the part that names
/// a place inside it. The fragment comes back without its `#`.
fn split_fragment(reference : String) -> (String, String) {
  let text = reference[:]
  for i = 0; i < text.length(); i = i + 1 {
    if text[i] == '#' {
      return (text[0:i].to_owned(), text[i + 1:].to_owned())
    }
  }
  (reference, "")
}

///|
/// `reference` resolved against `base`, RFC 3986 §5.2 in the shapes a schema
/// uses: an absolute URI stands alone, a network reference takes the base's
/// scheme, an absolute path takes its authority, and a relative path is merged
/// onto the base's directory. A fragment-only reference keeps the base entirely.
fn resolve(base : String, reference : String) -> String {
  let (target, fragment) = split_fragment(reference)
  let (base_document, _) = split_fragment(base)
  let merged = if target == "" {
    base_document
  } else if has_scheme(target) {
    target
  } else if target.has_prefix("//") {
    scheme_of(base_document) + target
  } else if target.has_prefix("/") {
    authority_of(base_document) + target
  } else {
    directory_of(base_document) + target
  }
  let tidy = without_dots(merged)
  if fragment == "" && !reference.has_suffix("#") {
    tidy
  } else {
    tidy + "#" + fragment
  }
}

///|
/// A path with its `.` and `..` segments taken out, RFC 3986 §5.2.4.
///
/// `./bar.json` beside `nested/foo.json` is `nested/bar.json`, and a validator
/// that left the dot in would look for a resource nobody named.
fn without_dots(uri : String) -> String {
  if !uri.contains("./") && !uri.has_suffix("/.") && !uri.has_suffix("/..") {
    return uri
  }
  let authority = authority_of(uri)
  let head = if authority == "" { scheme_of(uri) } else { authority }
  let path = uri[head.length():].to_owned()
  let kept : Array[String] = []
  let rooted = path.has_prefix("/")
  let mut trailing = false
  for segment in split_path(path) {
    match segment {
      "." => trailing = true
      ".." => {
        if kept.length() > 0 {
          kept.pop() |> ignore
        }
        trailing = true
      }
      _ => {
        kept.push(segment)
        trailing = false
      }
    }
  }
  let out = StringBuilder()
  out.write_string(head)
  if rooted {
    out.write_char('/')
  }
  for i = 0; i < kept.length(); i = i + 1 {
    if i > 0 {
      out.write_char('/')
    }
    out.write_string(kept[i])
  }
  if trailing && kept.length() > 0 {
    out.write_char('/')
  }
  out.to_string()
}

///|
/// A path's segments, with the empty ones its slashes leave behind dropped
/// except for the one a trailing slash means.
fn split_path(path : String) -> Array[String] {
  let text = path[:]
  let out : Array[String] = []
  let piece = StringBuilder()
  let mut trailing = false
  for i = 0; i < text.length(); i = i + 1 {
    if text[i] == '/' {
      let segment = piece.to_string()
      if segment != "" {
        out.push(segment)
      }
      piece.reset()
      trailing = true
    } else {
      piece.write_string(text[i:i + 1].to_owned())
      trailing = false
    }
  }
  let last = piece.to_string()
  if last != "" {
    out.push(last)
  } else if trailing && out.length() > 0 {
    out.push("")
  }
  out
}

///|
/// Whether a reference begins with a scheme, which is what makes it absolute.
///
/// A scheme is a letter followed by letters, digits, `+`, `-` or `.`, and then a
/// colon — so a Windows path and a relative name that happens to hold a colon
/// are not mistaken for one.
fn has_scheme(reference : String) -> Bool {
  let text = reference[:]
  if text.length() == 0 || !is_alpha(text[0].to_int()) {
    return false
  }
  for i = 1; i < text.length(); i = i + 1 {
    let c = text[i]
    if c == ':' {
      return i > 0
    }
    if !(is_alpha(c.to_int()) ||
      is_digit(c.to_int()) ||
      c == '+' ||
      c == '-' ||
      c == '.') {
      return false
    }
  }
  false
}

///|
/// `scheme:` of a URI, or the empty string when it has none.
fn scheme_of(uri : String) -> String {
  let text = uri[:]
  for i = 0; i < text.length(); i = i + 1 {
    if text[i] == ':' {
      return text[0:i + 1].to_owned()
    }
  }
  ""
}

///|
/// Everything up to the end of the authority — `https://example.test` — or the
/// empty string when the URI has no authority.
fn authority_of(uri : String) -> String {
  let text = uri[:]
  let scheme = scheme_of(uri)
  if scheme == "" || !text[scheme.length():].has_prefix("//") {
    return ""
  }
  for i = scheme.length() + 2; i < text.length(); i = i + 1 {
    if text[i] == '/' {
      return text[0:i].to_owned()
    }
  }
  uri
}

///|
/// The URI with everything after its last `/` removed, which is the directory a
/// relative reference is merged onto.
fn directory_of(uri : String) -> String {
  let text = uri[:]
  for i = text.length() - 1; i >= 0; i = i - 1 {
    if text[i] == '/' {
      return text[0:i + 1].to_owned()
    }
  }
  ""
}

///|
fn is_alpha(code : Int) -> Bool {
  (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A)
}

///|
fn is_digit(code : Int) -> Bool {
  code >= 0x30 && code <= 0x39
}

///|
/// The value a JSON Pointer points at, or `None` when the document has nothing
/// there (RFC 6901 §4).
fn pointer(document : Json, path : String) -> Json? {
  if path == "" {
    return Some(document)
  }
  if !path.has_prefix("/") {
    return None
  }
  let mut here = document
  for token in split_pointer(path) {
    match here {
      Object(members) =>
        match members.get(token) {
          Some(next) => here = next
          None => return None
        }
      Array(items) => {
        let index = index_of(token)
        if index < 0 || index >= items.length() {
          return None
        }
        here = items[index]
      }
      _ => return None
    }
  }
  Some(here)
}

///|
/// A pointer's reference tokens, each unescaped: `~1` is a `/` that belongs to a
/// name and `~0` a `~`, undone in that order so a name holding `~1` survives.
fn split_pointer(path : String) -> Array[String] {
  let text = path[:]
  let out : Array[String] = []
  let token = StringBuilder()
  let mut i = 1
  while i <= text.length() {
    if i == text.length() || text[i] == '/' {
      out.push(unescape(token.to_string()))
      token.reset()
    } else if text[i] == '%' && i + 2 < text.length() {
      // A pointer that arrived inside a URI is percent-encoded.
      match (nibble(text[i + 1].to_int()), nibble(text[i + 2].to_int())) {
        (Some(hi), Some(lo)) => {
          token.write_char(((hi << 4) | lo).unsafe_to_char())
          i = i + 2
        }
        _ => token.write_string(text[i:i + 1].to_owned())
      }
    } else {
      token.write_string(text[i:i + 1].to_owned())
    }
    i = i + 1
  }
  out
}

///|
/// `~1` and `~0` read back as the characters they stand for.
fn unescape(token : String) -> String {
  let text = token[:]
  let out = StringBuilder()
  let mut i = 0
  while i < text.length() {
    if text[i] == '~' && i + 1 < text.length() {
      match text[i + 1] {
        '1' => {
          out.write_char('/')
          i = i + 2
          continue
        }
        '0' => {
          out.write_char('~')
          i = i + 2
          continue
        }
        _ => ()
      }
    }
    out.write_string(text[i:i + 1].to_owned())
    i = i + 1
  }
  out.to_string()
}

///|
/// A reference token as the array index it spells, or `-1` when it spells none.
/// A leading zero is not an index, which is what keeps `01` out of an array.
fn index_of(token : String) -> Int {
  if token.length() == 0 {
    return -1
  }
  if token.length() > 1 && token[:][0] == '0' {
    return -1
  }
  let mut value = 0
  for c in token {
    if !is_digit(c.to_int()) {
      return -1
    }
    value = value * 10 + (c.to_int() - 0x30)
    if value < 0 {
      return -1
    }
  }
  value
}

///|
fn nibble(code : Int) -> Int? {
  if code >= 0x30 && code <= 0x39 {
    Some(code - 0x30)
  } else if code >= 0x41 && code <= 0x46 {
    Some(code - 0x41 + 10)
  } else if code >= 0x61 && code <= 0x66 {
    Some(code - 0x61 + 10)
  } else {
    None
  }
}

///|
/// One step deeper in a pointer, with the characters a reference token escapes.
fn step(path : String, token : String) -> String {
  let out = StringBuilder()
  out.write_string(path)
  out.write_char('/')
  for c in token {
    match c {
      '~' => out.write_string("~0")
      '/' => out.write_string("~1")
      _ => out.write_char(c)
    }
  }
  out.to_string()
}
