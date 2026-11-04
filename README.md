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
  See [docs/design/js-transpiler-ir.md](docs/design/js-transpiler-ir.md). Browser demo: `web/` — `web/build.sh web/examples/calc.lean && python3 -m http.server -d web 8000`
  (a big-number calculator reading stdin; the page shows the Lean source and prefilled sample input).
* `lean2js --init-all` runs the initializers of all imported modules ([docs/design/module-initializers.md](docs/design/module-initializers.md)).
* `runtime/lean_expr.js` — JS versions of the C++ `Expr`/`Level` primitives (see [docs/design/lean-expr-prims.md](docs/design/lean-expr-prims.md)).
* `tests/e2e/run.sh` — differential tests: native `lean --run` vs. transpiled JS under Node.
