// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The four output formats of §12: `flag`, `basic`, `detailed` and `verbose`.
//
// A validation collects `OutputUnit`s as it walks: one per keyword, with the
// reasons that keyword had to give as that unit's children. Three of the four
// formats are then one reading of that tree — flattened, pruned, or whole — so
// that the four cannot disagree about what happened, only about how much of it
// they say.

///|
/// One result of one keyword: the output unit of §12.3.
///
/// `keyword_at` is the *evaluation path*, which is a JSON Pointer that goes
/// through `$ref`; `absolute_at` is the *schema location*, which is the
/// resource's own URI and a pointer into it and never goes through one. The two
/// differ exactly when a reference was crossed, and a reader that has to fetch
/// the keyword needs the second.
#derive(Eq, Debug)
pub(all) struct OutputUnit {
  /// Whether this result is a pass.
  valid : Bool
  /// Where in the schema, following the walk that arrived.
  keyword_at : String
  /// The resource's canonical URI and a pointer into it, when it can be said.
  absolute_at : String?
  /// Where in the instance, as a JSON Pointer.
  at : String
  /// What went wrong, in one clause. A branch that only has children under it
  /// has nothing of its own to say.
  error : String?
  /// What the keyword contributed, when it produced an annotation.
  annotation : Json?
  /// The results this one encloses.
  children : Array[OutputUnit]
}

///|
pub extend OutputUnit with Eq::{equal, not_equal}

///|
pub extend OutputUnit with Debug::{to_repr}

///|
/// What a validation came to, in the shape the caller asked for.
///
/// `units` is the whole of it: empty for `flag`, flat for `basic`, a pruned tree
/// for `detailed`, and the tree the walk produced for `verbose`. [`Report::to_json`]
/// writes it as §12.4's object, which is what a caller sends over a wire.
#derive(Eq, Debug)
pub(all) struct Report {
  /// Whether the instance conformed.
  valid : Bool
  /// The results, nested as the format asks.
  units : Array[OutputUnit]
}

///|
pub extend Report with Eq::{equal, not_equal}

///|
pub extend Report with Debug::{to_repr}

///|
/// What a keyword contributes when it passes, which is its own value for the
/// keywords that §10 calls annotations and nothing for the rest.
fn annotation_of(keyword : String, value : Json) -> Json? {
  match keyword {
    "title"
    | "description"
    | "default"
    | "deprecated"
    | "readOnly"
    | "writeOnly"
    | "examples"
    | "format"
    | "contentEncoding"
    | "contentMediaType"
    | "contentSchema" => Some(value)
    _ => None
  }
}

///|
/// Validate `instance` and answer in the format `output` names.
///
/// ```moonbit check
/// test {
///   let schema = @moonschema.Schema::new(
///     @json.parse("{ \"type\": \"integer\", \"minimum\": 1 }"),
///   )
///   let report = schema.report(@json.parse("0"), output=@moonschema.Output::Basic)
///   assert_eq(report.valid, false)
///   assert_eq(report.units[0].keyword_at, "/minimum")
///   assert_eq(report.units[0].error, Some("below the minimum"))
/// }
/// ```
pub fn Schema::report(
  self : Schema,
  instance : Json,
  output~ : Output = output,
) -> Report {
  let collected : Array[OutputUnit] = []
  self.scope.clear()
  self.scope.push(self.base)
  let valid = self.check(
    self.root,
    self.base,
    instance,
    "",
    "",
    Some(collected),
    Marks::new(),
  )
  let placed = order(self.place(collected))
  let units = match output {
    Flag => []
    Basic =>
      if valid {
        // A validation that passed has annotations and no errors, and the flat
        // format lists whichever it has.
        annotated(placed)
      } else {
        flat(prune(placed))
      }
    Detailed => prune(placed)
    Verbose => placed
  }
  { valid, units, }
}

///|
/// The units in the order a reader follows them: by evaluation path, and by
/// instance location where two share one.
///
/// A schema is a `Map` here, so the order a walk visits its keywords in is the
/// order the map keeps them, which is neither the document's nor anyone's. Two
/// runs of one validation should read the same, so the output is put in an order
/// that depends on nothing but the paths.
fn order(units : Array[OutputUnit]) -> Array[OutputUnit] {
  let sorted = units.map(fn(unit) {
    { ..unit, children: order(unit.children), }
  })
  // An insertion sort, because the result has to be the same on every backend
  // and a comparison of two pointers is all this is.
  for i = 1; i < sorted.length(); i = i + 1 {
    let held = sorted[i]
    let mut j = i
    while j > 0 && after(sorted[j - 1], held) {
      sorted[j] = sorted[j - 1]
      j = j - 1
    }
    sorted[j] = held
  }
  sorted
}

///|
/// Whether `left` belongs after `right` in the output.
fn after(left : OutputUnit, right : OutputUnit) -> Bool {
  let by_keyword = lexical(left.keyword_at, right.keyword_at)
  if by_keyword != 0 {
    by_keyword > 0
  } else {
    lexical(left.at, right.at) > 0
  }
}

///|
/// Two strings by the code point at a time, which is what an order of pointers
/// means: `String::compare` is the library's own and is not this order.
fn lexical(left : String, right : String) -> Int32 {
  let a = left[:]
  let b = right[:]
  let shorter = if a.length() < b.length() { a.length() } else { b.length() }
  let mut i = 0
  while i < shorter {
    let here = a[i].to_int()
    let there = b[i].to_int()
    if here != there {
      if here < there {
        return -1
      } else {
        return 1
      }
    }
    i = i + 1
  }
  if a.length() == b.length() {
    0
  } else if a.length() < b.length() {
    -1
  } else {
    1
  }
}

