# Changes

Completed tasks, newest first. Each entry links the ticket and gives date and a brief summary.

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
