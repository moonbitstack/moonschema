#!/usr/bin/env python3
# Copyright 2026 Leo Cheng
# SPDX-License-Identifier: Apache-2.0
"""Generate the differential vectors the gate replays.

A JSON Schema validator has no wire format to exchange with another one, so
interoperability is agreement: the same document and the same instance, judged
by implementations written by other people, and the same answer from this
library. This script asks two of them — Ajv and python-jsonschema — and keeps
every case where the two agree. A case they disagree about says nothing about
this library and is dropped, with the disagreement recorded beside the vectors.

The output is `gate/differential/vectors.json`, committed, and the gate replays
it: the runs in CI need node and Python for nothing, only this script does.

    npm install ajv@8.20.0
    python -m pip install jsonschema==4.26.0
    python scripts/gen_differential_vectors.py

Versions are pinned in the header of the vector file so that a vector set can be
traced back to the two implementations that produced it.

One construct is left out on purpose: a `multipleOf` whose divisor is not a
binary fraction, with an instance that is a whole number of them in decimal and
not in binary. Both references divide in binary floating point, so both refuse
`0.3` against `{"multipleOf": 0.1}`; the specification's own suite requires
`0.0075` to be a multiple of `0.0001`, which only holds if the division is read
as a decimal one. This library takes the specification's side, and
`src/keywords_test.mbt` holds the case. Comparing it here would measure the
disagreement rather than the library.
"""

from __future__ import annotations

import json
import pathlib
import subprocess
import sys
import tempfile

from jsonschema.validators import (
    Draft7Validator,
    Draft201909Validator,
    Draft202012Validator,
)

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "gate" / "differential" / "vectors.json"
AJV = ROOT / "scripts" / "differential_ajv.cjs"

DRAFT_URIS = {
    "draft-07": "http://json-schema.org/draft-07/schema#",
    "2019-09": "https://json-schema.org/draft/2019-09/schema",
    "2020-12": "https://json-schema.org/draft/2020-12/schema",
}

VALIDATORS = {
    "draft-07": Draft7Validator,
    "2019-09": Draft201909Validator,
    "2020-12": Draft202012Validator,
}

