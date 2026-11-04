# Epic: compile the Lean compiler itself to JavaScript

Status: **open** (feasibility probe done 2026-11-04, see self-002)

## Goal

Run the Lean frontend (`Lean.Elab.runFrontend`: parser, elaborator, LCNF compiler, IR
generation) as JavaScript, so that in the browser/Node one can type Lean source, elaborate it,
and (with the existing `lean2js` backend) run it, with no native Lean installation.
Long-term pipeline: `Lean source -> [Lean frontend, as JS] -> IR -> [CodegenIR, as JS] -> JS -> eval`.

## Background / feasibility probe (self-002)

A 6-line program calling `Lean.Elab.runFrontend` (`import Lean`) transpiles with the existing
IR backend in ~2 s into a **21 MB** JS file (~12k functions). So the Lean-implemented part is
transpilable today. What is missing is everything that is native (C/C++) in the real `lean`:

1. **91 runtime primitives** missing in `runtime/lean_rt.js` (list reproducible with the script
   in self-002): Expr/Level/Name C++ helpers (`lean_expr_instantiate*`, `abstract*`, `lift/lower_loose_bvars`,
   `lean_expr_quick_lt`, `lean_find_expr`, `lean_replace_expr`, `lean_instantiate_*_mvars`, `lean_expr_mk_data`, ...),
   Int64, handles/process/metadata/realpath, promises, mutex, heartbeats, `lean_ptr_addr`, thunks etc.
2. **The kernel** (`lean_add_decl`, `lean_kernel_whnf/is_def_eq/check`, C++ in Lean 4.35): type checker,
   inductive types compiler (recursors!), quotient, etc. Not transpilable; must be reimplemented or skipped.
   (Probe oddity: no `lean_add_decl` reference showed up in the 21 MB output — verify in self-005.)
3. **Module initialization**: `builtin_initialize` / `[init]` declarations (thousands: parser tables,
   attributes, extensions, options) are run by `initialize_<Module>` in native Lean. The current lazy
   zero-arity-constant scheme does not run them (see js-014 item 2). Needed before any elaboration works.
4. **`.olean` loading**: `readModuleData` (`lean_compacted_region_read`) mmaps compacted object graphs.
   Need a JS parser for the olean format (and in the browser, fetching ~hundreds of MB of .olean or a
   trimmed subset).
5. **Tasks/threads**: elaborator uses `Task`, `IO.Promise`, `Language.Lean.process` snapshots. Single-threaded JS
   must run tasks eagerly/cooperatively.
6. **Size/startup/speed**: 21 MB JS without initializers but **327 MB with `--init-all`** (measured 2026-11-04), plus startup of ~5000 initializers and import of Init/Std/Lean .oleans. This is a gate for the first milestone (self-008).

## Subtickets

* [self-002-feasibility-probe](self-002-feasibility-probe.md) — done, findings
* [self-003-module-initializers](self-003-module-initializers.md)
* [self-004-expr-primitives](self-004-expr-primitives.md)
* [self-005-question-kernel-strategy](self-005-question-kernel-strategy.md) — **needs human decision** (recommended answer given)
* [self-006-olean-loader](self-006-olean-loader.md)
* [self-007-misc-primitives](self-007-misc-primitives.md)
* [self-008-bundle-startup-size](self-008-bundle-startup-size.md)
* [self-009-milestone-hello-elab](self-009-milestone-hello-elab.md) — first end-to-end milestone

## Suggested order

self-007 + self-004 (mechanical, testable by differential tests against native) -> self-003 -> self-006
-> self-009 (elaborate `def x := 1` with kernel checking disabled) -> self-005 (kernel) -> self-008.
