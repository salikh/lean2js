// .olean (compacted region) reader — `CompactedRegion.read` for the JS runtime. See docs/design/olean-loader.md.
//
// File layout (format v2, Lean 4.35): header of 88 bytes
//   0  "olean" | 5 version (2) | 6 flags | 7..39 Lean version string (33) | 40..79 git hash (40) | 80 base address (u64)
// then 88: pointer to the root object, and from 96 the objects, children before parents, each 8-byte aligned.
// A pointer is either a boxed scalar `(n << 1) | 1` or the absolute address `base + file offset` (also into *other* regions
// passed as `deps`, for multi-part modules). Object headers: `i32 rc (0 = persistent) | u16 cs_sz | u8 other | u8 tag`.
//   tag ≤ 244 constructor: `other` = #object fields, `cs_sz` = total size in bytes; then the pointers, then the scalar area
//   246 Array (size, capacity, elements) | 248 ScalarArray (`other` = element size) | 249 String (size incl. NUL, capacity, length, bytes)
//   250 MPZ (alloc i32, size i32 (sign), limb pointer, limbs) | 251 Thunk (value, closure) | 252 Task (value) | 253 Ref (value)
//
// Result objects use the IR runtime representation (see lean_rt.js): ctor objects `{t, rc: 0, n, a0…}`, boxed scalars as JS
// numbers (a BigInt beyond 2^53), Arrays as JS arrays, strings as JS strings. The *scalar area* of constructors is not decoded
// (its field types are unknown here): the object keeps `sbuf` (a DataView of the file) and `soff` (start of its scalar area) and
// the generated code reads fields through `sget`/`uget`, which decode and cache them as `s<n>_<off>` / `u<i>` properties.

const utf8 = new TextDecoder();

/** Decodes scalar field `s<n>_<off>` of a loaded constructor object `x` (type code: 1,2,4,8 = UIntN, 9 = Float, 10 = Float32). */
export function sget(x, n, off, code) {
  const dv = x.sbuf;
  const pos = x.soff + 8 * (n - x.n) + off;
  let v;
  switch (code) {
    case 1: v = dv.getUint8(pos); break;
    case 2: v = dv.getUint16(pos, true); break;
    case 4: v = dv.getUint32(pos, true); break;
    case 9: v = dv.getFloat64(pos, true); break;
    case 10: v = dv.getFloat32(pos, true); break;
    default: v = dv.getBigUint64(pos, true);
  }
  x["s" + n + "_" + off] = v;
  return v;
}
/** Decodes usize field `u<i>` (slot index `i` counts the object fields too). */
export function uget(x, i) {
  const v = x.sbuf.getBigUint64(x.soff + 8 * (i - x.n), true);
  x["u" + i] = v;
  return v;
}

/** Loaded regions sorted by base address (binary search for cross-region pointers). */
const regions = [];
function regionAt(addr, hint) {
  if (hint !== null && addr >= hint.base && addr < hint.base + hint.size) return hint;
  let lo = 0, hi = regions.length - 1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1, r = regions[mid];
    if (addr < r.base) hi = mid - 1;
    else if (addr >= r.base + r.size) lo = mid + 1;
    else return r;
  }
  return null;
}

/**
 * Parses an .olean file image. `deps`: regions (as returned here) whose objects may be referenced. `hooks`: { Thunk, Task, Ref }
 * constructors of the runtime. Returns { root, base, size, objs }.
 */
