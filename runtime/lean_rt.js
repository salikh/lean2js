// Lean 4 runtime for JavaScript, IR backend (see docs/design/js-transpiler-ir.md).
//
// Mirrors the native runtime's object model closely enough that the reference counts emitted by Lean's IR
// (`inc`/`dec`/`isShared`/`reset`/`reuse`) make in-place updates of arrays and structures safe:
//
//   Nat, Int, UInt64, USize : BigInt          UInt8/16/32, Char, Bool, other scalars : number
//   Float                   : number          String : JS string (immutable, no refcount)
//   nullary constructors / boxed scalars : the number (constructor index)
//   other constructors      : {t: ctorIndex, rc, n: #object fields, a0…a<n-1>, u<i>, s<i>_<off>}
//   Array                   : JS Array with own property `rc`        ByteArray/FloatArray : typed arrays with `rc`
//   closures                : Clo{fn, arity, args, rc}               Thunk, Task, Ref : classes with `rc`
//   rc: reference count; 1 = exclusive, >1 shared, 0 = persistent (never mutated, never freed)
//
// Primitives are named like the C functions of the Lean runtime (lean.h) and live in `prims`.
// Erased and `void` (state token) arguments are not passed to primitives, as in the C ABI.

import { install as installExpr } from "./lean_expr.js";
import { install as installFs } from "./lean_fs.js";
import { parseRegion, freeRegion, sget, uget } from "./lean_olean.js";
import { install as installNum } from "./lean_num.js";
import { install as installSys } from "./lean_sys.js";

export const erased = 0;

const isNode = !!(globalThis.process && globalThis.process.versions && globalThis.process.versions.node);
const nodeFs = isNode ? await import("node:fs") : null;
const nodeWorker = isNode ? await import("node:worker_threads") : null;

/* ---------- reference counting ---------- */

/** Visit the Lean objects directly referenced by heap object `o`. */
function forEachChild(o, f) {
  if (Array.isArray(o)) { for (let i = 0; i < o.length; i++) f(o[i]); return; }
  if (o instanceof Clo) { for (let i = 0; i < o.args.length; i++) f(o.args[i]); return; }
  if (o instanceof Ref) { f(o.v); return; }
  if (o instanceof Thunk) { if (o.c !== null) f(o.c); f(o.v); return; }
  if (o instanceof Task) { if (!o.pend) f(o.v); return; }
  const n = o.n;
  if (n === undefined) return;               // typed arrays etc.
  for (let i = 0; i < n; i++) f(o["a" + i]);
}

export function inc(x) { if (typeof x === "object" && x.rc > 0) x.rc++; }
export function incN(x, n) { if (typeof x === "object" && x.rc > 0) x.rc += n; }
export function dec(x) {
  if (typeof x !== "object") return;
  const rc = x.rc;
  if (rc > 1) x.rc = rc - 1;
  else if (rc === 1) free(x);
}
/** `x` died: release its children (iteratively, to survive long lists). */
function free(root) {
  const stack = [root];
  root.rc = -1;
  while (stack.length > 0) {
    const o = stack.pop();
    if (o instanceof Promise_ && o.task.pend) dropPromise(o);        // last reference to an unresolved promise: it resolves with `none`
    forEachChild(o, (c) => {
      if (typeof c !== "object") return;
      const rc = c.rc;
      if (rc > 1) c.rc = rc - 1;
      else if (rc === 1) { c.rc = -1; stack.push(c); }
    });
  }
}
/** Mark `x` and everything reachable from it persistent (rc = 0): used for global constants. */
export function persist(x) {
  if (typeof x !== "object" || !(x.rc > 0)) return;
  const stack = [x];
  x.rc = 0;
  while (stack.length > 0) {
    const o = stack.pop();
    forEachChild(o, (c) => { if (typeof c === "object" && c.rc > 0) { c.rc = 0; stack.push(c); } });
  }
}
export function isShared(x) { return typeof x === "object" && x.rc === 1 ? 0 : 1; }
/** `reset n x`: if `x` is exclusive release its `n` object fields and return it for reuse, else `dec x` and return box(0). */
export function reset(x, n) {
  if (x.rc === 1) {
    for (let i = 0; i < n; i++) { dec(x["a" + i]); x["a" + i] = 0; }
    return x;
  }
  dec(x);
  return 0;
}
const exclusive = (x) => x.rc === 1;

/* ---------- closures ---------- */

export class Clo {
  constructor(fn, arity, args) { this.fn = fn; this.arity = arity; this.args = args; this.rc = 1; }
}
export function pap(fn, arity, args) { return new Clo(fn, arity, args); }

/** Apply closure `f` to `args`; both are owned (consumed), like `lean_apply_n`. */
export function ap(f, args) {
  for (;;) {
    const fixed = f.args.length, have = fixed + args.length;
    if (have < f.arity) {
      const all = f.args.concat(args);
      if (f.rc !== 1) { for (let i = 0; i < fixed; i++) inc(f.args[i]); dec(f); }
      return new Clo(f.fn, f.arity, all);
    }
    const need = f.arity - fixed;
    const call = fixed === 0 ? (need === args.length ? args : args.slice(0, need))
      : f.args.concat(need === args.length ? args : args.slice(0, need));
    if (f.rc !== 1) { for (let i = 0; i < fixed; i++) inc(f.args[i]); dec(f); }
    const r = f.fn(...call);
    if (have === f.arity) return r;
    f = r;
    args = args.slice(need);
  }
}

export function missing(key) {
  return function () { throw new Error(`lean2js runtime: missing primitive '${key}'`); };
}
export function unreachable() { throw new Error("lean2js runtime: unreachable code executed"); }

/* ---------- helpers ---------- */

const bool = (b) => (b ? 1 : 0);
const unit = 0;
const none = () => 0;
const some = (v) => ({ t: 1, rc: 1, n: 1, a0: v });
const cons = (h, tl) => ({ t: 1, rc: 1, n: 2, a0: h, a1: tl });
/** Build a Lean list from a JS array of owned elements. */
export function listFromArray(xs) {
  let l = 0;
  for (let i = xs.length - 1; i >= 0; i--) l = cons(xs[i], l);
  return l;
}
/** Elements of a Lean list as JS array (borrowed: no refcount changes). */
export function listToArray(l) {
  const r = [];
  while (typeof l === "object") { r.push(l.a0); l = l.a1; }
  return r;
}
const okR = (v) => ({ t: 0, rc: 1, n: 1, a0: v });      // EST.Out.ok / Except.ok-like IO result
const errR = (e) => ({ t: 1, rc: 1, n: 1, a0: e });

/* ---------- primitives ---------- */

export const prims = {};
/** Compiled Lean functions registered by the generated program under their `@[export]` symbol (e.g. `lean_expr_mk_app`). */
export const exports = {};
const P = prims;

let stdoutSink, stderrSink;
function panicMsg(msg) { stderrSink(msg + "\n"); }
P.lean_panic_fn_borrowed = (def, msg) => { panicMsg(msg); inc(def); return def; };
P.lean_panic_fn = (def, msg) => { panicMsg(msg); return def; };
P.lean_system_platform_nbits = (_u) => 64n;
P.lean_dbg_trace = (s, f) => { stderrSink(s + "\n"); return ap(f, [0]); };

