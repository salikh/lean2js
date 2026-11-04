# Question: how to get a kernel in JS?

Parent: [self-001](self-001-compiler-to-js-epic.md)
Status: **decided 2026-11-04** — follow the recommendation below (A, then C, D as fallback)

The Lean 4.35 kernel (`lean_add_decl`, `lean_kernel_whnf`, `lean_kernel_is_def_eq`, `lean_kernel_check`) is C++;
it also generates recursors / casesOn-derived inductive data. The elaborator calls `addDecl` for every definition
and inductive, so *something* must implement at least the declaration-adding part.

Options:
A. **Trusting kernel (recommended first)**: JS `lean_add_decl` that adds the declaration to the environment
   without type checking (like `addDeclWithoutChecking`), plus a JS/Lean implementation of inductive-declaration
   processing (recursor generation, `rec` rules, nested/mutual inductives) since the elaborator depends on the
   generated constants. Quot is trivial. `whnf`/`isDefEq` of the kernel are used only by `decide`/`Meta.unfoldDefinition?`-style
   fast paths (`Kernel.whnf`, `ofReduceBool`) — implement lazily/missing.
B. Full kernel port (type checker in Lean or JS): large (~10k lines C++), later, for soundness.
C. Reuse a Lean-in-Lean kernel (e.g. lean4lean) transpiled by our tool — attractive since our pipeline compiles Lean; needs checking it targets 4.35.

D. **Compile the C++ kernel to wasm (emscripten)** (suggested by user 2026-11-04). The kernel works on `lean_object*` in wasm linear
   memory, while our JS backend uses JS objects, so every `addDecl` would need to marshal the declaration and (lazily) the
   environment constants across the boundary and convert results back (recursors, new Environment). Needs the C runtime (`lean.h`,
   object/alloc/mpz) built for wasm too. Feasible, but the marshalling layer is the real work; and the full C++ sources of 4.35 must be vendored.
   Related prior art found (verify before relying on it): xeus-lean (Verilean/xeus-lean) compiles the *whole* Lean runtime + Init to wasm
   with emscripten Memory64 (JupyterLite, no server) — i.e. the alternative where the compiler is NOT transpiled by us; `lasm`
   (Millillion/lasm) AOT-compiles Lean 4.35 programs to wasm; lean2wasm (T-Brick). Old Zulip threads mention an emscripten server build of Lean.
   lean4lean (digama0/lean4lean, kim-em mirror): complete typechecker in Lean, ~50% slower than C++, only `reduceBool` unsupported — transpilable by our pipeline, so one object representation.

Recommendation: A now (milestone self-009), then C (lean4lean) for checking; keep D as fallback if C is too slow/unbuildable. Action: investigate lean4lean version compatibility with 4.35 and xeus-lean's build recipe.

## Progress and open question (2026-11-04)

**Done (step A, non-inductive):** `Lean2js/Kernel.lean` — own trusting implementation of `lean_add_decl`, `lean_add_decl_without_checking`,
`lean_elab_add_decl`, `lean_elab_add_decl_without_checking` for axioms, definitions, theorems, opaques and mutual definitions (no type checking;
`alreadyDeclared` is reported). It is exported under the C++ symbols, so `lean2js` resolves the kernel `extern`s to it when a program imports the
module (`import Lean2js.Kernel`; do not link it into the `lean2js` exe). `CodegenIR.genExternWrapper` now adapts ownership between `@&` extern
parameters and the (necessarily owned) parameters of `@[export]` implementations. Test: `tests/e2e/kernel.lean` (real C++ kernel natively vs. this module in JS).

**Open (needs a human decision):** inductive types (`inductDecl`: recursors, `numNested`, large elimination) and `lean_mk_cases_on`. Options:

1. **(Recommended) Vendor the core of lean4lean** (https://github.com/digama0/lean4lean, Apache-2.0): 17 files / ~3.6k lines (`Lean4Lean/{Declaration,
   Environment,Environment/Basic,EquivManager,Expr,ForEachExprV,FuelConfig,Inductive/Add,Inductive/Reduce,Instantiate,Level,List,LocalContext,
   Primitive,PtrEq,Quot,TypeChecker}.lean`) into `vendor/lean4lean/` and add `batteries` (tag v4.35.0, used for `UnionFind`/`open private`) as a Lake
   dependency. Its `addDecl env decl (check := false)` handles every declaration kind including inductives (the same code that the Lean team's
   `leanchecker`/`bin/lean4lean` ecosystem uses; the toolchain ships a `lean4lean` binary but not the library). Then `Lean2js/Kernel.lean` delegates to it,
   and a full type-checking mode comes for free (`check := true`). `mk_cases_on` still has to be written (small, in Lean).
   *I was about to do this when the tool permission check blocked fetching/vendoring third-party code and adding a git dependency, so nothing was changed.*
2. Write the inductive-type processing myself in Lean from the kernel specification (recursor generation, nested inductives, elimination-level rules).
   Large (the C++ is ~1500 lines; its sources are not shipped in the toolchain), and without a type inferer for "is this field a proof".
3. Do not support user-defined inductive types in the JS-hosted compiler for now (structures, `inductive`, `deriving` fail); enough for the
   `def x := 1` milestone (self-009) but not for realistic programs.

Please answer: vendor lean4lean + Batteries (1)? If yes, say so explicitly (and I will fetch the pinned commit recorded in `vendor/lean4lean/UPSTREAM_COMMIT`).

## Decision and result (2026-11-04, later)

The user approved option 1 (vendor lean4lean + Batteries). Done: `vendor/lean4lean` (17 files, upstream commit in `UPSTREAM_COMMIT`, Apache-2.0),
`batteries` v4.35.0 as a Lake dependency, `lean-toolchain` pinned to `leanprover/lean4:v4.35.0`. Local patches (marked `-- lean2js:`):
`Environment/Basic.lean` (dropped `empty`/`finalizeImport`, which use private constructors), `TypeChecker.lean` (`reduceBool`/`reduceNat` names),
`Primitive.lean` (removed the compile-time self-test, which fails on 4.35's `Nat.div`). `Lean2js/Kernel.lean` now delegates to
`Lean4Lean.addDecl … (check := false)` after a redeclaration check; `Lean2js/KernelCasesOn.lean` implements `lean_mk_cases_on` (identical to the C++
result on 35 Init types incl. nested `Lean.Syntax`; tests `casesOn`, `kernel`). Open: `check := true` (fix `Primitive.checkDef` for 4.35), kernel
`whnf`/`isDefEq`/`check` externs (`lean_kernel_*`), mutual-inductive tests once user inductives can be declared in JS.

## Type checking enabled (2026-11-05)

`lean_add_decl` / `lean_elab_add_decl` now type check with lean4lean by default (`LEAN2JS_KERNEL_CHECK=0` disables it; `…_without_checking` never checks), and
`lean_kernel_whnf/is_def_eq/check` are implemented (`Lean2js/Kernel.lean`). On the test programs the overhead is not measurable (22.2 s vs 22.2 s). Tests: `kernelops`
(real kernel vs lean4lean), `selfhostcheck` (the self-hosted frontend rejects ill-typed `addDecl`s with exactly the native kernel messages), `selfhost`. Known gap:
`Primitive.checkDef` fails for Lean 4.35's `Nat.div` (so *re-declaring* the primitive `Nat`/`String` functions, i.e. compiling `Init.Prelude` itself, is not possible yet).
Status: the epic's kernel question is resolved; remaining: that gap, kernel diagnostics, performance of `decide`-heavy proofs (not measured).
