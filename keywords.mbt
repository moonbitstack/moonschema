// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The keywords whose work does not fit on one line of `check`: the ones that
// look at a whole array or object, and the ones the versions spell differently.

///|
/// `type`, which is one name or a list of them.
fn Schema::check_type(
  self : Schema,
  schema : Json,
  value : Json,
  at : String,
  spath : String,
  faults : Array[Fault]?,
) -> Bool {
  ignore(self)
  match schema {
    String(name) =>
      if is_type(value, name) {
        true
      } else {
        note(faults, at, spath, "type", "not of type " + name)
      }
    Array(names) => {
      for name in names {
        if name is String(text) && is_type(value, text) {
          return true
        }
      }
      note(faults, at, spath, "type", "not of any allowed type")
    }
    _ => true
  }
}

///|
/// `maximum` and `minimum`, and the flag draft-04 wrote beside them.
///
/// Before draft-06, `exclusiveMaximum` was a boolean that made `maximum`
/// exclusive; from draft-06 it is a number and stands on its own. Reading a
/// draft-04 document at a later version would silently loosen the bound, which
/// is why the version decides and not the shape.
fn Schema::check_bound(
  self : Schema,
  members : Map[String, Json],
  schema : Json,
  value : Json,
  at : String,
  spath : String,
  faults : Array[Fault]?,
  upper : Bool,
) -> Bool {
  guard schema is Number(limit, ..) && value is Number(number, ..) else {
    return true
  }
  let keyword = if upper { "maximum" } else { "minimum" }
  let exclusive = self.draft == Draft4 &&
    members.get(if upper { "exclusiveMaximum" } else { "exclusiveMinimum" })
    is Some(True)
  let ok = if upper {
    if exclusive {
      number < limit
    } else {
      number <= limit
    }
  } else if exclusive {
    number > limit
  } else {
    number >= limit
  }
  if ok {
    true
  } else {
    note(
      faults,
      at,
      spath,
      keyword,
      if upper {
        "above the maximum"
      } else {
        "below the minimum"
      },
    )
  }
}

///|
/// `prefixItems`, `items` and `additionalItems` — the one group the versions
/// really do spell differently.
///
/// Through 2019-09, `items` is either a schema for every item or a list for the
/// leading ones, and `additionalItems` takes the rest. From 2020-12 the list is
/// `prefixItems`, `items` is always the schema for the rest, and
/// `additionalItems` is not a keyword at all.
fn Schema::check_items(
  self : Schema,
  members : Map[String, Json],
  keyword : String,
  schema : Json,
  base : String,
  value : Json,
  at : String,
  spath : String,
  faults : Array[Fault]?,
  marks : Marks,
) -> Bool {
  guard value is Array(items) else { return true }
  let modern = self.draft == Draft2020
  match keyword {
    "prefixItems" =>
      if modern && schema is Array(schemas) {
        self.each_item(
          schemas, base, items, 0, at, spath, keyword, faults, marks,
        )
      } else {
        true
      }
    "additionalItems" =>
      if !modern && members.get("items") is Some(Array(prefix)) {
        self.rest_items(
          schema,
          base,
          items,
          prefix.length(),
          at,
          spath,
          keyword,
          faults,
          marks,
        )
      } else {
        true
      }
    "items" =>
      if modern {
        let prefix = match members.get("prefixItems") {
          Some(Array(schemas)) => schemas.length()
          _ => 0
        }
        self.rest_items(
          schema, base, items, prefix, at, spath, keyword, faults, marks,
        )
      } else {
        match schema {
          Array(schemas) =>
            self.each_item(
              schemas, base, items, 0, at, spath, keyword, faults, marks,
            )
          _ =>
            self.rest_items(
              schema, base, items, 0, at, spath, keyword, faults, marks,
            )
        }
      }
    _ => true
  }
}

///|
/// A list of schemas against the items at the same positions.
fn Schema::each_item(
  self : Schema,
  schemas : Array[Json],
  base : String,
  items : Array[Json],
  from : Int,
  at : String,
  spath : String,
  keyword : String,
  faults : Array[Fault]?,
  marks : Marks,
) -> Bool {
  let mut every = true
  for i = 0; i < schemas.length() && from + i < items.length(); i = i + 1 {
    let index = from + i
    if self.check(
        schemas[i],
        base,
        items[index],
        step(at, index.to_string()),
        step(step(spath, keyword), i.to_string()),
        faults,
        Marks::new(),
      ) {
      marks.idx.add(index)
    } else {
      every = false
      if faults is None {
        break
      }
    }
  }
  every
}