/* ---- Nat ---- */
P.lean_nat_add = (a, b) => a + b;
P.lean_nat_sub = (a, b) => (a > b ? a - b : 0n);
P.lean_nat_mul = (a, b) => a * b;
P.lean_nat_div = (a, b) => (b === 0n ? 0n : a / b);
P.lean_nat_mod = (a, b) => (b === 0n ? a : a % b);
P.lean_nat_pred = (a) => (a > 0n ? a - 1n : 0n);
P.lean_nat_succ = (a) => a + 1n;
P.lean_nat_dec_eq = (a, b) => bool(a === b);
P.lean_nat_dec_lt = (a, b) => bool(a < b);
P.lean_nat_dec_le = (a, b) => bool(a <= b);
P.lean_nat_pow = (a, b) => a ** b;
P.lean_nat_gcd = (a, b) => { while (b !== 0n) { [a, b] = [b, a % b]; } return a; };
P.lean_nat_log2 = (a) => (a === 0n ? 0n : BigInt(a.toString(2).length - 1));
P.lean_nat_land = (a, b) => a & b;
P.lean_nat_lor = (a, b) => a | b;
P.lean_nat_lxor = (a, b) => a ^ b;
P.lean_nat_shiftl = (a, b) => a << b;
P.lean_nat_shiftr = (a, b) => a >> b;
P.lean_nat_to_int = (a) => a;
P.lean_nat_abs = (a) => (a < 0n ? -a : a);

/* ---- Int ---- */
P.lean_int_add = (a, b) => a + b;
P.lean_int_sub = (a, b) => a - b;
P.lean_int_mul = (a, b) => a * b;
P.lean_int_neg = (a) => -a;
P.lean_int_div = (a, b) => (b === 0n ? 0n : a / b);                 // T-rounding
P.lean_int_mod = (a, b) => (b === 0n ? a : a % b);
P.lean_int_ediv = (a, b) => {
  if (b === 0n) return 0n;
  let q = a / b; const r = a % b;
  if (r < 0n) q = b > 0n ? q - 1n : q + 1n;
  return q;
};
P.lean_int_emod = (a, b) => {
  if (b === 0n) return a;
  let r = a % b;
  if (r < 0n) r += b < 0n ? -b : b;
  return r;
};
P.lean_int_dec_eq = (a, b) => bool(a === b);
P.lean_int_dec_lt = (a, b) => bool(a < b);
P.lean_int_dec_le = (a, b) => bool(a <= b);
P.lean_int_dec_nonneg = (a) => bool(a >= 0n);
P.lean_int_neg_succ_of_nat = (a) => -a - 1n;
P.lean_int_land = (a, b) => a & b;
P.lean_int_lor = (a, b) => a | b;
P.lean_int_xor = (a, b) => a ^ b;
P.lean_int_shiftr = (a, b) => a >> b;
P.lean_int_to_nat = (a) => (a < 0n ? 0n : a);

/* ---- fixed width unsigned integers ---- */
function defUInt(name, bits) {
  const big = bits === 64;
  if (big) {
    const m = (x) => BigInt.asUintN(64, x);
    const ob = BigInt(bits);
    P[`lean_${name}_add`] = (a, b) => m(a + b);
    P[`lean_${name}_sub`] = (a, b) => m(a - b);
    P[`lean_${name}_mul`] = (a, b) => m(a * b);
    P[`lean_${name}_div`] = (a, b) => (b === 0n ? 0n : a / b);
    P[`lean_${name}_mod`] = (a, b) => (b === 0n ? a : a % b);
    P[`lean_${name}_land`] = (a, b) => a & b;
    P[`lean_${name}_lor`] = (a, b) => a | b;
    P[`lean_${name}_xor`] = (a, b) => a ^ b;
    P[`lean_${name}_shift_left`] = (a, b) => m(a << (b % ob));
    P[`lean_${name}_shift_right`] = (a, b) => a >> (b % ob);
    P[`lean_${name}_complement`] = (a) => m(~a);
    P[`lean_${name}_neg`] = (a) => m(-a);
    P[`lean_${name}_log2`] = (a) => (a === 0n ? 0n : BigInt(a.toString(2).length - 1));
    P[`lean_${name}_of_nat`] = (n) => m(n);
    P[`lean_${name}_of_nat_mk`] = P[`lean_${name}_of_nat`];
    P[`lean_${name}_to_nat`] = (a) => a;
    P[`lean_${name}_dec_eq`] = (a, b) => bool(a === b);
    P[`lean_${name}_dec_lt`] = (a, b) => bool(a < b);
    P[`lean_${name}_dec_le`] = (a, b) => bool(a <= b);
  } else {
    const mask = bits === 32 ? 0xffffffff : (1 << bits) - 1;
    const m = bits === 32 ? (x) => x >>> 0 : (x) => x & mask;
    P[`lean_${name}_add`] = (a, b) => m(a + b);
    P[`lean_${name}_sub`] = (a, b) => m(a - b);
    P[`lean_${name}_mul`] = bits === 32 ? (a, b) => Math.imul(a, b) >>> 0 : (a, b) => m(a * b);
    P[`lean_${name}_div`] = (a, b) => (b === 0 ? 0 : Math.floor(a / b));
    P[`lean_${name}_mod`] = (a, b) => (b === 0 ? a : a % b);
    P[`lean_${name}_land`] = (a, b) => m(a & b);
    P[`lean_${name}_lor`] = (a, b) => m(a | b);
    P[`lean_${name}_xor`] = (a, b) => m(a ^ b);
    P[`lean_${name}_shift_left`] = (a, b) => m(a << (b % bits));
    P[`lean_${name}_shift_right`] = (a, b) => a >>> (b % bits);
    P[`lean_${name}_complement`] = (a) => m(~a);
    P[`lean_${name}_neg`] = (a) => m(-a);
    P[`lean_${name}_log2`] = (a) => (a === 0 ? 0 : 31 - Math.clz32(a));
    P[`lean_${name}_of_nat`] = (n) => Number(BigInt.asUintN(bits, n));
    P[`lean_${name}_of_nat_mk`] = P[`lean_${name}_of_nat`];
    P[`lean_${name}_to_nat`] = (a) => BigInt(a);
    P[`lean_${name}_dec_eq`] = (a, b) => bool(a === b);
    P[`lean_${name}_dec_lt`] = (a, b) => bool(a < b);
    P[`lean_${name}_dec_le`] = (a, b) => bool(a <= b);
  }
}
const widths = { uint8: 8, uint16: 16, uint32: 32, uint64: 64, usize: 64 };
for (const [n, b] of Object.entries(widths)) defUInt(n, b);
// conversions between widths
for (const [from, fb] of Object.entries(widths)) {
  for (const [to, tb] of Object.entries(widths)) {
    if (from === to) continue;
    const fbig = fb === 64, tbig = tb === 64;
    P[`lean_${from}_to_${to}`] =
      fbig && tbig ? (a) => a
      : fbig ? (a) => Number(BigInt.asUintN(tb, a))
      : tbig ? (a) => BigInt(a)
      : (a) => (tb >= fb ? a : a & ((1 << tb) - 1));
  }
}
P.lean_bool_to_uint8 = (b) => b;
P.lean_bool_to_uint16 = (b) => b;
P.lean_bool_to_uint32 = (b) => b;
P.lean_bool_to_uint64 = (b) => BigInt(b);
P.lean_bool_to_usize = (b) => BigInt(b);

