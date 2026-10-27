"""Write docs/api.html from the package interface and the `///` comments in the
sources, so the reference follows the code instead of drifting from it.

Usage: python scripts/gen_api.py, from the repository root.
"""
import html
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent

# One package: the root of the module. `gate` and `examples` are not published,
# and a consumer never imports them.
PACKAGES = [
    (
        "moonschema",
        ".",
        "JSON Schema validation. A schema is read, an instance is walked against it.",
    ),
]

DECL = re.compile(
    r"^pub(?:\((?:all|open)\))?\s+(fn|let|struct|enum|suberror|trait|type)\s+"
    r"([A-Za-z_]\w*(?:::[A-Za-z_]\w*)?)"
)

# The methods every MoonBit type gets from its derives. They are true, and they
# are not what a reader of this page came for.
TRAIT_METHODS = re.compile(
    r"::(equal|not_equal|output|to_string|to_repr|hash|hash_combine|compare|"
    r"to_json|from_json|inspect)\("
)

MEMBER = re.compile(r"^\s+([A-Za-z_]\w*)\s*((?::|\().*)?$")


def sources(folder):
    """The `.mbt` files of a package, tests and generated interfaces excluded."""
    base = ROOT / folder
    for path in sorted(base.glob("*.mbt")):
        if path.name.endswith("_test.mbt") or path.name.endswith("_wbtest.mbt"):
            continue
        yield path.read_text(encoding="utf-8").splitlines()


def docs_of(folder):
    """Doc comments by declared name, and by `Enum.Variant` for the variants.

    A `///` block belongs to the declaration that follows it. Inside an enum the
    block belongs to the variant instead, which is how the five drafts each get
    a sentence of their own.
    """
    out = {}
    for lines in sources(folder):
        pending, owner, block = [], None, []
        for line in lines:
            stripped = line.strip()
            if stripped == "///|":
                pending, block = [], []
                continue
            if stripped.startswith("///"):
                rest = stripped[3:]
                pending.append(rest[1:] if rest.startswith(" ") else rest)
                continue
            match = DECL.match(line)
            if match:
                if pending:
                    out[match.group(2)] = "\n".join(pending)
                owner = (
                    match.group(2)
                    if match.group(1) in ("enum", "struct") and line.rstrip().endswith("{")
                    else None
                )
                pending, block = [], []
                continue
            if owner:
                if line.startswith("}"):
                    owner = None
                else:
                    member = re.match(r"^\s+([A-Za-z_]\w*)\s*(?:\(.*\)|:.*)?\s*(?://\s*(.*))?$", line)
                    if member:
                        if member.group(2):
                            out[owner + "." + member.group(1)] = member.group(2)
                        elif pending:
                            out[owner + "." + member.group(1)] = "\n".join(pending)
            pending, block = [], []
    return out


def items_of(folder):
    """Declarations from the interface file, in the order it lists them."""
    path = ROOT / folder / "pkg.generated.mbti"
    lines = path.read_text(encoding="utf-8").splitlines()
    items, block = [], None
    for line in lines:
        if block is not None:
            if line.startswith("}"):
                items.append(block)
                block = None
            else:
                body_line = line.strip()
                if body_line and not body_line.startswith("//"):
                    block["body"].append(body_line)
            continue
        match = re.match(r"pub(?:\((?:all|open)\))?\s+(enum|struct|suberror)\s+(\w+)", line)
        if match:
            block = {
                "kind": match.group(1),
                "name": match.group(2),
                "sig": line.rstrip(" {"),
                "body": [],
            }
            if not line.rstrip().endswith("{"):
                items.append(block)
                block = None
            continue
        match = re.match(r"pub let (\w+) : (.+)", line)
        if match:
            items.append({"kind": "let", "name": match.group(1), "sig": line})
            continue
        match = re.match(r"pub fn (\w+)::(\w+)", line)
        if match:
            if not TRAIT_METHODS.search(line):
                items.append(
                    {
                        "kind": "method",
                        "name": match.group(1) + "::" + match.group(2),
                        "sig": line,
                        "owner": match.group(1),
                    }
                )
            continue
        match = re.match(r"pub fn (\w+)", line)
        if match:
            items.append({"kind": "fn", "name": match.group(1), "sig": line})
            continue
        match = re.match(r"pub impl (\w+) for (\w+)", line)
        if match:
            items.append(
                {"kind": "impl", "name": match.group(1), "sig": line, "owner": match.group(2)}
            )
    return items


def inline(text):
    """One run of doc comment as inline HTML: code spans and nothing else."""
    plain = " ".join(part.strip() for part in text.split("\n") if part.strip())
    escaped = html.escape(plain, quote=False)
    escaped = re.sub(r"\[`([^`]+)`\]", r"<code>\1</code>", escaped)
    return re.sub(r"`([^`]+)`", r"<code>\1</code>", escaped)


def prose(text):
    """A doc comment as paragraphs and examples, with `code` set as code."""
    if not text:
        return ""
    out = []
    for chunk in re.split(r"\n\s*\n", text):
        lines = [line for line in chunk.split("\n") if line.strip()]
        if not lines:
            continue
        if lines[0].strip().startswith("```"):
            # A fenced block is an example, and keeps its own line breaks and
            # indentation: it is code, not prose.
            # `moon fmt` writes the fence as ```moonbit nocheck; the first word
            # is the language and the rest is an instruction to the compiler.
            lang = (lines[0].strip()[3:].strip().split() or ["moonbit"])[0]
            body = [line for line in lines[1:]]
            if body and body[-1].strip() == "```":
                body = body[:-1]
            out.append(
                f'<pre data-lang="{lang}">'
                + html.escape("\n".join(body), quote=False)
                + "</pre>"
            )
            continue
        # A doc comment is wrapped by hand; a paragraph is the whole run between
        # two blank comment lines, not one line of it.
        paragraph = " ".join(line.strip() for line in lines)
        out.append(f"<p>{inline(paragraph)}</p>")
    return "".join(out)