export function parseRegion(bytes, deps, hooks, name = "<olean>") {
  const dv = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const magic = String.fromCharCode(...bytes.subarray(0, 5));
  if (magic !== "olean") throw new Error(`${name}: not an .olean file`);
  const version = bytes[5];
  if (version !== 2) throw new Error(`${name}: unsupported .olean format version ${version} (only v2)`);
  const base = dv.getUint32(80, true) + dv.getUint32(84, true) * 4294967296;
  const size = bytes.length;
  const objs = new Array(size >> 3);
  const region = { base, size, objs, bytes, dv };
  let hint = null;                                       // last dependency region hit (pointers cluster)

  const ptr = (lo, hi) => {
    if (lo & 1) {                                        // boxed scalar
      if (hi < 0x200000) return hi * 2147483648 + (lo >>> 1);
      return (BigInt(hi) << 31n) | BigInt(lo >>> 1);
    }
    if (lo === 0 && hi === 0) return undefined;
    const addr = hi * 4294967296 + lo;
    const off = addr - base;
    if (off >= 0 && off < size) {
      const v = objs[off >> 3];
      if (v === undefined) throw new Error(`${name}: forward reference to offset ${off}`);
      return v;
    }
    const r = regionAt(addr, hint) ?? deps.find((d) => addr >= d.base && addr < d.base + d.size) ?? null;
    if (r !== null) { hint = r; return r.objs[(addr - r.base) >> 3]; }
    throw new Error(`${name}: pointer 0x${addr.toString(16)} outside the region and its dependencies`);
  };

  // 32-bit view for the headers and pointers (copy when the buffer is not 4-byte aligned)
  const aligned = (bytes.byteOffset & 3) === 0;
  const u32 = new Uint32Array(aligned ? bytes.buffer : bytes.slice().buffer, aligned ? bytes.byteOffset : 0, size >> 2);
  let off = 96;
  while (off < size) {
    const w = u32[(off >> 2) + 1];
    const csSz = w & 0xffff, other = (w >>> 16) & 0xff, tag = w >>> 24;
    let obj, len;
    if (tag <= 244) {
      len = csSz;
      const q = (off >> 2) + 2;
      switch (other) {
        case 0: obj = { t: tag, rc: 0, n: 0 }; break;
        case 1: obj = { t: tag, rc: 0, n: 1, a0: ptr(u32[q], u32[q + 1]) }; break;
        case 2: obj = { t: tag, rc: 0, n: 2, a0: ptr(u32[q], u32[q + 1]), a1: ptr(u32[q + 2], u32[q + 3]) }; break;
        case 3: obj = { t: tag, rc: 0, n: 3, a0: ptr(u32[q], u32[q + 1]), a1: ptr(u32[q + 2], u32[q + 3]), a2: ptr(u32[q + 4], u32[q + 5]) }; break;
        default:
          obj = { t: tag, rc: 0, n: other };
          for (let i = 0; i < other; i++) obj["a" + i] = ptr(u32[q + 2 * i], u32[q + 2 * i + 1]);
      }
      if (len > 8 + 8 * other) { obj.sbuf = dv; obj.soff = off + 8 + 8 * other; }
    } else if (tag === 246) {
      const q = off >> 2, n = u32[q + 2], cap = u32[q + 4];
      obj = new Array(n);
      for (let i = 0; i < n; i++) obj[i] = ptr(u32[q + 6 + 2 * i], u32[q + 7 + 2 * i]);
      obj.rc = 0;
      len = 24 + 8 * cap;
    } else if (tag === 249) {
      const q = off >> 2, sz = u32[q + 2], cap = u32[q + 4];
      const start = off + 32, end = start + sz - 1;
      obj = utf8.decode(bytes.subarray(start, end));
      len = 32 + ((cap + 7) & ~7);
    } else if (tag === 248) {
      const n = dv.getUint32(off + 8, true), cap = dv.getUint32(off + 16, true);
      if (other === 1) obj = bytes.slice(off + 24, off + 24 + n);
      else if (other === 8) obj = new Float64Array(bytes.slice(off + 24, off + 24 + 8 * n).buffer);
      else throw new Error(`${name}: scalar array with element size ${other}`);
      obj.rc = 0;
      len = 24 + ((cap * other + 7) & ~7);
    } else if (tag === 250) {
      const sz = dv.getInt32(off + 12, true), n = Math.abs(sz);
      let v = 0n;
      for (let i = n - 1; i >= 0; i--) v = (v << 64n) | dv.getBigUint64(off + 24 + 8 * i, true);
      obj = sz < 0 ? -v : v;
      len = csSz;
    } else if (tag === 251) {
      obj = new hooks.Thunk(null, ptr(dv.getUint32(off + 8, true), dv.getUint32(off + 12, true))); obj.rc = 0; len = 24;
    } else if (tag === 252) {
      obj = new hooks.Task(ptr(dv.getUint32(off + 8, true), dv.getUint32(off + 12, true))); obj.rc = 0; len = 24;
    } else if (tag === 253) {
      obj = new hooks.Ref(ptr(dv.getUint32(off + 8, true), dv.getUint32(off + 12, true))); obj.rc = 0; len = 16;
    } else {
      throw new Error(`${name}: unsupported object tag ${tag} at offset ${off}`);
    }
    objs[off >> 3] = obj;
    off += len;
  }
  const rootOff = ptr(dv.getUint32(88, true), dv.getUint32(92, true));
  let i = regions.length;
  while (i > 0 && regions[i - 1].base > base) i--;
  regions.splice(i, 0, region);
  region.root = rootOff;
  return region;
}

export function freeRegion(base) {
  const i = regions.findIndex((r) => r.base === base);
  if (i >= 0) regions.splice(i, 1);
}
