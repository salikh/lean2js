# .olean loader (self-006)

`runtime/lean_olean.js` implements `CompactedRegion.read` (`lean_compacted_region_read`) for the JS runtime; `lean_fs.js` wires it to
the file system (Node `fs` or the in-memory `vfs`). `importModules` of real `Init` oleans works in JS (`tests/e2e/import.lean`,
`tests/e2e/olean.lean`; both differential against native).

## Format (v2, Lean 4.35)

88-byte header (`"olean"`, version 2, Lean version, git hash, **base address** at offset 80), a root pointer at 88, then objects from 96,
children before parents, 8-byte aligned. A pointer is a boxed scalar `(n << 1) | 1` or `base + file offset` (pointers into a *dependency*
region — the `.olean.private`/`.server` parts — resolve through the registry of loaded regions). Object kinds: constructor (`other` =
#object fields, `cs_sz` = size, then pointers, then raw scalar bytes), Array, ScalarArray, String, MPZ (GMP layout: alloc, size/sign, limb
pointer, limbs), Thunk, Task, Ref. Closures only exist in the experimental v3 format (not supported).
A single linear scan builds all objects (an offset-indexed table resolves child pointers).

## Representation decisions

1. **Boxed scalars become JS numbers** (BigInt beyond 2^53), whatever their static type — the file carries no types. A small `Nat` in a
   loaded object is therefore a number, whereas computed `Nat`s are BigInts. All `lean_nat_*`/`lean_int_*`/`*_of_nat`/`*_of_int` primitives
   accept both (wrapper block "Nat/Int tolerance" in lean_rt.js); `===` on Nats outside primitives must use `==` (done in lean_expr.js).
   *Known limitation:* a boxed small **Int** is a 32-bit two's complement pattern in the file; we read it as an unsigned Nat, so negative `Int`s
   inside oleans would come out wrong (none seen in Init/Lean oleans so far).
2. **Scalar fields are decoded lazily.** The constructor's scalar area (u8/u16/u32/u64/usize/float fields, e.g. `Name.hash`,
   `Expr.data`, binder info) has no type information at load time, so the loaded object keeps `sbuf` (DataView of the file) and `soff`.
   `CodegenIR` emits `y.s2_0 ?? rt.sget(y, 2, 0, 8)` (type code 1/2/4/8/9/10) and `y.u3 ?? rt.uget(y, 3)` for `sproj`/`uproj`; `sget` decodes
   and caches the value as the `s<n>_<off>` property, so objects built in JS pay only one `??`.
3. Loaded objects are persistent (`rc = 0`): never freed, never mutated in place.

## Not done / next

* Memory: everything is decoded eagerly (≈ 60 MB of `Init` oleans → a few hundred MB of JS objects). Lazy per-array decoding or chunk
  loading will be needed for `import Lean`; see self-008. Browser: fetch the files into `vfs` (or OPFS, see self-007) before running.
* `.olean.private`/`.olean.server` parts and `depRegions` are supported structurally but only the public part was tested.
* Writing oleans (`lean_compacted_region_save`) is not implemented.
