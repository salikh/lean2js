# Question: JS representation of Lean values

Parent: [js-001-transpiler-epic](js-001-transpiler-epic.md)

Status: **decided (2026-11-04)**: the recommended answer was accepted. Reopen by moving this ticket to "TODO for humans" in TODO.md.

## Question

How are Lean values represented in JavaScript? This is the central runtime ABI
(used by codegen and runtime library) and hard to change later.

## Recommended answer

| Lean | JS |
|---|---|
| `Nat`, `Int` | `BigInt` always (correct first; optimize later with small-int fast path behind the runtime API, e.g. `Nat.add(a,b)`) |
| `UInt8/16/32`, `Char` | JS `number` (masked after arithmetic) |
| `UInt64`, `USize` | `BigInt` (masked `& 0xFFFFFFFFFFFFFFFFn`; USize = 64-bit) |
| `Float` | `number` |
| `Bool`, other enum-like inductives (all ctors without fields) | `number` = ctor index (`false`=0, `true`=1) |
| `Unit`/`PUnit` and other erased values | `0` (a shared constant `erased`) |
| structure/inductive ctor with fields | JS object `{tag: cidx, f: [fields…]}` — or arrays `[tag, f0, f1…]` (decide by micro-benchmark; start with class-free objects `{t, a0, a1,…}`) |
| `String` | JS `string` (UTF-16); runtime functions convert for byte-position-based APIs (`String.utf8ByteSize`, `String.Pos` are UTF-8 byte offsets; correctness here needs care) |
| `Array α` | JS `Array`, treated as persistent (copy on write; optimization with uniqueness deferred) |
| `ByteArray` | `Uint8Array` (copy on write) |
| `List`, `Option`, … | ordinary ctor objects (no special case) |
| closures | JS functions, curried by arity: partial application via runtime `pap(f, arity, args)` |
| `Thunk`, `Task`, `IO.Ref` | runtime classes (see js-009) |
| `Decidable` | `Bool` (as Lean does) |

Types with special runtime representation in the Lean compiler (`Nat`, `Int`, `UIntN`, `Float`, `Char`,
`String`, `Array`, `ByteArray`, `FloatArray`, `Thunk`, `Task`, `Decidable`) must be matched by their
`cases`/constructor/projection usage (e.g. `cases` on `Nat` with `Nat.zero`/`Nat.succ` alternatives
becomes a comparison with `0n`).

## Alternatives

* `Nat` as `number` with overflow to `BigInt` (faster, more complex invariants).
* Tagged arrays for constructors (smaller, faster allocation; harder to debug).

## If revised

Affects js-007 (codegen), js-008/009 (runtime), js-011 goldens.
