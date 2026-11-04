# Milestone: elaborate `def x := 1` in JS

Parent: [self-001](self-001-compiler-to-js-epic.md)
Status: open (blocked by self-003, 004, 006, 007; kernel via option A of self-005)

Done when `node` (no native lean) runs the transpiled frontend over `def x : Nat := 1\n#eval x` with Init oleans loaded and prints `1`
(needs the IR interpreter or our JS codegen for `#eval`; initially just print `x : Nat` via `#check x`). Add as e2e test `tests/self/`.
