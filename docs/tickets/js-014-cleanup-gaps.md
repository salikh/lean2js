# Follow-ups after the IR backend

Parent: [js-001-transpiler-epic](js-001-transpiler-epic.md)

Status: open

Fresh-agent notes: read docs/design/js-transpiler-ir.md first. Runtime: `runtime/lean_rt.js` (IR backend, default),
`runtime/lean_runtime.js` (mono backend). Generator: `Lean2js/CodegenIR.lean` (IR), `Lean2js/Codegen.lean` (mono).

1. **Retire or share the mono backend.** Both runtimes duplicate Nat/Int/UInt/Float/String/hash primitives
   (copied verbatim). Either delete the mono backend + `lean_runtime.js` + JSON input path (and `lcnf-dump --with-deps`
   consumers), or split the shared primitives into `runtime/prims_core.js`. `lcnf-dump` itself stays useful.
2. **Missing primitives** (fail only when called, with "missing primitive 'x'"): file system (`IO.FS.*`, `Handle`),
   `IO.getRandomBytes`/`IO.rand` seeds, time (`IO.monoMsNow`, `IO.monoNanosNow`), env/args/process (`IO.Process.exit`,
   `IO.getEnv`, `IO.appPath`), `Mutex`/`Condvar`, `IO.sleep`, remaining Float math/`Float32`, `Int` bit ops,
   `String` ops not exercised yet. Use `node tests/e2e/missing.mjs` after transpiling a new program.
3. **Transpile-time check of missing primitives** (`--check`): list externs the runtime lacks instead of failing at run time.
4. **`--bundle`**: single self-contained JS file (inline runtime), source maps.
5. **ByteArray growth**: `ByteArray.push` allocates a new typed array each time (O(n)); use capacity doubling.
6. **Uncaught exception for `Task` panics**, `panic!` message format identical to native (stderr only; stdout/exit code already match).
7. **Performance**: profile `rt.inc/dec` overhead; consider `n`-field specialization in `free`; avoid `Array.isArray` checks.
