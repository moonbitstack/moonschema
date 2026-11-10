#!/usr/bin/env python3
# Copyright 2026 Leo Cheng
# SPDX-License-Identifier: Apache-2.0
"""Write the gate's own output into the places that publish it.

The numbers of cases the validator answers are not something to type by hand: a
suite that grows or a differential set that is regenerated would leave a page
claiming a count that is no longer true. So the gate prints them, and this
script puts the printed lines between two markers — one block in the README and
one on the guide — and does nothing else. CI runs the gate and then this script,
and fails when the files change, which means the page and the run disagree.

    cd gate && moon run . --target native > ../gate.log
    python scripts/gen_conformance.py gate.log
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
BEGIN = "<!-- conformance:begin -->"
END = "<!-- conformance:end -->"

RUN = re.compile(r"^\s*(?P<label>.+?): (?P<passed>\d+) passed, (?P<failed>\d+) failed$")
TOTAL = re.compile(r"^total: (?P<passed>\d+) of (?P<total>\d+) cases$")


def read_runs(path: pathlib.Path):
    """The runs, in the order the gate printed them, and the total it printed."""
    runs = []
    total = None
    for line in path.read_text(encoding="utf-8").splitlines():
        found = RUN.match(line)
        if found:
            runs.append(
                (
                    found.group("label").strip(),
                    int(found.group("passed")),
                    int(found.group("failed")),
                )
            )
            continue
        found = TOTAL.match(line)
        if found:
            total = (int(found.group("passed")), int(found.group("total")))
    if not runs or total is None:
        raise SystemExit(f"{path}: no runs, or no total — is this the gate's output?")
    if sum(passed for _, passed, _ in runs) != total[0]:
        raise SystemExit(
            f"{path}: the runs add up to {sum(p for _, p, _ in runs)}, the total says {total[0]}"
        )
    return runs, total


def markdown(runs, total) -> str:
    rows = [
        "<table>",
        "<tr><th>Set</th><th>Cases</th><th>Failed</th></tr>",
    ]
    for label, passed, failed in runs:
        rows.append(
            f"<tr><td><code>{label}</code></td>"
            f"<td>{passed:,}</td><td>{failed:,}</td></tr>"
        )
    rows.append(
        f"<tr><td><b>Total</b></td><td><b>{total[0]:,}</b></td>"
        f"<td><b>{total[1] - total[0]:,}</b></td></tr>"
    )
    rows.append("</table>")
    return "\n".join(rows)


def html(runs, total) -> str:
    rows = [
        '<div class="table-cloth" data-reveal>',
        '  <table class="sheet">',
        "    <thead>",
        "      <tr><th>Set</th><th>Cases</th><th>Failed</th></tr>",
        "    </thead>",
        "    <tbody>",
    ]
    for label, passed, failed in runs:
        rows.append(
            f"      <tr><td><code>{label}</code></td>"
            f"<td>{passed:,}</td><td>{failed:,}</td></tr>"
        )
    rows.append(
        "      <tr><td><b>Total</b></td>"
        f"<td><b>{total[0]:,}</b></td><td><b>{total[1] - total[0]:,}</b></td></tr>"
    )
    rows.append("    </tbody>")
    rows.append("  </table>")
    rows.append("</div>")
    return "\n".join(rows)


def fill(path: pathlib.Path, block: str) -> bool:
    text = path.read_text(encoding="utf-8")
    start = text.find(BEGIN)
    stop = text.find(END)
    if start < 0 or stop < start:
        raise SystemExit(f"{path}: no {BEGIN} … {END} block")
    head = text[: start + len(BEGIN)]
    tail = text[stop:]
    updated = head + "\n" + block + "\n" + tail
    if updated == text:
        print(f"{path.relative_to(ROOT)}: unchanged")
        return False
    path.write_text(updated, encoding="utf-8")
    print(f"{path.relative_to(ROOT)}: written")
    return True


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    runs, total = read_runs(pathlib.Path(sys.argv[1]))
    fill(ROOT / "README.md", markdown(runs, total))
    fill(ROOT / "docs" / "guide.html", html(runs, total))
    print(f"{total[0]:,} cases, {total[1] - total[0]:,} failing")
    return 0


if __name__ == "__main__":
    sys.exit(main())