///|
/// One schema against every item from `from` on.
fn Schema::rest_items(
  self : Schema,
  schema : Json,
  base : String,
  items : Array[Json],
  from : Int,
  at : String,
  spath : String,
  keyword : String,
  faults : Array[Fault]?,
  marks : Marks,
) -> Bool {
  let mut every = true
  for index = from; index < items.length(); index = index + 1 {
    if self.check(
        schema,
        base,
        items[index],
        step(at, index.to_string()),
        step(spath, keyword),
        faults,
        Marks::new(),
      ) {
      marks.idx.add(index)
    } else {
      every = false
      if faults is None {
        break
      }
    }
  }
  if every && from <= items.length() {
    // Everything from `from` on was evaluated, however many that was.
    marks.all_items = marks.all_items || from == 0
  }
  every
}

///|
/// `contains`, with the counts 2019-09 added.
fn Schema::check_contains(
  self : Schema,
  members : Map[String, Json],
  schema : Json,
  base : String,
  value : Json,
  at : String,
  spath : String,
  faults : Array[Fault]?,
  marks : Marks,
) -> Bool {
  // `contains` arrived in draft-06.
  guard self.draft != Draft4 && value is Array(items) else { return true }
  let counted = self.draft == Draft2019 || self.draft == Draft2020
  let least = match (counted, members.get("minContains")) {
    (true, Some(Number(n, ..))) => n.to_int()
    _ => 1
  }
  let most = match (counted, members.get("maxContains")) {
    (true, Some(Number(n, ..))) => n.to_int()
    _ => -1
  }
  let mut found = 0
  for index = 0; index < items.length(); index = index + 1 {
    if self.check(
        schema,
        base,
        items[index],
        step(at, index.to_string()),
        spath,
        None,
        Marks::new(),
      ) {
      found = found + 1
      marks.idx.add(index)
    }
  }
  if found < least {
    return note(
      faults, at, spath, "contains", "fewer matching items than required",
    )
  }
  if most >= 0 && found > most {
    return note(
      faults, at, spath, "contains", "more matching items than allowed",
    )
  }
  true
}

///|
/// `properties`, `patternProperties` and `additionalProperties`, which read the
/// same object and have to agree on which held each of them owns.
fn Schema::check_properties(
  self : Schema,
  members : Map[String, Json],
  keyword : String,
  schema : Json,
  base : String,
  value : Json,
  at : String,
  spath : String,
  faults : Array[Fault]?,
  marks : Marks,
) -> Bool {
  guard value is Object(instance) else { return true }
  let mut every = true
  match keyword {
    "properties" =>
      match schema {
        Object(schemas) =>
          for name, subschema in schemas {
            match instance.get(name) {
              Some(held) =>
                if self.check(
                    subschema,
                    base,
                    held,
                    step(at, name),
                    step(step(spath, keyword), name),
                    faults,
                    Marks::new(),
                  ) {
                  marks.props.add(name)
                } else {
                  every = false
                }
              None => ()
            }
          }
        _ => ()
      }
    "patternProperties" =>
      match schema {
        Object(schemas) =>
          for expression, subschema in schemas {
            for name, held in instance {
              if self.matches(expression, name) {
                if self.check(
                    subschema,
                    base,
                    held,
                    step(at, name),
                    step(step(spath, keyword), expression),
                    faults,
                    Marks::new(),
                  ) {
                  marks.props.add(name)
                } else {
                  every = false
                }
              }
            }
          }
        _ => ()
      }
    "additionalProperties" => {
      let named = match members.get("properties") {
        Some(Object(schemas)) => schemas
        _ => Map::Map([])
      }
      let patterns = match members.get("patternProperties") {
        Some(Object(schemas)) => schemas
        _ => Map::Map([])
      }
      for name, held in instance {
        if named.get(name) is Some(_) {
          continue
        }
        let mut covered = false
        for expression, _ in patterns {
          if self.matches(expression, name) {
            covered = true
            break
          }
        }
        if covered {
          continue
        }
        if self.check(
            schema,
            base,
            held,
            step(at, name),
            step(spath, keyword),
            faults,
            Marks::new(),
          ) {
          marks.props.add(name)
        } else {
          every = false
        }
      }
    }
    _ => ()
  }
  every
}

