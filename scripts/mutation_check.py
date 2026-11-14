"""Break one decision at a time and check that the test named for it notices.

Each entry changes the library in one place to a plausible mistake, runs the tests, and puts the
file back byte for byte. The tests are the unit tests and, when those do not name the expected one,
the official suite as `gate/` runs it (it needs the `gate/suite` submodule). An entry names the
test that must go red: a unit test's name, or a suite file such as `draft2020-12/minLength.json`.
The run fails when an entry turns nothing red, when what it names stays green, or when the mutated
library does not build.

    python3 scripts/mutation_check.py              # every entry, native
    python3 scripts/mutation_check.py --discover   # print every red test, to fill the table
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

K = "src/keywords.mbt"
C = "src/check.mbt"
F = "src/format.mbt"
U = "src/uri.mbt"
V = "src/validate.mbt"


def fmt(name: str, call: str, test: str):
    return (f"format {name} is asserted", F, f'"{name}" => Some({call})', f'"{name}" => Some(true)', test)


# (what breaks, file, text as it is, text as it would be if the decision were wrong, a test that must go red)
MUTATIONS = [
    # type
    ("integer allows a fraction", K, "number == number.floor() && number.is_inf() == false", "number.is_inf() == false", "type.json / integer type matches integers"),
    ("a single type is checked", K, "      if is_type(value, name) {", "      if true {", "type.json / string type matches strings"),
    ("a list of types is checked", K, "if name is String(text) && is_type(value, text) {", "if name is String(text) {", "type.json / multiple types can be specified in an array"),
    # enum and const
    ("enum looks for the value", C, "if allowed.search_by(one => same(one, value)) is Some(_) {", "if allowed.search_by(one => same(one, value)) is None {", "enum.json / simple enum validation"),
    ("const compares the value", C, '"const" =>\n            if same(schema, value) {', '"const" =>\n            if true {', "const.json / const validation"),
    ("objects of different sizes differ", K, "    (Object(a), Object(b)) => {\n      if a.length() != b.length() {\n        return false\n      }\n", "    (Object(a), Object(b)) => {\n", "enum.json / heterogeneous enum validation / extra properties in object is invalid"),
    ("arrays compare item by item", K, "        if !same(a[i], b[i]) {", "        if false {", "enum.json / enum with [false] does not match [0]"),
    # numbers
    ("maximum is inclusive", K, "      number <= limit", "      number < limit", "maximum.json / maximum validation / boundary point is valid"),
    ("minimum is inclusive", K, "    number >= limit", "    number > limit", "minimum.json / minimum validation / boundary point is valid"),
    ("exclusiveMaximum excludes the limit", C, "if number < limit {", "if number <= limit {", "exclusiveMaximum.json / exclusiveMaximum validation / boundary point is invalid"),
    ("exclusiveMinimum excludes the limit", C, "if number > limit {", "if number >= limit {", "exclusiveMinimum.json / exclusiveMinimum validation / boundary point is invalid"),
    ("draft-04's exclusive flag applies only there", K, "let exclusive = self.draft == Draft4 &&", "let exclusive = self.draft != Draft4 &&", "maximum.json / exclusiveMaximum validation / boundary point is invalid"),
    ("multipleOf allows only a float's error", K, "(quotient - nearest).abs() <= 1.0e-9 * scale", "(quotient - nearest).abs() <= 0.5", "a decimal multiple stays a multiple when binary division says otherwise"),
    # strings
    ("maxLength counts code points", C, "if code_points(text) <= limit.to_int() {", "if text.length() <= limit.to_int() {", "maxLength.json / maxLength validation / two graphemes is long enough"),
    ("minLength is inclusive", C, "if code_points(text) >= limit.to_int() {", "if code_points(text) > limit.to_int() {", "minLength.json / minLength validation / exact length is valid"),
    ("pattern is applied", C, "if self.matches(expression, text) {", "if true {", "pattern.json / pattern validation"),
    ("a pattern the engine cannot read matches nothing", K, "    Some(regex) => (regex.search(text) catch { _ => None }) is Some(_)\n    None => false", "    Some(regex) => (regex.search(text) catch { _ => None }) is Some(_)\n    None => true", "a pattern the engine cannot read refuses rather than admits"),
    # format
    ("format asserts only when asked", F, "guard self.asserts_format else { return true }", "guard true else { return true }", "format is an annotation until it is asked to assert"),
    ("v1 refuses a time without its offset", F, "Some(is_time(text, if draft == V1 { Refused } else { Allowed }))", "Some(is_time(text, Allowed))", "a time is not a leap second where a time has no date to say which"),
    ("v1 refuses a format it does not know", V, "        if !known_format(name) {", "        if false {", "v1 asserts without being asked, and refuses a format it cannot read"),
    fmt("date", "is_date(text)", "date.json / validation of date strings"),
    fmt("time", "is_time(text, if draft == V1 { Refused } else { Allowed })", "time.json / validation of time strings"),
    fmt("date-time", "is_date_time(text)", "date-time.json / validation of date-time strings"),
    fmt("duration", "is_duration(text)", "duration.json / validation of duration strings"),
    fmt("email", "is_email(text, Ascii)", "email.json / validation of e-mail addresses"),
    fmt("idn-email", "is_email(text, International)", "idn-email.json / validation of an internationalized e-mail addresses"),
    fmt("hostname", "is_hostname(text)", "hostname.json / validation of host names"),
    fmt("idn-hostname", "is_idn_hostname(text)", "idn-hostname.json / validation of internationalized host names"),
    fmt("ipv4", "is_ipv4(text)", "ipv4.json / validation of IP addresses"),
    fmt("ipv6", "is_ipv6(text)", "ipv6.json / validation of IPv6 addresses"),
    fmt("uri", "is_uri(text, Ascii)", "uri.json / validation of URIs"),
    fmt("uri-reference", "is_uri_reference(text, Ascii)", "uri-reference.json / validation of URI References"),
    fmt("iri", "is_uri(text, International)", "iri.json / validation of IRIs"),
    fmt("iri-reference", "is_uri_reference(text, International)", "iri-reference.json / validation of IRI References"),
    fmt("uri-template", "is_uri_template(text)", "uri-template.json / format"),
    fmt("uuid", "is_uuid(text)", "uuid.json / uuid format"),
    fmt("json-pointer", "is_json_pointer(text)", "json-pointer.json / validation of JSON-pointers"),
    fmt("relative-json-pointer", "is_relative_json_pointer(text)", "relative-json-pointer.json / validation of Relative JSON Pointers"),
    fmt("regex", "is_regex(text)", "regex.json / validation of regular expressions"),
    # arrays
    ("prefixItems is spelled so from 2020-12", K, "  let modern = self.draft.prefix_items()", "  let modern = true", "items.json / an array of schemas for items"),
    ("items after prefixItems starts past it", K, "          Some(Array(schemas)) => schemas.length()\n          _ => 0", "          Some(Array(schemas)) => 0\n          _ => 0", "items.json / prefixItems with no additional items allowed"),
    ("each prefix schema takes its own item", K, "    if self.check(\n        schemas[i],", "    if self.check(\n        schemas[0],", "items.json / an array of schemas for items / correct types"),
    ("additionalItems starts past the list", K, "          prefix.length(),", "          0,", "uniqueItems.json / uniqueItems with an array of items and additionalItems=false"),
    ("maxItems is inclusive", C, "if items.length() <= limit.to_int() {", "if items.length() < limit.to_int() {", "maxItems.json / maxItems validation / exact length is valid"),
    ("minItems is inclusive", C, "if items.length() >= limit.to_int() {", "if items.length() > limit.to_int() {", "minItems.json / minItems validation / exact length is valid"),
    ("uniqueItems compares neighbours", K, "    for j = i + 1; j < items.length(); j = j + 1 {", "    for j = i + 2; j < items.length(); j = j + 1 {", "uniqueItems.json / uniqueItems validation / non-unique array of integers is invalid"),
    ("contains needs one match", K, "  if found < least {", "  if found < least - 1 {", "contains.json / contains keyword validation / array without items matching schema is invalid"),
    ("maxContains caps the matches", K, "  if most >= 0 && found > most {", "  if most >= 0 && found > most + 1 {", "maxContains.json / maxContains with contains"),
    ("minContains and maxContains arrived in 2019-09", K, "  let counted = self.draft.vocabularies()", "  let counted = true", "minContains and maxContains are not keywords before 2019-09"),
    ("contains arrived in draft-06", K, "guard self.draft != Draft4 && value is Array(items) else { return true }", "guard value is Array(items) else { return true }", "contains is not a keyword in draft-04"),
    # objects
    ("required names what must be there", C, '                      if instance.get(text) is None {\n                        every = note(inner, at, kpath, "missing " + text)', '                      if false {\n                        every = note(inner, at, kpath, "missing " + text)', "missing required property is invalid"),
    ("properties applies to its names", K, "for name, subschema in schemas {\n            match instance.get(name) {", "for name, subschema in schemas {\n            match instance.get(name + \"_\") {", "properties.json / object properties validation"),
    ("patternProperties applies where it matches", K, "            for name, held in instance {\n              if self.matches(expression, name) {", "            for name, held in instance {\n              if !self.matches(expression, name) {", "properties.json / properties, patternProperties, additionalProperties interaction / patternProperty invalidates property"),
    ("additionalProperties skips the named ones", K, "        if named.get(name) is Some(_) {", "        if false {", "additionalProperties.json / additionalProperties being false does not allow other properties"),
    ("additionalProperties skips the patterned ones", K, "            covered = true", "            covered = false", "additionalProperties.json / additionalProperties being false does not allow other properties / patternProperties are not additional properties"),
    ("propertyNames sees each name", C, "                      Json::string(name),", '                      Json::string(""),', "propertyNames.json / propertyNames validation"),
    ("maxProperties is inclusive", C, "if instance.length() <= limit.to_int() {", "if instance.length() < limit.to_int() {", "maxProperties.json / maxProperties validation / exact length is valid"),
    ("minProperties is inclusive", C, "if instance.length() >= limit.to_int() {", "if instance.length() > limit.to_int() {", "minProperties.json / minProperties validation / exact length is valid"),
    ("dependentRequired names what must be there", K, "if needed is String(text) && instance.get(text) is None {", "if needed is String(text) && false {", "/ missing dependency"),
    ("dependencies is split from 2019-09", K, '  if (keyword == "dependencies" && split) ||', '  if (keyword == "dependencies" && false) ||', "dependencies is not a keyword from 2019-09"),
    ("dependentSchemas applies its schema", K, '        if keyword == "dependentRequired" {', '        if keyword == "dependentSchemas" {', "dependentSchemas.json / single dependency / wrong type"),
    ("propertyDependencies is v1's", K, "  if self.draft != V1 {\n    return true\n  }\n  guard schema is Object(dependencies)", "  if true {\n    return true\n  }\n  guard schema is Object(dependencies)", "propertyDependencies picks the subschema by a property's value"),
    # references
    ("$ref resolves against the schema's own base", C, "self.refer(reference, here, value, at, kpath, inner, own)", "self.refer(reference, base, value, at, kpath, inner, own)", "ref.json / refs with relative uris and defs / valid on both fields"),
    ("a pointer's ~1 is a slash", U, "        '1' => {\n          out.write_char('/')", "        '1' => {\n          out.write_char('~')", "a pointer's escapes are undone in the order that keeps a name whole"),
    ("before 2019-09 $ref is the whole schema", C, "  let alone = !self.draft.vocabularies()", "  let alone = false", "ref.json / ref overrides any sibling keywords / ref valid, maxItems ignored"),
    ("draft-04 spells it id", C, 'members.get(if self.draft == Draft4 { "id" } else { "$id" }) {', 'members.get("$id") {', "refRemote.json / base URI change / base URI change ref valid"),
    ("$dynamicRef looks at the dynamic scope", C, "                self.refer_dynamic(", "                self.refer(", "recursiveRef.json / $recursiveRef with nesting"),
    # applicators
    ("allOf applies every branch", C, "branches[i],\n                      here,\n                      value,\n                      at,\n                      step(kpath, i.to_string()),\n                      inner,", "branches[0],\n                      here,\n                      value,\n                      at,\n                      step(kpath, i.to_string()),\n                      inner,", "allOf.json / allOf with base schema / mismatch second allOf"),
    ("anyOf needs one branch", C, "                let mut any = false", "                let mut any = true", "anyOf.json / anyOf / neither anyOf valid"),
    ("oneOf needs exactly one branch", C, "                if count == 1 {\n                  own.take(winner)", "                if count >= 1 {\n                  own.take(winner)", "oneOf.json / oneOf / both oneOf valid"),
    ("not inverts", C, "            if self.check(schema, here, value, at, kpath, None, Marks::new()) {", "            if !self.check(schema, here, value, at, kpath, None, Marks::new()) {", "not.json / not / disallowed"),
    ("if picks then on success", C, 'let arm = if taken { "then" } else { "else" }', 'let arm = if taken { "else" } else { "then" }', "if-then-else.json / if and then without else / invalid through then"),
    ("unevaluatedItems skips what was evaluated", K, "          if marks.idx.contains(index) {", "          if false {", "unevaluatedItems.json"),
    ("unevaluatedProperties skips what was evaluated", K, "        if marks.props.contains(name) {", "        if false {", "unevaluatedProperties.json / unevaluatedProperties with adjacent properties / with no unevaluated properties"),
]

FAILED = re.compile(r'^\[moonbitstack/moonschema\] test \S+ \("([^"]+)"\) failed', re.M)
# A failing case of the suite, as the gate prints it: `    <file> / <group> / <case>: ...`.
CASE = re.compile(r"^    (\S+\.json / .*)$", re.M)


def run(command: list[str], cwd: Path, target_dir: str | None) -> str:
    if target_dir:
        command = [*command, "--target-dir", target_dir]
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    return result.stdout + result.stderr


def run_tests(target: str, target_dir: str | None, expected: str, discover: bool) -> tuple[list[str], str]:
    output = run(["moon", "test", "--target", target], ROOT, target_dir)
    red = FAILED.findall(output)
    if discover or not any(expected in one for one in red):
        gate = run(["moon", "run", ".", "--target", target], ROOT / "gate", target_dir and target_dir + "-gate")
        output += gate
        red += CASE.findall(gate)
    return red, output


def main() -> int:
    # A run takes half an hour; its lines are read as they come.
    sys.stdout.reconfigure(line_buffering=True)  # type: ignore[attr-defined]
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", default="native")
    parser.add_argument("--target-dir")
    parser.add_argument("--discover", action="store_true")
    parser.add_argument("--only", help="run the entries whose description contains this")
    args = parser.parse_args()

    entries = [m for m in MUTATIONS if not args.only or args.only in m[0]]
    tree = {f: (ROOT / f).read_bytes() for f in {m[1] for m in entries}}
    unseen, missed, broke = [], [], []
    for index, (what, name, before, after, expected) in enumerate(entries, 1):
        path = ROOT / name
        original = path.read_bytes()
        text = original.decode("utf-8")
        if text.count(before) != 1:
            print(f"{index:2d}  {what:52s} the text appears {text.count(before)} times")
            broke.append(what)
            continue
        try:
            path.write_bytes(text.replace(before, after, 1).encode("utf-8"))
            failed, output = run_tests(args.target, args.target_dir, expected, args.discover)
        finally:
            path.write_bytes(original)
        if not failed:
            if "Error" in output and "failed:" not in output:
                print(f"{index:2d}  {what:52s} DID NOT BUILD")
                broke.append(what)
            else:
                print(f"{index:2d}  {what:52s} NOTHING WENT RED")
                unseen.append(what)
            continue
        hit = any(expected in one for one in failed)
        print(f"{index:2d}  {what:52s} {len(failed):3d} red{'' if hit or args.discover else '  (not ' + repr(expected) + ')'}")
        if args.discover:
            for one in failed[:6]:
                print("       - " + one[:150])
        elif not hit:
            missed.append(what)

    # Every file is put back after its entry; this checks the whole run against the start, so edits
    # made before the run are not mistaken for ones it left behind.
    changed = [f for f, before in tree.items() if (ROOT / f).read_bytes() != before]
    print(f"\n{len(entries)} mutations: {len(entries) - len(unseen) - len(missed) - len(broke)} seen by the named test, "
          f"{len(unseen)} unseen, {len(missed)} seen by others only, {len(broke)} not applied")
    for what in unseen:
        print("unseen: " + what)
    for what in missed:
        print("the named test stayed green: " + what)
    for what in broke:
        print("not applied: " + what)
    if changed:
        print("not put back: " + ", ".join(changed))
        return 1
    return 1 if unseen or missed or broke else 0


if __name__ == "__main__":
    sys.exit(main())