/* ---- String (UTF-16 JS string; Lean positions are UTF-8 byte offsets) ---- */
const TE = new TextEncoder(), TD = new TextDecoder(), TDfatal = new TextDecoder("utf-8", { fatal: true });
const utf8Len = (cp) => (cp < 0x80 ? 1 : cp < 0x800 ? 2 : cp < 0x10000 ? 3 : 4);
const infoCache = new Map();
function sinfo(s) {
  let info = infoCache.get(s);
  if (info !== undefined) return info;
  let ascii = true;
  for (let i = 0; i < s.length; i++) if (s.charCodeAt(i) > 127) { ascii = false; break; }
  if (ascii) info = { ascii: true, n: s.length, size: s.length };
  else {
    const starts = [], bytes = [];
    let b = 0;
    for (let i = 0; i < s.length;) {
      const cp = s.codePointAt(i);
      starts.push(i); bytes.push(b);
      b += utf8Len(cp);
      i += cp > 0xffff ? 2 : 1;
    }
    const n = starts.length;
    starts.push(s.length); bytes.push(b);
    info = { ascii: false, starts, bytes, n, size: b };
  }
  if (infoCache.size > 64) infoCache.clear();
  infoCache.set(s, info);
  return info;
}
/** code point index of byte offset `p`, or -1 if `p` is not at a character boundary (or beyond the end) */
function cpIndex(info, p) {
  if (info.ascii) return p >= 0 && p <= info.n ? p : -1;
  let lo = 0, hi = info.n;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    const v = info.bytes[mid];
    if (v === p) return mid;
    if (v < p) lo = mid + 1; else hi = mid - 1;
  }
  return -1;
}
const jsIndex = (info, ci) => (info.ascii ? ci : info.starts[ci]);

P.lean_string_length = (s) => BigInt(sinfo(s).n);
P.lean_string_utf8_byte_size = (s) => BigInt(sinfo(s).size);
P.lean_string_append = (a, b) => a + b;
P.lean_string_push = (s, c) => s + String.fromCodePoint(c);
P.lean_string_pushn = (s, c, n) => s + String.fromCodePoint(c).repeat(Number(n));
P.lean_string_dec_eq = (a, b) => bool(a === b);
P.lean_string_dec_lt = (a, b) => bool(strLt(a, b));
function strLt(a, b) {                        // lexicographic by code point (= UTF-8 byte order)
  const x = Array.from(a), y = Array.from(b);
  for (let i = 0; i < x.length && i < y.length; i++) {
    const c = x[i].codePointAt(0), d = y[i].codePointAt(0);
    if (c !== d) return c < d;
  }
  return x.length < y.length;
}
P.lean_string_compare = (a, b) => (a === b ? 1 : strLt(a, b) ? 0 : 2);   // Ordering: lt=0, eq=1, gt=2
P.lean_string_utf8_get = (s, pos) => {
  const info = sinfo(s), ci = cpIndex(info, Number(pos));
  if (ci < 0 || ci >= info.n) return 65;       // default char
  return s.codePointAt(jsIndex(info, ci));
};
P.lean_string_utf8_get_fast = P.lean_string_utf8_get;
P.lean_string_utf8_get_bang = P.lean_string_utf8_get;
P.lean_string_utf8_get_opt = (s, pos) => {
  const info = sinfo(s), ci = cpIndex(info, Number(pos));
  if (ci < 0 || ci >= info.n) return none();
  return some(s.codePointAt(jsIndex(info, ci)));
};
P.lean_string_utf8_next = (s, pos) => {
  const info = sinfo(s), p = Number(pos), ci = cpIndex(info, p);
  if (ci < 0 || ci >= info.n) return pos + 1n;
  return BigInt(info.ascii ? p + 1 : info.bytes[ci + 1]);
};
P.lean_string_utf8_next_fast = P.lean_string_utf8_next;
P.lean_string_utf8_prev = (s, pos) => {
  const info = sinfo(s), p = Number(pos);
  if (p === 0) return 0n;
  if (info.ascii) return BigInt(Math.min(p, info.n + 1) - 1);
  if (p > info.size) return pos - 1n;
  let lo = 0, hi = info.n;                    // last char start strictly below p
  while (lo < hi) { const mid = (lo + hi + 1) >> 1; if (info.bytes[mid] < p) lo = mid; else hi = mid - 1; }
  return BigInt(info.bytes[lo]);
};
P.lean_string_utf8_at_end = (s, pos) => bool(pos >= BigInt(sinfo(s).size));
P.lean_string_utf8_extract = (s, b, e) => {
  const info = sinfo(s);
  const bn = Number(b), en = Math.min(Number(e), info.size);
  if (bn >= en) return "";
  const cb = cpIndex(info, bn), ce = cpIndex(info, en);
  if (cb < 0 || ce < 0) return "";
  return s.slice(jsIndex(info, cb), jsIndex(info, ce));
};
P.lean_string_utf8_extract_fast = P.lean_string_utf8_extract;
P.lean_string_memcmp = (l, r, ls, rs, len) => {
  const a = Number(ls), b = Number(rs), n = Number(len);
  const il = sinfo(l), ir = sinfo(r);
  if (il.ascii && ir.ascii) return bool(l.slice(a, a + n) === r.slice(b, b + n));
  const x = TE.encode(l), y = TE.encode(r);
  for (let i = 0; i < n; i++) if (x[a + i] !== y[b + i]) return 0;
  return 1;
};
P.lean_string_utf8_set = (s, pos, c) => {
  const info = sinfo(s), ci = cpIndex(info, Number(pos));
  if (ci < 0 || ci >= info.n) return s;
  return s.slice(0, jsIndex(info, ci)) + String.fromCodePoint(c) + s.slice(jsIndex(info, ci + 1));
};
P.lean_string_mk = (l) => { const r = String.fromCodePoint(...listToArray(l)); dec(l); return r; };
P.lean_string_data = (s) => listFromArray(Array.from(s, (ch) => ch.codePointAt(0)));
P.lean_string_of_usize = (n) => n.toString();
const scratch = new Uint8Array(4096);
P.lean_string_hash = (s) => {
  if (s.length <= 1365) {                       // up to 3 bytes per UTF-16 unit fit the scratch buffer: no allocation
    const { written } = TE.encodeInto(s, scratch);
    return hash64(scratch.subarray(0, written), 11n);
  }
  return hash64(TE.encode(s), 11n);
};
P.lean_string_from_utf8_unchecked = (b) => { const r = TD.decode(b); dec(b); return r; };
P.lean_string_validate_utf8 = (b) => { try { TDfatal.decode(b); return 1; } catch { return 0; } };
P.lean_string_get_byte_fast = (s, i) => {
  const k = Number(i);
  if (sinfo(s).ascii) return s.charCodeAt(k);   // ASCII: byte = code unit (no re-encoding on every call)
  return TE.encode(s)[k];
};

