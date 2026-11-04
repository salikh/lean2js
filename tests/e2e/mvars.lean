import Lean
open Lean Meta Elab

/-- Differential test of `instantiateMVars` (level and expression metavariables, nested assignments, beta, delayed assignments). -/
def sh (e : Expr) : String := toString (repr e)

def test : MetaM Unit := do
  let nat := mkConst `Nat
  let u ← mkFreshLevelMVar
  let v ← mkFreshLevelMVar
  let m1 ← mkFreshExprMVar (some nat)
  let m2 ← mkFreshExprMVar (some (← mkArrow nat nat))
  let m3 ← mkFreshExprMVar (some nat)
  let e := mkApp (mkApp (mkConst `f [u, v]) (mkApp m2 m1)) (mkSort (mkLevelMax u (Level.succ v)))
  -- nothing assigned
  IO.println (sh (← instantiateMVars e))
  -- chain: ?u := succ ?v, ?v := 0, ?m1 := g ?m3, ?m3 := 5, ?m2 := fun x => h x x
  if let .mvar uid := u then assignLevelMVar uid (Level.succ v)
  if let .mvar vid := v then assignLevelMVar vid Level.zero
  m1.mvarId!.assign (mkApp (mkConst `g) m3)
  m3.mvarId!.assign (mkRawNatLit 5)
  m2.mvarId!.assign (mkLambda `x .default nat (mkApp (mkApp (mkConst `h) (mkBVar 0)) (mkBVar 0)))
  IO.println (sh (← instantiateMVars e))
  -- the assignments were updated in the mctx (second call is a no-op)
  IO.println (sh (← instantiateMVars (mkMVar m1.mvarId!)))
  -- partially applied lambda, extra args
  let m4 ← mkFreshExprMVar none
  m4.mvarId!.assign (mkLambda `a .default nat (mkLambda `b .default nat (mkApp (mkBVar 1) (mkBVar 0))))
  IO.println (sh (← instantiateMVars (mkApp m4 (mkConst `c1))))
  IO.println (sh (← instantiateMVars (mkApp (mkApp m4 (mkConst `c1)) (mkConst `c2))))
  IO.println (sh (← instantiateMVars (mkApp (mkApp (mkApp m4 (mkConst `c1)) (mkConst `c2)) (mkConst `c3))))
  -- delayed assignment
  withLocalDeclD `x nat fun x => do
    let pending ← mkFreshExprMVar nat
    let delayed ← mkFreshExprMVar (some (← mkArrow nat nat))
    assignDelayedMVar delayed.mvarId! #[x] pending.mvarId!
    pending.mvarId!.assign (mkApp (mkConst `k) x)
    IO.println (sh (← instantiateMVars (mkApp delayed (mkConst `arg))))
    IO.println (sh (← instantiateMVars delayed))
    IO.println (sh (← instantiateMVars (mkApp (mkApp delayed (mkConst `arg)) (mkConst `more))))
  -- binder bodies and shared subterms
  let mut t : Expr := m3
  for _ in [0:40] do t := mkApp t t
  let t2 ← instantiateMVars (mkLambda `y .default nat t)
  IO.println s!"{t2.hash} {t2.hasMVar}"

def main : IO Unit := do
  let env ← mkEmptyEnvironment
  let _ ← (test.run' {} {}).toIO { fileName := "", fileMap := default } { env }
