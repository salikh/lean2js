import Lean
open Lean

/-- Differential test of the native Expr primitives (hashes, instantiate, abstract, lift/lower, find/replace, eqv). -/
def sh (e : Expr) : String := toString (repr e)

def main : IO Unit := do
  let c (n : Name) := mkConst n
  let f := c `f; let a := c `a; let b := c `b
  let e1 := mkApp (mkApp f (mkBVar 0)) (mkBVar 2)
  IO.println s!"{hash e1} {e1.looseBVarRange} {e1.approxDepth} {e1.hasLooseBVars}"
  let lam := mkLambda `x .default (c `N) (mkApp (mkBVar 0) (mkApp (mkBVar 1) (mkBVar 2)))
  IO.println (sh (lam.instantiate1 a))
  IO.println (sh (lam.instantiate #[a, b, f]))
  IO.println (sh (lam.instantiateRev #[a, b, f]))
  IO.println (sh (e1.instantiateRange 1 3 #[a, b, f, a]))
  IO.println (sh (e1.instantiateRevRange 0 2 #[a, b, f]))
  IO.println (sh (e1.liftLooseBVars 1 3))
  IO.println (sh (e1.lowerLooseBVars 1 1))
  IO.println s!"{e1.hasLooseBVar 0} {e1.hasLooseBVar 1} {e1.hasLooseBVar 2} {lam.hasLooseBVar 0} {lam.hasLooseBVar 1}"
  let x := mkFVar ⟨`x⟩; let y := mkFVar ⟨`y⟩
  let body := mkApp (mkApp f x) (mkLambda `z .implicit (c `N) (mkApp y x))
  IO.println (sh (body.abstract #[x, y]))
  IO.println (sh (body.abstractRange 1 #[x, y]))
  IO.println (sh (mkForall `h .instImplicit (c `P) (mkLet `v (c `T) a (mkApp (mkBVar 1) (mkBVar 0)) true) |>.instantiate1 b))
  IO.println s!"{body.hash} {body.hasFVar} {body.approxDepth} {(body.abstract #[x, y]).looseBVarRange}"
  -- equality
  let l1 := mkLambda `p .default (c `N) (mkBVar 0)
  let l2 := mkLambda `q .implicit (c `N) (mkBVar 0)
  IO.println s!"{l1 == l2} {l1.eqv l2} {Expr.equal l1 l2} {Expr.equal l1 l1} {body == body.abstract #[x]}"
  IO.println s!"{mkSort (.succ (.param `u)) == mkSort (.succ (.param `u))} {mkSort (.succ (.param `u)) == mkSort (.succ (.param `v))}"
  IO.println s!"{(Name.mkNum `a 3) == (Name.mkNum `a 3)} {(Name.mkNum `a 3) == (Name.mkNum `a 4)} {`a.b == `a.c}"
  -- find / replace
  IO.println (sh ((body.find? fun e => e.isFVar && e == y).getD f))
  IO.println s!"{(body.find? fun e => e.isConstOf `zzz).isSome} {body.occurs y} {body.containsFVar ⟨`y⟩}"
  IO.println (sh (body.replace fun e => if e == x then some a else none))
  IO.println (sh (body.replace fun e => if e.isFVar then some (mkBVar 7) else none))
  IO.println s!"{(body.replaceFVar x b) == (body.instantiate1 b |>.abstract #[x])}"
  -- shared subterms (DAG) must not blow up
  let mut t := a
  for _ in [0:60] do t := mkApp t t
  IO.println s!"{t.hash} {(t.replace fun e => if e == a then some b else none).hash} {(t.instantiate1 b).hash}"
  IO.println s!"{Expr.equal t (t.replace fun _ => none)}"