def sig(text):
    clean = html.escape(text.strip(), quote=False)
    clean = re.sub(r"\b(pub|fn|let|struct|enum|suberror)\b", r'<span class="k">\1</span>', clean)
    return f'<div class="sig">{clean}</div>'


def anchor(name):
    return name.replace("::", "-").replace("_", "-").lower()


def render():
    groups = {"Values": [], "Types": [], "Errors": []}
    nav = []
    bodies = []

    for pkg, folder, intro in PACKAGES:
        docs, items = docs_of(folder), items_of(folder)

        values = sorted([i for i in items if i["kind"] == "let"], key=lambda i: i["name"])
        kinds = sorted(
            [i for i in items if i["kind"] in ("enum", "struct")], key=lambda i: i["name"]
        )
        errors = sorted([i for i in items if i["kind"] == "suberror"], key=lambda i: i["name"])

        methods = {}
        for item in items:
            if item["kind"] == "method":
                methods.setdefault(item["owner"], []).append(item)

        for title, entries in (("Values", values), ("Types", kinds), ("Errors", errors)):
            groups[title] = entries

        nav.append('<li><a href="#values">Values</a><ol class="sub">')
        for value in values:
            nav.append(f'<li><a href="#value-{anchor(value["name"])}">{value["name"]}</a></li>')
        nav.append("</ol></li>")

        nav.append('<li><a href="#types">Types</a><ol class="sub">')
        for kind in kinds:
            nav.append(f'<li><a href="#{anchor(kind["name"])}">{kind["name"]}</a></li>')
        nav.append("</ol></li>")

        nav.append('<li><a href="#errors">Errors</a><ol class="sub">')
        for error in errors:
            nav.append(f'<li><a href="#{anchor(error["name"])}">{error["name"]}</a></li>')
        nav.append("</ol></li>")

        if values:
            bodies.append('<div class="kind-group"><p class="g" id="values">Values</p>')
            for value in values:
                bodies.append(f'<div class="entry" id="value-{anchor(value["name"])}">')
                bodies.append(
                    f'<h3><span class="kind">let</span>{value["name"]}</h3>'
                )
                bodies.append(sig(value["sig"]))
                bodies.append(prose(docs.get(value["name"], "")))
                bodies.append("</div>")
            bodies.append("</div>")

        if kinds:
            bodies.append('<div class="kind-group"><p class="g" id="types">Types</p>')
            for kind in kinds:
                bodies.append(f'<div class="entry" id="{anchor(kind["name"])}">')
                bodies.append(
                    f'<h3><span class="kind">{kind["kind"]}</span>{kind["name"]}</h3>'
                )
                bodies.append(prose(docs.get(kind["name"], "")))
                bodies.append(sig(kind["sig"] + (" {" if kind["body"] else "")))
                if kind["body"]:
                    chips = []
                    for field in kind["body"]:
                        leaf = re.match(r"([A-Za-z_]\w*)", field).group(1)
                        note = docs.get(f'{kind["name"]}.{leaf}', "")
                        chips.append(
                            f"<li>{html.escape(field, quote=False)}"
                            + (f"<small>{inline(note)}</small>" if note else "")
                            + "</li>"
                        )
                    bodies.append(f'<ul class="variants">{"".join(chips)}</ul>')
                for method in methods.get(kind["name"], []):
                    bodies.append(
                        f'<div class="member" id="{anchor(method["name"])}">'
                        + sig(method["sig"])
                        + prose(docs.get(method["name"], ""))
                        + "</div>"
                    )
                bodies.append("</div>")
            bodies.append("</div>")

        if errors:
            bodies.append('<div class="kind-group"><p class="g" id="errors">Errors</p>')
            for error in errors:
                bodies.append(f'<div class="entry" id="{anchor(error["name"])}">')
                bodies.append(
                    f'<h3><span class="kind">suberror</span>{error["name"]}</h3>'
                )
                bodies.append(prose(docs.get(error["name"], "")))
                bodies.append(sig(error["sig"] + (" {" if error["body"] else "")))
                if error["body"]:
                    chips = []
                    for field in error["body"]:
                        leaf = re.match(r"([A-Za-z_]\w*)", field).group(1)
                        note = docs.get(f'{error["name"]}.{leaf}', "")
                        chips.append(
                            f"<li>{html.escape(field, quote=False)}"
                            + (f"<small>{inline(note)}</small>" if note else "")
                            + "</li>"
                        )
                    bodies.append(f'<ul class="variants">{"".join(chips)}</ul>')
                bodies.append("</div>")
            bodies.append("</div>")

    page = (ROOT / "docs" / "api.template.html").read_text(encoding="utf-8")
    page = page.replace("<!-- nav -->", "\n".join(nav))
    page = page.replace("<!-- body -->", "\n".join(bodies))
    (ROOT / "docs" / "api.html").write_text(page, encoding="utf-8", newline="\n")


render()
