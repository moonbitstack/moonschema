// The thread map: a schema tree, an instance tree, and one thread per fault,
// drawn from the place in the schema to the place in the instance. The faults
// come from the compiled package, not from a table written here.

const CASES = {
  port: {
    draft: "https://json-schema.org/draft/2020-12/schema",
    schema: {
      type: "object",
      properties: {
        port: { type: "integer", minimum: 1, maximum: 65535 },
        tls: { type: "boolean" },
      },
      required: ["port"],
    },
    instance: { port: 70000, tls: "yes" },
    note: "Two values refused, and both ends are nodes that exist: /port and the keyword that refused it.",
  },
  order: {
    draft: "https://json-schema.org/draft/2020-12/schema",
    schema: {
      allOf: [
        { properties: { id: { type: "string", pattern: "^ORD-[0-9]{4}$" } } },
        { properties: { total: { type: "integer", minimum: 1 } } },
      ],
      unevaluatedProperties: false,
    },
    instance: { id: "ORD-0042", total: 5, note: "gift" },
    note: "The two applicators evaluated id and total; note was evaluated by nobody, so unevaluatedProperties is the one that refuses it.",
  },
  refs: {
    draft: "https://json-schema.org/draft/2020-12/schema",
    schema: {
      $defs: { port: { type: "integer", minimum: 1, maximum: 65535 } },
      properties: { listen: { $ref: "#/$defs/port" } },
    },
    instance: { listen: 0 },
    note: "The walk went through $ref, so schema_at names the route. The thread lands on the node nearest that route — the subschema the keyword was applied to.",
  },
};

const map = document.getElementById("threadmap");
if (map) start();

