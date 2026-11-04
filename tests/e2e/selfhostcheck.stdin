import Lean
open Lean

-- an ill-typed definition is rejected by the kernel (only when type checking is enabled in the JS kernel)
#eval show CoreM Unit from do
  addDecl (.defnDecl { name := `bad, levelParams := [], type := mkConst ``Nat, value := mkConst ``Bool.true,
                       hints := .abbrev, safety := .safe })
#eval show CoreM Unit from do
  addDecl (.thmDecl { name := `badThm, levelParams := [], type := mkConst ``True, value := mkConst ``Nat.zero })
#eval show CoreM Unit from do
  addDecl (.defnDecl { name := `good, levelParams := [], type := mkConst ``Nat, value := mkRawNatLit 3,
                       hints := .abbrev, safety := .safe })
theorem t (a b : Nat) : a + b = b + a := Nat.add_comm a b
def f (n : Nat) : Nat := match n with | 0 => 1 | n+1 => 2 * f n
#eval f 10
