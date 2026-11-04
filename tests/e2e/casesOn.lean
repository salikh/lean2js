import Lean
import Lean2js.Kernel
open Lean

/-- `casesOn` construction: the C++ `lean_mk_cases_on` natively, Lean2js.Kernel's replacement in JS; natively also checked for equality. -/
def main : IO Unit := do
  let sysroot ← IO.getEnv "LEAN_SYSROOT"
  searchPathRef.set [(sysroot.getD ".") / "lib" / "lean"]
  let env ← importModules #[{ module := `Init }] {}
  let kenv := env.toKernelEnv
  for n in [`Nat, `List, `Option, `Eq, `HEq, `Acc, `And, `Or, `Exists, `Prod, `Sum, `Subtype, `Fin, `Lean.Syntax, `Lean.Name,
      `Lean.Macro.Exception, `WellFounded, `Decidable, `Bool, `Ordering, `Lean.Syntax.Preresolved, `PSigma, `Sigma, `True, `False, `Nat.le,
      `Array, `String, `Char, `ForInStep, `Except, `EStateM.Result, `Std.Format, `Thunk, `Lean.SourceInfo] do
    match mkCasesOnImp kenv n with
    | .error _ => IO.println s!"{n}: error"
    | .ok (.defnDecl d) =>
      let mine := Lean2js.Kernel.mkCasesOnDecl kenv n
      let same := match mine with | .ok m => (m == Declaration.defnDecl d) | .error _ => false
      IO.println s!"{n}: {d.name} {d.levelParams} {hash d.type} {hash d.value} {same}"
    | .ok _ => IO.println s!"{n}: not a definition"
