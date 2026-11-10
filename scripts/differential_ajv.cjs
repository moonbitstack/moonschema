// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// One side of the differential run: every case of `cases.json`, judged by Ajv,
// written to `verdicts.json` in the order they arrived.
//
// Run by `gen_differential_vectors.py`, which does the other side with a second
// implementation and keeps only the cases where the two agree.

const fs = require("node:fs");

const [, , casesPath, outPath, draft] = process.argv;
const cases = JSON.parse(fs.readFileSync(casesPath, "utf8"));

const Ajv7 = require("ajv");
const Ajv2019 = require("ajv/dist/2019").default;
const Ajv2020 = require("ajv/dist/2020").default;

// A fresh engine per case: Ajv keeps every schema it has compiled by `$id`, and
// two cases that name the same `$id` are two documents here, not a duplicate.
function engine() {
  const options = {
    strict: false,
    allErrors: false,
    // `format` is an annotation in every version before v1: judging it here
    // would compare three opinions about RFCs rather than one about keywords.
    validateFormats: false,
  };
  switch (draft) {
    case "draft-07":
      return new Ajv7(options);
    case "2019-09":
      return new Ajv2019(options);
    case "2020-12":
      return new Ajv2020(options);
    default:
      throw new Error(`no Ajv class for ${draft}`);
  }
}

const verdicts = cases.map(({ schema, data }) => {
  try {
    return engine().validate(schema, data);
  } catch (error) {
    return { error: String(error && error.message ? error.message : error) };
  }
});

fs.writeFileSync(outPath, JSON.stringify(verdicts), "utf8");