/** MurmurHash64A as in Lean's runtime/hash.cpp */
function hash64(bytes, seed) {
  const M = 0xc6a4a7935bd1e995n, R = 47n, MASK = (1n << 64n) - 1n;
  const len = bytes.length;
  let h = (seed ^ (BigInt(len) * M)) & MASK;
  const nblocks = Math.floor(len / 8);
  for (let i = 0; i < nblocks; i++) {
    let k = 0n;
    for (let j = 7; j >= 0; j--) k = (k << 8n) | BigInt(bytes[i * 8 + j]);
    k = (k * M) & MASK; k ^= k >> R; k = (k * M) & MASK;
    h ^= k; h = (h * M) & MASK;
  }
  const tail = nblocks * 8;
  const rem = len & 7;
  if (rem > 0) {
    for (let j = rem - 1; j >= 0; j--) h ^= BigInt(bytes[tail + j]) << BigInt(8 * j);
    h = (h * M) & MASK;
  }
  h ^= h >> R; h = (h * M) & MASK; h ^= h >> R;
  return h;
}
P.lean_uint64_mix_hash = (h, k) => {
  const M = 0xc6a4a7935bd1e995n, R = 47n, MASK = (1n << 64n) - 1n;
  k = (k * M) & MASK; k ^= k >> R; k ^= M;   // as lean.h (`k ^= m`, not a second multiply)
  h ^= k; h = (h * M) & MASK;
  return h;
};


/* ---- Array ---- */
const mkArr = (a) => { a.rc = 1; return a; };
/** Make `a` (owned) exclusive: itself if rc == 1, else a fresh copy (the original loses one reference). */
function ensureExclusive(a) {
  if (a.rc === 1) return a;
  const r = a.slice();
  for (let i = 0; i < r.length; i++) inc(r[i]);
  dec(a);
  r.rc = 1;
  return r;
}
const oob = (def) => { panicMsg("PANIC: index out of bounds"); return def; };
P.lean_mk_empty_array_with_capacity = (_cap) => mkArr([]);
P.lean_mk_array = (n, v) => {
  const k = Number(n);
  if (k === 0) { dec(v); return mkArr([]); }
  incN(v, k - 1);
  return mkArr(new Array(k).fill(v));
};
P.lean_array_mk = (l) => {
  const a = listToArray(l);
  for (let i = 0; i < a.length; i++) inc(a[i]);
  dec(l);
  return mkArr(a);
};
P.lean_array_to_list = (a) => {
  const xs = a.slice();
  for (let i = 0; i < xs.length; i++) inc(xs[i]);
  dec(a);
  return listFromArray(xs);
};
P.lean_array_get_size = (a) => BigInt(a.length);
P.lean_array_size = P.lean_array_get_size;
P.lean_array_usize = P.lean_array_get_size;
P.lean_array_fget = (a, i) => { const v = a[Number(i)]; inc(v); return v; };
P.lean_array_uget = P.lean_array_fget;
P.lean_array_fget_borrowed = (a, i) => a[Number(i)];
P.lean_array_uget_borrowed = P.lean_array_fget_borrowed;
P.lean_array_get = (def, a, i) => {                          // def owned
  if (i < BigInt(a.length)) { dec(def); const v = a[Number(i)]; inc(v); return v; }
  return oob(def);
};
P.lean_array_get_borrowed = (def, a, i) => (i < BigInt(a.length) ? a[Number(i)] : oob(def));
P.lean_array_fset = (a, i, v) => {
  a = ensureExclusive(a);
  const k = Number(i);
  dec(a[k]);
  a[k] = v;
  return a;
};
P.lean_array_uset = P.lean_array_fset;
P.lean_array_set = (a, i, v) => (i < BigInt(a.length) ? P.lean_array_fset(a, i, v) : (dec(v), oob(0), a));
P.lean_array_push = (a, v) => { a = ensureExclusive(a); a.push(v); return a; };
P.lean_array_pop = (a) => { a = ensureExclusive(a); if (a.length > 0) dec(a.pop()); return a; };
P.lean_array_fswap = (a, i, j) => {
  a = ensureExclusive(a);
  const x = Number(i), y = Number(j);
  const t = a[x]; a[x] = a[y]; a[y] = t;
  return a;
};
P.lean_array_swap = (a, i, j) =>
  (i < BigInt(a.length) && j < BigInt(a.length) ? P.lean_array_fswap(a, i, j) : a);
P.lean_array_propagate_mark = (_src, dst) => dst;
P.lean_array_mark_linear = (a) => a;

/* ---- ByteArray (Uint8Array) / FloatArray (Float64Array) ---- */
function defScalarArray(prefix, Ctor, mkEmpty, dflt) {
  const mk = (a) => { a.rc = 1; return a; };
  const excl = (a) => (a.rc === 1 ? a : mk(a.slice()));
  const inb = (a, i) => i < BigInt(a.length);
  P[`lean_mk_empty_${mkEmpty}`] = (_cap) => mk(new Ctor(0));
  P[`lean_${prefix}_mk`] = (arr) => {
    const r = mk(Ctor.from(arr)); dec(arr); return r;
  };
  P[`lean_${prefix}_data`] = (a) => { const r = mkArr(Array.from(a)); dec(a); return r; };
  P[`lean_${prefix}_size`] = (a) => BigInt(a.length);
  P[`lean_sarray_size`] = P[`lean_${prefix}_size`];
  P[`lean_${prefix}_push`] = (a, v) => { const r = mk(new Ctor(a.length + 1)); r.set(a); r[a.length] = v; dec(a); return r; };
  P[`lean_${prefix}_get`] = (a, i) => (inb(a, i) ? a[Number(i)] : (oob(0), dflt));
  P[`lean_${prefix}_fget`] = (a, i) => a[Number(i)];
  P[`lean_${prefix}_uget`] = P[`lean_${prefix}_fget`];
  P[`lean_${prefix}_fset`] = (a, i, v) => { const r = excl(a); if (r !== a) dec(a); r[Number(i)] = v; return r; };
  P[`lean_${prefix}_uset`] = P[`lean_${prefix}_fset`];
  P[`lean_${prefix}_set`] = (a, i, v) => (inb(a, i) ? P[`lean_${prefix}_fset`](a, i, v) : a);
}
defScalarArray("byte_array", Uint8Array, "byte_array", 0);
defScalarArray("float_array", Float64Array, "float_array", 0.0);
P.lean_byte_array_copy_slice = (src, srcOff, dest, destOff, len, _exact) => {
  const so = Math.min(Number(srcOff), src.length);
  const l = Math.min(Number(len), src.length - so);
  const dof = Math.min(Number(destOff), dest.length);
  const r = new Uint8Array(Math.max(dest.length, dof + l));
  r.set(dest);
  r.set(src.subarray(so, so + l), dof);
  r.rc = 1;
  dec(dest);
  return r;
};
P.lean_byte_array_hash = (a) => hash64(a, 11n);
P.lean_string_to_utf8 = (s) => { const r = TE.encode(s); r.rc = 1; return r; };

