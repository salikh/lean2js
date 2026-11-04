/-! Statistics over the numbers in `data.json` (a JSON array of numbers, parsed by hand: no `import Lean` needed). -/

def parseFloat (s : String) : Option Float :=
  let s := s.trimAscii.toString
  let neg := s.startsWith "-"
  let s := if neg then (s.drop 1).toString else s
  let sign : Float := if neg then -1.0 else 1.0
  match s.splitOn "." with
  | [a] => a.toNat?.map fun n => sign * n.toFloat
  | [a, b] => do
    let n ← a.toNat?
    let m ← b.toNat?
    pure (sign * (n.toFloat + m.toFloat / (10.0 : Float) ^ b.length.toFloat))
  | _ => none

def readNumbers (path : System.FilePath) : IO (Array Float) := do
  let txt ← IO.FS.readFile path
  let body := (txt.trimAscii.toString.replace "[" "").replace "]" ""
  let mut out : Array Float := #[]
  for tok in body.splitOn "," do
    match parseFloat tok with
    | some x => out := out.push x
    | none => throw <| IO.userError s!"data.json: cannot parse '{tok.trimAscii}' as a number"
  return out

def mean (xs : Array Float) : Float := xs.foldl (· + ·) 0 / xs.size.toFloat

def stdev (xs : Array Float) : Float :=
  let m := mean xs
  Float.sqrt ((xs.foldl (fun acc x => acc + (x - m) * (x - m)) 0) / xs.size.toFloat)

def main : IO Unit := do
  let xs ← readNumbers "data.json"
  if xs.isEmpty then
    IO.println "data.json contains no numbers"
    return
  IO.println s!"count = {xs.size}"
  IO.println s!"mean  = {mean xs}"
  IO.println s!"min   = {xs.foldl min xs[0]!}"
  IO.println s!"max   = {xs.foldl max xs[0]!}"
  IO.println s!"stdev = {stdev xs}"
