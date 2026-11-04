# End-to-end differential tests

Parent: [js-001-transpiler-epic](js-001-transpiler-epic.md)

Status: **in progress** (2026-11-04): `tests/e2e/run.sh` (BACKEND=ir|mono), 29 programs pass on both backends (aliasing/bigperf IR only checked so far). Open: more coverage (IO.FS, time/random, Unicode edge cases, ByteArray-heavy code).

## Goal

A test driver (`tests/e2e/run.sh` or a Lean/Node script) that for each `tests/e2e/NAME.lean` (program with
`def main : IO Unit`, optional `NAME.stdin`, `NAME.args`):

1. compiles natively (`lake env lean --run` or `leanc`) and records stdout + exit code;
2. runs lcnf-dump → lean2js → `node` and compares stdout + exit code byte for byte.

Test corpus (add incrementally, each is a small program): arithmetic incl. big `Nat`/negative `Int`/`UInt`
wraparound, `String` Unicode ops, `List`/`Array` functions, `HashMap`/`RBMap`, structures/inductives/
`deriving Repr`, type classes, closures/partial application, mutual recursion, `partial def` loops
(1e6 iterations — tests js-005), `StateM`/`ExceptT` stacks, `IO.Ref`, exceptions, `Thunk`, `Task`, string
formatting (`toString`, `repr`, `Float` printing), `panic!`/`unreachable!`, `main` with args and exit code.

Known-difference list: anything intentionally unsupported (threads, FFI) documented in
docs/design/js-transpiler.md.

## Acceptance

CI-style script exits 0 when all pass; each failing case prints a diff. At least 20 programs.