/* ---- ST.Ref (BaseIO/ST primitives return plain values; state token and erased args are dropped) ---- */
class Ref { constructor(v) { this.v = v; this.rc = 1; } }
P.lean_st_mk_ref = (v) => new Ref(v);
P.lean_st_ref_get = (r) => { inc(r.v); return r.v; };
P.lean_st_ref_set = (r, v) => { const old = r.v; r.v = v; dec(old); return unit; };
P.lean_st_ref_put = P.lean_st_ref_set;
P.lean_st_ref_swap = (r, v) => { const old = r.v; r.v = v; return old; };
P.lean_st_ref_take = (r) => { const old = r.v; r.v = 0; return old; };
P.lean_st_ref_ptr_eq = (a, b) => bool(a === b);


/* ---- Float ---- */
P.lean_float_add = (a, b) => a + b;
P.lean_float_sub = (a, b) => a - b;
P.lean_float_mul = (a, b) => a * b;
P.lean_float_div = (a, b) => a / b;
P.lean_float_negate = (a) => -a;
P.lean_float_beq = (a, b) => bool(a === b);
P.lean_float_decLt = (a, b) => bool(a < b);
P.lean_float_decLe = (a, b) => bool(a <= b);
P.lean_float_of_nat = (n) => Number(n);
P.lean_float_of_int = (n) => Number(n);
P.lean_float_of_scientific = (m, neg, e) => Number(`${m}e${neg ? "-" : ""}${e}`);
P.lean_uint64_to_float = (n) => Number(n);
P.lean_float_of_bits = (b) => { const v = new DataView(new ArrayBuffer(8)); v.setBigUint64(0, b); return v.getFloat64(0); };
P.lean_float_to_bits = (x) => { const v = new DataView(new ArrayBuffer(8)); v.setFloat64(0, x); return v.getBigUint64(0); };
P.lean_float_is_nan = (x) => bool(Number.isNaN(x));
P.lean_float_is_inf = (x) => bool(x === Infinity || x === -Infinity);
P.lean_float_is_finite = (x) => bool(Number.isFinite(x));
P.lean_float_to_string = (x) => {
  if (Number.isNaN(x)) return "NaN";
  if (x === Infinity) return "inf";
  if (x === -Infinity) return "-inf";
  if (Math.abs(x) < 1e21) return x.toFixed(6);
  return BigInt(x).toString() + ".000000";
};
function floatToUInt(bits, big) {
  const max = 2 ** bits - 1;
  return (x) => {
    const v = Number.isNaN(x) || x <= 0 ? 0 : x >= max ? max : Math.trunc(x);
    return big ? (x >= 2 ** bits ? (1n << BigInt(bits)) - 1n : BigInt(v)) : v;
  };
}
P.lean_float_to_uint8 = floatToUInt(8, false);
P.lean_float_to_uint16 = floatToUInt(16, false);
P.lean_float_to_uint32 = floatToUInt(32, false);
P.lean_float_to_uint64 = floatToUInt(64, true);
P.lean_float_to_usize = floatToUInt(64, true);
for (const f of ["sin", "cos", "tan", "asin", "acos", "atan", "sinh", "cosh", "tanh", "asinh", "acosh",
                 "atanh", "exp", "log", "log2", "log10", "sqrt", "cbrt", "ceil", "floor", "round", "abs"]) {
  P[f] = Math[f] === undefined ? undefined : Math[f];
}
P.exp2 = (x) => 2 ** x;
P.pow = (a, b) => a ** b;
P.atan2 = Math.atan2;
P.fabs = Math.abs;
P.round = (x) => (x < 0 ? -Math.round(-x) : Math.round(x));
P.lean_float_scaleb = (x, i) => x * 2 ** Number(i);


/* ---- Thunk / Task (tasks run eagerly and synchronously) ---- */
class Thunk { constructor(c, v) { this.c = c; this.v = v; this.rc = 1; } }
P.lean_mk_thunk = (c) => new Thunk(c, 0);
P.lean_thunk_pure = (v) => new Thunk(null, v);
P.lean_thunk_get_own = (t) => {                              // t borrowed, result owned
  if (t.c !== null) { const c = t.c; t.c = null; t.v = ap(c, [0]); }
  inc(t.v);
  return t.v;
};
P.lean_thunk_get = P.lean_thunk_get_own;
/* ---- Tasks and promises: a cooperative, single-threaded scheduler ----
 * A task is either finished (`pend === false`, value in `v`) or pending: its computation sits in `runQueue` (or waits for another
 * task / a promise, recorded in `waiters`). Pending tasks run when somebody waits for them (`Task.get`, `IO.wait`) — the waiter runs
 * queued jobs, nested on its own stack, until the awaited task has finished — and at the end of `main`. A job always runs to
 * completion; a wait that finds the queue empty while its task is unresolved is a genuine deadlock. */
class Task {
  constructor(v) { this.v = v; this.rc = 1; this.pend = false; this.waiters = null; }
}
const runQueue = [];
let queueHead = 0;
function newPendingTask() { const t = new Task(0); t.pend = true; t.waiters = []; return t; }
function resolveTask(t, v) {
  t.v = v; t.pend = false;
  const ws = t.waiters; t.waiters = null;
  for (const w of ws) w();
}
/** Runs `job` (a function returning the task's value) later; returns the pending result task. */
function spawnJob(job) {
  const t = newPendingTask();
  runQueue.push(() => resolveTask(t, job()));
  return t;
}
/** After `src` has finished, run `job(src.v)` (a function of the value) later and resolve the returned task with its result. */
function afterTask(src, job) {
  const t = newPendingTask();
  const start = () => runQueue.push(() => resolveTask(t, job(src.v)));
  if (src.pend) src.waiters.push(start); else start();
  return t;
}
/** Like `afterTask` but `job` returns a Task whose value becomes the result (bind). */
function afterTaskBind(src, job) {
  const t = newPendingTask();
  const start = () => runQueue.push(() => {
    const inner = job(src.v);
    const fin = () => resolveTask(t, inner.v);
    if (inner.pend) inner.waiters.push(fin); else fin();
  });
  if (src.pend) src.waiters.push(start); else start();
  return t;
}
function runOneJob() {
  if (queueHead >= runQueue.length) return false;
  const job = runQueue[queueHead++];
  if (queueHead > 1024 && queueHead * 2 > runQueue.length) { runQueue.splice(0, queueHead); queueHead = 0; }
  job();
  return true;
}
function waitFor(t) {
  while (t.pend) {
    if (runOneJob()) continue;
    // Nothing can run any more. In native Lean a promise that is dropped without being resolved yields `none`; we do not track
    // drops, so the oldest still-unresolved promise is treated as dropped (a heuristic of last resort, see docs/design/tasks.md).
    let dropped = false;
    while (pendingPromises.length > 0) {
      const p = pendingPromises.shift();
      if (p.pend) {
        if (strictTasks) throw new Error("deadlock: an unresolved promise would be treated as dropped (LEAN2JS_STRICT_TASKS=1, see docs/tickets/self-010-promise-drop-heuristic.md)");
        if (droppedGuesses++ === 0) console.error("lean2js warning: an unresolved promise was treated as dropped (reference leak?); output may be incomplete. See docs/tickets/self-010-promise-drop-heuristic.md");
        if (traceTasks) console.error("task: treating unresolved promise as dropped; created at:\n" + (p.site || "").split("\n").slice(2, 9).join("\n"));
        resolveTask(p, 0); dropped = true; break;
      }
    }
    if (!dropped) throw new Error("deadlock: waiting for a task or promise that can never be resolved");
  }
}
const pendingPromises = [];
let droppedGuesses = 0;                 // how often the heuristic fired (reported with LEAN2JS_TIMING)
const strictTasks = !!(globalThis.process && globalThis.process.env && globalThis.process.env.LEAN2JS_STRICT_TASKS);
const traceTasks = !!(globalThis.process && globalThis.process.env && globalThis.process.env.LEAN2JS_TRACE_TASKS);
/** Runs all queued jobs (used at the end of `main`). */
export function runPendingTasks() { while (runOneJob()); }

