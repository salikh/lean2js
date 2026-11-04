// Native `Expr` / `Level` / `Name` primitives of the Lean runtime (C++ in the real implementation), see
// docs/design/lean-expr-prims.md and ticket self-004. Installed into `prims` by lean_rt.js.
//
// Object layouts (IR backend, see lean_rt.js):  Expr ctors  bvar 0, fvar 1, mvar 2, sort 3, const 4, app 5, lam 6, forallE 7,
// letE 8, lit 9, mdata 10, proj 11; all have a cached `data : UInt64` as scalar field `s<n>_0` (n = #object fields);
// lam/forallE keep the binder info in `s3_8`, letE the `nondep` flag in `s4_8`.
//   Expr.Data: hash 32 | approxDepth 8 | hasFVar | hasExprMVar | hasLevelMVar | hasLevelParam | looseBVarRange 20 (low → high bits)
//   Level.Data: hash 32 | hasMVar @32 | hasParam @33 | depth @40
// New expressions are built through the compiled Lean constructors registered in `rt.exports` (lean_expr_mk_app, …) so that the
// cached data is computed by Lean code. All functions here take their arguments borrowed (as the `@&` externs) and return owned values.

const MASK32 = 0xffffffffn;
const T = { bvar: 0, fvar: 1, mvar: 2, sort: 3, const: 4, app: 5, lam: 6, forallE: 7, letE: 8, lit: 9, mdata: 10, proj: 11 };

