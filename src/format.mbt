// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// `format`, and the assertion the specification asks for.
//
// A format is a name and a question about a string. There is one table of them
// and one call, because a format is a format: the keyword is the same in every
// version, and only whether it asserts changes.

///|
/// Whether `text` is the format `name` names.
///
/// `None` when the name is one this library does not know, which is not the
/// same as a name it knows and the text failing: a caller has to be able to tell
/// "not this format" from "not a format at all".
fn judge_format(name : String, text : String, draft : Draft) -> Bool? {
  match name {
    "date" => Some(is_date(text))
    "time" => Some(is_time(text, if draft == V1 { Refused } else { Allowed }))
    "date-time" => Some(is_date_time(text))
    "duration" => Some(is_duration(text))
    "email" => Some(is_email(text, Ascii))
    "idn-email" => Some(is_email(text, International))
    "hostname" => Some(is_hostname(text))
    "idn-hostname" => Some(is_idn_hostname(text))
    "ipv4" => Some(is_ipv4(text))
    "ipv6" => Some(is_ipv6(text))
    "uri" => Some(is_uri(text, Ascii))
    "uri-reference" => Some(is_uri_reference(text, Ascii))
    "iri" => Some(is_uri(text, International))
    "iri-reference" => Some(is_uri_reference(text, International))
    "uri-template" => Some(is_uri_template(text))
    "uuid" => Some(is_uuid(text))
    "json-pointer" => Some(is_json_pointer(text))
    "relative-json-pointer" => Some(is_relative_json_pointer(text))
    "regex" => Some(is_regex(text))
    _ => None
  }
}

///|
/// Whether `format` names a format this library knows.
///
/// v1 requires a schema naming one it does not know to be refused rather than
/// read with the keyword ignored, which is what this answers for.
fn known_format(name : String) -> Bool {
  judge_format(name, "", Draft2020) is Some(_)
}

///|
/// `format` as an assertion, which it is only when the caller or the document's
/// dialect asked for one.
fn Schema::check_format(
  self : Schema,
  schema : Json,
  value : Json,
  at : String,
  spath : String,
  sink : Array[OutputUnit]?,
) -> Bool {
  guard self.asserts_format else { return true }
  guard schema is String(name) && value is String(text) else { return true }
  // A name nobody here knows asserts nothing: an unknown format is not a
  // failure of the instance, and only v1 makes it a failure of the schema.
  match judge_format(name, text, self.draft) {
    Some(true) => true
    Some(false) => note(sink, at, spath, "format", "not a valid " + name)
    None => true
  }
}
