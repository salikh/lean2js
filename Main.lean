import Lean2js.Codegen
import Lean2js.LcnfDump

open Lean Lean2js

def usage : String :=
  "usage: lean2js FILE.lean|FILE.json [--out OUT.js] [--runtime PATH] [--entry NAME]... [--run] [--all]\n" ++
  "  FILE.json is the output of `lcnf-dump FILE.lean --with-deps`."

structure Args where
  file : Option String := none
  out : Option String := none
  opts : Codegen.Options := {}

partial def parseArgs (a : Args) : List String → Except String Args
  | [] => .ok a
  | "--out" :: o :: rest => parseArgs { a with out := some o } rest
  | "--runtime" :: r :: rest => parseArgs { a with opts := { a.opts with runtime := r } } rest
  | "--entry" :: e :: rest => parseArgs { a with opts := { a.opts with roots := a.opts.roots.push e } } rest
  | "--run" :: rest => parseArgs { a with opts := { a.opts with run := true } } rest
  | "--all" :: rest => parseArgs { a with opts := { a.opts with all := true } } rest
  | f :: rest =>
    if f.startsWith "--" then .error s!"unknown option '{f}'"
    else if a.file.isSome then .error "more than one input file"
    else parseArgs { a with file := some f } rest

def main (args : List String) : IO UInt32 := do
  let a ← match parseArgs {} args with
    | .ok a => pure a
    | .error e => IO.eprintln s!"{e}\n{usage}"; return 2
  let some file := a.file | IO.eprintln usage; return 2
  let json ← if file.endsWith ".json" then
      match Json.parse (← IO.FS.readFile file) with
      | .ok j => pure j
      | .error e => IO.eprintln s!"lean2js: {file}: invalid JSON: {e}"; return 1
    else
      let some env ← LcnfDump.elaborate file
        | IO.eprintln "lean2js: elaboration failed"; return 1
      pure (LcnfDump.dumpWithDepsJson env file)
  let prog ← match Ast.parseProgram json with
    | .ok p => pure p
    | .error e => IO.eprintln s!"lean2js: cannot decode LCNF JSON: {e}"; return 1
  match Codegen.genProgram prog a.opts with
  | .error e => IO.eprintln s!"lean2js: code generation failed: {e}"; return 1
  | .ok js =>
    match a.out with
    | some o => IO.FS.writeFile o js
    | none => IO.print js
    return 0
