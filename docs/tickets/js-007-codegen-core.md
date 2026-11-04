# Transpiler core: LCNF JSON → JavaScript

Parent: [js-001-transpiler-epic](js-001-transpiler-epic.md)

Status: **done** (2026-11-04); see docs/design/js-transpiler.md. Not covered: impure-phase input, `fun` closures with self-loops (by design), source maps.

## Goal

A Lean module `Lean2js/Codegen.lean` (+ exe `lean2js`, see js-010) that reads the JSON schema in
[docs/design/lcnf-json.md](../design/lcnf-json.md) (parse with `Lean.Json`/`FromJson` into a small
own AST — don't depend on `Lean.Compiler.LCNF` types) and emits an ES module.

## Mapping (mono phase; revise per js-003/004/005)

* Decl → `export function f(p1, …, pn) {…}`; names mangled to valid unique JS identifiers
  (`Foo.bar._lambda_1` → `Foo$bar$_lambda_1` with escaping of `$`, `«»`, non-ASCII). Zero-parameter decls
  are constants: evaluate lazily once (`let v; function c(){return v ??= init}`) to respect Lean's
  initialization semantics (closed terms / `_closed_N`).
* `let x := lit` → const/BigInt/string literal; `erased` → runtime `erased`.
* `let x := const f args` → direct call `f(args)` when saturated; `pap` through runtime `pap`
  when under-applied; over-application → call then apply result. Constructor names → object construction
  using metadata from js-006; extern primitives → runtime functions (`rt.Nat_add`).
* `let x := app g args` → `rt.apply(g, args)` (closures: arity-tagged JS functions).
* `proj` → field access. `cases` → `switch (x.t)` (enum types: on the number; `Nat`/`Int`/`Bool`/`String`/`Array`
  special-cased); `default` alt → `default:`. `unreach` → `throw`.
* `fun` (local lambda) → JS closure (arrow function); `jp`/`jmp` → labeled block with `continue`/assignment
  when all jumps are in tail position, otherwise local function call.
* Tail position `return` → `return`. All `let`s become `const` in nested blocks; erased-typed params keep
  their position (ABI = same params as LCNF decl).
* Self tail calls → loops (js-005).
* Dead decls: emit only decls reachable from the entry points (`main`, exported ones) — tree-shake.

## Acceptance

Hand-written test programs from `tests/lcnf/*.lean` transpile (with js-006 deps or with a stubbed
runtime) to JS that loads in Node without syntax errors and computes the expected results for pure
functions (`fact 10`, `Tree.sum`, `useTwice`). Add JS golden tests under `tests/js/`.
Document in docs/design/js-transpiler.md.
