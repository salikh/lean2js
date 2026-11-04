import Std.Data.HashMap
open Std

/-! A small big-number calculator, read from stdin one statement per line.

    1 + 2 * 3          expression with + - * / % ^ and parentheses (exact, arbitrary precision)
    x = 2 ^ 100        assignment
    fact(30) + x       functions: fact fib isqrt abs gcd(a, b)
    :vars              list variables
-/

inductive Tok where
  | num (n : Nat) | id (s : String) | op (c : Char) | lp | rp | comma
  deriving Repr, BEq

inductive Ex where
  | num (n : Int) | var (s : String) | neg (e : Ex)
  | bin (c : Char) (a b : Ex) | call (f : String) (args : List Ex)

def tokenize (s : String) : Except String (Array Tok) := do
  let mut out : Array Tok := #[]
  let mut cs := s.toList
  while !cs.isEmpty do
    match cs with
    | [] => break
    | c :: rest =>
      if c.isWhitespace then cs := rest
      else if c.isDigit then
        let ds := cs.takeWhile Char.isDigit
        out := out.push (.num (String.ofList ds).toNat!)
        cs := cs.drop ds.length
      else if c.isAlpha then
        let ds := cs.takeWhile fun c => c.isAlphanum || c == '_'
        out := out.push (.id (String.ofList ds))
        cs := cs.drop ds.length
      else if c == '(' then out := out.push .lp; cs := rest
      else if c == ')' then out := out.push .rp; cs := rest
      else if c == ',' then out := out.push .comma; cs := rest
      else if "+-*/%^=".contains c then out := out.push (.op c); cs := rest
      else throw s!"unexpected character '{c}'"
  return out

mutual
  partial def parseSum (ts : Array Tok) (i : Nat) : Except String (Ex × Nat) := do
    let r ← parseProd ts i
    let mut l := r.1
    let mut i := r.2
    repeat
      match ts[i]? with
      | some (.op c) =>
        if c == '+' || c == '-' then
          let (r, j) ← parseProd ts (i + 1)
          l := .bin c l r; i := j
        else break
      | _ => break
    return (l, i)

  partial def parseProd (ts : Array Tok) (i : Nat) : Except String (Ex × Nat) := do
    let r ← parseUnary ts i
    let mut l := r.1
    let mut i := r.2
    repeat
      match ts[i]? with
      | some (.op c) =>
        if c == '*' || c == '/' || c == '%' then
          let (r, j) ← parseUnary ts (i + 1)
          l := .bin c l r; i := j
        else break
      | _ => break
    return (l, i)

  partial def parseUnary (ts : Array Tok) (i : Nat) : Except String (Ex × Nat) := do
    match ts[i]? with
    | some (.op '-') => let (e, j) ← parseUnary ts (i + 1); return (.neg e, j)
    | _ => parsePow ts i

  partial def parsePow (ts : Array Tok) (i : Nat) : Except String (Ex × Nat) := do
    let (b, i) ← parseAtom ts i
    match ts[i]? with
    | some (.op '^') => let (e, j) ← parseUnary ts (i + 1); return (.bin '^' b e, j)   -- right assoc
    | _ => return (b, i)

  partial def parseArgs (ts : Array Tok) (i : Nat) (acc : List Ex) : Except String (List Ex × Nat) := do
    let (e, i) ← parseSum ts i
    match ts[i]? with
    | some .comma => parseArgs ts (i + 1) (e :: acc)
    | some .rp => return ((e :: acc).reverse, i + 1)
    | _ => throw "expected ',' or ')'"

  partial def parseAtom (ts : Array Tok) (i : Nat) : Except String (Ex × Nat) := do
    match ts[i]? with
    | some (.num n) => return (.num n, i + 1)
    | some (.id f) =>
      if ts[i + 1]? == some .lp then
        let (args, j) ← parseArgs ts (i + 2) []
        return (.call f args, j)
      else return (.var f, i + 1)
    | some .lp =>
      let (e, j) ← parseSum ts (i + 1)
      if ts[j]? == some .rp then return (e, j + 1) else throw "expected ')'"
    | some _ => throw "unexpected token"
    | none => throw "unexpected end of input"
end

def isqrt (n : Nat) : Nat := Id.run do   -- Newton iteration
  if n < 2 then return n
  let mut x := n
  let mut y := (x + 1) / 2
  while y < x do
    x := y
    y := (x + n / x) / 2
  return x

def fib (n : Nat) : Nat := Id.run do
  let mut a := 0
  let mut b := 1
  for _ in [0:n] do (a, b) := (b, a + b)
  return a

def eval (env : HashMap String Int) : Ex → Except String Int
  | .num n => pure n
  | .var s => match env[s]? with | some v => pure v | none => throw s!"unknown variable '{s}'"
  | .neg e => do return - (← eval env e)
  | .bin c a b => do
    let x ← eval env a
    let y ← eval env b
    match c with
    | '+' => return x + y
    | '-' => return x - y
    | '*' => return x * y
    | '/' => if y == 0 then throw "division by zero" else return x / y
    | '%' => if y == 0 then throw "division by zero" else return x % y
    | _ =>
      if y < 0 then throw "negative exponent"
      else if y > 100000 then throw "exponent too large"
      else return x ^ y.toNat
  | .call f args => do
    let vs ← args.mapM (eval env)
    match f, vs with
    | "fact", [n] =>
      if n < 0 || n > 5000 then throw "fact: argument out of range"
      else return Int.ofNat (((List.range (n.toNat + 1)).drop 1).foldl (fun a k => a * k) (1 : Nat))
    | "fib", [n] => if n < 0 || n > 100000 then throw "fib: argument out of range" else return Int.ofNat (fib n.toNat)
    | "isqrt", [n] => if n < 0 then throw "isqrt of negative" else return Int.ofNat (isqrt n.toNat)
    | "abs", [n] => return Int.ofNat n.natAbs
    | "gcd", [a, b] => return Int.ofNat (Nat.gcd a.natAbs b.natAbs)
    | _, _ => throw s!"unknown function or wrong arity: {f}/{vs.length}"

def runLine (env : HashMap String Int) (line : String) : Except String (HashMap String Int × Option String) := do
  let ts ← tokenize line
  if ts.isEmpty then return (env, none)
  let (target, body) :=
    match (ts[0]? : Option Tok), (ts[1]? : Option Tok) with
    | some (.id x), some (.op '=') => (some x, ts.extract 2 ts.size)
    | _, _ => (none, ts)
  let (e, j) ← parseSum body 0
  if j != body.size then throw "trailing input"
  let v ← eval env e
  match target with
  | some x => return (env.insert x v, some s!"{x} = {v}")
  | none => return (env, some (toString v))

partial def loop (env : HashMap String Int) (h : IO.FS.Stream) (n : Nat) : IO Unit := do
  let line ← h.getLine
  if line.isEmpty then
    IO.println s!"bye ({n} lines)"
    return
  let line := line.trimAscii.toString
  if line == ":vars" then
    for (k, v) in env.toList.toArray.qsort (fun a b => a.1 < b.1) do IO.println s!"  {k} = {v}"
    loop env h (n + 1)
  else
    match runLine env line with
    | .ok (env, some out) => IO.println out; loop env h (n + 1)
    | .ok (env, none) => loop env h (n + 1)
    | .error e => IO.println s!"error: {e}"; loop env h (n + 1)

def main : IO Unit := do
  IO.println "lean2js calculator — type expressions, `x = expr`, `:vars`"
  loop {} (← IO.getStdin) 0
