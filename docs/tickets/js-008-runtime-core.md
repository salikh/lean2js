# JS runtime: pure primitives

Parent: [js-001-transpiler-epic](js-001-transpiler-epic.md)

Status: open. Depends on js-004 (value representation).

## Goal

`runtime/lean_runtime.js` (ES module, no dependencies, works in browsers and Node) implementing the
non-IO primitives that Lean code reaches via `@[extern]`/builtin:

* Nat/Int: `add sub mul div mod pow gcd log2 shiftLeft/Right land lor xor decEq decLt decLe beq blt`,
  `Nat.sub` truncating, `Int` ops incl. `Int.div/ediv/emod/tdiv/tmod` semantic variants (consult Lean
  docs / `src/runtime/object.cpp`, `lean.h`).
* UInt8/16/32/64/USize/Char: arithmetic with wraparound, comparisons, conversions (`ofNat`, `toNat`, `toUInt*`).
* Float: arithmetic, `toString`, `ofScientific`, math functions, `floor/ceil`, bit casts.
* String: `append push length utf8ByteSize get extract next prev atEnd decEq lt hash`, `String.Pos` as UTF-8
  byte offsets, `toUTF8`/`fromUTF8`, `String.mk`/`data` (List Char conversions).
* Array/ByteArray/FloatArray: `mkEmpty push get set size uset swap pop extract` (copy-on-write),
  `Array.mkArray`, `getD/get!` with panic on out-of-bounds.
* `hash` functions (`mixHash`, `String.hash`, `Nat.hash`, `UInt64` hashing) — **bit-exact with native Lean**
  (so `HashMap` iteration order matches); MurmurHash64A in `src/runtime/hash.cpp`.
* closures: `pap`, `apply` (arity-tagged functions).
* `panic`, `dbgTrace`, `unreachable`, `lcProof`, `lcUnreachable` helpers.

The set of needed primitives is *driven by the `externs` list* produced by js-006 for real programs: build
a script that diffs `externs` of the test corpus against implemented names and reports missing ones.

## Acceptance

Unit tests (`tests/js/runtime.test.mjs`, run with `node --test`) for each primitive family, with
expected values taken from native Lean `#eval` output.
