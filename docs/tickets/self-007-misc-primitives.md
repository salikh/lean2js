# Remaining runtime primitives (non-Expr)

Parent: [self-001](self-001-compiler-to-js-epic.md) | see js-014 item 2
Status: **partly done** (2026-11-04)

Int64 ops, `lean_ptr_addr` (object identity ids via WeakMap), `lean_runtime_mark_persistent/forget`, `lean_strict_or`,
`lean_void_mk`, platform queries, heartbeats get/set (`lean_io_get/set_num_heartbeats`), `lean_io_get_tid`,
`lean_internal_get_hardware_concurrency` (=1), promises (`new/resolve/result_opt`), `lean_io_get_task_state`, BaseMutex (no-op),
`lean_profileit` (just call), `lean_option_get_or_block`, handles (`prim_handle_mk/put_str/read` in Node via fs; browser: in-memory FS),
`io_metadata`, `realpath`, process spawn (fail), uv sockets/timers (stub as IO error). Tasks must be cooperative (eager).
Test: `tests/e2e` programs using each; extend `tests/e2e/missing.mjs` to take a JS file argument.

## Progress (2026-11-04)

Done in `runtime/lean_rt.js` ("self-007" block): Int64 family (BigInt; narrower signed widths not yet), promises (`new/resolve/result_opt`; a
`result?` task over an unresolved promise throws "deadlock" when waited — no scheduler), `option_get_or_block`, task state, tid, hardware concurrency,
BaseMutex no-ops, heartbeats (counter stays 0, so `maxHeartbeats` never fires), `profileit`, `mark_persistent`, `forget`, `strict_or`, `void_mk`,
platform queries, `string_is_valid_pos`, `float_isnan/isinf`, `ptr_addr` (WeakMap ids). Test: `tests/e2e/prims2.lean`.
Also done: `runtime/lean_fs.js` — file handles (Node `fs`; in-memory `vfs` Map elsewhere), metadata, realpath, read/remove/rename/create dir,
std stream redirection (`setStdout` etc.), `Std.Time` now, error stubs for process spawn / sockets / timers / dynlib / `evalConst`. Test: `tests/e2e/fs.lean`.
Still open: file handles/metadata/realpath/process, uv sockets/timers stubs, dynlib/`eval_const`/`run_init` (see self-003), compacted region (self-006),
Condvar, real scheduler for tasks if the elaborator needs to block on promises.

## Browser file system: OPFS (user hint, 2026-11-04)

Checked: Node 24.21 has `navigator` but **no `navigator.storage` / OPFS**, so Node keeps using `fs`. In the browser OPFS
(`navigator.storage.getDirectory()`) is available; its *synchronous* API (`FileSystemSyncAccessHandle` via `createSyncAccessHandle()`:
`read/write/truncate/flush/getSize` at offsets) exists only in dedicated Web Workers — which matches our execution model (run the Lean
program in a Worker; the runtime is synchronous). Plan: make the backend in `runtime/lean_fs.js` pluggable (`node:fs` | OPFS sync handles in
a Worker | in-memory `vfs` fallback on the main thread). Needs the directory tree walk (`getDirectoryHandle`) to be async, so preload/mount step:
before `main` runs, the host (async) opens the needed handles or mirrors OPFS into `vfs` and flushes back on `close`/`flush`. Not implemented yet.
Useful for: persisting `.olean` caches (self-006) and user files across page reloads.
