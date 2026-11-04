# Question: how to get a kernel in JS?

Parent: [self-001](self-001-compiler-to-js-epic.md)
Status: **question** (provisional decision = recommended)

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

Recommendation: A now (milestone self-009), then C if lean4lean is usable.
