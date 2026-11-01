// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// One keyword at a time, in the order the specification groups them: the core
// keywords that address, the applicators that hand the instance on, and the
// assertions that look at it.

///|
/// Whether `value` validates against `node`, recording every reason in `sink`
/// when the caller asked for them.
///
/// `marks` is what this schema evaluated, which is what an `unevaluated*` keyword
/// in a *neighbouring* schema asks about. `base` is the URI a reference here
/// resolves against, which changes as `$id` changes it.
fn Schema::check(
  self : Schema,
  node : Json,
  base : String,
  value : Json,
  at : String,
  spath : String,
  sink : Array[OutputUnit]?,
  marks : Marks,
) -> Bool {
  match node {
    True => return true
    False =>
      return note(
        sink, at, spath, "schema", "no instance validates against false",
      )
    Object(members) => {
      let here = match
        members.get(if self.draft == Draft4 { "id" } else { "$id" }) {
        Some(String(id)) => split_fragment(resolve(base, id)).0
        _ => base
      }
      // Entering a schema resource is what makes the dynamic scope grow, and
      // what a `$dynamicRef` inside it resolves against.
      let entered = here != base
      if entered {
        self.scope.push(here)
      }
      defer (if entered { self.scope.pop() |> ignore })
      let own = Marks::new()
      let mut ok = true
      // Before 2019-09 a `$ref` is the whole schema: everything beside it is
      // ignored, which is why a document from then puts nothing beside one.
      let alone = !self.draft.vocabularies()
      if alone && members.get("$ref") is Some(String(reference)) {
        // Everything beside it is ignored, and a sibling `$id` is beside it: the
        // reference resolves against the base this schema was reached with.
        return self.refer(
          reference,
          base,
          value,
          at,
          step(spath, "$ref"),
          sink,
          marks,
        )
      }
      for keyword, schema in members {
        let kpath = step(spath, keyword)
        // With the validation vocabulary out of force, its keywords annotate
        // rather than assert, so the instance passes whatever they say.
        if !self.asserts && asserted(keyword) {
          continue
        }
        // The reasons this keyword has to give become its children, so that the
        // output has a node per keyword and a leaf per reason, which is the
        // structure §12 asks for.
        let reasons : Array[OutputUnit] = []
        let inner : Array[OutputUnit]? = if sink is None {
          None
        } else {
          Some(reasons)
        }
        // A keyword from a vocabulary outside this library answers with what it
        // contributes, if anything, and the node carries that.
        let mut given : Json? = None
        let passed = match keyword {
          "$ref" =>
            match schema {
              String(reference) =>
                self.refer(reference, here, value, at, kpath, inner, own)
              _ => true
            }
          "$dynamicRef" | "$recursiveRef" =>
            match schema {
              String(reference) =>
                self.refer_dynamic(
                  reference, here, value, at, kpath, inner, own,
                )
              _ => true
            }
          "type" => self.check_type(schema, value, at, kpath, inner)
          "enum" =>
            match schema {
              Array(allowed) =>
                if allowed.search_by(one => same(one, value)) is Some(_) {
                  true
                } else {
                  note(
                    inner, at, kpath, "enum", "not one of the allowed values",
                  )
                }
              _ => true
            }
          "const" =>
            if same(schema, value) {
              true
            } else {
              note(inner, at, kpath, "const", "not the constant value")
            }
          "multipleOf" =>
            match (schema, value) {
              (Number(divisor, ..), Number(number, ..)) =>
                if multiple_of(number, divisor) {
                  true
                } else {
                  note(inner, at, kpath, "multipleOf", "not a multiple")
                }
              _ => true
            }
          "maximum" =>
            self.check_bound(members, schema, value, at, kpath, inner, true)
          "minimum" =>
            self.check_bound(members, schema, value, at, kpath, inner, false)
          "exclusiveMaximum" =>
            match (schema, value) {
              (Number(limit, ..), Number(number, ..)) =>
                if number < limit {
                  true
                } else {
                  note(
                    inner, at, kpath, "exclusiveMaximum", "above the maximum",
                  )
                }
              // Before draft-06 this was a flag on `maximum`, handled there.
              _ => true
            }
          "exclusiveMinimum" =>
            match (schema, value) {
              (Number(limit, ..), Number(number, ..)) =>
                if number > limit {
                  true
                } else {
                  note(
                    inner, at, kpath, "exclusiveMinimum", "below the minimum",
                  )
                }
              _ => true
            }
          "maxLength" =>
            match (schema, value) {
              (Number(limit, ..), String(text)) =>
                if code_points(text) <= limit.to_int() {
                  true
                } else {
                  note(inner, at, kpath, "maxLength", "longer than allowed")
                }
              _ => true
            }
          "minLength" =>
            match (schema, value) {
              (Number(limit, ..), String(text)) =>
                if code_points(text) >= limit.to_int() {
                  true
                } else {
                  note(inner, at, kpath, "minLength", "shorter than allowed")
                }
              _ => true
            }
          "format" => self.check_format(schema, value, at, kpath, inner)
          "pattern" =>
            match (schema, value) {
              (String(expression), String(text)) =>
                if self.matches(expression, text) {
                  true
                } else {
                  note(
                    inner, at, kpath, "pattern", "does not match the pattern",
                  )
                }
              _ => true
            }
          "prefixItems" | "items" | "additionalItems" =>
            self.check_items(
              members, keyword, schema, here, value, at, spath, inner, own,
            )
          "contains" =>
            self.check_contains(
              members, schema, here, value, at, kpath, inner, own,
            )
          "maxItems" =>
            match (schema, value) {
              (Number(limit, ..), Array(items)) =>
                if items.length() <= limit.to_int() {
                  true
                } else {
                  note(inner, at, kpath, "maxItems", "more items than allowed")
                }
              _ => true
            }
          "minItems" =>
            match (schema, value) {
              (Number(limit, ..), Array(items)) =>
                if items.length() >= limit.to_int() {
                  true
                } else {
                  note(inner, at, kpath, "minItems", "fewer items than allowed")
                }
              _ => true
            }
          "uniqueItems" =>
            match (schema, value) {
              (True, Array(items)) =>
                if unique(items) {
                  true
                } else {
                  note(inner, at, kpath, "uniqueItems", "two items are equal")
                }
              _ => true
            }
          "properties" | "patternProperties" | "additionalProperties" =>
            self.check_properties(
              members, keyword, schema, here, value, at, spath, inner, own,
            )
          "propertyNames" =>
            match value {
              Object(instance) => {
                let mut every = true
                for name, _ in instance {
                  if !self.check(
                      schema,
                      here,
                      Json::string(name),
                      step(at, name),
                      kpath,
                      inner,
                      Marks::new(),
                    ) {
                    every = false
                    if inner is None {
                      break
                    }
                  }
                }
                every
              }
              _ => true
            }
          "required" =>
            match (schema, value) {
              (Array(names), Object(instance)) => {
                let mut every = true
                for name in names {
                  match name {
                    String(text) =>
                      if instance.get(text) is None {
                        every = note(
                          inner,
                          at,
                          kpath,
                          "required",
                          "missing " + text,
                        )
                        if inner is None {
                          break
                        }
                      }
                    _ => ()
                  }
                }
                every
              }
              _ => true
            }
          "maxProperties" =>
            match (schema, value) {
              (Number(limit, ..), Object(instance)) =>
                if instance.length() <= limit.to_int() {
                  true
                } else {
                  note(
                    inner, at, kpath, "maxProperties", "more properties than allowed",
                  )
                }
              _ => true
            }
          "minProperties" =>
            match (schema, value) {
              (Number(limit, ..), Object(instance)) =>
                if instance.length() >= limit.to_int() {
                  true
                } else {
                  note(
                    inner, at, kpath, "minProperties", "fewer properties than allowed",
                  )
                }
              _ => true
            }
          "dependencies" | "dependentRequired" | "dependentSchemas" =>
            self.check_dependencies(
              keyword, schema, here, value, at, kpath, inner, own,
            )
          "propertyDependencies" =>
            self.check_property_dependencies(
              schema, here, value, at, kpath, inner, own,
            )
          "allOf" =>
            match schema {
              Array(branches) => {
                let mut every = true
                for i = 0; i < branches.length(); i = i + 1 {
                  let branch = Marks::new()
                  if self.check(
                      branches[i],
                      here,
                      value,
                      at,
                      step(kpath, i.to_string()),
                      inner,
                      branch,
                    ) {
                    own.take(branch)
                  } else {
                    every = false
                    if inner is None {
                      break
                    }
                  }
                }
                every
              }
              _ => true
            }
          "anyOf" =>
            match schema {
              Array(branches) => {
                let mut any = false
                for i = 0; i < branches.length(); i = i + 1 {
                  let branch = Marks::new()
                  // A branch that fails is not a fault of the instance: only
                  // every branch failing is, so the reasons are dropped here.
                  if self.check(
                      branches[i],
                      here,
                      value,
                      at,
                      step(kpath, i.to_string()),
                      None,
                      branch,
                    ) {
                    own.take(branch)
                    any = true
                  }
                }
                if any {
                  true
                } else {
                  note(inner, at, kpath, "anyOf", "no branch validated")
                }
              }
              _ => true
            }
          "oneOf" =>
            match schema {
              Array(branches) => {
                let mut count = 0
                let winner = Marks::new()
                for i = 0; i < branches.length(); i = i + 1 {
                  let branch = Marks::new()
                  if self.check(
                      branches[i],
                      here,
                      value,
                      at,
                      step(kpath, i.to_string()),
                      None,
                      branch,
                    ) {
                    count = count + 1
                    if count == 1 {
                      winner.take(branch)
                    }
                  }
                }
                if count == 1 {
                  own.take(winner)
                  true
                } else if count == 0 {
                  note(inner, at, kpath, "oneOf", "no branch validated")
                } else {
                  note(
                    inner,
                    at,
                    kpath,
                    "oneOf",
                    count.to_string() + " branches validated, not one",
                  )
                }
              }
              _ => true
            }
          "not" =>
            if self.check(schema, here, value, at, kpath, None, Marks::new()) {
              note(
                inner, at, kpath, "not", "validated against the negated schema",
              )
            } else {
              true
            }
          // `if` never fails on its own: it picks which of `then` and `else`
          // applies, and the reasons come from whichever it picked.
          "if" => {
            let branch = Marks::new()
            let taken = self.check(schema, here, value, at, kpath, None, branch)
            if taken {
              own.take(branch)
            }
            let arm = if taken { "then" } else { "else" }
            match members.get(arm) {
              Some(consequent) => {
                let branch = Marks::new()
                if self.check(
                    consequent,
                    here,
                    value,
                    at,
                    step(spath, arm),
                    inner,
                    branch,
                  ) {
                  own.take(branch)
                  true
                } else {
                  false
                }
              }
              None => true
            }
          }
          // `then` and `else` are applied by `if` and never on their own.
          "then" | "else" => true
          _ =>
            match self.extra.get(keyword) {
              Some((judged, asserts)) =>
                // An optional vocabulary — one the metaschema names with `false`
                // — annotates and asserts nothing, whatever its keyword says.
                if !asserts {
                  given = Some(schema)
                  true
                } else {
                  match judged.judge(schema, value, { at, schema_at: kpath, }) {
                    Accept => true
                    Annotate(annotation~) => {
                      given = Some(annotation)
                      true
                    }
                    Refuse(why~) => note(inner, at, kpath, keyword, why)
                  }
                }
              None => true
            }
        }
        match sink {
          Some(list) =>
            list.push({
              valid: passed,
              keyword_at: kpath,
              absolute_at: None,
              at,
              error: None,
              annotation: match annotation_of(keyword, schema) {
                Some(found) => Some(found)
                None => given
              },
              children: reasons,
            })
          None => ()
        }
        if !passed {
          ok = false
          if sink is None {
            break
          }
        }
      }
      if ok && self.draft.vocabularies() {
        ok = self.check_unevaluated(members, here, value, at, spath, sink, own)
      }
      if ok {
        marks.take(own)
      }
      ok
    }
    _ => true
  }
}

