# demo.sh and test.sh

Status: **done** (2026-11-04)

Side request from the user: a walkthrough script and one entry point for all tests.

* `./demo.sh [demo/NAME.lean …]` — for each of the five small programs in `demo/` (hello, fib, squares, wordcount, primes; all < 10 lines):
  prints the Lean source, runs it with `lean --run`, compiles it to a native binary (`lean -c` then `leanc -O3`, two timed steps) and runs that,
  then compiles it with `lake exe lean2js … --run --out out/demo/NAME.js` and runs the result with `node`. Every step prints the command, its output and the elapsed time.
* `./test.sh [--quick] [--update]` — runs (1) the `lcnf-dump` golden tests (`tests/run.sh`, kept as the implementation; `--update` regenerates
  the goldens), (2) the demo programs as differential tests (`lean --run` vs native binary vs `node`, stdout and exit code), (3) all end-to-end differential
  tests `tests/e2e/run.sh`. `--quick` skips the slow e2e tests that transpile the whole of `Lean` (those with a `.flags` file: `mvars`, `import`).
  Exit status 0 iff everything passes.
* `tests/e2e/run.sh` conventions (unchanged, documented here): `NAME.args` command line arguments, `NAME.stdin` stdin, `NAME.flags` extra
  `lean2js` options, `NAME.expected` checked-in expected output for programs `lean --run` cannot run (e.g. `initialize` in the same module).
