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