///|
/// Follow a `$ref` and validate against what it names.
fn Schema::refer(
  self : Schema,
  reference : String,
  base : String,
  value : Json,
  at : String,
  spath : String,
  sink : Array[OutputUnit]?,
  marks : Marks,
) -> Bool {
  match self.follow(base, reference) {
    Some((target, outside)) => {
      let inner = Marks::new()
      let resource = split_fragment(resolve(base, reference)).0
      // Landing inside another resource enters it, however the reference was
      // written and whether or not the target itself carries the `$id`.
      let entered = resource != "" && resource != base
      if entered {
        self.scope.push(resource)
      }
      defer (if entered { self.scope.pop() |> ignore })
      let ok = self.check(target, outside, value, at, spath, sink, inner)
      if ok {
        marks.take(inner)
      }
      ok
    }
    None => note(sink, at, spath, "$ref", "reference resolves to nothing")
  }
}

///|
/// Follow a `$dynamicRef` or a `$recursiveRef`, which land on the outermost
/// anchor of the same name rather than the nearest (2020-12 §8.2.3.2).
fn Schema::refer_dynamic(
  self : Schema,
  reference : String,
  base : String,
  value : Json,
  at : String,
  spath : String,
  sink : Array[OutputUnit]?,
  marks : Marks,
) -> Bool {
  let name = if reference == "#" { "" } else { split_fragment(reference).1 }
  let target = if self.draft == V1 {
    // v1 dropped the bookending requirement: the name alone picks the target,
    // from the outermost resource in scope that carries a `$dynamicAnchor` by
    // it, and there is no falling back on a plain reference.
    self.outermost(name)
  } else {
    // Before v1 it resolves like a plain reference first. Only when what it
    // lands on is itself a dynamic anchor of that name does the dynamic scope
    // take over — and then it is the outermost resource in scope that answers,
    // not the nearest.
    let landed = self.follow(base, reference)
    let dynamic = match landed {
      Some((Object(members), _)) =>
        if name == "" {
          members.get("$recursiveAnchor") is Some(True)
        } else {
          match members.get("$dynamicAnchor") {
            Some(String(found)) => found == name
            _ => false
          }
        }
      _ => false
    }
    if dynamic {
      match self.outermost(name) {
        Some(found) => Some(found)
        None => landed
      }
    } else {
      landed
    }
  }
  match target {
    Some((found, outside)) => {
      let inner = Marks::new()
      let ok = self.check(found, outside, value, at, spath, sink, inner)
      if ok {
        marks.take(inner)
      }
      ok
    }
    None =>
      note(sink, at, spath, "$dynamicRef", "reference resolves to nothing")
  }
}

///|
/// Record a fault, and answer `false` so a caller can `return note(...)`.
fn note(
  sink : Array[OutputUnit]?,
  at : String,
  schema_at : String,
  keyword : String,
  message : String,
) -> Bool {
  ignore(keyword)
  match sink {
    Some(list) =>
      list.push({
        valid: false,
        keyword_at: schema_at,
        absolute_at: None,
        at,
        error: Some(message),
        annotation: None,
        children: [],
      })
    None => ()
  }
  false
}

///|
/// Whether a keyword belongs to the validation vocabulary, which is the set a
/// metaschema can leave out (2020-12 §6).
fn asserted(keyword : String) -> Bool {
  match keyword {
    "type"
    | "enum"
    | "const"
    | "multipleOf"
    | "maximum"
    | "exclusiveMaximum"
    | "minimum"
    | "exclusiveMinimum"
    | "maxLength"
    | "minLength"
    | "pattern"
    | "maxItems"
    | "minItems"
    | "uniqueItems"
    | "maxContains"
    | "minContains"
    | "maxProperties"
    | "minProperties"
    | "required"
    | "dependentRequired" => true
    _ => false
  }
}
