# Milestone: elaborate `def x := 1` in JS

Parent: [self-001](self-001-compiler-to-js-epic.md)
Status: **reached** (2026-11-05) — see [design/self-hosted-elaborator.md](../design/self-hosted-elaborator.md). The size/startup gate (self-008) is still open: 450 MB, ~40 s.

Original status line: open (self-003, 004 done; self-007 mostly; blocked by self-006 `.olean` loader and the trusting `add_decl` of self-005 option A). **Also gated by [self-008](self-008-bundle-startup-size.md)** (size/startup of the generated code: 327 MB with `--init-all` today).

Done when `node` (no native lean) runs the transpiled frontend over `def x : Nat := 1\n#eval x` with Init oleans loaded and prints `1`
(needs the IR interpreter or our JS codegen for `#eval`; initially just print `x : Nat` via `#check x`). Add as e2e test `tests/self/`.
