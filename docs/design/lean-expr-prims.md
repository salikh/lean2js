# Native Expr/Level/Name primitives in JS (self-004)

File: `runtime/lean_expr.js` (installed into `prims` by `runtime/lean_rt.js`). Differential test: `tests/e2e/expr.lean`.

* **Layouts.** Every `Expr` constructor carries a cached `data : UInt64` as scalar field `s<n>_0` (n = number of object fields);
  lam/forallE keep binder info in `s3_8`, letE the `nondep` flag in `s4_8`. `Level` likewise (zero is the number 0; its data is a
  compiled constant). `Name.str/num` keep their hash in `s2_0`. Single-field structures (`FVarId`, `MVarId`, `LMVarId`) are unboxed
  to the `Name`. Bit layouts of the data words are in the file header.
* **Constructing expressions.** The JS code never builds `Expr` objects itself: it calls the compiled Lean constructors that the
  native runtime also uses, via `rt.exports["lean_expr_mk_app"]` etc. `CodegenIR` makes every `@[export lean_expr_mk_*]`,
  `lean_level_mk_*`, `lean_name_mk_*` function a root and registers it (`runtimeExportPrefixes`), so the cached data is computed by
  Lean code and is bit-identical to native.
* **Ownership.** All primitives take arguments borrowed (`@&`) and return owned results; unchanged subterms are returned with `inc`.
* **Rewriting.** `replace` is the kernel's `replace_rec_fn` (offset-aware, cache for shared subterms keyed by (object, offset)),
  used by instantiate (all variants), abstract, lift/lower loose bvars, and `Expr.replace`. `find`/`replace` call the Lean closure
  with `ap`.
* **Ordering.** `lean_expr_lt`/`quick_lt` follow the C++ `is_lt` (kind, [hash], structure; names by `Name.cmp`-like order).
* **Known approximations.** `lean_expr_dbg_to_string` returns `<expr>` (so `toString e` is not the native text — use `repr`/`ppExpr`); `abstract` also matches
  metavariables by name.
* **instantiateMVars** (`makeInstantiator`): port of `instantiate_mvars.cpp` — assignments are read/updated through the compiled Lean
  `@[export lean_get_mvar_assignment / lean_assign_mvar / lean_get_delayed_mvar_assignment / …]` functions (registered in `rt.exports`);
  head-beta with `useZeta`, delayed assignments, and the simplifying `mk_max`/`mk_imax` of level.cpp.
* **Bug fixed on the way:** `lean_uint64_mix_hash` had a second multiplication where `lean.h` has `k ^= m`, so every derived hash
  (`Hashable` instances, `Name.hash`, `Expr.hash`) differed from native. The string hash itself was already right.
