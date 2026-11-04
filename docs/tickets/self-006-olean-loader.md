# .olean loader in JS

Parent: [self-001](self-001-compiler-to-js-epic.md)
Status: open

`lean_compacted_region_read` / `readModuleData` must turn an `.olean` file (compacted region: header with
base address + root pointer, objects laid out as `lean_object` headers, little-endian, pointers relative to base)
into our IR-backend object representation (`{t, rc:0 (persistent), n, a0...}`, Nat/Int bigints, strings as JS strings,
scalar arrays -> typed arrays, `Array`, `ByteArray`, thunks/tasks). Needs per-object tags: ctor (tag, num_objs, scalar size),
closure (not present), array, sarray, string, mpz, thunk, task, ref. Format description: `src/runtime/compact.cpp` (not shipped;
decode empirically from files in `$(lean --print-prefix)/lib/lean/**/*.olean`). Validate by loading Init.olean and comparing
`ModuleData` constants count with native `lean --run`. Browser: load via fetch + ArrayBuffer; consider a prebuilt index/subset.
