# Feasibility probe: transpile runFrontend

Parent: [self-001](self-001-compiler-to-js-epic.md)
Status: done (2026-11-04)

Probe program (`import Lean`, `def main : IO UInt32` calling `Lean.Elab.runFrontend "def x := 1" {} "<in>" `m`
inside `IO.FS.withIsolatedStreams`) transpiled with `lake exe lean2js p.lean --out p.js`: 2.3 s, 21 MB,
~12.1k functions, 268 distinct `rt.prims[...]` externs referenced, **91 not implemented** in `runtime/lean_rt.js`.

Reproduce missing list: `grep -o 'rt.prims\["[^"]*"\]'` on the output and diff against `Object.keys(rt.prims)`
(a throwaway script doing exactly that: iterate `/rt\.prims\["([^"]*)"\]/g`, check `in rt.prims`).

Missing groups: Expr/Level/Name (24), Int64 (4), IO handles/process/fs-metadata (8), promises/mutex/tasks (8),
uv sockets/timers (~20, can stub), dynlib/eval_const/run_init (5), compacted_region (2), misc (heartbeats,
ptr_addr, profileit, platform, `lean_void_mk`, strict_or ...).
Names in output use `$` mangling (`Lean$Elab$Command$elabCommand`), so grep with `$`.