///|
/// `dependencies` and the two keywords 2019-09 split it into.
fn Schema::check_dependencies(
  self : Schema,
  keyword : String,
  schema : Json,
  base : String,
  value : Json,
  at : String,
  spath : String,
  faults : Array[Fault]?,
  marks : Marks,
) -> Bool {
  guard value is Object(instance) && schema is Object(entries) else {
    return true
  }
  // `dependencies` was split in 2019-09; reading one at the other's version
  // would apply a keyword that version does not have.
  let split = self.draft == Draft2019 || self.draft == Draft2020
  if (keyword == "dependencies" && split) ||
    (keyword != "dependencies" && !split) {
    return true
  }
  let mut every = true
  for name, requirement in entries {
    if instance.get(name) is None {
      continue
    }
    let ok = match requirement {
      Array(names) => {
        let mut all = true
        for needed in names {
          if needed is String(text) && instance.get(text) is None {
            all = note(
              faults,
              at,
              step(spath, name),
              keyword,
              "missing " + text,
            )
          }
        }
        all
      }
      _ => {
        if keyword == "dependentRequired" {
          continue
        }
        let inner = Marks::new()
        let passed = self.check(
          requirement,
          base,
          value,
          at,
          step(spath, name),
          faults,
          inner,
        )
        if passed {
          marks.take(inner)
        }
        passed
      }
    }
    if !ok {
      every = false
      if faults is None {
        break
      }
    }
  }
  every
}

///|
/// `unevaluatedItems` and `unevaluatedProperties`, which apply to whatever every
/// other keyword in this schema — and every in-place applicator it reached —
/// left untouched.
fn Schema::check_unevaluated(
  self : Schema,
  members : Map[String, Json],
  base : String,
  value : Json,
  at : String,
  spath : String,
  faults : Array[Fault]?,
  marks : Marks,
) -> Bool {
  let mut every = true
  match (members.get("unevaluatedItems"), value) {
    (Some(schema), Array(items)) =>
      if !marks.all_items {
        for index = 0; index < items.length(); index = index + 1 {
          if marks.idx.contains(index) {
            continue
          }
          if self.check(
              schema,
              base,
              items[index],
              step(at, index.to_string()),
              step(spath, "unevaluatedItems"),
              faults,
              Marks::new(),
            ) {
            marks.idx.add(index)
          } else {
            every = false
          }
        }
      }
    _ => ()
  }
  match (members.get("unevaluatedProperties"), value) {
    (Some(schema), Object(instance)) =>
      for name, held in instance {
        if marks.props.contains(name) {
          continue
        }
        if self.check(
            schema,
            base,
            held,
            step(at, name),
            step(spath, "unevaluatedProperties"),
            faults,
            Marks::new(),
          ) {
          marks.props.add(name)
        } else {
          every = false
        }
      }
    _ => ()
  }
  every
}

// -------------------------------------------------------------- the instance

///|
/// The name the specification gives this instance's type.
fn kind(value : Json) -> String {
  match value {
    Null => "null"
    True | False => "boolean"
    Number(_, ..) => "number"
    String(_) => "string"
    Array(_) => "array"
    Object(_) => "object"
  }
}

///|
/// Whether an instance is of the named type.
///
/// `integer` is a number with nothing after the decimal point, which is what
/// JSON leaves it as: `1.0` and `1` are the same number.
fn is_type(value : Json, name : String) -> Bool {
  match name {
    "integer" =>
      match value {
        Number(number, ..) =>
          number == number.floor() && number.is_inf() == false
        _ => false
      }
    _ => kind(value) == name
  }
}

///|
/// Whether two instances are the same value.
///
/// Numbers compare as numbers, so `1.0` and `1` are equal however each was
/// written, and objects compare by their members rather than by the order the
/// members arrived in.
fn same(left : Json, right : Json) -> Bool {
  match (left, right) {
    (Null, Null) => true
    (True, True) => true
    (False, False) => true
    (Number(a, ..), Number(b, ..)) => a == b
    (String(a), String(b)) => a == b
    (Array(a), Array(b)) => {
      if a.length() != b.length() {
        return false
      }
      for i = 0; i < a.length(); i = i + 1 {
        if !same(a[i], b[i]) {
          return false
        }
      }
      true
    }
    (Object(a), Object(b)) => {
      if a.length() != b.length() {
        return false
      }
      for name, value in a {
        match b.get(name) {
          Some(other) => if !same(value, other) { return false }
          None => return false
        }
      }
      true
    }
    _ => false
  }
}

///|
/// Whether no two items are the same value.
fn unique(items : Array[Json]) -> Bool {
  for i = 0; i < items.length(); i = i + 1 {
    for j = i + 1; j < items.length(); j = j + 1 {
      if same(items[i], items[j]) {
        return false
      }
    }
  }
  true
}

