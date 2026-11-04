# LCNF → JavaScript transpiler (mono-LCNF backend)

> The default backend is now the reference-counted IR backend, see [js-transpiler-ir.md](js-transpiler-ir.md).
> This document describes the mono-LCNF backend (`--backend mono`, JSON input), kept as a reference.

Epic: [js-001](../tickets/js-001-transpiler-epic.md). Pipeline:

    File.lean --elaborate--> mono LCNF (+ all reachable deps) --Lean2js.Codegen--> File.js  (+ runtime/lean_runtime.js)

`lake exe lean2js FILE.lean|FILE.json [--out F.js] [--runtime PATH] [--entry NAME]... [--run] [--all]`

* `FILE.lean`: elaborated in-process (`Lean2js.LcnfDump.elaborate`, same as `lcnf-dump --with-deps`).
* `FILE.json`: output of `lcnf-dump FILE.lean --with-deps` (see [lcnf-json.md](lcnf-json.md)).
* `--run`: append `rt.runMain(main, arity)` so `node F.js [args]` runs the program.
* Only declarations reachable from the entry points (default `main`, else all declarations of the file)
  are emitted; `--all` disables tree shaking.

Source layout: `Lean2js/Ast.lean` (JSON → AST), `Lean2js/Codegen.lean` (generator), `Main.lean` (CLI),
`runtime/lean_runtime.js` (runtime). The transpiler is written in Lean 4 ([js-002](../tickets/js-002-question-implementation-language.md)).

## Input phase and dependencies

The generator consumes the `mono` phase ([js-003](../tickets/js-003-question-input-phase.md)). Imported
`Init`/`Std` functions have mono bodies available, so the whole program is compiled from LCNF; only
`@[extern]` primitives are implemented by hand in the runtime. Some externs (e.g. `String.Internal.posOf`
↦ `lean_string_posof`) are stubs whose real implementation is Lean code tagged `@[export lean_string_posof]`;
the dump records `"export"` for such decls and the generator wires the extern to the Lean implementation.

## Value representation ([js-004](../tickets/js-004-question-value-representation.md))

| Lean | JS |
|---|---|
| `Nat`, `Int`, `UInt64`, `USize` | `BigInt` |
| `UInt8/16/32`, `Char` | `number` |
| `Float` | `number` |
| `Bool`, enumeration-like inductives (all constructors without fields) | `number` = constructor index |
| other constructors | `{t: idx, a0: …, a1: …}` (type parameters are not fields; erased fields keep their position) |
| erased values, `Unit`, IO world token | `0` |
| `String` | JS string; byte positions (`String.Pos`) are UTF-8 offsets, converted by the runtime |
| `Array` | JS array, copied on every update |
| `ByteArray` | `Uint8Array` |
| closures | `rt.Clo{f, arity, args}`, applied with `rt.ap`; partial application with `rt.pap` |
| `Thunk`/`Task`/`IO.Ref` | runtime classes; tasks run eagerly and synchronously |

`Nat.zero/succ` and `Int.ofNat/negSucc` constructors and `cases` on them are compiled to `BigInt` arithmetic.
Trivial structures (e.g. `Fin`, `Subtype`) are already unwrapped by Lean's `toMono`.

## Code generation

* `f` ↦ `function l_f(params)`; names are mangled by `Codegen.mangle` (`.` ↦ `$`). Zero-parameter decls
  (`_closed_N`, constants) are memoized. Extern decls become wrappers `l_f(a0,…)` calling
  `rt.prims["lean_symbol"]` without the erased (`lcErased`) arguments, as the C ABI does.
  A missing primitive only fails when called (`rt.missing`).
* `let x := const f args`: saturated → direct call; fewer args → `rt.pap`; more → call then `rt.ap`.
* `cases` ↦ `switch (x.t)` (enum types: `switch (x)`; `Nat`/`Int`: if-chain). Fields are bound to `const`s.
* `jp`/`jmp` ↦ labeled block + variables for the jp parameters (`jmp` assigns and `break`s), so tail calls inside
  join points can still use `continue`.
* Tail calls ([js-005](../tickets/js-005-question-tail-calls.md)): saturated self tail calls become
  `_loop: while (true)`; groups of mutually tail-recursive functions (strongly connected components of the
  tail-call graph) are merged into one dispatch loop `g_<first>(w, a0, …)` with the original functions as
  wrappers. Non-tail recursion uses the JS stack; under Node `rt.runMain` runs the program in a worker thread
  with a 512 MB stack (set `LEAN2JS_NO_WORKER=1` to disable). Closures built by `fun` do not get loops.

## Runtime (`runtime/lean_runtime.js`)

ES module, no dependencies, Node and browser. Primitives are `rt.prims.<c symbol>` named as in `lean.h`.
Implemented: Nat/Int, UInt8…64/USize (+conversions), Float, String, Array, ST.Ref, Thunk/Task, stdout/stderr/stdin,
hashing (`lean_string_hash`, `lean_uint64_mix_hash`, MurmurHash64A — HashMap iteration order matches native),
`runMain` (exit codes, uncaught exception message via the program's own `IO.Error.toString`).
Browser hooks: `setStdout`, `setStderr`, `setStdinLine`.

Not implemented yet: file system and process APIs, `IO.getRandomBytes`/time, `ByteArray`/`FloatArray`
primitives, real concurrency, destructive array updates (see follow-up ticket js-012).

## Tests

`tests/e2e/run.sh [NAME…]` — differential tests: each `tests/e2e/NAME.lean` is run with `lean --run` and as
transpiled JS under Node; stdout and exit code must be equal (`NAME.stdin`/`NAME.args` optional).
`node tests/e2e/missing.mjs` lists primitives referenced by generated code but absent from the runtime.
