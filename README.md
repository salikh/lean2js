# Lean2js

A project to enable Lean4 code execution in browser.

## Goal

Enable execution of Lean4 code in modern web browser, through one or combination of

* Interpretation of Lean4 LCNF
* Transpilation of Lean4 LCNF to Javascript
* Compilation of Lean4 .cc code to wasm

## Status

*Updated at every commit (newest first; details in [docs/CHANGES.md](docs/CHANGES.md), open work in [TODO.md](TODO.md)).*

* **2026-11-05 — the Lean frontend runs as JavaScript.** `selfhost/Elab.lean`, transpiled by `lean2js --init-all --eval-all`, elaborates Lean source under
  Node with no native Lean code and prints exactly what native Lean prints: pattern-matching definitions, structures with `deriving Repr`, inductive types,
  `simp`, `decide`, `#check`, `#eval` (the compiler pipeline and an IR → JS generator run inside the JS program; see
  [docs/design/self-hosted-elaborator.md](docs/design/self-hosted-elaborator.md), test `tests/e2e/selfhost.lean`). Also new: cooperative task scheduler,
  `evalConst`, stdin `read`. Open: size (450 MB) and ~40 s startup ([self-008](docs/tickets/self-008-bundle-startup-size.md)), a type-checking kernel
  (`check := true`), a browser front end.

* **2026-11-04 — kernel for the JS-hosted compiler.** Lean programs (also big ones) already run as JavaScript. For the epic *run the Lean
  compiler itself in JS* ([self-001](docs/tickets/self-001-compiler-to-js-epic.md)): the whole `Lean` initialization, `MetaM`,
  `instantiateMVars`, reading real `.olean` files and `importModules Init` work in JS and match native Lean. New: a kernel written in
  Lean — vendored core of [lean4lean](https://github.com/digama0/lean4lean) (`vendor/lean4lean`, builds on Lean 4.35 with three small
  patches) used through `Lean2js/Kernel.lean` as a *trusting* `add_decl` (no type checking yet; handles inductive types), plus our own
  `casesOn` construction (matches the C++ one on 35 Init types). Next: elaborating `def x := 1` end to end (self-009); blockers: the
  size of the generated code (327 MB with all initializers, [self-008](docs/tickets/self-008-bundle-startup-size.md)) and the
  type-checking mode (`check := true`).
* 2026-11-04 — `.olean` loader, module initializers, `Expr`/`Level` primitives, filesystem; `demo.sh` and `test.sh`; web demo with a calculator.

## Tools

* `lake exe lcnf-dump FILE.lean [--phase base|mono|impure]` — elaborates a Lean file
  and dumps its LCNF (compiler IR) as JSON. See [docs/design/lcnf-json.md](docs/design/lcnf-json.md).
* `./demo.sh` — walkthrough on five tiny programs in `demo/`: source, `lean --run`, native binary (`lean -c` + `leanc`), compile to JS, `node` (commands and timings shown).
* `./test.sh [--quick]` — all tests: lcnf-dump goldens (`tests/run.sh`), demo programs and the e2e differential tests (`tests/e2e/run.sh`).
* `lake exe lean2js FILE.lean --run --out F.js` — transpile a Lean program (with all its dependencies) to
  JavaScript via Lean's reference-counted IR; run with `node F.js` (needs `runtime/lean_rt.js` next to it).
  See [docs/design/js-transpiler-ir.md](docs/design/js-transpiler-ir.md). Browser demo: `web/` — `web/build.sh web/examples/calc.lean && python3 -m http.server -d web 8000`
  (a big-number calculator reading stdin; the page shows the Lean source and prefilled sample input).
* `lean2js --init-all` runs the initializers of all imported modules ([docs/design/module-initializers.md](docs/design/module-initializers.md)).
* `runtime/lean_expr.js` — JS versions of the C++ `Expr`/`Level` primitives (see [docs/design/lean-expr-prims.md](docs/design/lean-expr-prims.md)).
* `Lean2js/Kernel.lean`, `Lean2js/KernelCasesOn.lean`, `vendor/lean4lean` — the kernel entry points for the self-hosted compiler ([docs/tickets/self-005-question-kernel-strategy.md](docs/tickets/self-005-question-kernel-strategy.md)).
* `tests/e2e/run.sh` — differential tests: native `lean --run` vs. transpiled JS under Node.
