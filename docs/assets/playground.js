// The loom: a schema on the left, an instance on the right, and the answer
// underneath — computed by the package itself, compiled to JavaScript, not by a
// description of it.

const PRESETS = {
  port: {
    draft: "https://json-schema.org/draft/2020-12/schema",
    schema: `{
  "type": "object",
  "properties": {
    "port": { "type": "integer", "minimum": 1, "maximum": 65535 },
    "tls":  { "type": "boolean" }
  },
  "required": ["port"]
}`,
    instance: `{
  "port": 70000,
  "tls": "yes"
}`,
  },
  order: {
    draft: "https://json-schema.org/draft/2020-12/schema",
    schema: `{
  "allOf": [
    { "properties": { "id": { "type": "string", "pattern": "^ORD-[0-9]{4}$" } } },
    { "properties": { "total": { "type": "integer", "minimum": 1 } } }
  ],
  "unevaluatedProperties": false
}`,
    instance: `{
  "id": "ORD-0042",
  "total": 5,
  "note": "gift"
}`,
  },
  refs: {
    draft: "https://json-schema.org/draft/2020-12/schema",
    schema: `{
  "$defs": {
    "port": { "type": "integer", "minimum": 1, "maximum": 65535 }
  },
  "type": "object",
  "properties": {
    "listen": { "$ref": "#/$defs/port" }
  }
}`,
    instance: `{ "listen": 0 }`,
  },
  text: {
    draft: "https://json-schema.org/draft/2020-12/schema",
    schema: `{
  "type": "object",
  "properties": {
    "tag": {
      "type": "string",
      "pattern": "^\\\\p{Letter}[\\\\p{Letter} ]*$",
      "maxLength": 12
    }
  }
}`,
    instance: `{ "tag": "hello 123" }`,
  },
  old: {
    draft: "https://json-schema.org/draft-04/schema#",
    schema: `{
  "$schema": "http://json-schema.org/draft-04/schema#",
  "maximum": 10,
  "exclusiveMaximum": true
}`,
    instance: `10`,
  },
};

const el = (id) => document.getElementById(id);

const engineState = el("engine-state");

let engine = null;
let ready = false;

const schemaBox = el("schema-text");
const instanceBox = el("instance-text");
const draftMenu = el("draft-menu");
const said = el("said");
const meta = el("meta");
const faultList = el("fault-list");
const notes = el("loom-note");

/* ------------------------------------------------------------- line gutters */

function paintGutter(box, gutter) {
  const lines = box.value.split("\n").length;
  let out = "";
  for (let i = 1; i <= lines; i += 1) out += i + "\n";
  gutter.textContent = out;
  gutter.scrollTop = box.scrollTop;
}

function wire(box, gutter) {
  const sync = () => paintGutter(box, gutter);
  box.addEventListener("input", () => {
    sync();
    queue();
  });
  box.addEventListener("scroll", () => {
    gutter.scrollTop = box.scrollTop;
  });
  sync();
}

/* ---------------------------------------------------------------- the answer */

function esc(s) {
  return String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
}

function pointer(text, empty) {
  if (!text) return `<span class="ptr">${empty}</span>`;
  return `<span class="ptr">${esc(text)}</span>`;
}

function paint(answer) {
  const status = answer.status;
  said.className = "said " + (status === "ok" ? (answer.valid ? "pass" : "fail") : "err");
  said.innerHTML = `<span></span>` +
    (status === "ok"
      ? answer.valid ? "valid" : `${answer.faults.length} fault${answer.faults.length === 1 ? "" : "s"}`
      : status === "json" ? "not json" : "refused");

  if (status === "ok") {
    meta.innerHTML = `read as <b>${esc(answer.draft)}</b> · <b>${answer.valid ? "flag: yes" : "flag: no"}</b> · ${answer.faults.length} fault${answer.faults.length === 1 ? "" : "s"}`;
  } else if (status === "json") {
    meta.innerHTML = `the <b>${esc(answer.side)}</b> is not JSON`;
  } else {
    meta.innerHTML = `the schema was refused, not read at a guessed version`;
  }

  if (status !== "ok") {
    faultList.innerHTML = `<li class="fault" style="grid-template-columns:1fr"><div class="msg">${esc(answer.error)}</div></li>`;
    return;
  }
  if (answer.valid) {
    faultList.innerHTML = `<li class="silent">no faults — nothing refused the instance</li>`;
    return;
  }
  faultList.innerHTML = answer.faults
    .map(
      (f, i) => `<li class="fault" style="animation-delay:${i * 40}ms">
        <span class="kw">${esc(f.keyword)}</span>
        <span class="msg">${esc(f.message)}</span>
        <span class="where"><span>instance ${pointer(f.at, "the instance")}</span><span>schema <b>${esc(f.schemaAt || "/")}</b></span></span>
      </li>`,
    )
    .join("");
}

let timer = 0;
function queue() {
  clearTimeout(timer);
  timer = setTimeout(run, 130);
}

function run() {
  if (!ready) return;
  const draft = draftMenu.value;
  let answer;
  try {
    answer = JSON.parse(engine.check(schemaBox.value, instanceBox.value, draft));
  } catch (err) {
    answer = { status: "json", side: "engine", error: String(err), faults: [] };
  }
  paint(answer);
}

/* ------------------------------------------------------------------- presets */

function load(name) {
  const p = PRESETS[name];
  if (!p) return;
  schemaBox.value = p.schema;
  instanceBox.value = p.instance;
  draftMenu.value = p.draft;
  paintGutter(schemaBox, el("schema-gutter"));
  paintGutter(instanceBox, el("instance-gutter"));
  document.querySelectorAll("[data-preset]").forEach((b) => {
    b.setAttribute("aria-pressed", b.dataset.preset === name ? "true" : "false");
  });
  if (notes) {
    notes.textContent =
      name === "old"
        ? "draft-04 reads the flag literally: ten is out of bounds. The same document at 2020-12 lets ten through."
        : name === "text"
          ? "\\p{Letter} is a property escape, spliced in from the Unicode tables the package carries — and maxLength counts code points, not bytes."
          : name === "order"
            ? "Two applicators evaluated id and total; nothing evaluated note, so unevaluatedProperties refuses it."
            : "";
  }
  run();
}

document.querySelectorAll("[data-preset]").forEach((b) => {
  b.addEventListener("click", () => load(b.dataset.preset));
});

draftMenu.addEventListener("change", run);

wire(schemaBox, el("schema-gutter"));
wire(instanceBox, el("instance-gutter"));

/* -------------------------------------------------------------------- engine */

// The panels are filled before the engine arrives, so the page reads correctly
// even when the compiled module is missing (a local checkout, a file:// view).
load("port");

try {
  engine = await import("../engine/moonschema.js");
  ready = true;
  if (engineState) {
    engineState.dataset.state = "live";
    engineState.title = "the compiled package is running";
  }
  run();
} catch (err) {
  ready = false;
  if (engineState) engineState.title = "the compiled package did not load";
  said.className = "said err";
  said.innerHTML = "<span></span>engine offline";
  meta.innerHTML = "the compiled package is not here, so this panel cannot answer";
  faultList.innerHTML =
    `<li class="fault" style="grid-template-columns:1fr"><div class="msg">` +
    `Build it with <code>moon build --target js --release examples/web</code>, then copy ` +
    `<code>_build/js/release/build/moonbitstack/moonschema/examples/web/web.js</code> over ` +
    `<code>docs/engine/moonschema.js</code>. The docs workflow does both on every push.</div></li>`;
}
