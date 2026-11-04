# IR backend (default): Lean IR with reference counting → JavaScript

Decision: [js-013](../tickets/js-013-question-ir-backend.md). `lake exe lean2js FILE.lean [--run] [--out F.js]` is the only backend. The older mono-LCNF backend
(JSON input, copy-on-write arrays) was removed on 2026-11-04 ([js-014](../tickets/js-014-cleanup-gaps.md)); it is in the jj history
(`jj log -r 'description(substring:"IR backend")'`, commits before the cleanup) together with its design doc `js-transpiler.md`.

Why: only the final IR (λRC) carries ownership information (`inc`/`dec`, borrowed params, `isShared`,
`reset`/`reuse`). With it, `Array.push` etc. mutate in place exactly when native Lean would: 100 000 pushes went from
55 s (copy on every update) to 0.14 s; 1M pushes + 200k `HashMap` inserts + sorting 100k elements run in ~1.3 s.

## Pipeline

    File.lean --Lean.Elab.runFrontend--> Environment --Lean.IR.findEnvDecl (closure from `main`)--> Lean.IR.Decl*
              --Lean2js.CodegenIR--> File.js (+ runtime/lean_rt.js)

No JSON in between: `lean2js` links Lean and consumes `Lean.IR.Decl` directly (`Lean2js/CodegenIR.lean`). `--dump-ir` prints
the collected IR as text. Collection (`CodegenIR.collect`) starts at `main` (or all local declarations if there is none)
plus `IO.Error.toString` (for uncaught-exception messages) and follows `fap`/`pap` references; imported modules
provide IR for everything, including `_boxed` wrappers. Externs whose real implementation is Lean code tagged
`@[export sym]` (e.g. `String.Internal.posOf`) are wired to that implementation.

## Object model (runtime/lean_rt.js)

| IR value | JS |
|---|---|
| `Nat`, `Int` (tobj), `UInt64`, `USize` | `BigInt` (boxing/unboxing is the identity) |
| `UInt8/16/32`, `Char`, `Bool`/enum (`u8`) | `number` |
| `Float` | `number` |
| nullary constructor / `box(n)` of small scalar | the number `cidx` |
| other constructor | `{t: cidx, rc, n: #object fields, a0…, u<i>, s<i>_<offset>}` (`proj`→`aI`, `uproj`→`uI`, `sproj n off`→`s<n>_<off>`) |
| `String` | JS string (no refcount) |
| `Array`, `ByteArray`, `FloatArray` | JS `Array` / typed arrays with own property `rc` |
| closure | `Clo{fn, arity, args, rc}`; `pap` creates, `rt.ap` applies with the same ownership rules as `lean_apply_n` |
| `Thunk`, `Task`, `ST.Ref` | classes with `rc` (tasks run eagerly) |
| IO results (`EIO`) | `EST.Out.ok/error` = `{t:0/1, rc, n:1, a0}`; `BaseIO`/`ST` primitives return raw values |
| erased / state token | `0` |

Reference counts: `rc` = 1 exclusive, >1 shared, 0 persistent (global constants, marked by `rt.persist` when first
computed; never mutated). `inc`/`dec` follow the IR exactly; when an object's count reaches 0 its children are
released iteratively (like `lean_free_object`), which is what keeps arrays stored in structures (e.g. `HashMap`
buckets) exclusive. Over-counting is always safe (extra copy); primitives that return an element aliasing stored data
must `inc` it (`lean_array_fget`, `lean_st_ref_get`, `lean_thunk_get_own`, …) and primitives consuming owned
arguments must `dec` them when not storing them. Primitives never receive erased/`void` arguments (as in the C ABI).

## Code generation

* `fdecl f` ↦ `function l_f(x1, …)`; zero-parameter declarations are memoized and persisted.
* `vdecl` ↦ `const xN = …`; `case` ↦ `switch` on the scalar or on `typeof x === "number" ? x : x.t`; `jdecl`/`jmp` ↦
  labeled block + assignments + `break` (so tail calls inside join points still work).
* `reset`/`reuse` ↦ `rt.reset(x, n)` and an inline allocate-or-reuse; `del` is a no-op; `isShared` ↦ `rt.isShared`.
* Tail calls: saturated self tail calls ↦ `while (true)` loops; strongly connected groups of mutually tail-calling
  functions ↦ one dispatch loop. Non-tail recursion uses the JS stack; Node runs
  the program in a worker with a 512 MB stack.
* Extern wrappers `l_f(a0, …)` call `rt.prims["lean_symbol"]` without erased/void arguments.

## Tests

`tests/e2e/run.sh [NAME…]` runs the differential tests `aliasing.lean`
checks that copies stay persistent (arrays shared through values, closures, thunks, refs, constants, structure updates);
`bigperf.lean` is a performance smoke test. `node tests/e2e/missing.mjs [FILE.js…]` lists primitives used by generated code that the
runtime lacks.
