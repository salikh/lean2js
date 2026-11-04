# Remaining runtime primitives (non-Expr)

Parent: [self-001](self-001-compiler-to-js-epic.md) | see js-014 item 2
Status: open

Int64 ops, `lean_ptr_addr` (object identity ids via WeakMap), `lean_runtime_mark_persistent/forget`, `lean_strict_or`,
`lean_void_mk`, platform queries, heartbeats get/set (`lean_io_get/set_num_heartbeats`), `lean_io_get_tid`,
`lean_internal_get_hardware_concurrency` (=1), promises (`new/resolve/result_opt`), `lean_io_get_task_state`, BaseMutex (no-op),
`lean_profileit` (just call), `lean_option_get_or_block`, handles (`prim_handle_mk/put_str/read` in Node via fs; browser: in-memory FS),
`io_metadata`, `realpath`, process spawn (fail), uv sockets/timers (stub as IO error). Tasks must be cooperative (eager).
Test: `tests/e2e` programs using each; extend `tests/e2e/missing.mjs` to take a JS file argument.
