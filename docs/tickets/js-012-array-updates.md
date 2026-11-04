# Avoid O(n) copy on every Array update

Parent: [js-001-transpiler-epic](js-001-transpiler-epic.md)

Status: **done** (2026-11-04) via the IR backend ([js-013](js-013-question-ir-backend.md)); `tests/e2e/aliasing.lean` and `bigperf.lean` cover it.

## Problem

The runtime treats `Array` as immutable: `lean_array_push/set/uset/pop/swap` copy the array
(`runtime/lean_runtime.js`, section "Array"). Loops building an array of n elements take O(n²)
(`tests/e2e/bigloop.lean` only pushes 20000). Native Lean updates in place when the array is
uniquely referenced.

## Ideas (pick one, measure first)

1. In the transpiler: a last-use analysis on mono LCNF — if the array argument variable is not used after the
   call (and is not captured/aliased), call a destructive primitive variant (`lean_array_push_inplace`).
   Needs a liveness pass over `Code`; params are "owned" unless borrowed (the dump has `borrow` flags only
   for impure phase).
2. In the runtime: ownership flag on arrays (`arr.shared`), set when an array is read from a field / passed
   twice; conservative and hard to get right.
3. Use the `impure` phase, which already has explicit `inc`/`dec`/`isShared` — reference counts would have to be
   emulated; probably not worth it.

## Acceptance

Pushing 1e6 elements takes < 1 s; semantics unchanged (all e2e tests still pass, add a test that aliases an array
before and after a push to check persistence).
