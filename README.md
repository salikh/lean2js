# Lean2js

A project to enable Lean4 code execution in browser.

## Goal

Enable execution of Lean4 code in modern web browser, through one or combination of

* Interpretation of Lean4 LCNF
* Transpilation of Lean4 LCNF to Javascript
* Compilation of Lean4 .cc code to wasm

## Status

*Updated at every commit (newest first; details in [docs/CHANGES.md](docs/CHANGES.md), open work in [TODO.md](TODO.md)).*

* **2026-11-05 (final for now) — all open tickets wait for a human decision.** Done: the transpiler, the self-hosted Lean frontend (kernel, `.olean` loader, browser build), three web demos, an infoview that agrees with the real language server
  (goals, term goals, hover, messages; 15 oracle cases). Questions in [TODO.md](TODO.md): interactive goals representation (info-006), LSP server for `lsp.html` (demo-002), further memory work (self-008).

* Hover works too: `Lean2js.Info` returns the `textDocument/hover` markdown identical to the real server's on 6 cases (15 infoview cases in total, [info-006](docs/tickets/info-006-interactive-hover.md)).
* **2026-11-05 (night 3) — the real language server in JS: tried, blocked.** `Lean.Server.FileWorker` starts in the JS runtime (batch mode, `selfhost/LspBatch.lean`) but cannot finish
  elaboration: it relies on concurrent threads and the runtime has no coroutines. Scheduler improvements that came out of it: real cancellation, polling that makes progress, lazy dedicated tasks, `LEAN2JS_WATCHDOG`.
  Decision needed (recommended: an in-memory LSP *protocol adapter* over `Lean2js.Info`, already verified against the real server): [demo-002](docs/tickets/demo-002-lsp-infoview-in-demo.md).

* **2026-11-05 (night 2) — a browser infoview.** `web/selfhost/infoview.html`: an editor and a panel with the goals, the expected type and the messages at the cursor (or, in prefix mode, for the text
  before the cursor), computed by the Lean frontend running in the page (`Lean2js/Info.lean`, ~65 ms per request after the one-time `Init` import). The answers are identical to the real language server's
  `$/lean/plainGoal` / `$/lean/plainTermGoal` on the test cases (`tests/info/run.sh`) and the page is checked in headless Chrome ([info-007](docs/tickets/info-007-web-ui.md)).

* Promise-drop investigation closed: 38-file corpus identical to native with 0 guesses ([self-010](docs/tickets/self-010-promise-drop-heuristic.md)).
* **2026-11-05 (last) — infoview started; filed demo-002 (real LSP server + live infoview in the demo, after the self-* tickets).** `Lean2js/Info.lean` (goals / term goal / messages at a position, prefix and cursor mode) works, identical natively and in JS, and identical to the real language server's `$/lean/plainGoal` / `$/lean/plainTermGoal` on 9 test cases (`tests/info/run.sh`, part of `test.sh`). The olean loader now uses ~40% less external memory (RSS ≈ 2.6 GB, [self-008](docs/tickets/self-008-bundle-startup-size.md)) ([info-004](docs/tickets/info-004-infotree-goals.md)).

* **2026-11-05 (late) — interactive demo.** `web/selfhost/demo.html`: a Lean script pane, a `data.json` pane (visible to the script as the file `data.json`) and a console that shows the script's
  output and **evaluates what you type** — `main`, `mean #[1.0, 2.0, 6.0]`, `def …`, any `IO` action — in a persistent Lean session (`Lean2js/Session.lean`). The default example computes count/mean/min/max/stdev of the
  numbers in the JSON. Checked in headless Chrome by `web/selfhost/test-browser.sh` ([demo-001](docs/tickets/demo-001-interactive-web-app.md)).

* **2026-11-05 (night) — promise drops are exact.** The cooperative scheduler resolves a promise with `none` when its last reference disappears (reference counting), as native Lean does; the
  "guess" fallback fired 36× per sample before and never now ([self-010](docs/tickets/self-010-promise-drop-heuristic.md), strict mode in the selfhost tests). Infoview design decision recorded:
  thin layer over the `InfoTree` ([info-002](docs/tickets/info-002-question-architecture.md)); work on it starts after the remaining `self-*` tickets.
* **2026-11-05 (evening) — the Lean frontend runs in the browser.** `web/selfhost/build.sh` builds `elab.js` (174 MB) and the `Init` library files; `python3 -m http.server -d web/selfhost 8000`
  (or `node web/selfhost/serve.mjs`) serves a page with an editor and an "Elaborate" button; `web/selfhost/test-browser.sh` checks it in headless Chrome (output identical to native, ~40 s
  including the 160 MB download from localhost). It runs on the page's main thread because Chrome gives Web Workers only ~40% of the stack, which the compiler's recursion exceeds.
  Planned next (after the remaining `self-*` tickets): an infoview equivalent, [info-001](docs/tickets/info-001-infoview-epic.md).

* Dropped promises are now detected by reference counting (like native Lean); the old "guess" fallback never fires on the tests ([self-010](docs/tickets/self-010-promise-drop-heuristic.md)).
* **2026-11-05 (latest) — the JS kernel type checks.** `Kernel.whnf/isDefEq/check` and `addDecl` run lean4lean's type checker in JS (on by default, `LEAN2JS_KERNEL_CHECK=0` to disable):
  the self-hosted frontend rejects ill-typed declarations with exactly the native kernel's messages (tests `kernelops`, `selfhostcheck`).
* **2026-11-05 (later) — smaller and faster.** `lean2js --small` (short identifiers, no indentation) shrinks the self-hosted frontend from 452 MB to 174 MB of JS
  (~14 MB with brotli); a faster `.olean` loader brings a complete run (load, initialize, import `Init`, elaborate, `#eval`) from ~40 s to ~14 s. Memory (~3 GB) is the next problem
  ([self-008](docs/tickets/self-008-bundle-startup-size.md)).
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
* `web/selfhost/` — the Lean frontend in the browser: `index.html` (editor → messages) and `demo.html` (script + data + console, see Status); `selfhost/Elab.lean` is the program (stdin → messages).
* `tests/e2e/run.sh` — differential tests: native `lean --run` vs. transpiled JS under Node.
