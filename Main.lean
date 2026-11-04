import Lean2js.CodegenIR
import Lean2js.LcnfDump

open Lean Lean2js

def usage : String :=
  "usage: lean2js FILE.lean [--out OUT.js] [--runtime PATH] [--run] [--all] [--init-all] [--eval-all] [--small] [--dump-ir]\n" ++
  "  Translates the final (reference-counted) IR of FILE.lean and everything it reaches to JavaScript.\n" ++
  "  --run      the generated file runs `main` when loaded\n" ++
  "  --all      also emit declarations not reachable from `main`\n" ++
  "  --init-all run the initializers of all imported modules at startup (default: main module only, others lazily)\n" ++
  "  --eval-all emit every declaration of the imported modules and a name lookup for `evalConst` (large)\n" ++
  "  --small    smaller output: short global identifiers, no indentation\n" ++
  "  --runtime  import path of the runtime (default ./lean_rt.js)\n" ++
  "  --dump-ir  print the IR declarations instead of JavaScript"

structure Args where
  file : Option String := none
  out : Option String := none
  opts : CodegenIR.Options := {}
  dumpIr : Bool := false

partial def parseArgs (a : Args) : List String → Except String Args
  | [] => .ok a
  | "--out" :: o :: rest => parseArgs { a with out := some o } rest
  | "--runtime" :: r :: rest => parseArgs { a with opts := { a.opts with runtime := r } } rest
  | "--dump-ir" :: rest => parseArgs { a with dumpIr := true } rest
  | "--run" :: rest => parseArgs { a with opts := { a.opts with run := true } } rest
  | "--init-all" :: rest => parseArgs { a with opts := { a.opts with initAll := true } } rest
  | "--eval-all" :: rest => parseArgs { a with opts := { a.opts with evalAll := true } } rest
  | "--small" :: rest => parseArgs { a with opts := { a.opts with small := true } } rest
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
  let some env ← LcnfDump.elaborate file
    | IO.eprintln "lean2js: elaboration failed"; return 1
  match CodegenIR.genProgram env file a.opts with
  | .error e => IO.eprintln s!"lean2js: code generation failed: {e}"; return 1
  | .ok (js, decls) =>
    let out := if a.dumpIr then "\n".intercalate (decls.toList.map toString) ++ "\n" else js
    match a.out with
    | some o => IO.FS.writeFile o out
    | none => IO.print out
    return 0
