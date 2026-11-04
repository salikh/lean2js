// Build/version/platform queries, share-common, misc runtime hooks.

export function install(P, { inc, ap, some, bool, unit, okR, errR, P: _P }) {
  const mkPair = (a, b) => ({ t: 0, rc: 1, n: 2, a0: a, a1: b });
  // Lean version 4.35.0 (release)
  P.lean_version_get_major = () => 4n;
  P.lean_version_get_minor = () => 35n;
  P.lean_version_get_patch = () => 0n;
  P.lean_version_get_is_release = () => 1;
  P.lean_version_get_special_desc = () => "";
  P.lean_get_githash = () => "";
  P.lean_internal_is_stage0 = () => 0;
  P.lean_internal_get_default_max_heartbeat = () => 200000n;
  P.lean_internal_get_default_max_memory = () => 2048n;
  P.lean_internal_get_default_verbose = () => 0;
  P.lean_closure_max_args = () => 16n;
  P.lean_max_small_nat = () => (1n << 63n) - 1n;
  P.lean_get_max_ctor_fields = () => 256n;
  P.lean_get_max_ctor_scalars_size = () => 1024n;
  P.lean_get_max_ctor_tag = () => 244n;
  P.lean_get_usize_size = () => 8n;
  P.lean_manual_get_root = () => "https://lean-lang.org/doc/reference/latest/";
  // Platform: we present ourselves like the official wasm build
  P.lean_system_platform_linux = () => 0;
  P.lean_system_platform_emscripten = () => 1;
  P.lean_system_platform_target = () => "wasm32-unknown-emscripten";

  /* ---- ShareCommon: maximal sharing is only an optimization, so identity is a valid implementation ---- */
  P.lean_sharecommon_eq = (a, b) => bool(a === b);
  P.lean_sharecommon_hash = (a) => P.lean_ptr_addr(a);
  P.lean_state_sharecommon = (_factory, s, a) => mkPair(a, s);
  P.lean_sharecommon_quick = (a) => { inc(a); return a; };

  P.lean_dbg_sleep = (_ms, f) => ap(f, [0]);
  P.lean_io_wait_any = (tasks) => { const t = tasks.a0; inc(t.v); return t.v; };
  P.lean_string_uget_byte_fast = (s, i) => P.lean_string_get_byte_fast(s, i);
  const unsupported = (what) => () => errR({ t: 4, rc: 1, n: 1, a0: `${what} is not supported in this JavaScript runtime`, s1_0: 0 });
  P.lean_io_create_tempfile = unsupported("temporary files");
  P.lean_io_process_child_kill = unsupported("process control");
  P.lean_io_process_child_try_wait = unsupported("process control");
  P.lean_uv_tcp_shutdown = unsupported("libuv networking");
}
