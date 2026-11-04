import Lean
import Lean2js.KernelCasesOn
import Lean4Lean.Environment

/-!
# Trusting kernel entry points for the JS port of the Lean compiler (ticket self-005, option A)

The real kernel (`lean_add_decl`, …) is C++. This module provides Lean implementations that are exported under the same
symbols, so that `lean2js` (which resolves `@[extern "sym"]` declarations to `@[export sym]` Lean definitions) uses them when a
program importing this module is transpiled:

* `lean_add_decl`, `lean_add_decl_without_checking` (on `Kernel.Environment`) and `lean_elab_add_decl`,
  `lean_elab_add_decl_without_checking` (on `Lean.Environment`).
* Exported functions cannot have borrowed parameters, while the `extern` declarations they implement do (`@&`); `CodegenIR.genExternWrapper`
  adapts the reference counts of such calls.
* **No type checking is done** (like `addDeclWithoutChecking`); the elaborator's own checks remain. All declaration kinds are handled by
  the vendored lean4lean (`Lean4Lean.addDecl … (check := false)`), including inductive types and `init_quot`.
* `lean_mk_cases_on` is implemented in `Lean2js.KernelCasesOn` (the other auxiliary constructions are already written in Lean).

This module is only meant to be imported by the self-hosted program (it defines symbols that the native Lean also defines, so it must
not be linked into the `lean2js` executable).
-/

namespace Lean2js.Kernel

open Lean

/-- `Lean.Environment.updateBaseAfterKernelAdd` (private), bound through its export symbol. -/
@[extern "lean_elab_environment_update_base_after_kernel_add"]
opaque updateBaseAfterKernelAdd (env : Lean.Environment) (kenv : Kernel.Environment) (decl : Declaration) : Lean.Environment

/-- Adds `decl` to the kernel environment **without type checking** (`check := false`), using the vendored lean4lean kernel
(`vendor/lean4lean`), which also processes inductive types (recursors, nested inductives) and `init_quot`. -/
def addDeclTrusting (env : Kernel.Environment) (decl : Declaration) : Except Kernel.Exception Kernel.Environment := do
  -- redeclaration is reported even without type checking (as the C++ kernel does)
  for n in decl.getNames do
    if (env.find? n).isSome then throw (.alreadyDeclared env n)
  Lean4Lean.addDecl env decl (check := false)

@[export lean_add_decl]
def addDeclExport (env : Kernel.Environment) (_maxHeartbeats _maxRecDepth : USize) (decl : Declaration)
    (_cancelTk? : Option IO.CancelToken) : Except Kernel.Exception Kernel.Environment :=
  addDeclTrusting env decl

@[export lean_add_decl_without_checking]
def addDeclWithoutCheckingExport (env : Kernel.Environment) (decl : Declaration) :
    Except Kernel.Exception Kernel.Environment :=
  addDeclTrusting env decl

private def addDeclElab (env : Lean.Environment) (decl : Declaration) : Except Kernel.Exception Lean.Environment :=
  match addDeclTrusting env.toKernelEnv decl with
  | .ok kenv => .ok (updateBaseAfterKernelAdd env kenv decl)
  | .error e => .error e

@[export lean_elab_add_decl]
def addDeclElabExport (env : Lean.Environment) (_maxHeartbeats _maxRecDepth : USize) (decl : Declaration)
    (_cancelTk? : Option IO.CancelToken) : Except Kernel.Exception Lean.Environment :=
  addDeclElab env decl

@[export lean_elab_add_decl_without_checking]
def addDeclElabWithoutCheckingExport (env : Lean.Environment) (decl : Declaration) :
    Except Kernel.Exception Lean.Environment :=
  addDeclElab env decl

/-! Kernel `whnf` / `isDefEq` / `check` (used by `Kernel.whnf`, `decide +kernel`, …), through the vendored lean4lean type checker. -/

@[export lean_kernel_whnf]
def kernelWhnf (env : Lean.Environment) (lctx : LocalContext) (e : Expr) : Except Kernel.Exception Expr :=
  Lean4Lean.TypeChecker.M.run env.toKernelEnv (lctx := lctx) (Lean4Lean.TypeChecker.whnf e)

@[export lean_kernel_is_def_eq]
def kernelIsDefEq (env : Lean.Environment) (lctx : LocalContext) (a b : Expr) : Except Kernel.Exception Bool :=
  Lean4Lean.TypeChecker.M.run env.toKernelEnv (lctx := lctx) (Lean4Lean.TypeChecker.isDefEq a b)

@[export lean_kernel_check]
def kernelCheck (env : Lean.Environment) (lctx : LocalContext) (e : Expr) : Except Kernel.Exception Expr :=
  Lean4Lean.TypeChecker.M.run env.toKernelEnv (lctx := lctx) (Lean4Lean.TypeChecker.checkType e)

@[export lean_mk_cases_on]
def mkCasesOnExport (env : Kernel.Environment) (declName : Name) : Except Kernel.Exception Declaration :=
  mkCasesOnDecl env declName

end Lean2js.Kernel
