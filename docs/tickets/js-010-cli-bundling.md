# `lean2js` command and bundling

Parent: [js-001-transpiler-epic](js-001-transpiler-epic.md)

Status: **partly done** (2026-11-04): `lake exe lean2js FILE.lean|FILE.json --out F.js --run`. Browser demo done: `web/index.html` + `web/build.sh` (verified with headless Chrome). Open: `--bundle` single file, `--allow-missing`/transpile-time listing of missing primitives, source maps.

## Goal

* `lake exe lean2js FILE.json [--out FILE.js] [--entry main] [--no-treeshake]` (or taking `FILE.lean` directly
  and invoking the dump internally, `lean2js FILE.lean --run` pipeline convenience:
  `lean2js prog.lean -o prog.js`).
* Output: a single ES module importing `./lean_runtime.js`, exporting `main`; plus
  `--bundle` option that inlines the runtime into one standalone file usable via `<script>`.
* Browser demo: `web/index.html` that loads the generated JS, displays stdout in a `<pre>`, and has a
  stdin textarea. Node runner `node prog.js args…`.
* Source maps are optional / a follow-up ticket.
* Exit codes/diagnostics: unknown extern → error listing missing primitives (fail at transpile time, not at
  runtime), unless `--allow-missing` (emits stubs that throw).

## Acceptance

`lake exe lean2js tests/lcnf/basic.lean -o /tmp/basic.js && node /tmp/basic.js` prints `Hello, world`;
the web demo works in a browser (verify with the browser skill if available).
