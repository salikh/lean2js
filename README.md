# Lean2js

A project to enable Lean4 code execution in browser.

## Goal

Enable execution of Lean4 code in modern web browser, through one or combination of

* Interpretation of Lean4 LCNF
* Transpilation of Lean4 LCNF to Javascript
* Compilation of Lean4 .cc code to wasm

## Tools

* `lake exe lcnf-dump FILE.lean [--phase base|mono|impure]` — elaborates a Lean file
  and dumps its LCNF (compiler IR) as JSON. See [docs/design/lcnf-json.md](docs/design/lcnf-json.md).
* `tests/run.sh` — golden tests for the above.
* `lake exe lean2js FILE.lean --run --out F.js` — transpile a Lean program (with all its dependencies) to
  JavaScript via Lean's reference-counted IR; run with `node F.js` (needs `runtime/lean_rt.js` next to it).
  See [docs/design/js-transpiler-ir.md](docs/design/js-transpiler-ir.md) (older mono-LCNF backend:
  [docs/design/js-transpiler.md](docs/design/js-transpiler.md)). Browser demo: `web/`.
* `tests/e2e/run.sh` — differential tests: native `lean --run` vs. transpiled JS under Node.
