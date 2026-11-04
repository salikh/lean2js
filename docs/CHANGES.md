# Changes

Completed tasks, newest first. Each entry links the ticket and gives date and a brief summary.

* 2026-11-05 — [self-010-promise-drop-heuristic](tickets/self-010-promise-drop-heuristic.md): dropped promises detected by reference counting (`dropPromise` in `free`), fallback counted/strict; `.env` files in tests/e2e; info-002 decided (thin layer).

* 2026-11-05 — browser version of the self-hosted frontend: `web/selfhost/` (driver, worker option, `build.sh`, `serve.mjs`, `test-browser.sh`); `LEAN2JS_ENV` for `IO.getEnv` outside Node; fetch pool; stack-size finding documented.

* 2026-11-05 — [info-001-infoview-epic](tickets/info-001-infoview-epic.md): plan for an infoview equivalent (tickets info-002 … info-008); no code. Browser build of the self-hosted frontend (`web/selfhost/`, verified in headless Chrome).

* 2026-11-05 — [self-010-promise-drop-heuristic](tickets/self-010-promise-drop-heuristic.md) filed: the scheduler's "oldest unresolved promise is dropped" guess needs confirmation.

* 2026-11-05 — [self-005-question-kernel-strategy](tickets/self-005-question-kernel-strategy.md): type-checking kernel on by default (lean4lean `check := true`), `lean_kernel_whnf/is_def_eq/check`; tests `kernelops`, `selfhostcheck`.

* 2026-11-05 — [self-008-bundle-startup-size](tickets/self-008-bundle-startup-size.md): `--small` (short ids, no indentation: 452 → 174 MB), olean loader 6× faster (binary search of regions, 32-bit reads), no-alloc string hash; startup 40 s → 14 s.

* 2026-11-05 — [self-009-milestone-hello-elab](tickets/self-009-milestone-hello-elab.md) **reached**: `selfhost/Elab.lean` (the Lean frontend) elaborates and evaluates Lean source as JavaScript, output identical to native;
  `--eval-all`, `evalConst` incl. run-time codegen (`genChunk`), structural `nameId` mangling, cooperative tasks/promises ([design](design/tasks.md)), stdin `read`; tests `selfhost`, `tasks`, `stdinread`, `casesOn`, `kernel`.
  Design: [design/self-hosted-elaborator.md](design/self-hosted-elaborator.md).

* 2026-11-04 — [self-005-question-kernel-strategy](tickets/self-005-question-kernel-strategy.md): vendored lean4lean + Batteries; `Lean2js/Kernel.lean` (trusting add_decl incl. inductives),
  `Lean2js/KernelCasesOn.lean` (casesOn); ownership adapters for `@[export]` implementations of `@&` externs; `Expr` debug printer; tests `kernel`, `casesOn`; test scripts no longer inherit stdin.

* 2026-11-04 — [tools-001-demo-and-test-scripts](tickets/tools-001-demo-and-test-scripts.md): `demo.sh` (5 tiny programs in `demo/`, with timings) and `test.sh` (all tests, `--quick`).

* 2026-11-04 — [self-006-olean-loader](tickets/self-006-olean-loader.md): `runtime/lean_olean.js` reads real .olean files; lazy scalar-field decoding (`rt.sget`/`uget` emitted by CodegenIR);
  Nat/Int primitives accept boxed-scalar numbers; `importModules Init` works in JS; tests `olean`, `import` ([design](design/olean-loader.md)).

* 2026-11-04 — [self-003-module-initializers](tickets/self-003-module-initializers.md) done (`--init-all`, lazy init constants, `IO.initializing`, retrying order-tolerant startup;
  [design](design/module-initializers.md)); signed Int8/16/32/64 + Float32 + version/platform primitives (`lean_num.js`, `lean_sys.js`); tests `init`, `sints`, `mvars`
  (the full `Lean` initialization and `MetaM` run in JS).

* 2026-11-04 — self-004/self-007: `instantiateMVars` port (untested in JS until self-003), `runtime/lean_fs.js` (files, dirs, metadata, stream redirection, stubs); test `tests/e2e/fs.lean`.

* 2026-11-04 — [js-001-transpiler-epic](tickets/js-001-transpiler-epic.md): updated to say the transpiler's source is now Lean IR (not LCNF JSON).

* 2026-11-04 — [self-004-expr-primitives](tickets/self-004-expr-primitives.md) (mostly): `runtime/lean_expr.js` with Expr/Level/Name primitives, `rt.exports`
  registry for calling compiled Lean constructors, `tests/e2e/expr.lean`; fixed `lean_uint64_mix_hash` (now bit-identical hashes). Design: [design/lean-expr-prims.md](design/lean-expr-prims.md).

* 2026-11-04 — Web demo: example `web/examples/calc.lean` (parser + evaluator, big numbers, HashMap), `web/build.sh` copies source and
  sample stdin, page shows both; output verified identical to native `lean --run`.

* 2026-11-04 — [js-014-cleanup-gaps](tickets/js-014-cleanup-gaps.md) item 1: removed the mono-LCNF backend (Codegen, Ast, lean_runtime.js,
  `--backend`, JSON input, docs/design/js-transpiler.md); shared helpers in `Lean2js/JsUtil.lean`. `lcnf-dump` stays.

* 2026-11-04 — [self-007-misc-primitives](tickets/self-007-misc-primitives.md) (partly): Int64, promises, ptr_addr, heartbeats,
  mutex stubs etc. in `runtime/lean_rt.js`; test `tests/e2e/prims2.lean` (31 e2e programs pass). Kernel decision for self-005 recorded.

* 2026-11-04 — [self-001-compiler-to-js-epic](tickets/self-001-compiler-to-js-epic.md): new epic to compile the Lean
  frontend to JS; feasibility probe (self-002) and subtickets self-003…009 created, no code changes.

* 2026-11-04 — [js-013-question-ir-backend](tickets/js-013-question-ir-backend.md), [js-012](tickets/js-012-array-updates.md):
  new default IR backend (`Lean2js/CodegenIR.lean`, `runtime/lean_rt.js`) that translates Lean's final IR with
  reference counting; Array/structure updates are in place when exclusive (100k pushes: 55 s → 0.14 s).
  Design: [design/js-transpiler-ir.md](design/js-transpiler-ir.md).

* 2026-11-04 — [js-001-transpiler-epic](tickets/js-001-transpiler-epic.md) (in progress): `lean2js`
  LCNF→JavaScript transpiler in Lean (js-007), JS runtime (js-008, js-009 partly), CLI (js-010 partly) and
  22 differential e2e tests (js-011); design in [design/js-transpiler.md](design/js-transpiler.md).

* 2026-11-04 — [js-006-dump-dependencies](tickets/js-006-dump-dependencies.md): `lcnf-dump --with-deps`
  dumps transitive (imported) dependencies, extern primitives and inductive metadata.

* 2026-11-04 — [lcnf-001-json-dump](tickets/lcnf-001-json-dump.md): added the
  `lcnf-dump` command (`lake exe lcnf-dump FILE.lean [--phase base|mono|impure]
  [--compact] [--out F]`) that elaborates a Lean file and dumps its LCNF as JSON;
  golden tests in `tests/run.sh`; schema in
  [design/lcnf-json.md](design/lcnf-json.md). Open design choices were split into
  tickets lcnf-002 … lcnf-006 (provisionally decided, revisable).

* 2026-11-04 — Initial empty Lean 4 project setup (`lakefile.toml`, `Lean2js` library,
  `lean2js` hello-world executable).