export function install(P, h) {
  const { inc, dec, ap, some, exports: X, mixHash } = h;
  const bool = (b) => (b ? 1 : 0);

  const dataOf = (e) => e["s" + e.n + "_0"];
  const range = (e) => Number(dataOf(e) >> 44n);
  const hashOf = (e) => dataOf(e) & MASK32;
  const hasFVarOrMVar = (e) => (dataOf(e) & (3n << 40n)) !== 0n;

  /* ---- Name / Level equality ---- */
  function nameEq(a, b) {
    for (;;) {
      if (a === b) return true;
      if (typeof a === "number" || typeof b === "number") return false;
      if (a.t !== b.t || a.s2_0 !== b.s2_0 || a.a1 !== b.a1) return false;
      a = a.a0; b = b.a0;
    }
  }
  function levelEq(a, b) {
    if (a === b) return true;
    if (typeof a === "number" || typeof b === "number") return false;
    if (a.t !== b.t || dataOf(a) !== dataOf(b)) return false;
    switch (a.t) {
      case 1: return levelEq(a.a0, b.a0);
      case 2: case 3: return levelEq(a.a0, b.a0) && levelEq(a.a1, b.a1);
      default: return nameEq(a.a0, b.a0);          // param, mvar
    }
  }
  function levelsEq(a, b) {
    while (typeof a !== "number" && typeof b !== "number") {
      if (!levelEq(a.a0, b.a0)) return false;
      a = a.a1; b = b.a1;
    }
    return a === b;                                // both nil
  }
  P.lean_name_eq = (a, b) => bool(nameEq(a, b));
  P.lean_level_eq = (a, b) => bool(levelEq(a, b));

  /* ---- cached data ---- */
  P.lean_expr_data = (e) => dataOf(e);
  P.lean_expr_mk_data = (hash, looseBVarRange, approxDepth, fv, em, lm, lp) => {
    if (looseBVarRange >= (1n << 20n)) throw new Error("bound variable index is too big");
    const d = approxDepth > 255 ? 255n : BigInt(approxDepth);
    return (hash & MASK32) + (d << 32n) + (BigInt(fv) << 40n) + (BigInt(em) << 41n) + (BigInt(lm) << 42n) + (BigInt(lp) << 43n) + (looseBVarRange << 44n);
  };
  P.lean_expr_mk_app_data = (f, a) => {
    const df = (f >> 32n) & 255n, da = (a >> 32n) & 255n;
    let depth = (df > da ? df : da) + 1n;
    if (depth > 255n) depth = 255n;
    const rf = f >> 44n, ra = a >> 44n;
    const r = rf > ra ? rf : ra;
    if (r >= (1n << 20n)) throw new Error("bound variable index is too big");
    const hash = mixHash(f, a) & MASK32;
    return ((f | a) & (15n << 40n)) | hash | (depth << 32n) | (r << 44n);
  };
  P.lean_level_mk_data = (hash, depth, hasMVar, hasParam) => {
    if (depth >= (1n << 24n)) throw new Error("universe level depth is too big");
    return (hash & MASK32) + (BigInt(hasMVar) << 32n) + (BigInt(hasParam) << 33n) + (depth << 40n);
  };

  /* ---- generic bottom-up rewriting (the kernel's replace_rec_fn): f(m, offset) → owned Expr, or null to descend ---- */
  const mkBVar = (i) => X.lean_expr_mk_bvar(i);
  function replace(e, f) {
    const cache = new Map();                       // offset → Map(shared subterm → owned result)
    function go(m, off) {
      const shared = m.rc !== 1;
      let c;
      if (shared) {
        c = cache.get(off);
        if (c === undefined) cache.set(off, (c = new Map()));
        const r = c.get(m);
        if (r !== undefined) { inc(r); return r; }
      }
      let r = f(m, off);
      if (r === null) r = rebuild(m, off);
      if (shared) { inc(r); c.set(m, r); }
      return r;
    }
    function same(m, ...pairs) {                   // all rebuilt children identical to the originals? then drop them
      for (let i = 0; i < pairs.length; i += 2) if (pairs[i] !== pairs[i + 1]) return false;
      for (let i = 0; i < pairs.length; i += 2) dec(pairs[i]);
      inc(m);
      return true;
    }
    function rebuild(m, off) {
      switch (m.t) {
        case T.app: {
          const a = go(m.a0, off), b = go(m.a1, off);
          return same(m, a, m.a0, b, m.a1) ? m : X.lean_expr_mk_app(a, b);
        }
        case T.lam: case T.forallE: {
          const d = go(m.a1, off), b = go(m.a2, off + 1);
          if (same(m, d, m.a1, b, m.a2)) return m;
          inc(m.a0);
          return (m.t === T.lam ? X.lean_expr_mk_lambda : X.lean_expr_mk_forall)(m.a0, d, b, m.s3_8);
        }
        case T.letE: {
          const t = go(m.a1, off), v = go(m.a2, off), b = go(m.a3, off + 1);
          if (same(m, t, m.a1, v, m.a2, b, m.a3)) return m;
          inc(m.a0);
          return X.lean_expr_mk_let(m.a0, t, v, b, m.s4_8);
        }
        case T.mdata: {
          const x = go(m.a1, off);
          if (same(m, x, m.a1)) return m;
          inc(m.a0);
          return X.lean_expr_mk_mdata(m.a0, x);
        }
        case T.proj: {
          const x = go(m.a2, off);
          if (same(m, x, m.a2)) return m;
          inc(m.a0); inc(m.a1);
          return X.lean_expr_mk_proj(m.a0, m.a1, x);
        }
        default: inc(m); return m;
      }
    }
    const r = go(e, 0);
    for (const c of cache.values()) for (const v of c.values()) dec(v);
    return r;
  }
  const keep = (m) => { inc(m); return m; };

  /* ---- loose bound variables ---- */
  function lift(e, s, d) {
    if (d === 0 || range(e) <= s) return keep(e);
    return replace(e, (m, off) => {
      const s1 = s + off;
      if (range(m) <= s1) return keep(m);
      if (m.t === T.bvar) return mkBVar(m.a0 + BigInt(d));       // idx >= s1 here
      return null;
    });
  }
  function lower(e, s, d) {
    if (d === 0 || range(e) <= s) return keep(e);
    return replace(e, (m, off) => {
      const s1 = s + off;
      if (range(m) <= s1) return keep(m);
      if (m.t === T.bvar) return mkBVar(m.a0 - BigInt(d));
      return null;
    });
  }
  P.lean_expr_lift_loose_bvars = (e, s, d) => lift(e, Number(s), Number(d));
  P.lean_expr_lower_loose_bvars = (e, s, d) => lower(e, Number(s), Number(d));

  function hasLoose(m, i) {
    if (range(m) <= i) return false;
    switch (m.t) {
      case T.bvar: return Number(m.a0) === i;
      case T.app: return hasLoose(m.a0, i) || hasLoose(m.a1, i);
      case T.lam: case T.forallE: return hasLoose(m.a1, i) || hasLoose(m.a2, i + 1);
      case T.letE: return hasLoose(m.a1, i) || hasLoose(m.a2, i) || hasLoose(m.a3, i + 1);
      case T.mdata: return hasLoose(m.a1, i);
      case T.proj: return hasLoose(m.a2, i);
      default: return false;
    }
  }
  P.lean_expr_has_loose_bvar = (e, i) => bool(i < (1n << 20n) && hasLoose(e, Number(i)));

  /* ---- instantiate / abstract ---- */
  // bvar (off + j) for j < n  ↦  get(j) (lifted by off); bvars beyond are lowered by n
  function instantiate(e, n, get) {
    if (n === 0 || range(e) === 0) return keep(e);
    return replace(e, (m, off) => {
      if (range(m) <= off) return keep(m);
      if (m.t === T.bvar) {
        const idx = Number(m.a0);
        if (idx < off + n) return lift(get(idx - off), 0, off);
        return mkBVar(BigInt(idx - n));
      }
      return null;
    });
  }
  P.lean_expr_instantiate = (e, subst) => instantiate(e, subst.length, (j) => subst[j]);
  P.lean_expr_instantiate1 = (e, s) => instantiate(e, 1, () => s);
  P.lean_expr_instantiate_rev = (e, subst) => instantiate(e, subst.length, (j) => subst[subst.length - j - 1]);
  const rangeArgs = (b, en, subst) => {
    const lo = Number(b), hi = Number(en);
    if (lo > hi || hi > subst.length) throw new Error("invalid instantiateRange arguments");
    return [lo, hi];
  };
  P.lean_expr_instantiate_range = (e, b, en, subst) => {
    const [lo, hi] = rangeArgs(b, en, subst);
    return instantiate(e, hi - lo, (j) => subst[lo + j]);
  };
  P.lean_expr_instantiate_rev_range = (e, b, en, subst) => {
    const [lo, hi] = rangeArgs(b, en, subst);
    return instantiate(e, hi - lo, (j) => subst[hi - j - 1]);
  };
  function abstractRange(e, n, xs) {
    n = Math.min(n, xs.length);
    if (n === 0 || !hasFVarOrMVar(e)) return keep(e);
    return replace(e, (m, off) => {
      if (!hasFVarOrMVar(m)) return keep(m);
      if (m.t === T.fvar || m.t === T.mvar) {
        for (let i = n - 1; i >= 0; i--) {
          const x = xs[i];
          if (x.t === m.t && nameEq(x.a0, m.a0)) return mkBVar(BigInt(off + n - i - 1));
        }
        return keep(m);
      }
      return null;
    });
  }
  P.lean_expr_abstract = (e, xs) => abstractRange(e, xs.length, xs);
  P.lean_expr_abstract_range = (e, n, xs) => abstractRange(e, Number(n), xs);

  /* ---- equality and ordering ---- */
  function exprEq(a, b, binderInfo) {
    const seen = new Map();                        // shared pairs already proven equal
    function go(a, b) {
      if (a === b) return true;
      if (hashOf(a) !== hashOf(b) || a.t !== b.t) return false;
      const shared = a.rc !== 1 && b.rc !== 1;
      if (shared) { const s = seen.get(a); if (s !== undefined && s.has(b)) return true; }
      let r;
      switch (a.t) {
        case T.bvar: r = a.a0 === b.a0; break;
        case T.fvar: case T.mvar: r = nameEq(a.a0, b.a0); break;
        case T.sort: r = levelEq(a.a0, b.a0); break;
        case T.const: r = nameEq(a.a0, b.a0) && levelsEq(a.a1, b.a1); break;
        case T.app: r = go(a.a0, b.a0) && go(a.a1, b.a1); break;
        case T.lam: case T.forallE:
          r = go(a.a1, b.a1) && go(a.a2, b.a2) && (!binderInfo || a.s3_8 === b.s3_8); break;
        case T.letE: r = go(a.a1, b.a1) && go(a.a2, b.a2) && go(a.a3, b.a3); break;
        case T.lit: r = a.a0.t === b.a0.t && a.a0.a0 === b.a0.a0; break;
        case T.mdata: r = go(a.a1, b.a1); break;
        case T.proj: r = a.a1 === b.a1 && nameEq(a.a0, b.a0) && go(a.a2, b.a2); break;
        default: r = false;
      }
      if (r && shared) { let s = seen.get(a); if (s === undefined) seen.set(a, (s = new Set())); s.add(b); }
      return r;
    }
    return go(a, b);
  }
  P.lean_expr_eqv = (a, b) => bool(exprEq(a, b, false));
  P.lean_expr_equal = (a, b) => bool(exprEq(a, b, true));
  // Approximation of the C++ total order: by hash first, then by constructor; ties between different structures are broken
  // arbitrarily but consistently (hash collisions are rare). See self-004.
  P.lean_expr_quick_lt = (a, b) => {
    if (a === b) return 0;
    const ha = hashOf(a), hb = hashOf(b);
    if (ha !== hb) return bool(ha < hb);
    if (a.t !== b.t) return bool(a.t < b.t);
    return 0;
  };
  P.lean_expr_dbg_to_string = (_e) => "<expr>";

  /* ---- find / replace with Lean callbacks ---- */
  function children(m) {
    switch (m.t) {
      case T.app: return [m.a0, m.a1];
      case T.lam: case T.forallE: return [m.a1, m.a2];
      case T.letE: return [m.a1, m.a2, m.a3];
      case T.mdata: return [m.a1];
      case T.proj: return [m.a2];
      default: return [];
    }
  }
  P.lean_find_expr = (p, e) => {
    const seen = new Set();
    function go(m) {
      if (m.rc !== 1) { if (seen.has(m)) return null; seen.add(m); }
      inc(p); inc(m);
      if (ap(p, [m])) return m;
      for (const c of children(m)) { const r = go(c); if (r !== null) return r; }
      return null;
    }
    const r = go(e);
    if (r === null) return 0;
    inc(r);
    return some(r);
  };
  P.lean_replace_expr = (f, e) =>
    replace(e, (m, _off) => {
      inc(f); inc(m);
      const r = ap(f, [m]);                         // Option Expr, owned
      if (typeof r === "number") return null;
      const v = r.a0; inc(v); dec(r);
      return v;
    });
}