P.lean_task_pure = (v) => new Task(v);
P.lean_task_spawn = (c, _prio) => spawnJob(() => ap(c, [0]));
P.lean_task_get_own = (t) => { waitFor(t); inc(t.v); const v = t.v; dec(t); return v; };
P.lean_task_get = (t) => { waitFor(t); return t.v; };
P.lean_task_map = (f, t, _prio, sync) => {
  if (sync && !t.pend) { inc(t.v); return new Task(ap(f, [t.v])); }
  inc(t);
  return afterTask(t, (v) => { inc(v); return ap(f, [v]); });
};
P.lean_task_bind = (t, f, _prio, _sync) => {
  inc(t);
  return afterTaskBind(t, (v) => { inc(v); return ap(f, [v]); });
};
// BaseIO.asTask / mapTask / bindTask: the actions are BaseIO (raw result, state token passed as 0)
P.lean_io_as_task = (act, _prio) => spawnJob(() => ap(act, [0]));
P.lean_io_map_task = (f, t, _prio, sync) => {
  if (sync && !t.pend) { inc(t.v); return new Task(ap(f, [t.v, 0])); }
  inc(t);
  return afterTask(t, (v) => { inc(v); return ap(f, [v, 0]); });
};
P.lean_io_bind_task = (t, f, _prio, _sync) => {
  inc(t);
  return afterTaskBind(t, (v) => { inc(v); return ap(f, [v, 0]); });
};
P.lean_io_wait = (t) => { waitFor(t); inc(t.v); const v = t.v; dec(t); return v; };
P.lean_io_wait_any = (tasks) => {
  const ts = listToArray(tasks);
  for (;;) {
    const d = ts.find((t) => !t.pend);
    if (d !== undefined) { inc(d.v); return d.v; }
    if (!runOneJob()) throw new Error("deadlock: IO.waitAny on tasks that can never finish");
  }
};
P.lean_io_cancel = (_t) => unit;
P.lean_io_check_canceled = () => 0;
P.lean_io_has_finished = (t) => bool(!t.pend);

/* ---- promises: `result?` is a task that finishes when the promise is resolved ---- */
/** The last reference to an unresolved promise disappeared: native Lean resolves `result?` with `none` (see docs/tickets/self-010). */
function dropPromise(pr) {
  droppedPromises++;
  if (traceTasks) console.error("task: promise dropped (reference count reached zero)");
  resolveTask(pr.task, 0);
}
let droppedPromises = 0;
class Promise_ { constructor() { this.rc = 1; this.task = newPendingTask(); if (traceTasks) this.task.site = new Error().stack; pendingPromises.push(this.task); } }
P.lean_io_promise_new = () => new Promise_();
P.lean_io_promise_resolve = (value, p) => { if (p.task.pend) resolveTask(p.task, some(value)); else dec(value); return unit; };
P.lean_io_promise_result_opt = (p) => { inc(p.task); return p.task; };
P.lean_option_get_or_block = (o) => {
  if (typeof o === "object") { inc(o.a0); const v = o.a0; dec(o); return v; }
  throw new Error("deadlock: Option.getOrBlock! on none (dropped Promise)");
};
P.lean_io_get_task_state = (t) => (t.pend ? 0 : 2);
P.lean_io_get_tid = () => 1n;
P.lean_internal_get_hardware_concurrency = () => 1;
P.lean_io_basemutex_new = () => ({ rc: 1 });
P.lean_io_basemutex_lock = (_m) => unit;
P.lean_io_basemutex_unlock = (_m) => unit;
let heartbeats = 0n;
P.lean_io_get_num_heartbeats = () => heartbeats;
P.lean_io_set_heartbeats = (n) => { heartbeats = n; return unit; };
P.lean_profileit = (_cat, _opts, fn, decl) => { dec(decl); return ap(fn, [0]); };
P.lean_runtime_mark_persistent = (a) => { persist(a); return a; };
P.lean_runtime_forget = (_a) => unit;
P.lean_strict_or = (a, b) => (a | b);
P.lean_void_mk = (x) => x;
P.lean_system_platform_osx = () => 0;
P.lean_system_platform_windows = () => 0;
P.lean_string_is_valid_pos = (s, pos) => {
  const n = Number(pos);
  if (n === 0) return 1;
  const total = P.lean_string_utf8_byte_size(s);
  if (BigInt(n) > BigInt(total)) return 0;
  if (BigInt(n) === BigInt(total)) return 1;
  return bool(isCharBoundary(s, n));
};
function isCharBoundary(s, n) {            // is UTF-8 byte offset n the start of a code point of s?
  let off = 0;
  for (const ch of s) { if (off === n) return true; if (off > n) return false; off += utf8Len(ch.codePointAt(0)); }
  return off === n;
}
P.lean_float_isnan = (x) => bool(Number.isNaN(x));
P.lean_float_isinf = (x) => bool(x === Infinity || x === -Infinity);
const objIds = new WeakMap(); let nextId = 8n;
P.lean_ptr_addr = (a) => {
  if (typeof a === "object" && a !== null) { let i = objIds.get(a); if (i === undefined) { i = nextId; nextId += 8n; objIds.set(a, i); } return i; }
  return BigInt(a) * 2n + 1n;
};
installNum(P, { bool });
installSys(P, { inc, dec, ap, some, bool, unit, okR, errR, objId: (o) => P.lean_ptr_addr(o), P });
installExpr(P, { inc, dec, ap, some, exports, mixHash: P.lean_uint64_mix_hash, sget });

