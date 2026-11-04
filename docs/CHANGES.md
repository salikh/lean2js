# Changes

Completed tasks, newest first. Each entry links the ticket and gives date and a brief summary.

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
