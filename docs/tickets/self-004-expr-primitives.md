# Expr/Level/Name native primitives in JS

Parent: [self-001](self-001-compiler-to-js-epic.md)
Status: **mostly done** (2026-11-04) — see [design/lean-expr-prims.md](../design/lean-expr-prims.md). `instantiate_expr_mvars`/`instantiate_level_mvars` are ported (`lean_expr.js`, via `rt.exports` mctx callbacks) but their test `tests/e2e/mvars.lean` needs module initializers (self-003) to run in JS. Open: exact `quick_lt`, `dbg_to_string`.

Implement in `runtime/lean_rt.js` (or a new `runtime/lean_expr.js`) the C++ helpers: `lean_expr_instantiate{,1,_rev,_range,_rev_range}`,
`lean_expr_abstract{,_range}`, `lean_expr_lift/lower_loose_bvars`, `lean_expr_has_loose_bvar`, `lean_expr_quick_lt`,
`lean_expr_eqv/equal`, `lean_expr_data`/`mk_data`/`mk_app_data`, `lean_level_eq/mk_data`, `lean_name_eq`,
`lean_find_expr`, `lean_replace_expr`, `lean_instantiate_expr_mvars`, `lean_instantiate_level_mvars`.
Semantics in Lean sources: `src/lean/Lean/Expr.lean` + C++ `src/kernel/instantiate.cpp`, `abstract.cpp`,
`src/library/expr_lt.cpp` (not shipped; port from memory/docs, test differentially).
Alternative: write them in Lean (as `implemented_by` replacements compiled by our own pipeline) — easier
to verify against native. Test by running both the native and JS versions on Exprs produced by `lean --run`.