function start() {
  const schemaPane = document.getElementById("tm-schema");
  const instancePane = document.getElementById("tm-instance");
  const svg = document.getElementById("tm-threads");
  const list = document.getElementById("tm-list");
  const note = document.getElementById("tm-note");

  let engine = null;
  let ready = false;
  let threads = [];
  let currentFaults = [];
  // The case the reader last asked for, so a click that lands before the engine
  // has loaded is not overwritten when it does.
  let chosen = "port";

  /* ---------------------------------------------------------- the two trees */

  const escape = (s) => String(s).replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" })[c]);

  const token = (s) => String(s).replace(/~/g, "~0").replace(/\//g, "~1");

  function kindOf(v) {
    if (Array.isArray(v)) return "arr";
    if (v === null) return "null";
    return typeof v === "object" ? "obj" : typeof v === "boolean" ? "bool" : typeof v === "number" ? "num" : "str";
  }

  function preview(v) {
    const k = kindOf(v);
    if (k === "obj") return "{ }";
    if (k === "arr") return "[ ]";
    if (k === "str") return '"' + v + '"';
    return String(v);
  }

  // Every node as one row, depth first, with the JSON Pointer that names it.
  function flatten(value, ptr, depth, label, out) {
    const k = kindOf(value);
    out.push({ ptr, depth, label, kind: k, text: preview(value) });
    if (k === "obj") {
      for (const name of Object.keys(value)) {
        flatten(value[name], ptr + "/" + token(name), depth + 1, name + ":", out);
      }
    } else if (k === "arr") {
      value.forEach((item, i) => flatten(item, ptr + "/" + i, depth + 1, "[" + i + "]", out));
    }
    return out;
  }

  function paint(pane, rows) {
    pane.innerHTML = rows
      .map(
        (r) =>
          `<div class="node" data-ptr="${escape(r.ptr)}" style="padding-left:${4 + r.depth * 13}px"` +
          ` title="${escape(r.ptr || "/")}">` +
          `<span class="key">${escape(r.label)}</span>` +
          `<span class="val ${r.kind}">${escape(r.text)}</span></div>`,
      )
      .join("");
  }

  /* --------------------------------------------------------------- the walk */

  // The deepest node a pointer names: a fault can name a keyword, which is not
  // a node of its own.
  function nearest(rows, ptr) {
    let here = ptr;
    while (here !== "") {
      const hit = rows.find((r) => r.ptr === here);
      if (hit) return hit.ptr;
      const cut = here.lastIndexOf("/");
      here = cut <= 0 ? "" : here.slice(0, cut);
    }
    return rows.length ? rows[0].ptr : "";
  }

  function draw() {
    const box = map.getBoundingClientRect();
    svg.setAttribute("viewBox", `0 0 ${box.width} ${box.height}`);
    svg.setAttribute("width", box.width);
    svg.setAttribute("height", box.height);
    svg.innerHTML = "";

    threads = [];
    for (const fault of currentFaults) {
      const from = schemaPane.querySelector(`[data-ptr="${cssEsc(fault.schemaAt)}"]`);
      const to = instancePane.querySelector(`[data-ptr="${cssEsc(fault.at)}"]`);
      if (!from || !to) continue;
      const a = from.getBoundingClientRect();
      const b = to.getBoundingClientRect();
      const x1 = a.right - box.left;
      const y1 = a.top - box.top + a.height / 2;
      const x2 = b.left - box.left;
      const y2 = b.top - box.top + b.height / 2;
      const reach = Math.max(40, (x2 - x1) * 0.5);

      const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
      path.setAttribute("d", `M${x1} ${y1} C${x1 + reach} ${y1}, ${x2 - reach} ${y2}, ${x2} ${y2}`);
      path.setAttribute("class", "thread");
      svg.appendChild(path);

      const label = document.createElementNS("http://www.w3.org/2000/svg", "text");
      label.setAttribute("x", (x1 + x2) / 2);
      label.setAttribute("y", (y1 + y2) / 2 - 5);
      label.setAttribute("text-anchor", "middle");
      label.setAttribute("class", "dg-label");
      label.style.paintOrder = "stroke";
      label.style.stroke = "var(--cloth)";
      label.style.strokeWidth = "3px";
      // A boolean schema is reported as the keyword `schema`, which says
      // nothing on a thread; the last step of the path names the keyword that
      // actually asked.
      const steps = (fault.schemaAt || "").split("/").filter(Boolean);
      label.textContent =
        fault.keyword === "schema" ? steps[steps.length - 1] || "schema" : fault.keyword;
      svg.appendChild(label);

      threads.push({ fault, path, label, from, to });
    }
  }

  const cssEsc = (s) => String(s).replace(/["\\]/g, "\\$&");

  function highlight(index) {
    threads.forEach((t, i) => {
      const on = i === index;
      t.path.classList.toggle("on", on);
      t.label.style.opacity = index === -1 || on ? "1" : ".35";
      t.from.classList.toggle("hit", on);
      t.to.classList.toggle("hit", on);
    });
    [...list.children].forEach((li, i) => li.classList.toggle("on", i === index));
  }

  /* ------------------------------------------------------------- the answer */

  function load(name) {
    chosen = name;
    const c = CASES[name];
    const schemaRows = flatten(c.schema, "", 0, "", []);
    const instanceRows = flatten(c.instance, "", 0, "", []);
    paint(schemaPane, schemaRows);
    paint(instancePane, instanceRows);
    note.textContent = c.note;

    if (!ready) {
      list.innerHTML =
        '<li style="border:0;background:none;font-family:var(--mono);font-size:11.5px;color:var(--ink-3)">reading the compiled package…</li>';
      return;
    }
    const answer = JSON.parse(
      engine.check(JSON.stringify(c.schema), JSON.stringify(c.instance), c.draft),
    );
    currentFaults = (answer.faults || []).map((f) => ({
      ...f,
      schemaAt: nearest(schemaRows, f.schemaAt),
    }));
    list.innerHTML = currentFaults
      .map(
        (f, i) =>
          `<li data-i="${i}"><span class="i">${i + 1}</span>` +
          `<span class="t">${escape(f.message)}</span>` +
          `<span class="p">${escape(f.keyword)} · ${escape(f.schemaAt || "/")} → ${escape(f.at || "/")}</span></li>`,
      )
      .join("");
    requestAnimationFrame(draw);
  }

  list.addEventListener("pointerover", (e) => {
    const li = e.target.closest("li");
    if (li) highlight(Number(li.dataset.i));
  });
  list.addEventListener("pointerleave", () => highlight(-1));

  document.querySelectorAll("[data-case]").forEach((b) => {
    b.addEventListener("click", () => {
      document.querySelectorAll("[data-case]").forEach((x) =>
        x.setAttribute("aria-pressed", x === b ? "true" : "false"),
      );
      load(b.dataset.case);
    });
  });

  addEventListener("resize", () => requestAnimationFrame(draw));

  (async () => {
    try {
      engine = await import("../engine/moonschema.js");
      ready = true;
      const lamp = document.getElementById("tm-engine");
      if (lamp) lamp.dataset.state = "live";
    } catch {
      note.textContent = "The compiled package did not load, so the threads and faults are not drawn.";
    }
    load(chosen);
  })();
}
