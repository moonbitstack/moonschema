// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The validator. A schema is read as the `Json` it is — there is no compilation
// step, by the decision recorded in the README — and an instance is walked
// against it keyword by keyword.
//
// Every keyword of every version lives in one `check`, switched on the draft
// where the versions differ, because that is what the versions are: one language
// with a handful of differences, not five languages.

///|
/// Why a schema could not be read.
///
/// These are faults in the schema, not in the instance an instance that fails
/// validation produces [`Fault`]s instead.
pub(all) suberror Refused {
  /// A `$schema` naming a version this does not know.
  Unknown(String)
  /// A reference that resolves to nothing, or a keyword whose value is not the
  /// shape the specification gives it.
  Broken(at~ : String, why~ : String)
} derive(Eq, Debug)

///|
pub extend Refused with Eq::{equal, not_equal}

///|
pub extend Refused with Debug::{to_repr}

///|
pub impl Show for Refused with fn output(self, logger) {
  logger.write_string(
    match self {
      Unknown(uri) => "unknown $schema: " + uri
      Broken(at~, why~) => "broken schema at " + at + ": " + why
    },
  )
}

///|
pub extend Refused with Show::{output, to_string}

///|
/// One reason an instance failed, in the shape the basic output gives it
/// (2020-12 §12.4.2).
pub(all) struct Fault {
  /// Where in the instance, as a JSON Pointer.
  at : String
  /// Where in the schema, as a JSON Pointer.
  schema_at : String
  /// The keyword that refused it.
  keyword : String
  /// What that keyword had to say.
  message : String
} derive(Eq, Debug)

///|
pub extend Fault with Eq::{equal, not_equal}

///|
pub extend Fault with Debug::{to_repr}

///|
pub impl Show for Fault with fn output(self, logger) {
  logger.write_string(
    (if self.at == "" { "the instance" } else { self.at }) +
    ": " +
    self.message +
    " (" +
    self.keyword +
    " at " +
    (if self.schema_at == "" { "/" } else { self.schema_at }) +
    ")",
  )
}

///|
pub extend Fault with Show::{output, to_string}

///|
/// A schema document, read and ready to validate instances against.
///
/// The version is the one the document names in `$schema`, whatever `draft` said;
/// a document is more specific than a setting. `remotes` are the documents a
/// `$ref` may reach outside this one, by the URI each is registered under: this
/// library opens no sockets, so what is not fed to it does not exist.
pub struct Schema {
  priv root : Json
  priv draft : Draft
  /// Whether the validation vocabulary is in force, which is what decides
  /// whether `minimum` and its like assert or merely annotate.
  priv asserts : Bool
  /// Whether `format` asserts rather than annotates: on when the dialect's
  /// metaschema says so, or when the caller asked for it.
  priv asserts_format : Bool
  priv base : String
  /// Every `$id`, `$anchor` and `$dynamicAnchor` in reach, by absolute URI.
  priv ids : Map[String, Json]
  /// The `$dynamicAnchor` of each resource, by the resource's URI and then by
  /// the anchor's name. A `$recursiveAnchor` is the anchor whose name is empty.
  priv dynamic : Map[String, Map[String, Json]]
  /// The base in effect *outside* each node a reference can land on, by the
  /// same URI the reference resolves to. A target's own `$id` is applied by the
  /// validator when it reads it, so what is remembered here is the base before
  /// that — otherwise a relative `$id` would be applied twice.
  priv outer : Map[String, String]
  /// Each pattern as it was read, so a class of a few thousand ranges is built
  /// once rather than once per member of every instance. `None` is a pattern
  /// the engine could not read.
  priv patterns : Map[String, @moonregex.Pattern?]
  /// The resources evaluation has entered, outermost first. A `$dynamicRef`
  /// resolves against this and not against where it was written, which is the
  /// whole of what makes it dynamic.
  priv scope : Array[String]
}