P.lean_eval_const = (_env, _opts, name) => {
  const id = nameId(name);
  let f = fn(id);
  let genError = null;
  if (f === undefined && evalFn !== null && exports.lean2js_gen_chunk !== undefined) {
    // a declaration of the module being elaborated: generate JS from its IR now
    // Always regenerate the whole closure of local declarations: names like `_eval` are reused by every `#eval`, so caching by name
    // would return stale code (the code of a few user declarations is small).
    const defined = []; defined.rc = 1;
    inc(_env); inc(name);
    const r = exports.lean2js_gen_chunk(_env, name, defined);
    if (r.t === 1) { const D = {}; evalFn(r.a0)(D); f = D[id]; }
    else genError = r.a0;
  }
  if (typeof f !== "function") {
    if (genError !== null) return { t: 0, rc: 1, n: 1, a0: genError };
    if (globalThis.process && globalThis.process.env.LEAN2JS_TRACE_EVAL) console.error("evalConst: not found", id);
    return { t: 0, rc: 1, n: 1, a0: `evalConst: no compiled code for '${P.__nameStr(name)}' (transpile with --eval-all)` };   // Except.error
  }
  return { t: 1, rc: 1, n: 1, a0: f.length === 0 ? f() : new Clo(f, f.length, []) };                                          // Except.ok
};

/* ---------- IO ---------- */

function fdWrite(fd, s) {                    // synchronous, ordered, works from worker threads
  const buf = Buffer.from(s, "utf8");
  let off = 0;
  while (off < buf.length) {
    try { off += nodeFs.writeSync(fd, buf, off); }
    catch (e) { if (e.code !== "EAGAIN") throw e; }
  }
}
stdoutSink = (s) => (nodeFs ? fdWrite(1, s) : console.log(s));
stderrSink = (s) => (nodeFs ? fdWrite(2, s) : console.error(s));
export function setStdout(f) { stdoutSink = f; }
export function setStderr(f) { stderrSink = f; }

// stdin: Node: blocking reads from fd 0; browser: set with setStdinLine(fn) (returns "" at EOF, else a line with "\n").
let stdinLine = null;
export function setStdinLine(f) { stdinLine = f; }
let inBuf = typeof Buffer !== "undefined" ? Buffer.alloc(0) : null;
function nodeGetLine() {
  const chunk = Buffer.alloc(65536);
  for (;;) {
    const nl = inBuf.indexOf(10);
    if (nl >= 0) { const line = inBuf.subarray(0, nl + 1).toString("utf8"); inBuf = inBuf.subarray(nl + 1); return line; }
    let n = 0;
    try { n = nodeFs.readSync(0, chunk, 0, chunk.length, null); }
    catch (e) { if (e.code === "EAGAIN") continue; if (e.code === "EOF") n = 0; else throw e; }
    if (n === 0) { const rest = inBuf.toString("utf8"); inBuf = Buffer.alloc(0); return rest; }
    inBuf = Buffer.concat([inBuf, chunk.subarray(0, n)]);
  }
}
function getLine() {
  if (stdinLine) return stdinLine();
  if (nodeFs) return nodeGetLine();
  return "";
}
/** `Stream.read`: up to `n` bytes (empty at end of input). */
let carry = new Uint8Array(0);
function stdinRead(n) {
  if (stdinLine) {
    if (carry.length === 0) carry = TE.encode(stdinLine());
    const r = carry.slice(0, n); carry = carry.slice(n); return r;
  }
  if (nodeFs) {
    if (inBuf.length === 0) {
      const chunk = Buffer.alloc(65536);
      let k = 0;
      for (;;) {
        try { k = nodeFs.readSync(0, chunk, 0, chunk.length, null); break; }
        catch (e) { if (e.code === "EAGAIN") continue; if (e.code === "EOF") { k = 0; break; } throw e; }
      }
      inBuf = Buffer.from(chunk.subarray(0, k));
    }
    const r = new Uint8Array(inBuf.subarray(0, n)); inBuf = inBuf.subarray(n); return r;
  }
  return new Uint8Array(0);
}

function mkStream(sink, readLine, readBytes = () => new Uint8Array(0)) {
  // IO.FS.Stream.mk flush read write getLine putStr isTty; fields are closures taking the state token last.
  const clo = (f, n) => { const c = new Clo(f, n, []); c.rc = 0; return c; };
  return {
    t: 0, rc: 0, n: 6,
    a0: clo((_w) => okR(unit), 1),
    a1: clo((n, _w) => okR(mkBytes(readBytes(Number(n)))), 2),
    a2: clo((_b, _w) => okR(unit), 2),
    a3: clo((_w) => okR(readLine()), 1),
    a4: clo((s, _w) => { sink(s); return okR(unit); }, 2),
    a5: clo((_w) => 0, 1),
  };
}
const mkBytes = (b) => { b.rc = 1; return b; };
const stdoutStream = mkStream((s) => stdoutSink(s), () => "");
const stderrStream = mkStream((s) => stderrSink(s), () => "");
const stdinStream = mkStream((_s) => {}, () => getLine(), stdinRead);
const curStreams = { out: stdoutStream, err: stderrStream, in: stdinStream };
P.lean_get_stdout = () => { inc(curStreams.out); return curStreams.out; };
P.lean_get_stderr = () => { inc(curStreams.err); return curStreams.err; };
P.lean_get_stdin = () => { inc(curStreams.in); return curStreams.in; };
/** In-memory file system used instead of `fs` outside Node (path → Uint8Array); hosts may preload files. */
export const vfs = new Map();
export { sget, uget };
installFs(P, { inc, dec, okR, errR, some, mkBytes, unit, nodeFs, vfs,
  olean: { parseRegion, freeRegion, hooks: { get Thunk() { return Thunk; }, get Task() { return Task; }, get Ref() { return Ref; } } },
  getStdStreams: () => curStreams, setStdStreams: (o) => Object.assign(curStreams, o) });

/* ---- time, environment, process ---- */
P.lean_io_mono_ms_now = () => BigInt(Math.floor(performance.now()));
P.lean_io_mono_nanos_now = () => BigInt(Math.floor(performance.now() * 1e6));
P.lean_io_get_random_bytes = (n) => {
  const b = new Uint8Array(Number(n));
  for (let i = 0; i < b.length; i += 65536) crypto.getRandomValues(b.subarray(i, Math.min(i + 65536, b.length)));
  b.rc = 1;
  return okR(b);
};
P.lean_io_getenv = (name) => {
  // outside Node the host provides the environment as `globalThis.LEAN2JS_ENV = { NAME: "value" }`
  const v = isNode ? globalThis.process.env[name] : (globalThis.LEAN2JS_ENV ? globalThis.LEAN2JS_ENV[name] : undefined);
  return v === undefined ? none() : some(v);
};
P.lean_io_initializing = () => bool(initDepth > 0);
class ExitSignal { constructor(code) { this.code = code; } }
// Unwinds the stack up to `runMain` (process.exit from a worker thread with a huge stack crashes V8 teardown).
P.lean_io_exit = (code) => { throw new ExitSignal(code); };
P.lean_io_process_get_pid = () => (isNode ? globalThis.process.pid : 0);
P.lean_io_app_path = () => okR(isNode ? globalThis.process.argv[1] : "");
P.lean_io_sleep = (_ms) => unit;

