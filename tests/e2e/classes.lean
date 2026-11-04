class Shape (α : Type) where
  area : α → Nat
  name : String

structure Sq where side : Nat
structure Rect where (w h : Nat)

instance : Shape Sq := ⟨fun s => s.side * s.side, "square"⟩
instance : Shape Rect := ⟨fun r => r.w * r.h, "rect"⟩

def describe [Shape α] (x : α) : String := s!"{Shape.name α}: {Shape.area x}"

inductive Color | red | green | blue deriving Repr, BEq, DecidableEq

instance : ToString Color where
  toString | .red => "R" | .green => "G" | .blue => "B"

def main : IO Unit := do
  IO.println (describe (Sq.mk 4))
  IO.println (describe (Rect.mk 3 5))
  IO.println [Color.red, .green, .blue]
  IO.println (Color.red == Color.blue)
  IO.println (repr Color.green)
  IO.println (if Color.red = Color.red then "eq" else "ne")
