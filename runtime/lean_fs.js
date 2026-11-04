// File system, stream redirection, process/socket/dynlib stubs for the IR runtime (self-007).
// Node: real files via `fs`. Elsewhere (browser): a tiny in-memory file system `vfs` (Map path → Uint8Array), exported by
// lean_rt.js as `vfs` so a host page can preload files (e.g. .olean files for the elaborator).
// Installed into `prims` by lean_rt.js.

const enc = new TextEncoder(), dec_ = new TextDecoder();

export function install(P, h) {
  const { inc, dec, okR, errR, some, mkBytes, unit, nodeFs, vfs, getStdStreams, setStdStreams, olean } = h;

  /* ---- IO.Error values (constructor tags of `IO.Error`) ---- */
  // tags: alreadyExists 0 (Option filename), otherError 1, unsupportedOperation 4, noFileOrDirectory 11 (filename), invalidArgument…noSuchThing 12–16 (Option filename)
  const ioErr = (tag, details, filename) => {
    if (tag === 11) return { t: 11, rc: 1, n: 2, a0: filename ?? "", a1: details, s2_0: 2 };
    if (tag === 0 || (tag >= 12 && tag <= 16)) return { t: tag, rc: 1, n: 2, a0: filename === undefined ? 0 : some(filename), a1: details, s2_0: 0 };
    return { t: tag, rc: 1, n: 1, a0: details, s1_0: 0 };
  };
  const userError = (msg) => ({ t: 18, rc: 1, n: 1, a0: msg });
  const fail = (e, path) => {                                   // Node/system error → IO.Error
    const code = e && e.code;
    if (code === "ENOENT") return errR(ioErr(11, "no such file or directory", path));
    if (code === "EEXIST") return errR(ioErr(0, "file exists", path));
    if (code === "EACCES" || code === "EPERM") return errR(ioErr(13, "permission denied", path));
    if (code === "EISDIR" || code === "ENOTDIR") return errR(ioErr(15, e.message, path));
    return errR(ioErr(1, String((e && e.message) || e)));
  };
  const unsupported = (what) => () => errR(ioErr(4, `${what} is not supported in this JavaScript runtime`));

  /* ---- handles ---- */
  class Handle { constructor(impl) { this.impl = impl; this.rc = 1; } }
  const MODES = ["r", "w", "wx", "r+", "a"];
  function openFile(path, mode) {
    if (nodeFs) return { fd: nodeFs.openSync(path, MODES[mode]), pos: null };
    const exists = vfs.has(path);
    if ((mode === 0 || mode === 3) && !exists) { const e = new Error("no such file"); e.code = "ENOENT"; throw e; }
    if (mode === 2 && exists) { const e = new Error("exists"); e.code = "EEXIST"; throw e; }
    if (mode === 1 || mode === 2 || !exists) vfs.set(path, new Uint8Array(0));
    return { path, pos: mode === 4 ? vfs.get(path).length : 0 };
  }
  function readBytes(hd, n) {
    if (nodeFs) {
      const buf = Buffer.alloc(n); const k = nodeFs.readSync(hd.fd, buf, 0, n, null);
      return new Uint8Array(buf.buffer, buf.byteOffset, k).slice();
    }
    const data = vfs.get(hd.path) || new Uint8Array(0);
    const r = data.slice(hd.pos, hd.pos + n); hd.pos += r.length; return r;
  }
  function writeBytes(hd, bytes) {
    if (nodeFs) { let off = 0; while (off < bytes.length) off += nodeFs.writeSync(hd.fd, bytes, off); return; }
    const data = vfs.get(hd.path) || new Uint8Array(0);
    const out = new Uint8Array(Math.max(data.length, hd.pos + bytes.length)); out.set(data); out.set(bytes, hd.pos);
    vfs.set(hd.path, out); hd.pos += bytes.length;
  }
  P.lean_io_prim_handle_mk = (path, mode) => {
    try { return okR(new Handle(openFile(path, mode))); } catch (e) { return fail(e, path); }
  };
  P.lean_io_prim_handle_read = (hd, n) => {
    try { return okR(mkBytes(readBytes(hd.impl, Number(n)))); } catch (e) { return fail(e); }
  };
  P.lean_io_prim_handle_write = (hd, bytes) => {
    try { writeBytes(hd.impl, bytes); return okR(unit); } catch (e) { return fail(e); }
  };
  P.lean_io_prim_handle_put_str = (hd, s) => {
    try { writeBytes(hd.impl, enc.encode(s)); return okR(unit); } catch (e) { return fail(e); }
  };
  P.lean_io_prim_handle_get_line = (hd) => {
    try {
      const bytes = [];
      for (;;) {
        const b = readBytes(hd.impl, 1);
        if (b.length === 0) break;
        bytes.push(b[0]);
        if (b[0] === 10) break;
      }
      return okR(dec_.decode(new Uint8Array(bytes)));
    } catch (e) { return fail(e); }
  };
  P.lean_io_prim_handle_flush = (_hd) => okR(unit);
  P.lean_io_prim_handle_is_tty = (_hd) => 0;
  P.lean_io_prim_handle_lock = (_hd, _ex) => okR(unit);
  P.lean_io_prim_handle_try_lock = (_hd, _ex) => okR(1);
  P.lean_io_prim_handle_unlock = (_hd) => okR(unit);
  P.lean_io_prim_handle_rewind = (hd) => {
    if (nodeFs) { try { hd.impl.pos = null; return okR(unit); } catch (e) { return fail(e); } }
    hd.impl.pos = 0; return okR(unit);
  };
  P.lean_io_prim_handle_truncate = (hd) => {
    if (!nodeFs) { vfs.set(hd.impl.path, (vfs.get(hd.impl.path) || new Uint8Array(0)).slice(0, hd.impl.pos)); return okR(unit); }
    try { nodeFs.ftruncateSync(hd.impl.fd, 0); return okR(unit); } catch (e) { return fail(e); }
  };

  /* ---- file system queries ---- */
  P.lean_io_realpath = (path) => {
    if (nodeFs) { try { return okR(nodeFs.realpathSync(path)); } catch (e) { return fail(e, path); } }
    return okR(path);
  };
  const sysTime = (ms) => ({ t: 0, rc: 1, n: 1, a0: BigInt(Math.floor(ms / 1000)), s1_0: Math.floor((ms % 1000) * 1e6) });
  P.lean_io_metadata = (path) => {
    let size, type, atime = 0, mtime = 0;
    if (nodeFs) {
      try {
        const st = nodeFs.statSync(path);
        size = BigInt(st.size); type = st.isDirectory() ? 0 : st.isFile() ? 1 : 3; atime = st.atimeMs; mtime = st.mtimeMs;
      } catch (e) { return fail(e, path); }
    } else {
      if (vfs.has(path)) { size = BigInt(vfs.get(path).length); type = 1; }
      else if ([...vfs.keys()].some((k) => k.startsWith(path.replace(/\/$/, "") + "/"))) { size = 0n; type = 0; }
      else return errR(ioErr(11, "no such file or directory", path));
    }
    // IO.FS.Metadata: objects accessed, modified; scalars byteSize @0, numLinks @8, type @16
    return okR({ t: 0, rc: 1, n: 2, a0: sysTime(atime), a1: sysTime(mtime), s2_0: size, s2_8: 1n, s2_16: type });
  };


  const sync = (path, nodeOp, vfsOp) => {
    try { if (nodeFs) nodeOp(); else vfsOp(); return okR(unit); } catch (e) { return fail(e, path); }
  };
  const enoent = () => { const e = new Error("no such file or directory"); e.code = "ENOENT"; return e; };
  P.lean_io_remove_file = (path) => sync(path, () => nodeFs.unlinkSync(path), () => { if (!vfs.delete(path)) throw enoent(); });
  P.lean_io_remove_dir = (path) => sync(path, () => nodeFs.rmdirSync(path), () => {});
  P.lean_io_create_dir = (path) => sync(path, () => nodeFs.mkdirSync(path), () => {});
  P.lean_io_rename = (a, b) => sync(a, () => nodeFs.renameSync(a, b), () => { if (!vfs.has(a)) throw enoent(); vfs.set(b, vfs.get(a)); vfs.delete(a); });
  P.lean_io_hard_link = (a, b) => sync(a, () => nodeFs.linkSync(a, b), () => { if (!vfs.has(a)) throw enoent(); vfs.set(b, vfs.get(a)); });
  P.lean_io_current_dir = () => okR(nodeFs ? globalThis.process.cwd() : "/");
  P.lean_io_symlink_metadata = (path) => P.lean_io_metadata(path);
  P.lean_io_read_dir = (path) => {
    let names;
    try {
      if (nodeFs) names = nodeFs.readdirSync(path);
      else {
        const pre = path.replace(/\/$/, "") + "/";
        names = [...new Set([...vfs.keys()].filter((k) => k.startsWith(pre)).map((k) => k.slice(pre.length).split("/")[0]))];
      }
    } catch (e) { return fail(e, path); }
    const arr = names.map((n) => ({ t: 0, rc: 1, n: 2, a0: path, a1: n }));
    arr.rc = 1;
    return okR(arr);
  };

  /* ---- .olean files: CompactedRegion.read / free (the region id is its base address) ---- */
  P.lean_compacted_region_read = (path, _deps) => {
    let bytes;
    try { bytes = nodeFs ? nodeFs.readFileSync(path) : vfs.get(path); } catch (e) { return fail(e, path); }
    if (bytes === undefined) return errR(ioErr(11, "no such file or directory", path));
    try {
      const region = olean.parseRegion(bytes, [], olean.hooks, path);
      return okR({ t: 0, rc: 1, n: 2, a0: region.root, a1: BigInt(region.base) });
    } catch (e) { return errR(userError(String(e && e.message || e))); }
  };
  P.lean_compacted_region_free = (base) => { olean.freeRegion(Number(base)); return okR(unit); };
  P.lean_compacted_region_save = unsupported(".olean writing");

  /* ---- redirection of the standard streams (thread-local in native Lean; global here) ---- */
  P.lean_get_set_stdout = (s) => { const old = getStdStreams().out; setStdStreams({ out: s }); return old; };
  P.lean_get_set_stderr = (s) => { const old = getStdStreams().err; setStdStreams({ err: s }); return old; };
  P.lean_get_set_stdin = (s) => { const old = getStdStreams().in; setStdStreams({ in: s }); return old; };

  /* ---- time ---- */
  P.lean_get_current_time = () => {                       // Timestamp = Duration {second : Int, nano : Int}
    const ms = Date.now();
    return okR({ t: 0, rc: 1, n: 2, a0: BigInt(Math.floor(ms / 1000)), a1: BigInt((ms % 1000) * 1000000) });
  };
  P.lean_windows_get_next_transition = unsupported("Windows time zone lookup");

  /* ---- unsupported: processes, sockets, timers, dynamic loading, native evaluation ---- */
  P.lean_io_process_spawn = unsupported("process spawning");
  P.lean_io_process_child_wait = unsupported("process spawning");
  for (const n of ["tcp_new", "tcp_bind", "tcp_listen", "tcp_accept", "tcp_try_accept", "tcp_cancel_accept", "tcp_cancel_recv",
    "tcp_getpeername", "tcp_getsockname", "tcp_nodelay", "tcp_recv", "tcp_send", "tcp_wait_readable", "timer_mk", "timer_next",
    "timer_cancel", "ntop_v4", "ntop_v6", "pton_v4", "pton_v6"]) P["lean_uv_" + n] = unsupported("libuv networking");
  P.lean_dynlib_load = unsupported("dynamic library loading");
  P.lean_dynlib_get = () => 0;
  P.lean_dynlib_symbol_run_as_init = unsupported("dynamic library loading");
  P.lean_eval_const = (_env, _opts, _name) => ({ t: 0, rc: 1, n: 1, a0: "native evaluation (evalConst) is not supported in this JavaScript runtime" });   // Except.error
}
