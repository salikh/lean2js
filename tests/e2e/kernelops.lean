import Lean
import Lean2js.Kernel
open Lean

/-- `Kernel.whnf`, `Kernel.isDefEq`, `Kernel.check`: the C++ kernel natively, lean4lean in JS. -/
def main : IO Unit := do
  let sysroot ← IO.getEnv "LEAN_SYSROOT"
  searchPathRef.set [(sysroot.getD ".") / "lib" / "lean"]
  let env ← importModules #[{ module := `Init }] {}
  let nat := mkConst `Nat
  let two := mkApp (mkConst `Nat.succ) (mkApp (mkConst `Nat.succ) (mkConst `Nat.zero))
  let sum := mkApp2 (mkConst `Nat.add) two two
  match Kernel.whnf env {} sum with
  | .ok e => IO.println s!"whnf: {e}"
  | .error _ => IO.println "whnf: error"
  IO.println s!"isDefEq: {repr (Kernel.isDefEq env {} sum (mkRawNatLit 4) |>.toOption)} {repr (Kernel.isDefEq env {} sum (mkRawNatLit 5) |>.toOption)}"
  match Kernel.check env {} (mkApp (mkConst `Nat.succ) (mkRawNatLit 1)) with
  | .ok t => IO.println s!"check: {t}"
  | .error _ => IO.println "check: error"
  match Kernel.check env {} (mkApp (mkConst `Nat.succ) (mkConst `Bool.true)) with
  | .ok t => IO.println s!"check bad: ok?! {t}"
  | .error (.appTypeMismatch ..) => IO.println "check bad: appTypeMismatch"
  | .error _ => IO.println "check bad: other error"
  let lam := mkLambda `x .default nat (mkApp (mkConst `Nat.succ) (mkBVar 0))
  match Kernel.check env {} (mkApp lam (mkRawNatLit 3)) with
  | .ok t => IO.println s!"check app: {t}"
  | .error _ => IO.println "check app: error"
  match Kernel.whnf env {} (mkApp lam (mkRawNatLit 3)) with
  | .ok e => IO.println s!"whnf beta: {e}"
  | .error _ => IO.println "whnf beta: error"
