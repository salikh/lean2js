# The Lean frontend running as JavaScript (self-009)

`selfhost/Elab.lean` is an ordinary Lean program: it reads Lean source from stdin, runs the Lean parser/elaborator/compiler on it and prints
the messages (`#check`, `#eval`, errors). `lake exe lean2js selfhost/Elab.lean --init-all --eval-all --run --out out/selfhost.js`
turns it — together with the whole of `Lean`, `Std` and `Init` — into JavaScript; then

    LEAN_SYSROOT=$(lean --print-prefix) node out/selfhost.js < selfhost/sample2.lean

elaborates the input with **no native Lean code** except the Node runtime (`runtime/*.js`). The output is identical to
`lean --run selfhost/Elab.lean` (differential test `tests/e2e/selfhost.lean`). Covered by the test: pattern-matching definitions,
structures with `deriving Repr`, inductive types (kernel: vendored lean4lean), `simp`, `decide`, `#check`, `#eval`.

## How the pieces fit

| Native Lean component | In the JS-hosted compiler |
|---|---|
| runtime (`lean.h`, objects, `Nat`, strings, IO) | `runtime/lean_rt.js`, `lean_num.js`, `lean_fs.js`, `lean_sys.js` |
| `Expr`/`Level`/`instantiateMVars` (C++) | `runtime/lean_expr.js` ([lean-expr-prims.md](lean-expr-prims.md)) |
| kernel `add_decl`, inductive types, `whnf`/`isDefEq` | `Lean2js/Kernel.lean` → vendored lean4lean (type checking on by default) |
| `casesOn` construction (C++) | `Lean2js/KernelCasesOn.lean` |
| module initialization | `--init-all` ([module-initializers.md](module-initializers.md)) |
| `.olean` mmap | `runtime/lean_olean.js` ([olean-loader.md](olean-loader.md)) |
| threads/tasks | cooperative scheduler in `lean_rt.js` ([tasks.md](tasks.md)) |
| `evalConst` of imported declarations (macros, `syntax` descriptors) | `--eval-all`: every IR declaration is emitted; the program registers `rt.setLookup(id => eval(id))` (direct `eval` in the module scope) and `rt.nameId` maps a `Name` to the mangled identifier, the same encoding as `JsUtil.nameId` |
| `evalConst` of *new* declarations (`#eval`) | `CodegenIR.genChunk` (exported as `lean2js_gen_chunk`, compiled into the program): IR of the current module's declarations → JS text → `eval`; regenerated for each `evalConst` because names like `_eval` are reused |
| interpreter / native code for `#eval` | not needed: the IR → JS generator is the evaluator |

Identifiers: `nameId` encodes a `Name` by components (`l_` + components joined by `$$`, special characters `$u<hex>_`, numeric components
`$n<k>`), instead of `Name.toString`, which is ambiguous.

## In the browser (`web/selfhost/`)

`build.sh` transpiles `selfhost/Elab.lean` without `--run` (`elab.js`), copies the runtime and the library files of `Init` (`lib/…`, listed in `files.json`). `driver.js` fills the
runtime's in-memory file system (`rt.vfs`, paths `/lean/lib/lean/…`; a 12-connection fetch pool), sets `LEAN2JS_ENV = {LEAN_SYSROOT: "/lean"}`, hooks stdin/stdout and calls `rt.runMain`.
The default is the **main thread**: V8 gives Chrome's workers ~570 KB-equivalent of stack (measured: a trivial recursion reaches 4.5 k frames in a worker, 12.4 k on the main thread, 7.8 k in Node) while
the compiler needs 500–700 KB even for small inputs (`Simp.simp` overflowed in a worker); `?worker=1` runs it in a worker anyway. Memory ≈ 3 GB. The page freezes during elaboration.
`test-browser.sh` runs the default program in headless Chrome through a local server and compares the output.

## Limits / known gaps

* Size and startup: 452 MB (`--init-all --eval-all`), 174 MB with `--small`; a complete small run takes ~14 s and ~3 GB of memory ([self-008](../tickets/self-008-bundle-startup-size.md)). Build with `--init-all --eval-all --small` for everyday use.
* The kernel is lean4lean (`Lean2js/Kernel.lean`): it type checks declarations by default (`LEAN2JS_KERNEL_CHECK=0` to skip), `Kernel.whnf/isDefEq/check` work; gap: `Primitive.checkDef` vs. Lean 4.35's `Nat.div` (only matters when compiling `Init.Prelude` itself).
* Unresolved promises are treated as dropped when nothing else can run (heuristic, see tasks.md).
* `import` of anything but `Init`/`Std`/`Lean` oleans under `$LEAN_SYSROOT/lib/lean` was not tested; evaluation of declarations from other modules needs their code (`--eval-all` only covers what the program was built with).
