# JS runtime: IO, state and concurrency primitives

Parent: [js-001-transpiler-epic](js-001-transpiler-epic.md)

Status: open. Depends on js-004; can start before js-007 is done.

## Goal

Runtime support for effectful primitives in `runtime/lean_runtime.js` (or `lean_io.js`):

* `IO` representation: in mono LCNF, `IO α` is a function taking a world token and returning `EStateM.Result`
  objects (`ok val world` / `error err world`) — implement as ordinary ctor objects so the compiled Lean
  `bind`/`pure` code just works; don't add a separate monad.
* Streams: `IO.getStdout/getStderr/getStdin`, `IO.FS.Stream` ctor objects with `putStr/flush/getLine/read/write/isTty`.
  Node: `process.stdout.write` (sync via `fs.writeSync`); browser: configurable sink callback (`runtime.setStdout(fn)`).
* `IO.Ref` / `ST.Ref`: `mkRef get set swap modify take`; `IO.mkRef`.
* Errors: `IO.userError`, `IO.Error` ctors, `throw`/`try-catch` come from Lean code (EStateM), runtime only
  constructs error values (`IO.Error.userError` etc.).
* Time/random/env: `IO.monoMsNow`, `IO.monoNanosNow`, `IO.getRandomBytes`, `IO.getEnv`, `IO.Process.exit`, `IO.appPath`.
* Files (Node only; browser: in-memory FS or throw): `IO.FS.readFile/writeFile/Handle.*`.
* `Thunk` (`mk get pure map`), `Task` (synchronous eager: `Task.spawn` runs immediately; `IO.asTask`, `IO.wait`,
  `IO.mapTask`; document that true parallelism is out of scope), `IO.CancelToken`, `Mutex`/`Condvar` stubs.
* `main` entry: `runMain(mainFn, args)` building `List String` args, running with world token, mapping
  `IO.Error` to message on stderr and exit code (see Lean's `lean_io_result_show_error`).

## Acceptance

Tests in `tests/js/io.test.mjs`: println to captured stdout, refs, exceptions (`throw`/`try catch`),
exit codes, `Task.spawn`, `IO.FS` round trip under Node.