# Schemas every version spells the same way, with the instances to judge. The
# point is the keywords that decide real documents, not the rare corners — the
# official suite already walks those, and it is the other half of the gate.
COMMON = [
    (
        {
            "type": "object",
            "properties": {
                "name": {"type": "string", "minLength": 2},
                "age": {"type": "integer", "minimum": 0, "maximum": 130},
            },
            "required": ["name"],
            "additionalProperties": False,
        },
        [
            {"name": "Lee", "age": 41},
            {"name": "Lee"},
            {"name": "L"},
            {"age": 41},
            {"name": "Lee", "age": 131},
            {"name": "Lee", "age": 0.5},
            {"name": "Lee", "extra": True},
            [],
            "not an object",
        ],
    ),
    (
        {
            "type": "array",
            "items": {"type": "integer"},
            "minItems": 2,
            "maxItems": 4,
            "uniqueItems": True,
        },
        [[1, 2], [1, 1], [1], [1, 2, 3, 4, 5], [1, "2"], [], [1, 2, 3, 3.0]],
    ),
    (
        {"type": "string", "pattern": "^[a-z]+(-[a-z]+)*$", "maxLength": 10},
        ["alpha", "alpha-beta", "alpha-", "Alpha", "alpha beta", "abcdefghijk", ""],
    ),
    (
        {
            "enum": ["red", "green", {"nested": 1}, [1, 2], None, 3],
        },
        ["red", "blue", {"nested": 1}, {"nested": 2}, [1, 2], [2, 1], None, 3, 3.0],
    ),
    (
        {"const": {"a": [1, 2, {"b": True}]}},
        [{"a": [1, 2, {"b": True}]}, {"a": [1, 2, {"b": False}]}, {"a": [1, 2]}, [1, 2]],
    ),
    (
        {"multipleOf": 2},
        [4, 5, 4.0, 0, -6, 2.5],
    ),
    (
        {
            "allOf": [
                {"type": "object"},
                {"required": ["a"]},
                {"properties": {"a": {"type": "integer"}}},
            ],
        },
        [{"a": 1}, {"a": "1"}, {"b": 1}, [], 1],
    ),
    (
        {"anyOf": [{"type": "string"}, {"type": "number", "minimum": 10}]},
        ["x", 10, 9, True, None, []],
    ),
    (
        {"oneOf": [{"type": "integer"}, {"type": "number", "multipleOf": 2}]},
        [3, 4, 5, 4.5, "4"],
    ),
    (
        {"not": {"type": "string"}},
        ["x", 1, None, [], {}],
    ),
    (
        {
            "if": {
                "properties": {"kind": {"const": "a"}},
                "required": ["kind"],
            },
            "then": {"required": ["x"]},
            "else": {"required": ["y"]},
        },
        [{"kind": "a", "x": 1}, {"kind": "a", "y": 1}, {"kind": "b", "y": 1}, {"kind": "b"}, {}],
    ),
    (
        {
            "properties": {"a": {"type": "string"}},
            "patternProperties": {"^x-": {"type": "integer"}},
            "additionalProperties": False,
        },
        [{"a": "s", "x-1": 1}, {"x-1": "1"}, {"b": 1}, {"a": 1}, {}],
    ),
    (
        {"propertyNames": {"pattern": "^[a-z]+$", "maxLength": 4}},
        [{"ab": 1}, {"ABC": 1}, {"abcde": 1}, {"a-b": 1}, {}],
    ),
    (
        {"maxProperties": 2, "minProperties": 1},
        [{}, {"a": 1}, {"a": 1, "b": 2}, {"a": 1, "b": 2, "c": 3}, []],
    ),
    (
        {"$defs": {"pos": {"type": "integer", "minimum": 1}}},
        [1, 0, "1"],
    ),
    (
        {
            "$defs": {"pos": {"type": "integer", "minimum": 1}},
            "properties": {"n": {"$ref": "#/$defs/pos"}},
        },
        [{"n": 2}, {"n": 0}, {"n": "2"}, {}],
    ),
    (
        {"type": ["string", "null"]},
        ["x", None, 1, True],
    ),
    (
        {"type": "number", "exclusiveMaximum": 10, "exclusiveMinimum": 0},
        [5, 0, 10, 0.5, -1, "5"],
    ),
    (
        {"type": "integer", "multipleOf": 5},
        [10, 11, 0, -15, 10.5],
    ),
    (
        {"contains": {"type": "integer"}},
        [[1, "a"], ["a"], [], [1.5], [1, 2]],
    ),
    (
        {"uniqueItems": True},
        [[1, 2], [1, 1], [{"a": 1}, {"a": 1}], [{"a": 1}, {"a": 2}], [1, 1.0], [True, 1]],
    ),
    (
        {"maxLength": 3},
        ["abc", "abcd", "\u00e9\u00e9\u00e9", "\u4e2d\u6587", "\U0001f600\U0001f600\U0001f600"],
    ),
    (
        {"items": {"type": ["integer", "string"]}},
        [[1, "a"], [1, True], [], ["a"]],
    ),
    (
        {"additionalProperties": {"type": "integer"}},
        [{"a": 1}, {"a": "1"}, {}],
    ),
    (
        {"multipleOf": 0.5},
        [1.5, 1.25, 0.5, 0, -2.5],
    ),
    (
        {"type": "integer", "exclusiveMinimum": 0, "exclusiveMaximum": 10},
        [1, 0, 10, 9.999, -1],
    ),
    # Annotations from a branch that passed are what closes a composed object;
    # a branch that failed contributes nothing.
    (
        {
            "anyOf": [
                {"properties": {"a": {"type": "string"}}, "required": ["a"]},
                {"properties": {"b": {"type": "integer"}}, "required": ["b"]},
            ],
        },
        [{"a": "s"}, {"b": 1}, {"a": "s", "b": 1}, {"a": 1}],
    ),
    (
        {"allOf": [{"properties": {"a": {"type": "integer"}}}], "properties": {"b": {"type": "string"}}},
        [{"a": 1, "b": "s"}, {"a": "1", "b": "s"}, {"a": 1, "b": 1}],
    ),
    (
        {"type": "object", "properties": {"kind": {"enum": ["a", "b"]}}, "required": ["kind"]},
        [{"kind": "a"}, {"kind": "c"}, {}],
    ),
    (
        {"maxProperties": 1, "additionalProperties": {"type": ["string", "number"]}},
        [{"a": "s"}, {"a": 1}, {"a": True}, {"a": "s", "b": 1}],
    ),
    (
        {"patternProperties": {"^[0-9]+$": {"type": "integer"}}},
        [{"1": 1}, {"1": "1"}, {"x": "1"}, {}],
    ),
    (
        {"propertyNames": {"enum": ["a", "b"]}},
        [{"a": 1}, {"c": 1}, {}],
    ),
    (
        {"items": {"enum": ["x", "y", 1, None]}},
        [["x", 1, None], ["x", 2], []],
    ),
    (
        {"properties": {"list": {"items": {"type": "object", "required": ["id"]}}}},
        [{"list": [{"id": 1}, {"id": 2}]}, {"list": [{"id": 1}, {}]}, {"list": []}, {}],
    ),
    (
        {"not": {"required": ["forbidden"]}},
        [{"allowed": 1}, {"forbidden": 1}, {}],
    ),
    (
        {"const": 1},
        [1, 1.0, True, "1", 2],
    ),
    (
        {"enum": [True, False]},
        [True, False, 1, 0, "true"],
    ),
    (
        {"type": "null"},
        [None, 0, False, ""],
    ),
    (
        {"type": "boolean"},
        [True, False, 0, 1, "true"],
    ),
    (
        {"maximum": 100, "multipleOf": 3},
        [99, 100, 101, 0, -99],
    ),
    (
        {"minLength": 1, "pattern": "\\S"},
        ["a", " ", "", " a "],
    ),
]

