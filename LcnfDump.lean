import Lean2js.LcnfDump

open Lean2js LcnfDump

def usage : String :=
  "usage: lcnf-dump FILE.lean [--phase base|mono|impure] [--compact] [--out OUT.json]"

structure Args where
  file : Option String := none
  phase : DumpPhase := defaultPhase
  compact : Bool := false
  out : Option String := none

partial def parseArgs (a : Args) : List String → Except String Args
  | [] => .ok a
  | "--phase" :: p :: rest =>
    match DumpPhase.parse? p with
    | some ph => parseArgs { a with phase := ph } rest
    | none => .error s!"unknown phase '{p}'"
  | "--compact" :: rest => parseArgs { a with compact := true } rest
  | "--out" :: o :: rest => parseArgs { a with out := some o } rest
  | f :: rest =>
    if f.startsWith "--" then .error s!"unknown option '{f}'"
    else if a.file.isSome then .error "more than one input file"
    else parseArgs { a with file := some f } rest

def main (args : List String) : IO UInt32 := do
  let a ← match parseArgs {} args with
    | .ok a => pure a
    | .error e => IO.eprintln s!"{e}\n{usage}"; return 2
  let some file := a.file | IO.eprintln usage; return 2
  let some env ← elaborate file
    | IO.eprintln "lcnf-dump: elaboration failed"; return 1
  let j := dumpJson env file a.phase
  let s := if a.compact then j.compress else j.pretty
  match a.out with
  | some o => IO.FS.writeFile o (s ++ "\n")
  | none => IO.println s
  return 0
