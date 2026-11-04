# Follow-ups after the IR backend

Parent: [js-001-transpiler-epic](js-001-transpiler-epic.md)

Status: **mostly done** (2026-11-05). Done: mono backend removed (1), missing primitives (2; the rest is unsupported on purpose), missing-primitive listing via `node tests/e2e/missing.mjs FILE.js` (3), ByteArray amortized push (5), cancellation. Optional and not planned unless needed: `--bundle`/source maps (4), `Task` panic message format (6), `inc`/`dec` profiling (7).

Fresh-agent notes: read docs/design/js-transpiler-ir.md first. Runtime: `runtime/lean_rt.js` (IR backend, default),
Generator: `Lean2js/CodegenIR.lean` (+ `JsUtil.lean`). The mono backend no longer exists (item 1).

1. **DONE 2026-11-04 — mono backend removed** (`Codegen.lean`, `Ast.lean`, `runtime/lean_runtime.js`, `--backend`, JSON input, `BACKEND=` in run.sh; shared helpers moved to `Lean2js/JsUtil.lean`). `lcnf-dump` (incl. `--with-deps`) is kept as a standalone tool. Original text: **Retire or share the mono backend.** Both runtimes duplicate Nat/Int/UInt/Float/String/hash primitives
   (copied verbatim). Either delete the mono backend + `lean_runtime.js` + JSON input path (and `lcnf-dump --with-deps`
   consumers), or split the shared primitives into `runtime/prims_core.js`. `lcnf-dump` itself stays useful.
2. **Missing primitives** (time, getenv, exit, random bytes, pid already done in `lean_rt.js`) (fail only when called, with "missing primitive 'x'"): file system (`IO.FS.*`, `Handle`),
   `IO.rand` (needs `[init]` declarations such as `IO.stdGenRef`, which the lazy-constant scheme does not run — design needed), `Mutex`/`Condvar`, `IO.sleep`, remaining Float math/`Float32`, `Int` bit ops,
   `String` ops not exercised yet. Use `node tests/e2e/missing.mjs` after transpiling a new program.
3. **Transpile-time check of missing primitives** (`--check`): list externs the runtime lacks instead of failing at run time.
4. **`--bundle`**: single self-contained JS file (inline runtime), source maps.
5. **ByteArray growth**: `ByteArray.push` allocates a new typed array each time (O(n)); use capacity doubling.
6. **Uncaught exception for `Task` panics**, `panic!` message format identical to native (stderr only; stdout/exit code already match).
7. **Performance**: profile `rt.inc/dec` overhead; consider `n`-field specialization in `free`; avoid `Array.isArray` checks.