# Schemas a version spells its own way. Each entry is (schema, instances) and is
# read only at the version it names.
PER_DRAFT = {
    "draft-07": [
        (
            {
                "items": [{"type": "integer"}, {"type": "string"}],
                "additionalItems": False,
            },
            [[1, "a"], [1, "a", 2], [1], ["a", 1], []],
        ),
        (
            {"dependencies": {"a": ["b"], "c": {"required": ["d"]}}},
            [{"a": 1, "b": 2}, {"a": 1}, {"c": 1, "d": 2}, {"c": 1}, {}],
        ),
    ],
    "2019-09": [
        (
            {
                "items": [{"type": "integer"}, {"type": "string"}],
                "additionalItems": False,
            },
            [[1, "a"], [1, "a", 2], [1], ["a", 1], []],
        ),
        (
            {
                "dependentRequired": {"a": ["b"]},
                "dependentSchemas": {"c": {"required": ["d"]}},
            },
            [{"a": 1, "b": 2}, {"a": 1}, {"c": 1, "d": 2}, {"c": 1}, {}],
        ),
        (
            {
                "properties": {"a": {"type": "string"}},
                "unevaluatedProperties": False,
            },
            [{"a": "s"}, {"a": "s", "b": 1}, {"b": 1}, {}],
        ),
        (
            {
                "allOf": [{"properties": {"a": {"type": "string"}}}],
                "unevaluatedProperties": False,
            },
            [{"a": "s"}, {"a": 1}, {"a": "s", "b": 1}],
        ),
        (
            {
                "prefixItems": [{"type": "integer"}],
                "unevaluatedItems": False,
            },
            [[1], [1, 2], []],
        ),
        (
            {"contains": {"type": "integer"}, "minContains": 2, "maxContains": 2},
            [[1, 2], [1, 2, 3], [1], [], [1, "a", 2]],
        ),
        (
            {
                "$id": "https://example.test/tree",
                "$recursiveAnchor": True,
                "type": "object",
                "properties": {"children": {"type": "array", "items": {"$recursiveRef": "#"}}},
            },
            [{"children": []}, {"children": [{"children": []}]}, {"children": [1]}],
        ),
        (
            {
                "$id": "https://example.test/outer",
                "$defs": {
                    "inner": {"$id": "inner", "type": "integer", "minimum": 1},
                },
                "properties": {"n": {"$ref": "inner"}, "m": {"$ref": "#/$defs/inner"}},
            },
            [{"n": 1}, {"n": 0}, {"m": 2}, {"m": 0}, {}],
        ),
        (
            {
                "$ref": "#/$defs/name",
                "$defs": {"name": {"type": "string", "minLength": 1}},
                "maxLength": 3,
            },
            ["ab", "", "abcd"],
        ),
    ],
    "2020-12": [
        (
            {"prefixItems": [{"type": "integer"}, {"type": "string"}], "items": False},
            [[1, "a"], [1, "a", 2], [1], ["a", 1], []],
        ),
        (
            {
                "dependentRequired": {"a": ["b"]},
                "dependentSchemas": {"c": {"required": ["d"]}},
            },
            [{"a": 1, "b": 2}, {"a": 1}, {"c": 1, "d": 2}, {"c": 1}, {}],
        ),
        (
            {
                "properties": {"a": {"type": "string"}},
                "unevaluatedProperties": False,
            },
            [{"a": "s"}, {"a": "s", "b": 1}, {"b": 1}, {}],
        ),
        (
            {
                "allOf": [{"properties": {"a": {"type": "string"}}}],
                "unevaluatedProperties": False,
            },
            [{"a": "s"}, {"a": 1}, {"a": "s", "b": 1}],
        ),
        (
            {
                "prefixItems": [{"type": "integer"}],
                "unevaluatedItems": False,
            },
            [[1], [1, 2], []],
        ),
        (
            {"contains": {"type": "integer"}, "minContains": 2, "maxContains": 2},
            [[1, 2], [1, 2, 3], [1], [], [1, "a", 2]],
        ),
        (
            {
                "$id": "https://example.test/tree",
                "$dynamicAnchor": "node",
                "type": "object",
                "properties": {
                    "children": {
                        "type": "array",
                        "items": {"$dynamicRef": "#node"},
                    }
                },
            },
            [{"children": []}, {"children": [{"children": []}]}, {"children": [1]}],
        ),
        (
            {
                "$id": "https://example.test/outer",
                "$defs": {
                    "inner": {"$id": "inner", "type": "integer", "minimum": 1},
                },
                "properties": {"n": {"$ref": "inner"}, "m": {"$ref": "#/$defs/inner"}},
            },
            [{"n": 1}, {"n": 0}, {"m": 2}, {"m": 0}, {}],
        ),
        (
            {
                "$ref": "#/$defs/name",
                "$defs": {"name": {"type": "string", "minLength": 1}},
                "maxLength": 3,
            },
            ["ab", "", "abcd"],
        ),
        (
            {
                "if": {"properties": {"kind": {"const": "a"}}},
                "then": {"properties": {"a": {"type": "integer"}}},
                "properties": {"kind": {"type": "string"}},
                "unevaluatedProperties": False,
            },
            [{"kind": "a", "a": 1}, {"kind": "a", "b": 1}, {"kind": "b", "b": 1}],
        ),
    ],
}


