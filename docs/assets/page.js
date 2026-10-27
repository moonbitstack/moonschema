// Shared page behaviour: the theme switch, the code highlighter, copy buttons,
// the running table of contents, and the reveal of sections as they arrive.

/* ------------------------------------------------------------------- theme */

const THEME_KEY = "moonschema-theme";

function currentTheme() {
  const set = document.documentElement.getAttribute("data-theme");
  if (set) return set;
  return matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
}

function paintThemeButton() {
  const dark = currentTheme() === "dark";
  document.querySelectorAll("[data-theme-toggle]").forEach((b) => {
    b.setAttribute("aria-pressed", dark ? "true" : "false");
    b.setAttribute("title", dark ? "Switch to the light sheet" : "Switch to the dark sheet");
    b.querySelector(".sun")?.toggleAttribute("hidden", dark);
    b.querySelector(".moon")?.toggleAttribute("hidden", !dark);
  });
}

document.querySelectorAll("[data-theme-toggle]").forEach((b) => {
  b.addEventListener("click", () => {
    const next = currentTheme() === "dark" ? "light" : "dark";
    document.documentElement.setAttribute("data-theme", next);
    try {
      localStorage.setItem(THEME_KEY, next);
    } catch {}
    paintThemeButton();
  });
});

matchMedia("(prefers-color-scheme: dark)").addEventListener("change", paintThemeButton);
paintThemeButton();

/* -------------------------------------------------------------- highlighter */

const KEYWORDS = new Set([
  "fn", "let", "mut", "for", "in", "match", "with", "try", "catch", "if", "else",
  "while", "return", "raise", "guard", "pub", "priv", "struct", "enum", "impl",
  "trait", "type", "const", "break", "continue", "defer", "test", "async", "extern",
]);

const RULES = {
  moonbit: [
    ["c", /\/\/[^\n]*/y],
    ["p", /#\|/y],
    ["s", /"(?:[^"\\\n]|\\.)*"/y],
    ["s", /'(?:[^'\\\n]|\\.)'/y],
    ["n", /\b\d+(?:\.\d+)?(?:e[+-]?\d+)?\b/iy],
    ["f", /@[A-Za-z_][\w.]*/y],
    ["k", /[A-Za-z_]\w*/y],
    ["p", /[{}()[\];:,.]/y],
  ],
  json: [
    ["c", /\/\/[^\n]*/y],
    ["s", /"(?:[^"\\\n]|\\.)*"(?=\s*:)/y],
    ["s", /"(?:[^"\\\n]|\\.)*"/y],
    ["n", /-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b/y],
    ["k", /\b(?:true|false|null)\b/y],
    ["p", /[{}[\]:,]/y],
  ],
  bash: [
    ["c", /#[^\n]*/y],
    ["s", /"(?:[^"\\]|\\.)*"|'[^']*'/y],
    ["f", /^\$ /my],
  ],
  text: [],
};

function paintPre(pre) {
  const lang = pre.dataset.lang || "text";
  const rules = RULES[lang];
  if (!rules || !rules.length) return;

  const walk = (node) => {
    for (const child of [...node.childNodes]) {
      if (child.nodeType === Node.ELEMENT_NODE) {
        // A wrapped glyph keeps its own box; only its inside is fair game.
        if (child.classList.contains("w1") || child.classList.contains("w2")) continue;
        walk(child);
        continue;
      }
      if (child.nodeType !== Node.TEXT_NODE) continue;
      const text = child.nodeValue;
      if (!text) continue;

      const frag = document.createDocumentFragment();
      let plain = "";
      let i = 0;
      outer: while (i < text.length) {
        for (const [cls, re] of rules) {
          re.lastIndex = i;
          const m = re.exec(text);
          if (m && m.index === i) {
            if (plain) {
              frag.appendChild(document.createTextNode(plain));
              plain = "";
            }
            const word = m[0];
            let name = cls;
            if (lang === "moonbit" && cls === "k") {
              // A keyword, a type, or a plain name — the three read differently.
              name = KEYWORDS.has(word) ? "k" : /^[A-Z]/.test(word) ? "fn" : "";
            }
            if (name) {
              const s = document.createElement("span");
              s.className = name;
              s.textContent = word;
              frag.appendChild(s);
            } else {
              frag.appendChild(document.createTextNode(word));
            }
            i += word.length;
            continue outer;
          }
        }
        plain += text[i];
        i += 1;
      }
      if (plain) frag.appendChild(document.createTextNode(plain));
      child.replaceWith(frag);
    }
  };
  walk(pre);
}

document.querySelectorAll("pre[data-lang]").forEach(paintPre);

/* -------------------------------------------------------------- copy buttons */

document.querySelectorAll("[data-copy]").forEach((btn) => {
  btn.addEventListener("click", async () => {
    const sel = btn.dataset.copy;
    const src = sel === "self" ? btn : document.querySelector(sel);
    if (!src) return;
    const text = (src.dataset.copyText || src.textContent || "").trim();
    try {
      await navigator.clipboard.writeText(text);
      const was = btn.textContent;
      btn.textContent = "copied";
      setTimeout(() => (btn.textContent = was), 1400);
    } catch {
      btn.textContent = "press ⌘C";
    }
  });
});

/* ------------------------------------------------------------------ reveal */

const revealables = document.querySelectorAll("[data-reveal]");
if (revealables.length && !matchMedia("(prefers-reduced-motion: reduce)").matches) {
  const io = new IntersectionObserver(
    (entries) => {
      entries.forEach((e) => {
        if (!e.isIntersecting) return;
        e.target.classList.add("in");
        io.unobserve(e.target);
      });
    },
    { rootMargin: "0px 0px -12% 0px", threshold: 0.05 },
  );
  revealables.forEach((el) => io.observe(el));

  const style = document.createElement("style");
  style.textContent =
    "[data-reveal]{opacity:0;transform:translateY(10px);transition:opacity .5s ease,transform .5s cubic-bezier(.2,.7,.3,1)}" +
    "[data-reveal].in{opacity:1;transform:none}";
  document.head.appendChild(style);
}

/* --------------------------------------------------------------- toc tracking */

const tocLinks = [...document.querySelectorAll(".toc a[href^='#']")];
if (tocLinks.length) {
  const targets = tocLinks
    .map((a) => ({ a, el: document.getElementById(a.getAttribute("href").slice(1)) }))
    .filter((t) => t.el);
  const mark = (id) => {
    tocLinks.forEach((a) => {
      const li = a.parentElement;
      li.classList.toggle("on", a.getAttribute("href") === "#" + id);
    });
  };
  const io = new IntersectionObserver(
    (entries) => {
      const visible = entries.filter((e) => e.isIntersecting);
      if (visible.length) mark(visible[0].target.id);
    },
    { rootMargin: "-84px 0px -62% 0px", threshold: 0 },
  );
  targets.forEach((t) => io.observe(t.el));
  if (targets.length) mark(targets[0].el.id);
}

/* --------------------------------------------------------------- year stamp */

document.querySelectorAll("[data-year]").forEach((el) => {
  el.textContent = String(new Date().getFullYear());
});
