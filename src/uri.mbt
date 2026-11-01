// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The two addressing schemes a schema is written in: the URI references `$id`,
// `$ref` and `$anchor` carry, and the JSON Pointer a fragment beginning with
// `/` is (RFC 6901).
//
// URI reading and relative-reference resolution are moonurl's: the five
// components, the merge and the dot segments are one algorithm, and a second
// copy of it would only be subtly wrong. What is here is the pointer, which is a
// different addressing scheme, and the two places where the two meet.

///|
/// A reference split into the part that names a document and the part that names
/// a place inside it. The fragment comes back without its `#`.
fn split_fragment(reference : String) -> (String, String) {
  let url = @moonurl.Url::decode(reference) catch {
    _ => return (reference, "")
  }
  match url.fragment {
    Some(fragment) => {
      let document : @moonurl.Url = { ..url, fragment: None, }
      (document.encode(), fragment)
    }
    None => (reference, "")
  }
}

///|
/// `reference` read against `base`, RFC 3986 §5.2.
///
/// A reference moonurl will not read is left as it was written: nothing can be
/// said about where it lands, and a reference that resolves to nothing becomes a
/// fault rather than a guess.
fn resolve(base : String, reference : String) -> String {
  let root = @moonurl.Url::decode(base) catch { _ => @moonurl.Url::new() }
  let target = @moonurl.Url::decode(reference, base=root) catch {
    _ => return reference
  }
  target.encode()
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
fn index_of(token : String) -> Int32 {
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
fn is_digit(code : Int32) -> Bool {
  code >= 0x30 && code <= 0x39
}

///|
fn nibble(code : Int32) -> Int32? {
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
