// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The seam a vocabulary outside this library plugs into: one trait for a
// keyword, one for a vocabulary, and a registry that decides which of them a
// given document puts in force.
//
// The rules, which are the whole of the contract:
//
// | Question | Answer |
// |:--|:--|
// | how a keyword is shaped | `pub(open) trait Keyword`, one method, `Verdict` back |
// | how a vocabulary is shaped | `pub(open) trait Vocabulary`, its URI and its keywords |
// | how one is registered | `Registry::add`, raising `Refused` on a clash |
// | when it is in force | the document's `$vocabulary` names the vocabulary's URI |
// | a name a built-in uses | not available; the registration is refused |
// | a name another vocabulary took | not available; the second is refused |
// | `false` in `$vocabulary` | its keywords annotate, and assert nothing |
// | a wanted vocabulary nobody holds | the document is refused, not half-read |

///|
/// Where a keyword sits, for the benefit of a keyword that has to say where it
/// looked.
pub(all) struct Site {
  /// Where in the instance, as a JSON Pointer; empty for the instance itself.
  at : String
  /// Where in the schema, as a JSON Pointer, following the walk that arrived.
  schema_at : String
} derive(Eq, Debug)

///|
pub extend Site with Eq::{equal, not_equal}

///|
pub extend Site with Debug::{to_repr}

///|
/// What a keyword says about one instance.
pub(all) enum Verdict {
  /// It conforms. `annotation` is what the keyword contributes to the output
  /// when the caller asks for annotations; `None` when it contributes nothing.
  Accept(annotation~ : Json?)
  /// It does not conform, and this says why in one clause.
  Refuse(why~ : String)
} derive(Eq, Debug)

///|
pub extend Verdict with Eq::{equal, not_equal}

///|
pub extend Verdict with Debug::{to_repr}

///|
/// A keyword someone outside this library defines.
///
/// It is written in a schema as [`Keyword::name`] and read once per instance,
/// with the keyword's own value, the instance, and where both sit. It asserts,
/// annotates, or both; it does not apply subschemas — a keyword that has to walk
/// a subschema is an applicator, and applicators are this library's own.
///
/// ```moonbit nocheck
/// struct Even {}
///
/// pub impl Keyword for Even with fn name(_self) {
///   "x-even"
/// }
///
/// pub impl Keyword for Even with fn judge(_self, value, instance, site) {
///   ignore(site)
///   match (value, instance) {
///     (True, Number(number, ..)) =>
///       if number % 2.0 == 0.0 {
///         Accept()
///       } else {
///         Refuse("odd")
///       }
///     _ => Accept()
///   }
/// }
///
/// pub extend Even with Keyword::{name, judge}
/// ```
pub(open) trait Keyword {
  /// The name it is written as in a schema.
  fn name(Self) -> String
  /// What it says about `instance` at `site`.
  fn judge(Self, value : Json, instance : Json, site : Site) -> Verdict
}

///|
/// A set of keywords that a document puts in force by naming its URI in
/// `$vocabulary`.
///
/// The URI is the one the schema's metaschema uses — a vocabulary is identified
/// by an absolute URI, conventionally one ending in `/vocab/<name>`. A document
/// whose metaschema names this URI with `true` gets the keywords; with `false`,
/// they annotate and assert nothing.
pub(open) trait Vocabulary {
  /// The URI a `$vocabulary` names it by.
  fn uri(Self) -> String
  /// The keywords it defines.
  fn keywords(Self) -> Array[&Keyword]
}

///|
/// The vocabularies a caller can offer a document, by URI.
///
/// A registry is not global: two schemas in one program may be read against
/// different vocabularies, and a schema is read against what its own caller
/// handed it. [`registry`] is the empty one, which is what a caller who adds
/// nothing gets; a caller with vocabularies of their own starts from
/// [`Registry::new`].
pub struct Registry {
  priv held : Map[String, &Vocabulary]
  /// Every name taken so far, by the URI of the vocabulary that took it. A
  /// built-in keyword's name is in here from the start, held by the empty URI.
  priv names : Map[String, String]
}

///|
/// A registry that holds nothing, and answers for no name but the built-in ones.
pub fn Registry::new() -> Registry {
  let names : Map[String, String] = Map::Map([])
  for keyword in builtin_keywords() {
    names[keyword] = ""
  }
  { held: Map::Map([]), names, }
}

///|
/// No vocabularies beyond the built-in ones.
pub let registry : Registry = Registry::new()

///|
/// The names the built-in keywords answer to, across every version. A
/// third-party keyword cannot take one of them.
fn builtin_keywords() -> Array[String] {
  [
    "$anchor", "$comment", "$defs", "$dynamicAnchor", "$dynamicRef", "$id", "$recursiveAnchor",
    "$recursiveRef", "$ref", "$schema", "$vocabulary", "additionalItems", "additionalProperties",
    "allOf", "anyOf", "const", "contains", "contentEncoding", "contentMediaType",
    "contentSchema", "default", "definitions", "dependencies", "dependentRequired",
    "dependentSchemas", "deprecated", "description", "else", "enum", "examples",
    "exclusiveMaximum", "exclusiveMinimum", "format", "if", "items", "maxContains",
    "maximum", "maxItems", "maxLength", "maxProperties", "minContains", "minimum",
    "minItems", "minLength", "minProperties", "multipleOf", "not", "oneOf", "pattern",
    "patternProperties", "prefixItems", "properties", "propertyNames", "propertyDependencies",
    "readOnly", "required", "then", "title", "type", "unevaluatedItems", "unevaluatedProperties",
    "uniqueItems", "writeOnly",
  ]
}

///|
/// Add a vocabulary.
///
/// It is refused when the vocabulary's URI is already held, when one of its
/// keywords is a name a built-in keyword answers to, or when one of them is a
/// name another vocabulary already took. A clash is refused rather than
/// resolved in someone's favour: a keyword that quietly means one thing to the
/// library and another to the document is worse than one that does not load.
pub fn Registry::add(
  self : Registry,
  vocabulary : &Vocabulary,
) -> Unit raise Refused {
  let uri = vocabulary.uri()
  guard self.held.get(uri) is None else {
    raise Broken(at=uri, why="this vocabulary is already in the registry")
  }
  let claimed = vocabulary.keywords()
  for keyword in claimed {
    let name = keyword.name()
    match self.names.get(name) {
      Some(_) =>
        raise Broken(
          at=name,
          why="a keyword of that name is already answered for",
        )
      None => ()
    }
    self.names[name] = uri
  }
  self.held[uri] = vocabulary
}
