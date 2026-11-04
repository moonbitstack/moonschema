// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Which version of JSON Schema a document is written against.
///
/// The six released versions that are in use. `draft-03` is not here: it
/// predates the `$` keywords and nothing has been written against it since 2010.
/// The next release arrives as another value of this enum and a keyword table,
/// not as a second validator.
#derive(Eq, Debug)
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
  /// v1 (2026). `format` asserts by default and `propertyDependencies` joins the
  /// applicators; the rest of the language is 2020-12's.
  V1
}

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
      V1 => "v1"
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
    V1 => "https://json-schema.org/v1"
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
    // The release IRI is `…/v1/<year>`, and the version alone names the latest
    // release within it, which is what a document written against either means.
    "json-schema.org/v1" | "json-schema.org/v1/2026" => Some(V1)
    _ => None
  }
}

///|
/// How much a validation says when it fails.
///
/// The four formats the specification itself defines (2020-12 §12.4), named as
/// it names them.
#derive(Eq, Debug)
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
}

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
/// Whether this version has vocabularies: 2019-09 and everything after it.
///
/// One question asked five times in the validator — does a `$ref` replace its
/// siblings, does `unevaluated*` apply, is `dependencies` split — and asked here
/// once so that a release added later cannot be forgotten in one of the five.
fn Draft::vocabularies(self : Draft) -> Bool {
  match self {
    Draft4 | Draft6 | Draft7 => false
    Draft2019 | Draft2020 | V1 => true
  }
}

///|
/// Whether this version asserts `format` without being asked.
///
/// Before v1 the keyword is an annotation unless the schema's own dialect
/// declares the assertion vocabulary; v1 made assertion the requirement, so a v1
/// document asserts it unless its reader says otherwise.
fn Draft::asserts_format(self : Draft) -> Bool {
  match self {
    Draft4 | Draft6 | Draft7 | Draft2019 | Draft2020 => false
    V1 => true
  }
}

///|
/// Whether this version spells the tuple form of `items` as `prefixItems`, which
/// 2020-12 introduced and v1 kept.
fn Draft::prefix_items(self : Draft) -> Bool {
  match self {
    Draft4 | Draft6 | Draft7 | Draft2019 => false
    Draft2020 | V1 => true
  }
}

///|
/// The output format a validation produces unless asked for another.
///
/// `Flag`, because the common case is a guard that wants a yes or a no and
/// collecting errors nobody reads is work nobody asked for. A caller that wants
/// to tell someone what went wrong asks for `Basic`.
pub let output : Output = Flag
