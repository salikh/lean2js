// Fixed-width signed integers (Int8/16/32/64, ISize) and Float32 for the IR runtime.
// Representation (as in the C runtime): the unsigned bit pattern — a JS number for 8/16/32 bits, a BigInt for 64 bits (ISize = 64).

export function install(P, { bool }) {
  const widths = { int8: 8, int16: 16, int32: 32, int64: 64, isize: 64 };
  for (const [name, bits] of Object.entries(widths)) {
    const big = bits === 64;
    const B = BigInt(bits);
    const toBig = big ? (x) => x : (x) => BigInt(x);
    const out = big ? (v) => BigInt.asUintN(bits, v) : (v) => Number(BigInt.asUintN(bits, v));
    const sgn = (x) => BigInt.asIntN(bits, toBig(x));
    const def = (op, f) => { P[`lean_${name}_${op}`] = f; };
    def("neg", (a) => out(-sgn(a)));
    def("add", (a, b) => out(sgn(a) + sgn(b)));
    def("sub", (a, b) => out(sgn(a) - sgn(b)));
    def("mul", (a, b) => out(sgn(a) * sgn(b)));
    def("div", (a, b) => (sgn(b) === 0n ? out(0n) : out(sgn(a) / sgn(b))));        // truncating; x / 0 = 0
    def("mod", (a, b) => (sgn(b) === 0n ? a : out(sgn(a) % sgn(b))));              // sign of the dividend; x % 0 = x
    def("land", (a, b) => out(toBig(a) & toBig(b)));
    def("lor", (a, b) => out(toBig(a) | toBig(b)));
    def("xor", (a, b) => out(toBig(a) ^ toBig(b)));
    def("complement", (a) => out(~toBig(a)));
    const sh = (b) => ((sgn(b) % B) + B) % B;                                      // shift amount: b mod bits (non-negative)
    def("shift_left", (a, b) => out(toBig(a) << sh(b)));
    def("shift_right", (a, b) => out(sgn(a) >> sh(b)));                            // arithmetic
    def("dec_eq", (a, b) => bool(a === b));
    def("dec_lt", (a, b) => bool(sgn(a) < sgn(b)));
    def("dec_le", (a, b) => bool(sgn(a) <= sgn(b)));
    def("of_nat", (n) => out(n));
    def("of_int", (n) => out(n));
    def("to_int", (a) => sgn(a));
    def("to_int_sint", (a) => sgn(a));
    def("to_nat", (a) => { const v = sgn(a); return v < 0n ? 0n : v; });
    for (const [other, ob] of Object.entries(widths)) {
      if (other === name) continue;
      const oBig = ob === 64;
      def(`to_${other}`, (a) => (oBig ? BigInt.asUintN(ob, sgn(a)) : Number(BigInt.asUintN(ob, sgn(a)))));
    }
    def(`to_int${bits}`, (a) => a);
    for (const [u, ub] of [["uint8", 8], ["uint16", 16], ["uint32", 32], ["uint64", 64], ["usize", 64]]) {
      // Int → UInt conversions keep the bit pattern (two's complement truncation)
      def(`to_${u}`, (a) => (ub === 64 ? BigInt.asUintN(64, sgn(a)) : Number(BigInt.asUintN(ub, sgn(a)))));
    }
  }
  P.lean_int64_to_int_sint = P.lean_int64_to_int;

  /* ---- Float32: JS numbers kept rounded with Math.fround ---- */
  const f32 = Math.fround;
  P.lean_float32_add = (a, b) => f32(a + b);
  P.lean_float32_sub = (a, b) => f32(a - b);
  P.lean_float32_mul = (a, b) => f32(a * b);
  P.lean_float32_div = (a, b) => f32(a / b);
  P.lean_float32_negate = (a) => -a;
  P.lean_float32_beq = (a, b) => bool(a === b);
  P.lean_float32_decLt = (a, b) => bool(a < b);
  P.lean_float32_decLe = (a, b) => bool(a <= b);
  P.lean_float32_of_nat = (n) => f32(Number(n));
  P.lean_float32_of_int = (n) => f32(Number(n));
  P.lean_float32_of_scientific = (m, neg, e) => f32(Number(`${m}e${neg ? "-" : ""}${e}`));
  P.lean_float32_of_bits = (b) => { const v = new DataView(new ArrayBuffer(4)); v.setUint32(0, b); return v.getFloat32(0); };
  P.lean_float32_to_bits = (x) => { const v = new DataView(new ArrayBuffer(4)); v.setFloat32(0, x); return v.getUint32(0); };
  P.lean_float32_isnan = (x) => bool(Number.isNaN(x));
  P.lean_float32_isinf = (x) => bool(x === Infinity || x === -Infinity);
  P.lean_float32_isfinite = (x) => bool(Number.isFinite(x));
  P.lean_float32_to_string = (x) => P.lean_float_to_string(x);
  P.lean_float_to_float32 = (x) => f32(x);
  P.lean_float32_to_float = (x) => x;
  P.lean_uint64_to_float32 = (n) => f32(Number(n));

  /* ---- exact division, modular power ---- */
  P.lean_nat_div_exact = (a, b) => a / b;
  P.lean_int_div_exact = (a, b) => a / b;
  P.lean_nat_powmod = (a, b, m) => {
    if (m === 0n) return a ** b;
    let r = 1n % m, x = a % m, e = b;
    while (e > 0n) { if (e & 1n) r = (r * x) % m; x = (x * x) % m; e >>= 1n; }
    return r;
  };
}
