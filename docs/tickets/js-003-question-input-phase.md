# Question: Which LCNF phase should the transpiler consume?

Parent: [js-001-transpiler-epic](js-001-transpiler-epic.md)

Status: **decided (2026-11-04)**: the recommended answer was accepted. Reopen by moving this ticket to "TODO for humans" in TODO.md.

## Question

`lcnf-dump` supports `base`, `mono`, `impure` ([lcnf-002](lcnf-002-question-phase.md)).
Which is the transpiler's input?

## Recommended answer

`mono`. It is pure, monomorphized, and has no reference counting, boxing or scalar-layout
details that are meaningless in JS. Constructor applications appear as `const` calls with
the constructor name and `cases` alternatives carry constructor names, so the transpiler needs
constructor metadata (index/`cidx`, number of fields, enclosing inductive, which types are
enumerations or "special" builtin representations); this is provided by
[js-006](js-006-dump-dependencies.md) (`inductives` section in the dump).

## Alternatives

* `impure`: has `ctor` with `CtorInfo` (cidx, sizes) and `proj` split into `oproj/uproj/sproj` with
  byte offsets and `sset` — scalar-field layout is an obstacle for JS objects; `inc/dec/reset/reuse`
  would be ignored. It is, however, what Lean's own C/IR backends consume, so semantics of
  boxed vs unboxed scalars (`UInt64` etc.) are explicit.
* `base`: still polymorphic with type-class dictionaries not specialized; slower, no benefit.

## If revised

Changes js-007 `LetValue` handling and js-006 (metadata not needed for `impure`).
