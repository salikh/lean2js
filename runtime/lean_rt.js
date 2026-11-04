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
  if (o instanceof Task) { f(o.v); return; }
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
  const enc = new TextEncoder(), x = enc.encode(l), y = enc.encode(r);
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
P.lean_string_hash = (s) => hash64(new TextEncoder().encode(s), 11n);
P.lean_string_from_utf8_unchecked = (b) => { const r = new TextDecoder().decode(b); dec(b); return r; };
P.lean_string_validate_utf8 = (b) => { try { new TextDecoder("utf-8", { fatal: true }).decode(b); return 1; } catch { return 0; } };
P.lean_string_get_byte_fast = (s, i) => new TextEncoder().encode(s)[Number(i)];

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
  k = (k * M) & MASK; k ^= k >> R; k = (k * M) & MASK;
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
P.lean_string_to_utf8 = (s) => { const r = new TextEncoder().encode(s); r.rc = 1; return r; };

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
class Task { constructor(v) { this.v = v; this.rc = 1; } }
P.lean_task_pure = (v) => new Task(v);
P.lean_task_spawn = (c, _prio) => new Task(ap(c, [0]));
P.lean_task_get_own = (t) => { inc(t.v); const v = t.v; dec(t); return v; };
P.lean_task_get = (t) => t.v;
P.lean_task_map = (f, t, _prio, _sync) => { inc(t.v); const v = ap(f, [t.v]); dec(t); return new Task(v); };
P.lean_task_bind = (t, f, _prio, _sync) => { inc(t.v); const r = ap(f, [t.v]); dec(t); return r; };
// BaseIO.asTask / mapTask / bindTask: the actions are BaseIO (raw result, state token passed as 0)
P.lean_io_as_task = (act, _prio) => new Task(ap(act, [0]));
P.lean_io_map_task = (f, t, _prio, _sync) => { inc(t.v); const v = ap(f, [t.v, 0]); dec(t); return new Task(v); };
P.lean_io_bind_task = (t, f, _prio, _sync) => { inc(t.v); const r = ap(f, [t.v, 0]); dec(t); return r; };
P.lean_io_wait = (t) => { inc(t.v); const v = t.v; dec(t); return v; };
P.lean_io_cancel = (_t) => unit;
P.lean_io_check_canceled = () => 0;
P.lean_io_has_finished = (_t) => 1;

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

function mkStream(sink, readLine) {
  // IO.FS.Stream.mk flush read write getLine putStr isTty; fields are closures taking the state token last.
  const clo = (f, n) => { const c = new Clo(f, n, []); c.rc = 0; return c; };
  return {
    t: 0, rc: 0, n: 6,
    a0: clo((_w) => okR(unit), 1),
    a1: clo((_n, _w) => okR(mkBytes(new Uint8Array(0))), 2),
    a2: clo((_b, _w) => okR(unit), 2),
    a3: clo((_w) => okR(readLine()), 1),
    a4: clo((s, _w) => { sink(s); return okR(unit); }, 2),
    a5: clo((_w) => 0, 1),
  };
}
const mkBytes = (b) => { b.rc = 1; return b; };
const stdoutStream = mkStream((s) => stdoutSink(s), () => "");
const stderrStream = mkStream((s) => stderrSink(s), () => "");
const stdinStream = mkStream((_s) => {}, () => getLine());
P.lean_get_stdout = () => stdoutStream;
P.lean_get_stderr = () => stderrStream;
P.lean_get_stdin = () => stdinStream;

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
  const v = isNode ? globalThis.process.env[name] : undefined;
  return v === undefined ? none() : some(v);
};
P.lean_io_initializing = () => 0;
class ExitSignal { constructor(code) { this.code = code; } }
// Unwinds the stack up to `runMain` (process.exit from a worker thread with a huge stack crashes V8 teardown).
P.lean_io_exit = (code) => { throw new ExitSignal(code); };
P.lean_io_process_get_pid = () => (isNode ? globalThis.process.pid : 0);
P.lean_io_app_path = () => okR(isNode ? globalThis.process.argv[1] : "");
P.lean_io_sleep = (_ms) => unit;

let errorToString = null;
export function setErrorToString(f) { errorToString = f; }

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
    r = arity >= 2 ? main(listFromArray(args), 0) : main(0);
  } catch (e) {
    if (e instanceof ExitSignal) {
      if (isNode) globalThis.process.exitCode = e.code;
      return e.code;
    }
    throw e;
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