///|
/// Whether `number` is a multiple of `divisor`.
///
/// The comparison allows the error a binary float carries: `0.0075` divided by
/// `0.0001` is `74.999999999999986`, and calling that not a multiple of the
/// other would be an artefact of the arithmetic rather than a fact about the
/// numbers.
fn multiple_of(number : Double, divisor : Double) -> Bool {
  if divisor == 0.0 {
    return false
  }
  let quotient = number / divisor
  if quotient.is_inf() {
    return false
  }
  let nearest = quotient.round()
  let scale = if quotient.abs() > 1.0 { quotient.abs() } else { 1.0 }
  (quotient - nearest).abs() <= 1.0e-9 * scale
}

///|
/// How many code points a string is, which is what a length is counted in: an
/// emoji is one character however many units it takes to store.
fn code_points(text : String) -> Int {
  let mut count = 0
  for _ in text {
    count = count + 1
  }
  count
}

///|
/// Whether `text` holds a match for the ECMA-262 regular expression.
///
/// `pattern` searches rather than anchors (§6.3.3), so a match anywhere is a
/// match. A pattern the engine cannot read matches nothing: a schema's own
/// mistake should refuse instances rather than admit every one of them.
///
/// A pattern is read once and kept, because the same one is applied to every
/// member of every instance and a property escape expands into a class of a
/// few thousand ranges.
fn Schema::matches(self : Schema, expression : String, text : String) -> Bool {
  match self.patterns.get(expression) {
    Some(Some(regex)) => regex.execute(text[:]) is Some(_)
    Some(None) => false
    None => {
      let read : @string.Regex? = Some(
        @string.Regex::Regex(ecma(expression)[:]),
      ) catch {
        _ => None
      }
      self.patterns[expression] = read
      match read {
        Some(regex) => regex.execute(text[:]) is Some(_)
        None => false
      }
    }
  }
}

///|
/// An ECMA-262 pattern in the spelling this engine reads.
///
/// Three things are rewritten. `\d`, `\w` and `\s` are ECMA-262's shorthand
/// classes and the engine wants the POSIX names for the same sets. A property
/// escape, `\p{Letter}` and its like, becomes the ranges that category holds —
/// the engine has no Unicode properties of its own, and its `[[:alpha:]]` is
/// ASCII, so the ranges are carried here instead. Everything else, backslash
/// escapes included, is the engine's already and passes through.
///
/// A property nobody here knows — a script, a binary property — is left as it
/// was written, which the engine refuses: a name this cannot honour should not
/// quietly match something else.
fn ecma(pattern : String) -> String {
  let text = pattern[:]
  let out = StringBuilder()
  let mut inside = false
  let mut i = 0
  while i < text.length() {
    let c = text[i]
    if c == '\\' && i + 1 < text.length() {
      let next = text[i + 1]
      let name = match next {
        'd' | 'D' => "digit"
        'w' | 'W' => "word"
        's' | 'S' => "space"
        _ => ""
      }
      let negated = next == 'D' || next == 'W' || next == 'S' || next == 'P'
      if next == 'p' || next == 'P' {
        match property(text, i + 2) {
          Some((body, after)) => {
            if inside {
              // A negated property inside a class has no spelling here, so it
              // is left alone and the engine says so.
              if negated {
                out.write_string(text[i:after].to_owned())
              } else {
                out.write_string(body)
              }
            } else if negated {
              out.write_string("[^" + body + "]")
            } else {
              out.write_string("[" + body + "]")
            }
            i = after
            continue
          }
          None => {
            out.write_string(text[i:i + 2].to_owned())
            i = i + 2
            continue
          }
        }
      }
      if name == "" {
        // Every other escape is this engine's as well, backslash included.
        out.write_string(text[i:i + 2].to_owned())
      } else if inside {
        if negated {
          out.write_string(text[i:i + 2].to_owned())
        } else {
          out.write_string("[:" + name + ":]")
        }
      } else if negated {
        out.write_string("[^[:" + name + ":]]")
      } else {
        out.write_string("[[:" + name + ":]]")
      }
      i = i + 2
      continue
    }
    if c == '[' {
      inside = true
    } else if c == ']' {
      inside = false
    }
    out.write_string(text[i:i + 1].to_owned())
    i = i + 1
  }
  out.to_string()
}

///|
/// The ranges the property escape starting at `from` names, and where it ends,
/// or `None` when the escape is not one this knows.
fn property(text : StringView, from : Int) -> (String, Int)? {
  if from >= text.length() || text[from] != '{' {
    return None
  }
  for i = from + 1; i < text.length(); i = i + 1 {
    if text[i] == '}' {
      let name = text[from + 1:i].to_owned()
      // `General_Category=Lu` names the same thing as `Lu`.
      let bare = if name.has_prefix("General_Category=") {
        name[17:].to_owned()
      } else {
        name
      }
      return match categories.get(bare) {
        Some(body) => Some((body, i + 1))
        None => None
      }
    }
  }
  None
}
