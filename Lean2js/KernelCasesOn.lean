import Lean

/-!
# `casesOn` construction (replacement for the C++ `lean_mk_cases_on`)

Given an inductive type `I` with recursor `I.rec`, builds the definition
`I.casesOn : {params} → {motive : indices → I params indices → Sort u} → {indices} → (t : I params indices) → (minor premises without
induction hypotheses) → motive indices t`, defined by `I.rec` with the other motives of a mutual/nested block replaced by constant
`PUnit` (`True` when eliminating only into `Prop`). Tested differentially against the C++ implementation (tests/e2e/casesOn.lean).
-/

namespace Lean2js.Kernel

open Lean

private structure S where
  lctx : LocalContext := {}
  ngen : NameGenerator := { namePrefix := `_casesOn }

private abbrev M := StateT S (Except Kernel.Exception)

private def mkLocal (n : Name) (ty : Expr) (bi : BinderInfo) : M Expr := do
  let s ← get
  let id := s.ngen.curr
  let ngen := s.ngen.next
  let fv : FVarId := ⟨id⟩
  set { s with ngen, lctx := s.lctx.mkLocalDecl fv n ty bi }
  return mkFVar fv

private def declOf (x : Expr) : M LocalDecl := do
  match (← get).lctx.find? x.fvarId! with
  | some d => return d
  | none => throw (.other "mkCasesOn: unknown free variable")

/-- Opens the leading `∀` binders of `e` as local variables. -/
private partial def telescope (e : Expr) (fvs : Array Expr := #[]) : M (Array Expr × Expr) :=
  match e with
  | .forallE n d b bi => do
    let x ← mkLocal n (d.instantiateRev fvs) bi
    telescope b (fvs.push x)
  | _ => return (fvs, e.instantiateRev fvs)

private def mkLambdaM (xs : Array Expr) (e : Expr) : M Expr := return (← get).lctx.mkLambda xs e
private def mkForallM (xs : Array Expr) (e : Expr) : M Expr := return (← get).lctx.mkForall xs e

/-- For each binder of the minor premise type `ty`: is it an induction hypothesis (its type ends in a motive application)? -/
private def ihFlags (motives : Array Expr) (ty : Expr) : Array Bool :=
  let isMotiveApp (t : Expr) : Bool :=
    let rec body : Expr → Expr
      | .forallE _ _ b _ => body b
      | e => e
    match (body t).getAppFn with
    | .fvar id => motives.any fun m => m.fvarId! == id
    | _ => false
  let rec go (e : Expr) (acc : Array Bool) : Array Bool :=
    match e with
    | .forallE _ d b _ => go b (acc.push (isMotiveApp d))
    | _ => acc
  go ty #[]

/-- Replaces applications of the motives by the (beta-reduced) motive arguments of `rec`. -/
private def substMotives (motives motiveArgs : Array Expr) (e : Expr) : Expr :=
  e.replace fun x =>
    match x.getAppFn with
    | .fvar id =>
      match motives.findIdx? (·.fvarId! == id) with
      | some j => some ((motiveArgs[j]!).beta x.getAppArgs)
      | none => none
    | _ => none

private def build (ind : InductiveVal) (rec : RecursorVal) (n : Name) : M Declaration := do
  let recName := n ++ `rec
  let (recFvars, recResult) ← telescope rec.type
  let nparams := ind.numParams
  let nmotives := rec.numMotives
  let nminors := rec.numMinors
  let nindices := ind.numIndices
  let minorStart := nparams + nmotives
  let idxStart := minorStart + nminors
  let mainIdx := ind.all.idxOf n
  let elimToProp := rec.levelParams.length == ind.levelParams.length
  let elimUniv : Level := if elimToProp then Level.zero else .param rec.levelParams.head!
  let lvls := rec.levelParams.map mkLevelParam
  let unitTy : Expr := if elimToProp then mkConst ``True else mkConst ``PUnit [elimUniv]
  let unitVal : Expr := if elimToProp then mkConst ``True.intro else mkConst ``PUnit.unit [elimUniv]
  let params := recFvars.extract 0 nparams
  let motives := recFvars.extract nparams minorStart
  let cMain := motives[mainIdx]!
  let indices := recFvars.extract idxStart (idxStart + nindices)
  let major := recFvars[idxStart + nindices]!
  -- motives of the other types: constant functions returning `PUnit`
  let mut motiveArgs : Array Expr := #[]
  for j in [0:nmotives] do
    if j == mainIdx then motiveArgs := motiveArgs.push cMain
    else
      let d ← declOf motives[j]!
      let (xs, _) ← telescope d.type
      motiveArgs := motiveArgs.push (← mkLambdaM xs unitTy)
  -- minor premises
  let mut newMinors : Array Expr := #[]
  let mut minorArgs : Array Expr := #[]
  for j in [0:nminors] do
    let m := recFvars[minorStart + j]!
    let d ← declOf m
    let flags := ihFlags motives d.type
    -- as in the C++ construction, the minor premise types are those of `rec` instantiated with the actual motive arguments
    let (xs, res) ← telescope (substMotives motives motiveArgs d.type)
    if res.getAppFn == cMain then
      let mut fields : Array Expr := #[]
      for h : i in [0:xs.size] do
        unless flags[i]! do fields := fields.push xs[i]
      let newTy ← mkForallM fields res
      let nm ← mkLocal d.userName newTy d.binderInfo
      newMinors := newMinors.push nm
      minorArgs := minorArgs.push (← mkLambdaM xs (mkAppN nm fields))
    else
      minorArgs := minorArgs.push (← mkLambdaM xs unitVal)
  let casesOnParams := params ++ #[cMain] ++ indices ++ #[major] ++ newMinors
  let ty ← mkForallM casesOnParams recResult
  let recArgs := params ++ motiveArgs ++ minorArgs ++ indices ++ #[major]
  let val ← mkLambdaM casesOnParams (mkAppN (mkConst recName lvls) recArgs)
  let name := n ++ `casesOn
  return .defnDecl
    { name, levelParams := rec.levelParams, type := ty, value := val, hints := .abbrev
      safety := if ind.isUnsafe then .unsafe else .safe, all := [name] }

/-- The `casesOn` definition of the inductive type `n` (not yet added to the environment). -/
def mkCasesOnDecl (env : Kernel.Environment) (n : Name) : Except Kernel.Exception Declaration := do
  let some (.inductInfo ind) := env.find? n | throw (.other s!"mkCasesOn: '{n}' is not an inductive type")
  let some (.recInfo rec) := env.find? (n ++ `rec) | throw (.other s!"mkCasesOn: '{n}.rec' not found")
  (build ind rec n |>.run {}).map (·.1)

end Lean2js.Kernel
