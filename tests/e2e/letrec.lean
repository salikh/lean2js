def process (xs : List Nat) : Nat :=
  go xs 0
where
  go : List Nat → Nat → Nat
    | [], acc => acc
    | x :: rest, acc => go rest (acc + x * x)

def digits (n : Nat) : List Nat :=
  let rec loop (n : Nat) (acc : List Nat) (fuel : Nat) : List Nat :=
    match fuel with
    | 0 => acc
    | fuel+1 => if n < 10 then n :: acc else loop (n / 10) (n % 10 :: acc) fuel
  loop n [] 100

def fizz (n : Nat) : String :=
  match n % 3, n % 5 with
  | 0, 0 => "FizzBuzz"
  | 0, _ => "Fizz"
  | _, 0 => "Buzz"
  | _, _ => toString n

def finTest (i : Fin 5) : Nat := i.val * 2

def main : IO Unit := do
  IO.println (process [1,2,3,4])
  IO.println (digits 90210)
  IO.println ((List.range 16).map fizz)
  IO.println (finTest 3)
  IO.println ((List.range 5).map fun i => (i, i * i))
  IO.println (String.intercalate ", " ["a", "b", "c"])
  IO.println (Nat.toDigits 2 37)
  IO.println ((255 : Nat).toDigits 16)
  IO.println ("-42".toInt?)
  IO.println ("abc".toInt?)
  IO.println (List.lookup 2 [(1, "a"), (2, "b")])
