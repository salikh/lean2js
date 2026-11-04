# Module initializers ([init] / builtin_initialize)

Parent: [self-001](self-001-compiler-to-js-epic.md) | related: js-014 item 2
Status: open

Native Lean runs `initialize_<Module>(builtin, w)` for each module in import order: it evaluates
closed terms and runs `[init]`/`[builtin_init]` decls (registering parsers, attributes, env extensions,
options, `IO.stdGenRef`, ...). Order matters (e.g. `registerBuiltinAttribute` before use, env extension
indices are assigned by registration order and must match the order used when .oleans were produced for
persistent extensions).

Tasks:
1. In `CodegenIR`, emit per-module `initialize_M(builtin)` functions (data in IR: `Decl.getInitFn?`/`isIOUnitInitFn`/
   `isIOUnitBuiltinInitFn` via `Lean.getInitFnNameFor?`, `regularInitAttr`, `builtinInitAttr`); needs module of
   each decl (`env.getModuleIdxFor?`) and import order (`env.header.moduleNames`).
2. Replace lazy memoization for decls that have an init fn (value = result of running the IO init action).
3. Test: program using `IO.rand`, then `import Lean` + `Lean.Parser` builtin table size > 0.