///|
/// Read a schema document.
///
/// `draft` is the version to read it at when it does not name one; a `$schema`
/// it does name wins. `remotes` are the documents a `$ref` may reach, each under
/// the URI it is referred to by.
///
/// `format` decides whether `format` asserts. Left out, the document answers for
/// itself: an annotation before v1 unless its dialect's metaschema declares the
/// assertion vocabulary, and an assertion throughout v1. Given, it is the
/// answer, because a call is more specific than a document's dialect, which is
/// more specific than a version's default.
///
/// ```moonbit nocheck
/// let schema = @moonschema.Schema::new(
///   @json.parse("{ \"type\": \"object\", \"required\": [\"id\"] }"),
/// )
/// schema.valid(@json.parse("{\"id\": 1}"))   // true
/// ```
pub fn Schema::new(
  document : Json,
  draft~ : Draft = draft,
  remotes~ : Map[String, Json] = Map::Map([]),
  format? : Bool,
) -> Schema raise Refused {
  let mut version = draft
  // Every keyword this validates with is in the validation vocabulary. A
  // metaschema that does not declare that vocabulary is asking for the rest of
  // the keywords to be read as annotations, and a validator that asserted them
  // anyway would refuse instances the schema's own author allows.
  let mut asserts = true
  let mut asserts_format = draft.asserts_format()
  match document {
    Object(members) =>
      match members.get("$schema") {
        Some(String(uri)) => {
          let (named, validating, formatting) = read_version(uri, remotes)
          version = named
          asserts = validating
          asserts_format = formatting
        }
        _ => ()
      }
    _ => ()
  }
  let base = match document {
    Object(members) =>
      match members.get(if version == Draft4 { "id" } else { "$id" }) {
        Some(String(id)) => split_fragment(id).0
        _ => ""
      }
    _ => ""
  }
  let schema = {
    root: document,
    draft: version,
    asserts,
    // The version's own answer unless the caller overrode it: a document is
    // more specific than a setting, and a setting is more specific than the
    // version's default.
    asserts_format: match format {
      Some(wanted) => wanted
      None => asserts_format
    },
    base,
    ids: Map::Map([]),
    outer: Map::Map([]),
    dynamic: Map::Map([]),
    patterns: Map::Map([]),
    scope: [],
  }
  schema.index(document, base, base, "")
  for uri, remote in remotes {
    let remote_base = split_fragment(uri).0
    schema.ids[remote_base] = remote
    schema.outer[remote_base] = remote_base
    schema.index(remote, remote_base, remote_base, "")
  }
  schema
}

///|
/// Whether `instance` validates.
///
/// This is the flag output (§12.4.1): the cheapest answer, and the one a guard on
/// a request wants. [`Schema::faults`] says why not.
///
/// ```moonbit nocheck
/// let schema = @moonschema.Schema::new(@json.parse("{ \"type\": \"integer\" }"))
/// schema.valid(@json.parse("7"))          // true
/// schema.valid(@json.parse("\"seven\""))   // false
/// ```
pub fn Schema::valid(self : Schema, instance : Json) -> Bool {
  self.scope.clear()
  self.scope.push(self.base)
  self.check(self.root, self.base, instance, "", "", None, Marks::new())
}

///|
/// Every reason `instance` failed, or an empty array when it validated.
///
/// The reasons, and not the shape of the walk: each fault says where in the
/// instance it was, which keyword refused it, and where that keyword was.
/// [`Schema::report`] is the other reading of the same walk, in the four formats
/// §12 names.
///
/// ```moonbit nocheck
/// let schema = @moonschema.Schema::new(
///   @json.parse("{ \"type\": \"integer\", \"minimum\": 1 }"),
/// )
/// for fault in schema.faults(@json.parse("0")) {
///   println(fault.to_string())
/// }
/// // the instance: below the minimum (minimum at /minimum)
/// ```
pub fn Schema::faults(self : Schema, instance : Json) -> Array[Fault] {
  let collected : Array[OutputUnit] = []
  self.scope.clear()
  self.scope.push(self.base)
  self.check(
    self.root,
    self.base,
    instance,
    "",
    "",
    Some(collected),
    Marks::new(),
  )
  |> ignore
  // Every reason, in the order the walk found them: a branch node says only
  // that something under it failed, and a caller asking for reasons wants the
  // leaves that failed.
  let faults : Array[Fault] = []
  gather_reasons(collected, faults)
  faults
}

///|
/// The leaves of the tree that hold a reason, in order.
fn gather_reasons(units : Array[OutputUnit], out : Array[Fault]) -> Unit {
  for unit in units {
    match unit.error {
      Some(message) =>
        out.push({
          at: unit.at,
          schema_at: unit.keyword_at,
          keyword: last_step(unit.keyword_at),
          message,
        })
      None => ()
    }
    gather_reasons(unit.children, out)
  }
}

///|
/// The last step of a pointer, unescaped: the keyword a reason is about.
fn last_step(path : String) -> String {
  let text = path[:]
  let mut start = 0
  for i = 0; i < text.length(); i = i + 1 {
    if text[i] == '/' {
      start = i + 1
    }
  }
  unescape(text[start:].to_owned())
}

// ------------------------------------------------------------------ annotation

///|
/// What a schema evaluated, which is what `unevaluatedProperties` and
/// `unevaluatedItems` ask their neighbours about (2019-09 §9.3.2.4).
priv struct Marks {
  /// The members an applicator validated.
  props : Set[String]
  /// The item positions one validated.
  idx : Set[Int32]
  /// Whether one validated every item there is, however many arrive.
  mut all_items : Bool
}