///|
/// Every result in the tree, in the order the walk produced them.
fn flat(units : Array[OutputUnit]) -> Array[OutputUnit] {
  let out : Array[OutputUnit] = []
  for unit in units {
    out.push({ ..unit, children: [], error: message_of(unit), })
    for child in flat(unit.children) {
      out.push(child)
    }
  }
  out
}

///|
/// What a flat entry says, which for a branch is that something under it failed.
fn message_of(unit : OutputUnit) -> String? {
  match unit.error {
    Some(message) => Some(message)
    None => if unit.valid { None } else { Some("a subschema had errors") }
  }
}

///|
/// What passed and said something: the annotations of a validation that held.
fn annotated(units : Array[OutputUnit]) -> Array[OutputUnit] {
  let out : Array[OutputUnit] = []
  for unit in units {
    for child in annotated(unit.children) {
      out.push(child)
    }
    if unit.annotation is Some(_) {
      out.push({ ..unit, children: [], })
    }
  }
  out
}

///|
/// The tree with everything that explains nothing taken out.
///
/// A pass explains nothing about a failure. A branch with one reason under it
/// is that reason, one level up: the hierarchy exists to show where several
/// reasons share a place, and a chain of single reasons shows nothing.
fn prune(units : Array[OutputUnit]) -> Array[OutputUnit] {
  let out : Array[OutputUnit] = []
  for unit in units {
    if unit.valid {
      continue
    }
    let children = prune(unit.children)
    if children.length() == 1 && unit.error is None {
      out.push(children[0])
      continue
    }
    if children.length() == 0 && unit.error is None {
      continue
    }
    out.push({ ..unit, error: message_of(unit), children, })
  }
  out
}

///|
/// Every unit with its schema location filled in.
///
/// The walk knows the evaluation path and not the resource it passes through, so
/// the location is worked out afterwards by walking the same path through the
/// document: a pointer step stays in the resource, and a `$ref` step moves to
/// the one it names.
fn Schema::place(self : Schema, units : Array[OutputUnit]) -> Array[OutputUnit] {
  let out : Array[OutputUnit] = []
  for unit in units {
    out.push({
      ..unit,
      absolute_at: self.absolute_of(unit.keyword_at),
      children: self.place(unit.children),
    })
  }
  out
}

///|
/// The schema location of the keyword at `path`, or `None` when the walk went
/// through an anchor and no pointer says where it landed.
fn Schema::absolute_of(self : Schema, path : String) -> String? {
  // A document that names no `$id` has no location to point at, and §12.3.2
  // lets the answer be nothing.
  if self.base == "" {
    return None
  }
  let text = path[:]
  let mut base = self.base
  let mut location = ""
  let mut node = self.root
  let mut i = 0
  while i < text.length() {
    let start = i
    let mut end = i + 1
    while end < text.length() && text[end] != '/' {
      end = end + 1
    }
    // Kept as it was written: a JSON Pointer escapes `~` and `/`, and a path
    // that has been through `step` is already escaped.
    let raw = text[start + 1:end].to_owned()
    let token = unescape(raw)
    let reference = if (token == "$ref" || token == "$dynamicRef") &&
      node is Object(members) {
      match members.get(token) {
        Some(String(found)) => Some(found)
        _ => None
      }
    } else {
      None
    }
    match reference {
      Some(found) => {
        let (document, fragment) = split_fragment(resolve(base, found))
        // An anchor names a place without a pointer, and no pointer can say
        // where it was.
        if !fragment.has_prefix("/") {
          return None
        }
        let resolved_base = if document == "" { base } else { document }
        let root = if resolved_base == self.base || resolved_base == "" {
          Some(self.root)
        } else {
          self.ids.get(resolved_base)
        }
        match root {
          Some(document_root) =>
            match pointer(document_root, fragment) {
              Some(target) => node = target
              None => return None
            }
          None => return None
        }
        base = resolved_base
        location = fragment
      }
      None => {
        location = location + "/" + raw
        node = match node {
          Object(members) =>
            match members.get(token) {
              Some(next) => next
              None => return None
            }
          Array(items) => {
            let index = index_of(token)
            if index < 0 || index >= items.length() {
              return None
            }
            items[index]
          }
          _ => return None
        }
      }
    }
    i = end
  }
  Some(base + "#" + location)
}

///|
/// The report as the object §12.4 describes.
pub impl ToJson for Report with fn to_json(self) {
  let out : Map[String, Json] = Map::Map([])
  out["valid"] = Json::boolean(self.valid)
  // Nested results are `errors` when the validation failed and `annotations`
  // when it held: the plural, because a keyword may have both a result of its
  // own and results under it.
  if self.units.length() > 0 {
    let key = if self.valid { "annotations" } else { "errors" }
    out[key] = Json::array(self.units.map(fn(unit) { ToJson::to_json(unit) }))
  }
  Json::object(out)
}

///|
pub impl ToJson for OutputUnit with fn to_json(self) {
  let out : Map[String, Json] = Map::Map([])
  out["valid"] = Json::boolean(self.valid)
  out["keywordLocation"] = Json::string(self.keyword_at)
  match self.absolute_at {
    Some(location) => out["absoluteKeywordLocation"] = Json::string(location)
    None => ()
  }
  out["instanceLocation"] = Json::string(self.at)
  match self.error {
    Some(message) => out["error"] = Json::string(message)
    None => ()
  }
  match self.annotation {
    Some(value) => out["annotation"] = value
    None => ()
  }
  if self.children.length() > 0 {
    let key = if self.valid { "annotations" } else { "errors" }
    out[key] = Json::array(
      self.children.map(fn(child) { ToJson::to_json(child) }),
    )
  }
  Json::object(out)
}

///|
pub extend Report with ToJson::{to_json}

///|
pub extend OutputUnit with ToJson::{to_json}
