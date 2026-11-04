import Std.Data.TreeMap
open Std

structure Emp where
  name : String
  age : Nat
  deriving Repr, BEq, Hashable, Ord

inductive Expr where
  | num (n : Int)
  | add (a b : Expr)
  | mul (a b : Expr)
  | neg (a : Expr)
  deriving Repr, BEq, Inhabited

def Expr.eval : Expr → Int
  | .num n => n
  | .add a b => a.eval + b.eval
  | .mul a b => a.eval * b.eval
  | .neg a => - a.eval

def main : IO Unit := do
  let m : TreeMap String Nat compare := TreeMap.empty |>.insert "b" 2 |>.insert "a" 1 |>.insert "c" 3
  IO.println (m.toList)
  IO.println (m["b"]?)
  IO.println (m.contains "z")
  IO.println (m.foldl (fun acc _ v => acc + v) 0)
  let e := Expr.add (.num 3) (.mul (.num 4) (.neg (.num 5)))
  IO.println (repr e)
  IO.println e.eval
  IO.println (e == e)
  let a : Emp := ⟨"ann", 30⟩
  let b : Emp := ⟨"bob", 25⟩
  IO.println (repr a)
  IO.println (repr (compare a b))
  IO.println (hash a != hash b)
  IO.println (a == b)
