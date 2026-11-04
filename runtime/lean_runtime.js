// Lean 4 runtime for JavaScript (see docs/design/js-transpiler.md).
//
// Value representation:
//   Nat, Int, UInt64, USize : BigInt          UInt8/16/32, Char : number (unsigned)
//   Float                   : number          String            : JS string
//   Bool & enum-like types  : number (constructor index; false = 0, true = 1)
//   other constructors      : {t: ctorIndex, a0: field0, a1: field1, ...}
//   erased values / world   : 0
//   closures                : Clo
//   Array                   : JS Array (treated as immutable, copy on write)
//
// Primitives are named like the C functions of the Lean runtime (lean.h), e.g. `lean_nat_add`.

export const erased = 0;

/* ---------- closures ---------- */

export class Clo {
  constructor(f, arity, args) { this.f = f; this.arity = arity; this.args = args; }
}
export function mkClo(f, arity) { return new Clo(f, arity, []); }
export function pap(f, arity, args) { return new Clo(f, arity, args); }

/** Apply closure `f` to the array `args`. */
export function ap(f, args) {
  for (;;) {
    const have = f.args.length + args.length;
    if (have < f.arity) return new Clo(f.f, f.arity, f.args.concat(args));
    const need = f.arity - f.args.length;
    const r = need === args.length
      ? f.f(...f.args, ...args)
      : f.f(...f.args, ...args.slice(0, need));
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
const nil = () => ({ t: 0 });
const cons = (h, tl) => ({ t: 1, a0: h, a1: tl });
export function listFromArray(xs) {
  let l = nil();
  for (let i = xs.length - 1; i >= 0; i--) l = cons(xs[i], l);
  return l;
}
export function listToArray(l) {
  const r = [];
  while (l.t === 1) { r.push(l.a0); l = l.a1; }
  return r;
}
const okResult = (v) => ({ t: 0, a0: v, a1: 0 });         // EST.Out.ok / ST.Out.mk
const errResult = (e) => ({ t: 1, a0: e, a1: 0 });        // EST.Out.error

/* ---------- primitives ---------- */

export const prims = {};
const P = prims;

const none = () => ({ t: 0 });
const some = (v) => ({ t: 1, a0: v });

function panicMsg(msg) { stderrSink(msg + "\n"); }
P.lean_panic_fn_borrowed = (def, msg) => { panicMsg(msg); return def; };
P.lean_panic_fn = P.lean_panic_fn_borrowed;
P.lean_system_platform_nbits = (_u) => 64n;

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
P.lean_string_mk = (l) => String.fromCodePoint(...listToArray(l));
P.lean_string_data = (s) => listFromArray(Array.from(s, (ch) => ch.codePointAt(0)));
P.lean_string_of_usize = (n) => n.toString();
P.lean_string_hash = (s) => hash64(new TextEncoder().encode(s), 11n);
P.lean_string_to_utf8 = (s) => new TextEncoder().encode(s);
P.lean_string_from_utf8_unchecked = (b) => new TextDecoder().decode(b);
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

/* ---- Array (immutable: every update copies) ---- */
const oob = (def) => { panicMsg("PANIC: index out of bounds"); return def; };
P.lean_mk_empty_array_with_capacity = (_cap) => [];
P.lean_mk_array = (n, v) => new Array(Number(n)).fill(v);
P.lean_array_mk = (l) => listToArray(l);
P.lean_array_to_list = (a) => listFromArray(a);
P.lean_array_get_size = (a) => BigInt(a.length);
P.lean_array_size = (a) => BigInt(a.length);
P.lean_array_fget = (a, i) => a[Number(i)];
P.lean_array_uget = P.lean_array_fget;
P.lean_array_get = (def, a, i) => (i < BigInt(a.length) ? a[Number(i)] : oob(def));
P.lean_array_get_borrowed = P.lean_array_get;
P.lean_array_fset = (a, i, v) => { const r = a.slice(); r[Number(i)] = v; return r; };
P.lean_array_uset = P.lean_array_fset;
P.lean_array_set = (a, i, v) => (i < BigInt(a.length) ? P.lean_array_fset(a, i, v) : (oob(0), a));
P.lean_array_push = (a, v) => { const r = a.slice(); r.push(v); return r; };
P.lean_array_pop = (a) => a.slice(0, -1);
P.lean_array_fswap = (a, i, j) => {
  const r = a.slice(), x = Number(i), y = Number(j);
  [r[x], r[y]] = [r[y], r[x]]; return r;
};
P.lean_array_swap = (a, i, j) =>
  (i < BigInt(a.length) && j < BigInt(a.length) ? P.lean_array_fswap(a, i, j) : a);

P.lean_array_propagate_mark = (_src, dst) => dst;
P.lean_array_mark_linear = (a) => a;

/* ---- ST.Ref ---- */
P.lean_st_mk_ref = (v, _w) => okResult({ v });
P.lean_st_ref_get = (r, _w) => okResult(r.v);
P.lean_st_ref_set = (r, v, _w) => { r.v = v; return okResult(unit); };
P.lean_st_ref_put = P.lean_st_ref_set;
P.lean_st_ref_swap = (r, v, _w) => { const o = r.v; r.v = v; return okResult(o); };
P.lean_st_ref_take = (r, _w) => { const o = r.v; r.v = undefined; return okResult(o); };
P.lean_st_ref_ptr_eq = (a, b, _w) => okResult(bool(a === b));

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
class Thunk { constructor(f, v) { this.f = f; this.v = v; } }
P.lean_mk_thunk = (f) => new Thunk(f, undefined);
P.lean_thunk_pure = (v) => new Thunk(null, v);
P.lean_thunk_get_own = (t) => {
  if (t.f !== null) { t.v = ap(t.f, [0]); t.f = null; }
  return t.v;
};
P.lean_thunk_get = P.lean_thunk_get_own;
class Task { constructor(v) { this.v = v; } }
P.lean_task_pure = (v) => new Task(v);
P.lean_task_spawn = (c, _prio) => new Task(ap(c, [0]));
P.lean_task_get_own = (t) => t.v;
P.lean_task_get = P.lean_task_get_own;
P.lean_task_map = (f, t, _prio, _sync) => new Task(ap(f, [t.v]));
P.lean_task_bind = (t, f, _prio, _sync) => ap(f, [t.v]);
// BaseIO.asTask / mapTask / bindTask: the actions are `BaseIO`, i.e. never fail (IO versions wrap with `toBaseIO`).
P.lean_io_as_task = (act, _prio, w) => okResult(new Task(ap(act, [w]).a0));
P.lean_io_map_task = (f, t, _prio, _sync, w) => okResult(new Task(ap(f, [t.v, w]).a0));
P.lean_io_bind_task = (t, f, _prio, _sync, w) => okResult(ap(f, [t.v, w]).a0);
P.lean_io_wait = (t, _w) => okResult(t.v);
P.lean_io_cancel = (_t, _w) => okResult(unit);
P.lean_io_check_canceled = (_w) => okResult(0);
P.lean_io_has_finished = (_t, _w) => okResult(1);

/* ---------- IO ---------- */

let stdoutSink = (s) => {
  if (globalThis.process && globalThis.process.stdout) globalThis.process.stdout.write(s);
  else console.log(s);
};
let stderrSink = (s) => {
  if (globalThis.process && globalThis.process.stderr) globalThis.process.stderr.write(s);
  else console.error(s);
};
// stdin: a line source. Node: blocking reads from fd 0; browser: set with setStdinLine(fn).
const nodeFs = globalThis.process && globalThis.process.versions && globalThis.process.versions.node
  ? await import("node:fs") : null;
let stdinLine = null;       // () => string ("" at EOF, otherwise including "\n")
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

export function setStdout(f) { stdoutSink = f; }
export function setStderr(f) { stderrSink = f; }

function mkStream(sink, readLine) {
  // IO.FS.Stream.mk flush read write getLine putStr isTty
  const clo = (f, n) => mkClo(f, n);
  return {
    t: 0,
    a0: clo((_w) => okResult(unit), 1),
    a1: clo((_n, _w) => okResult(new Uint8Array(0)), 2),
    a2: clo((_b, _w) => okResult(unit), 2),
    a3: clo((_w) => okResult(readLine()), 1),
    a4: clo((s, _w) => { sink(s); return okResult(unit); }, 2),
    a5: clo((_w) => okResult(0), 1),
  };
}
const stdoutStream = mkStream((s) => stdoutSink(s), () => "");
const stderrStream = mkStream((s) => stderrSink(s), () => "");
const stdinStream = mkStream((_s) => {}, () => getLine());
P.lean_get_stdin = (_w) => okResult(stdinStream);
P.lean_get_stdout = (_w) => okResult(stdoutStream);
P.lean_get_stderr = (_w) => okResult(stderrStream);

/** Run `main` (arity 1: `IO Unit`/`IO UInt32`; arity 2: also takes `List String`). */
export function runMain(main, arity, args = (globalThis.process ? globalThis.process.argv.slice(2) : [])) {
  const r = arity >= 2 ? main(listFromArray(args), 0) : main(0);
  if (r.t === 0) {
    const code = typeof r.a0 === "number" ? r.a0 : 0;
    if (globalThis.process) globalThis.process.exitCode = code;
    return code;
  }
  stderrSink("uncaught exception: " + JSON.stringify(r.a0) + "\n");
  if (globalThis.process) globalThis.process.exitCode = 1;
  return 1;
}