///|
fn Marks::new() -> Marks {
  { props: Set::Set([]), idx: Set::Set([]), all_items: false, }
}

///|
/// Take in what a sibling applicator evaluated, which only happens when that
/// applicator validated: a failed branch annotates nothing.
fn Marks::take(self : Marks, other : Marks) -> Unit {
  for name in other.props {
    self.props.add(name)
  }
  for index in other.idx {
    self.idx.add(index)
  }
  if other.all_items {
    self.all_items = true
  }
}

// ------------------------------------------------------------------- the walk

///|
/// Index every `$id`, `$anchor` and `$dynamicAnchor` the document holds, so a
/// `$ref` has somewhere to land.
fn Schema::index(
  self : Schema,
  node : Json,
  base : String,
  document : String,
  path : String,
) -> Unit raise Refused {
  guard node is Object(members) else { return }
  // Every node is addressable by a pointer into the document it is in, and the
  // base outside it is what a reference landing there resolves against.
  self.outer[document + "#" + path] = base
  let mut here = base
  let id_keyword = if self.draft == Draft4 { "id" } else { "$id" }
  match members.get(id_keyword) {
    Some(String(id)) => {
      let resolved = resolve(here, id)
      // Before 2019-09 an `$id` that is only a fragment is how an anchor was
      // written; from 2019-09 that is `$anchor` and an `$id` names a document.
      let (named, fragment) = split_fragment(resolved)
      if fragment != "" {
        self.ids[named + "#" + fragment] = node
        self.outer[named + "#" + fragment] = base
      } else {
        here = named
        self.ids[named] = node
        self.outer[named] = base
      }
    }
    _ => ()
  }
  match members.get("$anchor") {
    Some(String(anchor)) => {
      self.ids[here + "#" + anchor] = node
      self.outer[here + "#" + anchor] = base
    }
    _ => ()
  }
  match members.get("$dynamicAnchor") {
    Some(String(anchor)) => {
      self.ids[here + "#" + anchor] = node
      self.outer[here + "#" + anchor] = base
      self.anchor_dynamic(here, anchor, node)
    }
    _ => ()
  }
  match members.get("$recursiveAnchor") {
    Some(True) => self.anchor_dynamic(here, "", node)
    _ => ()
  }
  // v1 makes an unknown format a schema this cannot read: `format` asserts
  // there, and an assertion nobody can make is not one to skip over silently.
  if self.draft == V1 {
    match members.get("format") {
      Some(String(name)) =>
        if !known_format(name) {
          raise Broken(at=step(path, "format"), why="no such format: " + name)
        }
      _ => ()
    }
  }
  for keyword, value in members {
    match keyword {
      "additionalProperties"
      | "additionalItems"
      | "contains"
      | "propertyNames"
      | "not"
      | "if"
      | "then"
      | "else"
      | "unevaluatedItems"
      | "unevaluatedProperties"
      | "contentSchema"
      | "items" =>
        match value {
          Array(schemas) =>
            for i = 0; i < schemas.length(); i = i + 1 {
              self.index(
                schemas[i],
                here,
                document,
                step(step(path, keyword), i.to_string()),
              )
            }
          _ => self.index(value, here, document, step(path, keyword))
        }
      "allOf" | "anyOf" | "oneOf" | "prefixItems" =>
        match value {
          Array(schemas) =>
            for i = 0; i < schemas.length(); i = i + 1 {
              self.index(
                schemas[i],
                here,
                document,
                step(step(path, keyword), i.to_string()),
              )
            }
          _ => ()
        }
      "properties"
      | "patternProperties"
      | "$defs"
      | "definitions"
      | "dependentSchemas"
      | "dependencies" =>
        match value {
          Object(schemas) =>
            for name, schema in schemas {
              self.index(
                schema,
                here,
                document,
                step(step(path, keyword), name),
              )
            }
          _ => ()
        }
      // Two levels of names, and a schema under the pair: a property, the value
      // it may hold, and what the instance must be when it holds it.
      "propertyDependencies" =>
        match value {
          Object(by_value) =>
            for name, choices in by_value {
              match choices {
                Object(schemas) =>
                  for held, schema in schemas {
                    self.index(
                      schema,
                      here,
                      document,
                      step(step(step(path, keyword), name), held),
                    )
                  }
                _ => ()
              }
            }
          _ => ()
        }
      _ => ()
    }
  }
}

