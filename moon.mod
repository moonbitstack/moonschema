name = "moonbitstack/moonschema"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/moonbitstack/moonschema"

license = "Apache-2.0"

keywords = [
  "json-schema",
  "schema",
  "validation",
  "openapi",
  "json",
  "moonbit",
]

description = "moonschema — JSON Schema validation for MoonBit: draft-04, draft-06, draft-07, 2019-09 and 2020-12, measured against the official JSON-Schema-Test-Suite. It validates; it does not parse JSON — that is moonjson."

preferred_target = "wasm-gc"

import {
  "moonbitstack/moonjson@0.2.0",
}