def cases_for(draft: str):
    """Every (schema, data) pair of one version, with its `$schema` attached."""
    out = []
    for schema, instances in COMMON + PER_DRAFT[draft]:
        document = {"$schema": DRAFT_URIS[draft], **schema}
        for data in instances:
            out.append((document, data))
    return out


def ask_ajv(draft: str, cases):
    with tempfile.TemporaryDirectory() as scratch:
        scratch = pathlib.Path(scratch)
        given = scratch / "cases.json"
        answer = scratch / "verdicts.json"
        given.write_text(
            json.dumps([{"schema": s, "data": d} for s, d in cases]),
            encoding="utf-8",
        )
        subprocess.run(
            ["node", str(AJV), str(given), str(answer), draft],
            check=True,
            cwd=ROOT,
        )
        return json.loads(answer.read_text(encoding="utf-8"))


def ask_jsonschema(draft: str, cases):
    validator_of = VALIDATORS[draft]
    out = []
    for schema, data in cases:
        try:
            out.append(validator_of(schema).is_valid(data))
        except Exception as error:  # the implementation refused the schema
            out.append({"error": str(error)})
    return out


def main() -> int:
    kept = []
    dropped = []
    for draft in DRAFT_URIS:
        cases = cases_for(draft)
        ajv = ask_ajv(draft, cases)
        python = ask_jsonschema(draft, cases)
        assert len(ajv) == len(python) == len(cases)
        for (schema, data), one, other in zip(cases, ajv, python):
            if isinstance(one, bool) and isinstance(other, bool) and one == other:
                kept.append({"draft": draft, "schema": schema, "data": data, "valid": one})
            else:
                dropped.append(
                    {
                        "draft": draft,
                        "schema": schema,
                        "data": data,
                        "ajv": one,
                        "jsonschema": other,
                    }
                )

    versions = {
        "ajv": subprocess.run(
            ["node", "-p", "require('ajv/package.json').version"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip(),
        "jsonschema": __import__("importlib.metadata", fromlist=["version"]).version(
            "jsonschema"
        ),
    }

    document = {
        "about": (
            "The cases Ajv and python-jsonschema judge alike, with the verdict they "
            "agree on. Regenerate with scripts/gen_differential_vectors.py."
        ),
        "references": versions,
        "kept": len(kept),
        "dropped": len(dropped),
        "cases": kept,
        "disagreements": dropped,
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(
        json.dumps(document, indent=1, ensure_ascii=False, sort_keys=False) + "\n",
        encoding="utf-8",
    )
    print(f"{len(kept)} cases kept, {len(dropped)} dropped, written to {OUT}")
    for case in dropped:
        print(
            "  dropped: "
            + json.dumps(case["schema"], ensure_ascii=False)
            + " over "
            + json.dumps(case["data"], ensure_ascii=False)
            + f" — ajv {case['ajv']}, jsonschema {case['jsonschema']}"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