///|
/// The subschema a reference names, or `None` when nothing is there.
fn Schema::follow(
  self : Schema,
  base : String,
  reference : String,
) -> (Json, String)? {
  let resolved = resolve(base, reference)
  let (document, fragment) = split_fragment(resolved)
  if fragment.has_prefix("/") || fragment == "" {
    // A pointer into whichever document the reference names.
    let root = if document == self.base || document == "" {
      Some(self.root)
    } else {
      self.ids.get(document)
    }
    match root {
      Some(found) =>
        match pointer(found, fragment) {
          Some(node) =>
            Some(
              (
                node,
                self.outside(resolved, document + "#" + fragment, document),
              ),
            )
          None => None
        }
      None =>
        match self.ids.get(resolved) {
          Some(node) =>
            Some(
              (
                node,
                self.outside(resolved, document + "#" + fragment, document),
              ),
            )
          None => None
        }
    }
  } else {
    match self.ids.get(resolved) {
      Some(found) =>
        Some(
          (found, self.outside(resolved, document + "#" + fragment, document)),
        )
      // An anchor written against a document that named no `$id` of its own.
      None =>
        match self.ids.get("#" + fragment) {
          Some(found) =>
            Some(
              (found, self.outside("#" + fragment, "#" + fragment, document)),
            )
          None => None
        }
    }
  }
}

///|
/// The base in effect outside the node an address names.
///
/// A node is addressable two ways — by the URI its own `$id` gave it, and by a
/// pointer into the document it sits in — and only one of them is recorded when
/// the node has an `$id`. Both are tried, because a reference may arrive either
/// way, and the answer has to be the base *outside* the node: applying its own
/// `$id` is the validator's job, and doing it twice moves the resource.
fn Schema::outside(
  self : Schema,
  named : String,
  pointed : String,
  fallback : String,
) -> String {
  match self.outer.get(named) {
    Some(base) => base
    None =>
      match self.outer.get(pointed) {
        Some(base) => base
        None => fallback
      }
  }
}

///|
/// Record a dynamic anchor under the resource it belongs to.
fn Schema::anchor_dynamic(
  self : Schema,
  resource : String,
  anchor : String,
  node : Json,
) -> Unit {
  match self.dynamic.get(resource) {
    Some(anchors) => anchors[anchor] = node
    None => {
      let anchors : Map[String, Json] = Map::Map([])
      anchors[anchor] = node
      self.dynamic[resource] = anchors
    }
  }
}

///|
/// The schema a dynamic anchor names, taken from the outermost resource in the
/// current dynamic scope that has one by that name (2020-12 §8.2.3.2, v1 §8.2.3.2).
///
/// The resource comes back with it: an anchor's base is the resource it is in,
/// not the one the reference was written in, and the two differ exactly when the
/// dynamic scope is doing its job.
fn Schema::outermost(self : Schema, anchor : String) -> (Json, String)? {
  for resource in self.scope {
    match self.dynamic.get(resource) {
      Some(anchors) =>
        match anchors.get(anchor) {
          Some(found) => return Some((found, resource))
          None => ()
        }
      None => ()
    }
  }
  None
}

///|
/// What a metaschema says about the document read against it: the version, and
/// which of the two vocabularies that change behaviour it declares.
///
/// A URI this does not know is looked for among the documents the caller fed:
/// a custom metaschema is a document like any other, and what it says about
/// itself — the version it is written against, the vocabularies it declares —
/// is read from it. A URI that is neither known nor fed is refused, because a
/// document written against something nobody can read is not one to guess at.
fn read_version(
  uri : String,
  remotes : Map[String, Json],
) -> (Draft, Bool, Bool) raise Refused {
  match Draft::of(uri[:]) {
    Some(named) => (named, true, named.asserts_format())
    None =>
      match remotes.get(split_fragment(uri).0) {
        Some(Object(meta)) => {
          let (version, asserting) = match meta.get("$schema") {
            Some(String(parent)) => {
              let (named, _, asserting) = read_version(parent, remotes)
              (named, asserting)
            }
            _ => raise Unknown(uri)
          }
          let mut asserts = true
          // A dialect that names the assertion vocabulary asserts `format`,
          // whether the entry beside it is `true` or `false`: the boolean is
          // advice for readers that do not know the vocabulary, and this one
          // does.
          let mut format = asserting
          match meta.get("$vocabulary") {
            Some(Object(declared)) => {
              asserts = false
              format = false
              for vocabulary, wanted in declared {
                if vocabulary.has_suffix("/vocab/validation") && wanted is True {
                  asserts = true
                }
                if vocabulary.has_suffix("/vocab/format-assertion") {
                  format = true
                }
              }
            }
            _ => ()
          }
          (version, asserts, format)
        }
        _ => raise Unknown(uri)
      }
  }
}
