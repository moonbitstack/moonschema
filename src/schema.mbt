// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Which version of JSON Schema a document is written against.
///
/// The five released versions that are still in use. `draft-03` is not here: it
/// predates the `$` keywords and nothing has been written against it since 2010.
/// The next release is not here yet either; it arrives as another value of this
/// enum and a keyword table, not as a second validator.
pub(all) enum Draft {
  /// draft-04 (2013). What OpenAPI 3.0 profiles, and what a great deal of Java
  /// and Python tooling still emits.
  Draft4
  /// draft-06 (2017). `$id` replaces `id`, `exclusiveMinimum` becomes a number.
  Draft6
  /// draft-07 (2018). The most widely deployed version.
  Draft7
  /// 2019-09. Vocabularies, `$defs`, `$recursiveRef`, and the annotation-aware
  /// `unevaluatedProperties`.
  Draft2019
  /// 2020-12. `$dynamicRef`, `prefixItems`, and what OpenAPI 3.1 is.
  Draft2020
} derive(Eq, Debug)

///|
pub extend Draft with Eq::{equal, not_equal}

///|
pub extend Draft with Debug::{to_repr}

///|
/// A version prints as the name the specification gives it, which is what a
/// message about a document should say.
pub impl Show for Draft with fn output(self, logger) {
  logger.write_string(
    match self {
      Draft4 => "draft-04"
      Draft6 => "draft-06"
      Draft7 => "draft-07"
      Draft2019 => "2019-09"
      Draft2020 => "2020-12"
    },
  )
}

///|
pub extend Draft with Show::{output, to_string}

///|
/// The version assumed when a document does not name one.
///
/// 2020-12: the current release, and the one OpenAPI 3.1 is defined against. A
/// document that says `$schema` is read at the version it says, whatever this is
/// set to — the document is more specific than the setting.
pub let draft : Draft = Draft2020

///|
/// The `$schema` URI that names this version.
pub fn Draft::uri(self : Draft) -> String {
  match self {
    Draft4 => "http://json-schema.org/draft-04/schema#"
    Draft6 => "http://json-schema.org/draft-06/schema#"
    Draft7 => "http://json-schema.org/draft-07/schema#"
    Draft2019 => "https://json-schema.org/draft/2019-09/schema"
    Draft2020 => "https://json-schema.org/draft/2020-12/schema"
  }
}

///|
/// The version a `$schema` URI names.
///
/// It answers `None` for a URI it does not know rather than falling back to a
/// version of its own choosing: a document written against something else is not
/// a document to guess at. Both the `http` and `https` spellings are accepted,
/// and a trailing `#` is optional, because both are found in the wild.
pub fn Draft::of(uri : StringView) -> Draft? {
  let trimmed = if uri.has_suffix("#") {
    uri[0:uri.length() - 1]
  } else {
    uri[:]
  }
  let bare = if trimmed.has_prefix("https://") {
    trimmed[8:]
  } else if trimmed.has_prefix("http://") {
    trimmed[7:]
  } else {
    trimmed
  }
  match bare.to_owned() {
    "json-schema.org/draft-04/schema" => Some(Draft4)
    "json-schema.org/draft-06/schema" => Some(Draft6)
    "json-schema.org/draft-07/schema" => Some(Draft7)
    "json-schema.org/draft/2019-09/schema" => Some(Draft2019)
    "json-schema.org/draft/2020-12/schema" => Some(Draft2020)
    _ => None
  }
}

///|
/// How much a validation says when it fails.
///
/// The four formats the specification itself defines (2020-12 §12.4), named as
/// it names them.
pub(all) enum Output {
  /// Whether it validated, and nothing else. The cheapest, and what a guard on
  /// a request wants.
  Flag
  /// A flat list of the errors, each with the location in the instance and in
  /// the schema.
  Basic
  /// The errors as a tree, with the schema's own structure preserved.
  Detailed
  /// Every annotation as well as every error, which is what a tool that explains
  /// a schema to a person needs.
  Verbose
} derive(Eq, Debug)

///|
pub extend Output with Eq::{equal, not_equal}

///|
pub extend Output with Debug::{to_repr}

///|
/// An output format prints as the specification names it (2020-12 §12.4).
pub impl Show for Output with fn output(self, logger) {
  logger.write_string(
    match self {
      Flag => "flag"
      Basic => "basic"
      Detailed => "detailed"
      Verbose => "verbose"
    },
  )
}

///|
pub extend Output with Show::{output, to_string}

///|
/// The output format a validation produces unless asked for another.
///
/// `Flag`, because the common case is a guard that wants a yes or a no and
/// collecting errors nobody reads is work nobody asked for. A caller that wants
/// to tell someone what went wrong asks for `Basic`.
pub let output : Output = Flag