/** Result of running an `[init]` action (an `EStateM` result): the value, or an `InitError` carrying the `IO.Error`. */
class InitError { constructor(err, what) { this.err = err; this.what = what; } }
export function initResult(r, what) {
  if (r.t !== 0) throw new InitError(r.a0, what);
  return r.a0;
}
let initDepth = 0;                       // > 0 while an initializer runs: `IO.initializing` is true (option/attribute registration)
/** Runs the `[init]` action `f` (a function of the state token) and returns its value; see `IO.initializing`. */
export function runInit(f, what) {
  initDepth++;
  try { return initResult(f(0), what); } finally { initDepth--; }
}
/**
 * Runs the startup steps (each returns null or an error result, or throws `InitError`) in order. A failing step is retried after the
 * others have run (the declaration order of imported modules is only approximated, see CodegenIR.initOrder); returns the last error
 * result if some step keeps failing, else null.
 */
export function runInitSteps(steps) {
  let pending = steps;
  for (;;) {
    const failed = []; let lastErr = null;
    for (const step of pending) {
      let r;
      try { r = step(); } catch (e) { if (e instanceof InitError) r = errR(e.err); else throw e; }
      if (r !== null && r.t !== 0) { failed.push(step); lastErr = r; }
    }
    if (failed.length === 0) return null;
    if (failed.length === pending.length) return lastErr;     // no progress
    pending = failed;
  }
}
/** Name lookup for `evalConst`, emitted by `--eval-all`: JS identifier → the compiled function (module-scope `eval`). */
let lookupFn = null;
export function setLookup(f) { lookupFn = f; }
/** With `--small`: long identifier (`JsUtil.nameId`) → short identifier of the emitted function. */
let nameIndex = null;
export function setIndex(o) { nameIndex = o; }
/** The compiled function with the (long) identifier `id`, or undefined. */
export function fn(id) {
  if (lookupFn === null) return undefined;
  if (nameIndex !== null) { const s = nameIndex[id]; return s === undefined ? undefined : lookupFn(s); }
  return lookupFn(id);
}
/** Direct `eval` in the scope of the generated program (so that new code can call its functions); see `lean2js_gen_chunk`. */
let evalFn = null;
export function setEval(f) { evalFn = f; }

/** JS identifier of a Lean name; must agree with `Lean2js.JsUtil.nameId`. */
function nameId(n) {
  const comps = [];
  for (; typeof n !== "number"; n = n.a0) {
    if (n.t === 1) {
      let e = "";
      for (const ch of n.a1) {
        const c = ch.codePointAt(0);
        e += (c < 128 && /[A-Za-z0-9_]/.test(ch)) ? ch : "$u" + c.toString(16) + "_";
      }
      comps.push(e);
    } else comps.push("$n" + String(n.a1));
  }
  return "l_" + comps.reverse().join("$$");
}
let initFn = null;
let initialized = false;
/** Registers the generated `initialize()` (returns null, or an error result); run by `runMain` before `main`. */
export function setInit(f) { initFn = f; }
let initDone = false;
/** Runs the module initializers once (what `runMain` does before `main`); for hosts that call exported functions without `main`. Throws on failure. */
export function runInitializers() {
  if (initDone || initFn === null) return;
  initDone = true;
  initDepth++;
  let r;
  try { r = initFn(); } finally { initDepth--; }
  if (r !== null && r.t !== 0) throw new Error("initialization failed: " + errorMessage(r.a0));
}

let errorToString = null;
/** Message of an `IO.Error` value (for hosts that call exported IO functions). */
export function errorMessage(e) { return errorToString ? errorToString(e) : JSON.stringify(e); }
export function setErrorToString(f) { errorToString = f; }

/* ---- Nat/Int tolerance ----
 * Computed Nat/Int values are BigInts, but small values read from .olean files are boxed scalars, i.e. plain JS numbers (their static
 * type is not known to the loader, see lean_olean.js). Primitives that take a Nat/Int therefore accept both; results are BigInts. */
{
  const w1 = (f) => (a) => f(typeof a === "number" ? BigInt(a) : a);
  const w2 = (f) => (a, b) => f(typeof a === "number" ? BigInt(a) : a, typeof b === "number" ? BigInt(b) : b);
  const w3 = (f) => (a, b, c) => f(typeof a === "number" ? BigInt(a) : a, typeof b === "number" ? BigInt(b) : b, typeof c === "number" ? BigInt(c) : c);
  const wrapAll = (f) => (f.length <= 1 ? w1(f) : f.length === 2 ? w2(f) : w3(f));
  const wrapFirst = (f) => (a, ...r) => f(typeof a === "number" ? BigInt(a) : a, ...r);
  for (const name of Object.keys(P)) {
    if (/^lean_(nat|int)_/.test(name) && !/^lean_(nat|int)_to_uint/.test(name)) P[name] = wrapAll(P[name]);
    else if (/^lean_(u?int(8|16|32|64)|usize|isize|float|float32)_of_(nat|int)(_mk)?$/.test(name)) P[name] = wrapFirst(P[name]);
  }
}

/** Stack size (MB) of the worker thread running `main` under Node; Lean programs recurse deeply. */
export const STACK_MB = 512;

/**
 * Run `main` (arity 1: `IO Unit`/`IO UInt32`; arity 2: also takes `List String`).
 * Under Node the program runs in a worker thread with a large stack, unless LEAN2JS_NO_WORKER is set.
 */
export function runMain(main, arity, args = (isNode ? globalThis.process.argv.slice(2) : [])) {
  if (isNode && nodeWorker.isMainThread && !globalThis.process.env.LEAN2JS_NO_WORKER) {
    const script = globalThis.process.argv[1];
    const w = new nodeWorker.Worker(script, {
      argv: args, resourceLimits: { stackSizeMb: STACK_MB, maxOldGenerationSizeMb: 8192 },
    });
    w.on("exit", (code) => { globalThis.process.exitCode = code; });
    w.on("error", (e) => { console.error(e); globalThis.process.exitCode = 1; });
    return;
  }
  return runMainHere(main, arity, args);
}

function runMainHere(main, arity, args) {
  let r;
  try {
    const tm = globalThis.process && globalThis.process.env && globalThis.process.env.LEAN2JS_TIMING;
    const ms = () => Math.round(performance.now());
    if (tm) console.error(`[timing] program loaded at ${ms()} ms (since process start)`);
    initDepth++;
    try { r = initFn && !initDone ? initFn() : null; initDone = true; } finally { initDepth--; }
    if (tm) console.error(`[timing] initializers done at ${ms()} ms`);   // module initializers; an error result aborts like in a native executable
    if (r === null) { r = arity >= 2 ? main(listFromArray(args), 0) : main(0); runPendingTasks(); if (tm) console.error(`[timing] main done at ${ms()} ms; promises dropped by refcount: ${droppedPromises}, dropped-promise guesses: ${droppedGuesses}`); }
  } catch (e) {
    if (e instanceof ExitSignal) {
      if (isNode) globalThis.process.exitCode = e.code;
      return e.code;
    }
    if (e instanceof InitError) r = errR(e.err);
    else throw e;
  }
  if (r.t === 0) {
    const code = typeof r.a0 === "number" ? r.a0 : 0;
    if (isNode) globalThis.process.exitCode = code;
    return code;
  }
  const msg = errorToString ? errorToString(r.a0) : JSON.stringify(r.a0);
  stderrSink("uncaught exception: " + msg + "\n");
  if (isNode) globalThis.process.exitCode = 1;
  return 1;
}
