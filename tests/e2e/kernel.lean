import Lean
import Lean2js.Kernel
open Lean

/-- `addDecl` of non-inductive declarations: the C++ kernel natively, the trusting Lean kernel (Lean2js.Kernel) in JS. -/
def main : IO Unit := do
  let sysroot ← IO.getEnv "LEAN_SYSROOT"
  searchPathRef.set [(sysroot.getD ".") / "lib" / "lean"]
  let env ← importModules #[{ module := `Init }] {}
  let nat := mkConst `Nat
  let defn : Declaration := .defnDecl
    { name := `foo, levelParams := [], type := nat, value := mkRawNatLit 5, hints := .abbrev, safety := .safe }
  match env.addDeclCore 0 0 defn none with
  | .error _ => IO.println "defn: error"
  | .ok env1 =>
    IO.println s!"defn: {(env1.find? `foo).map (·.type)} {(env1.find? `foo).isSome} {(env.find? `foo).isSome}"
    match env1.addDeclCore 0 0 defn none with
    | .error (.alreadyDeclared _ n) => IO.println s!"again: alreadyDeclared {n}"
    | .error _ => IO.println "again: other error"
    | .ok _ => IO.println "again: ok?!"
    let ax : Declaration := .axiomDecl { name := `myAx, levelParams := [`u], type := mkSort (.param `u), isUnsafe := false }
    let thm : Declaration := .thmDecl
      { name := `myThm, levelParams := [], type := mkConst `True, value := mkConst `True.intro }
    let some env2 := (env1.addDeclCore 0 0 ax none).toOption | IO.println "ax: error"
    let some env3 := (env2.addDeclCore 0 0 thm none).toOption | IO.println "thm: error"
    IO.println s!"{(env3.find? `myAx).map (·.levelParams)} {(env3.find? `myThm).map (·.isTheorem)} {env3.constants.map₂.toList.length}"
    let opq : Declaration := .opaqueDecl
      { name := `myOpq, levelParams := [], type := nat, value := mkRawNatLit 1, isUnsafe := false }
    match env3.addDeclCore 0 0 opq none with
    | .ok env4 => IO.println s!"opaque: {(env4.find? `myOpq).map (fun c => match c with | .opaqueInfo _ => true | _ => false)}"
    | .error _ => IO.println "opaque: error"
  -- the elaborator-level environment
  match Lean.Environment.addDeclCore env 0 0 defn none with
  | .ok e => IO.println s!"elab: {(e.find? `foo).isSome} {e.contains `foo}"
  | .error _ => IO.println "elab: error"
