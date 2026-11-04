import Lean
import Std.Data.HashMap

/-! Helpers shared by the JS code generator: name mangling and strongly connected components. -/

namespace Lean2js.JsUtil

open Lean (Name)

private def isIdentChar (c : Char) : Bool := c.isAlphanum && c.toNat < 128 || c == '_'

/-- Mangle a (dotted) Lean name into a valid JS identifier. -/
def mangle (prefix_ : String) (s : String) : String :=
  s.foldl (init := prefix_) fun acc c =>
    if isIdentChar c then acc.push c
    else if c == '.' then acc.push '$'
    else acc ++ s!"$u{String.ofList (Nat.toDigits 16 c.toNat)}_"

/-- JS identifier of a Lean declaration given as a string (only for fixed names like `main`; use `nameId` for names). -/
def declId (n : String) : String := mangle "l_" n

/-- Escapes a name component: identifier characters are kept, any other character becomes `$u<hex>_` (so `$` only occurs in escapes,
as component separator `$$`, or in the prefix `$n` of numeric components). -/
private def escapeComp (s : String) : String :=
  s.foldl (init := "") fun acc c =>
    if isIdentChar c then acc.push c else acc ++ s!"$u{String.ofList (Nat.toDigits 16 c.toNat)}_"

/-- Unambiguous encoding of a hierarchical name (by components, not via `Name.toString`, which can collide and depends on escaping rules);
the runtime reproduces it in `nameId` of `runtime/lean_rt.js` to resolve `evalConst`. -/
def nameBody (n : Name) : String :=
  let comps := n.components.map fun
    | .str _ s => escapeComp s
    | .num _ k => s!"$n{k}"
    | .anonymous => ""
  "$$".intercalate comps

/-- JS identifier of the Lean declaration `n`. -/
def nameId (n : Name) : String := "l_" ++ nameBody n

def jsString (s : String) : String := (Lean.Json.str s).compress

/-! ## Strongly connected components (Tarjan) of the tail-call graph -/

structure Tarjan where
  next : Nat := 0
  index : Array (Option Nat)
  low : Array Nat
  onStack : Array Bool
  stack : List Nat := []
  sccs : Array (Array Nat) := #[]

partial def strongConnect (adj : Array (Array Nat)) (v : Nat) : StateM Tarjan Unit := do
  modify fun st =>
    { st with
      index := st.index.set! v (some st.next)
      low := st.low.set! v st.next
      next := st.next + 1
      stack := v :: st.stack
      onStack := st.onStack.set! v true }
  for w in adj[v]! do
    match (← get).index[w]! with
    | none =>
      strongConnect adj w
      modify fun st => { st with low := st.low.set! v (min st.low[v]! st.low[w]!) }
    | some iw =>
      if (← get).onStack[w]! then
        modify fun st => { st with low := st.low.set! v (min st.low[v]! iw) }
  let st ← get
  if some st.low[v]! == st.index[v]! then
    let mut comp := #[]
    let mut stack := st.stack
    let mut onStack := st.onStack
    repeat
      match stack with
      | [] => break
      | x :: rest =>
        stack := rest
        onStack := onStack.set! x false
        comp := comp.push x
        if x == v then break
    set { st with stack, onStack, sccs := st.sccs.push comp }

end Lean2js.JsUtil
