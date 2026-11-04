/-- Cooperative tasks and promises: spawn, map, bind, wait, promises resolved after the waiter started. -/
def main : IO Unit := do
  let t1 := Task.spawn fun _ => (List.range 1000).foldl (· + ·) 0
  let t2 := t1.map (· * 2)
  let t3 := t2.bind fun x => Task.spawn fun _ => x + 1
  IO.println s!"{t1.get} {t2.get} {t3.get}"
  let io1 ← IO.asTask (do IO.println "in asTask"; return 21)
  let io2 ← IO.mapTask (fun r => do return (r.toOption.getD 0) * 2) io1
  IO.println s!"{(← IO.wait io2).toOption}"
  let p ← IO.Promise.new (α := Nat)
  let waiter := p.result!.map (· + 100)
  let resolver ← IO.asTask (do p.resolve 5; return ())
  IO.println s!"{waiter.get}"
  let _ ← IO.wait resolver
  let ts := (List.range 5).map fun i => Task.spawn fun _ => i * i
  IO.println s!"{ts.map Task.get}"
  let any ← IO.waitAny [Task.spawn fun _ => 7, Task.spawn fun _ => 8]
  IO.println s!"{any == 7 || any == 8}"
  IO.println (← IO.getNumHeartbeats |>.map (fun _ => "done"))
