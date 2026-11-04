# Module initializers (`[init]`, `builtin_initialize`)

Native Lean runs `initialize_<Module>(builtin, w)` for every module in import order at startup: it evaluates closed constants
and runs `[init]`/`[builtin_init]` actions (registering parsers, attributes, options, environment extensions, `IO.stdGenRef`, …).
The JS backend (ticket [self-003](../tickets/self-003-module-initializers.md)) reproduces this as follows.

* **Constants with an init function** (`initialize x : T ← act`, `builtin_initialize …`, and Init's `IO.stdGenRef`): the IR body of the
  constant is `unreachable`; the generated getter instead evaluates `rt.runInit(initFn, name)` once (lazy, memoized, persistent).
  So references from reachable code initialize on demand, in dependency order — `IO.rand` works. `IO.initializing` is true while an
  initializer runs (needed by `registerOption`, `registerBuiltinAttribute`, …).
* **IO-unit initializers** (`initialize IO.println …`, `_regBuiltin…` registrations): run eagerly at startup by `initialize()`,
  registered with `rt.setInit` and executed by `rt.runMain` before `main`. By default only those of the main module; with
  `lean2js --init-all` those of **all imported modules** (what a native executable does) — the whole of `Lean` is then
  reachable (≈ 5000 init decls; the generated file is ~330 MB for `import Lean`, see [self-008](../tickets/self-008-bundle-startup-size.md)).
* **Order.** Imported oleans do not record declaration order, so `CodegenIR.initOrder` sorts by (module index in
  `env.header.moduleNames`, explicit initializers by the `_hyg` macro-scope counter of the init function's name, then the generated
  `_regBuiltin` registrations by name). A failing step is retried after the other steps (`rt.runInitSteps`), which absorbs
  remaining ordering mistakes (e.g. "unknown parser category"). Source order within a module is not available; if order-sensitive
  behaviour shows up (parser alternatives, trace class order), look here first.
* **Errors.** An init error aborts like in a native executable: `uncaught exception: …`, exit code 1.
* **Tests.** `tests/e2e/init.lean` (checked-in `init.expected`, since `lean --run` refuses `initialize` in the same module),
  `tests/e2e/mvars.lean` (`mvars.flags` = `--init-all`; runs `MetaM` and `instantiateMVars` in JS).
