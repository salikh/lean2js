# Question: transpile Lean's final IR (λRC) instead of mono LCNF, to get in-place updates?

Parent: [js-001-transpiler-epic](js-001-transpiler-epic.md); supersedes the approaches in
[js-012-array-updates](js-012-array-updates.md) if accepted.

Status: **decided (2026-11-04)**: the user approved the recommendation; implementation in progress.
Deviation from the plan: the IR generator consumes `Lean.IR.Decl` in-process (no JSON dump), because `lean2js` links Lean anyway; `--dump-ir` prints the collected IR as text for debugging.

## Context / evidence

* The current backend (mono LCNF) has no ownership information, so every `Array.push/set` copies:
  100 000 pushes take ~55 s (`out/perf1.lean` experiment). Native Lean mutates in place when the
  array's reference count is 1.
* The `impure` LCNF phase / the final `Lean.IR` (λRC) has exactly what is needed: explicit `inc`/`dec`,
  borrowed (`@&`) parameters, `isShared`, `reset`/`reuse`, boxing. Verified in Lean 4.35.0:
  `Lean.IR.findEnvDecl env n` returns IR for local decls (`localFn`) and for imported ones (`List.foldl`,
  `Array.foldlMUnsafe`, `Std.HashMap.insert`), with `extern` decls for primitives (`Array.push`, `Nat.add`).
  The *impure LCNF* of imported modules is NOT stored (`impureExt` is a non-persistent env extension), so
  dependencies must come from `Lean.IR` (declMapExt); using IR for everything is simplest.

## Answer to "would the impure output let us keep mutations in JS?"

Yes, but only with exact reference counting emulated at runtime:

* `Array.push x v` may mutate iff `x` is exclusive (rc == 1). IR makes `inc`/`dec` explicit, so the
  generated JS keeps an `rc` field on arrays (and, to be exact, on all heap objects) and executes
  `inc`/`dec`/`isShared` faithfully. Over-counting is safe (just an extra copy); under-counting is unsafe.
* Pitfall: JS has no destructor hook, so when a container reaches rc 0 its children must be `dec`ed by
  the runtime (as `lean_free_object` does), otherwise arrays stored in structures (the `HashMap` bucket
  array, `StateT` state) look shared forever and every update copies — again O(n) per `insert`.
  Hence a *partial* emulation (arrays only) loses the main benefit; a full one (rc on every object, recursive
  `dec`) is needed. Expect a constant-factor slowdown (~2×) on non-array code.
* Primitives must follow the C ownership conventions (owned vs borrowed args; results that alias stored
  elements must be `inc`ed, e.g. `Array.get`, `ST.Ref.get`).
* Lower-level data model: ctor objects with scalar fields (`sset/sproj` byte offsets, `uset/uproj`),
  boxed vs unboxed scalars, `_boxed` wrappers, `USize`, tagged `box(n)` for nullary constructors — all emulated
  in JS (e.g. scalar area as properties keyed by offset).
* Alternative without IR (static last-use analysis on mono LCNF, plus "projections/pattern-bound/captured values
  are shared") is possible but loses wrapped-array cases the same way, and needs a hand-rolled ownership analysis
  that Lean already has.

## Recommendation

Adopt the IR (λRC) as the transpiler input with full RC emulation:

1. `lcnf-dump`-like command `ir-dump FILE.lean` → JSON of `Lean.IR.Decl`s of the file and all reachable
   imported decls (IR is small: ~12 `FnBody` and ~15 `Expr` constructors; see `Lean/Compiler/IR/Basic.lean`).
2. New generator `Lean2js/CodegenIR.lean` (keeps AST/mangling/tail-call/SCC machinery; join points and `case`
   map as today); runtime gets `rc`, `inc`, `dec` (recursive free), `isShared`, in-place array prims.
3. Keep the mono-LCNF backend as the reference/fallback until the IR backend passes all e2e tests; then decide
   whether to delete it.

Estimated effort: the runtime and codegen are each comparable to what exists now; the e2e corpus (27 programs)
carries over unchanged.

## Alternatives

* Keep copy-on-write (correct, quadratic for array-heavy code; fine for small programs).
* Static ownership analysis on mono LCNF (see js-012).
