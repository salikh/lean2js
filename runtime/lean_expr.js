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
  /** Rebuild `m` from its transformed children (`sub(child, binderDepthDelta)` → owned); returns an owned `m` itself if nothing changed. */
  function rebuildNode(m, sub) {
    const same = (...pairs) => {
      for (let i = 0; i < pairs.length; i += 2) if (pairs[i] !== pairs[i + 1]) return false;
      for (let i = 0; i < pairs.length; i += 2) dec(pairs[i]);
      inc(m);
      return true;
    };
    switch (m.t) {
      case T.app: {
        const a = sub(m.a0, 0), b = sub(m.a1, 0);
        return same(a, m.a0, b, m.a1) ? m : X.lean_expr_mk_app(a, b);
      }
      case T.lam: case T.forallE: {
        const d = sub(m.a1, 0), b = sub(m.a2, 1);
        if (same(d, m.a1, b, m.a2)) return m;
        inc(m.a0);
        return (m.t === T.lam ? X.lean_expr_mk_lambda : X.lean_expr_mk_forall)(m.a0, d, b, m.s3_8);
      }
      case T.letE: {
        const t = sub(m.a1, 0), v = sub(m.a2, 0), b = sub(m.a3, 1);
        if (same(t, m.a1, v, m.a2, b, m.a3)) return m;
        inc(m.a0);
        return X.lean_expr_mk_let(m.a0, t, v, b, m.s4_8);
      }
      case T.mdata: {
        const x = sub(m.a1, 0);
        if (same(x, m.a1)) return m;
        inc(m.a0);
        return X.lean_expr_mk_mdata(m.a0, x);
      }
      case T.proj: {
        const x = sub(m.a2, 0);
        if (same(x, m.a2)) return m;
        inc(m.a0); inc(m.a1);
        return X.lean_expr_mk_proj(m.a0, m.a1, x);
      }
      default: inc(m); return m;
    }
  }
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
    const rebuild = (m, off) => rebuildNode(m, (c, d) => go(c, off + d));
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

  /* ---- instantiate metavariables (port of kernel/instantiate_mvars.cpp; mctx accessors are compiled Lean `@[export]`s) ---- */
  const hasLMVar = (l) => typeof l !== "number" && ((dataOf(l) >> 32n) & 1n) === 1n;
  const hasAnyMVar = (e) => (dataOf(e) & (3n << 41n)) !== 0n;
  const hasExprMVar = (e) => (dataOf(e) & (1n << 41n)) !== 0n;
  const mkPair = (a, b) => ({ t: 0, rc: 1, n: 2, a0: a, a1: b });
  const mkCons = (a, b) => ({ t: 1, rc: 1, n: 2, a0: a, a1: b });

  /** Substitutes bvars `0..sz-1` of `f`'s body binders by `revArgs` (Expr.betaRev with useZeta := true). All arguments borrowed. */
  function betaRev(f, revArgs) {
    const sz = revArgs.length;
    if (sz === 0) return keep(f);
    let e = f, i = 0;
    for (;;) {
      if (e.t === T.lam) {
        if (i + 1 < sz) { e = e.a2; i++; continue; }
        return instantiate(e.a2, sz, (j) => revArgs[j]);
      }
      if (e.t === T.letE) { e = instantiate(e.a3, 1, () => e.a2); continue; }       // zeta (the new `e` is owned and leaked on purpose)
      if (e.t === T.mdata) { e = e.a1; continue; }
      const n = sz - i;
      let r = instantiate(e, sz - n, (j) => revArgs[n + j]);
      for (let k = n - 1; k >= 0; k--) { inc(revArgs[k]); r = X.lean_expr_mk_app(r, revArgs[k]); }
      return r;
    }
  }

  function makeInstantiator(mctxIn) {
    let mctx = mctxIn;                                  // owned; threaded through assignments
    const call = (fn, ...args) => { inc(mctx); for (const a of args) inc(a); return fn(mctx, ...args); };
    const assign = (fn, mid, v) => { inc(mid); inc(v); mctx = fn(mctx, mid, v); };

    function lvl(l) {
      if (!hasLMVar(l)) return keep(l);
      switch (l.t) {
        case 1: { const x = lvl(l.a0); if (x === l.a0) { dec(x); return keep(l); } return X.lean_level_mk_succ(x); }
        case 2: case 3: {
          const a = lvl(l.a0), b = lvl(l.a1);
          if (a === l.a0 && b === l.a1) { dec(a); dec(b); return keep(l); }
          return (l.t === 2 ? X.lean_level_mk_max : X.lean_level_mk_imax)(a, b);
        }
        case 5: {
          const o = call(X.lean_get_lmvar_assignment, l.a0);
          if (typeof o === "number") return keep(l);
          const a = o.a0; inc(a); dec(o);
          if (!hasLMVar(a)) return a;
          const a2 = lvl(a);
          if (a2 !== a) assign(X.lean_assign_lmvar, l.a0, a2);
          return a2;
        }
        default: return keep(l);
      }
    }
    const cache = new Map();
    function getAssign(mid) {                           // instantiated assignment (owned) or null
      const o = call(X.lean_get_mvar_assignment, mid);
      if (typeof o === "number") return null;
      const a = o.a0; inc(a); dec(o);
      if (!hasAnyMVar(a)) return a;
      const a2 = visit(a);
      if (a2 !== a) assign(X.lean_assign_mvar, mid, a2);
      return a2;
    }
    function visit(e) {
      if (!hasAnyMVar(e)) return keep(e);
      const shared = e.rc !== 1;
      if (shared) { const r = cache.get(e); if (r !== undefined) { inc(r); return r; } }
      let r;
      switch (e.t) {
        case T.sort: { const l = lvl(e.a0); if (l === e.a0) { dec(l); r = keep(e); } else r = X.lean_expr_mk_sort(l); break; }
        case T.const: {
          const lv = []; for (let l = e.a1; typeof l !== "number"; l = l.a1) lv.push(l.a0);
          const nv = lv.map(lvl);
          if (nv.every((x, i) => x === lv[i])) { nv.forEach(dec); r = keep(e); }
          else { let lst = 0; for (let i = nv.length - 1; i >= 0; i--) lst = mkCons(nv[i], lst); inc(e.a0); r = X.lean_expr_mk_const(e.a0, lst); }
          break;
        }
        case T.mvar: { const a = getAssign(e.a0); r = a === null ? keep(e) : a; break; }
        case T.app: r = visitApp(e); break;
        default: r = rebuildNode(e, (c) => visit(c));
      }
      if (shared) { inc(r); cache.set(e, r); }
      return r;
    }
    function mvarAppArgs(e) {
      return e.t === T.app ? X.lean_expr_mk_app(mvarAppArgs(e.a0), visit(e.a1)) : keep(e);
    }
    function visitApp(e) {
      const args = []; let f = e;
      while (f.t === T.app) { args.push(f.a1); f = f.a0; }
      args.reverse();                                   // a_1 … a_n
      if (f.t !== T.mvar) return rebuildNode(e, (c) => visit(c));
      const mid = f.a0;
      const a = getAssign(mid);
      if (a !== null) {
        const vs = args.map(visit).reverse();           // reversed for betaRev
        return betaRev(a, vs);
      }
      const d = call(X.lean_get_delayed_mvar_assignment, mid);
      if (typeof d === "number") return mvarAppArgs(e);
      const dv = d.a0, fvars = dv.a0, pending = dv.a1;
      if (fvars.length > args.length) return mvarAppArgs(e);
      const val = getAssign(pending);
      if (val === null || hasExprMVar(val)) return mvarAppArgs(e);
      const vs = args.map(visit);
      const abs = abstractRange(val, fvars.length, fvars);
      let r = instantiate(abs, fvars.length, (j) => vs[fvars.length - j - 1]);   // instantiateRevRange 0 fvars.size args
      for (let i = fvars.length; i < vs.length; i++) { inc(vs[i]); r = X.lean_expr_mk_app(r, vs[i]); }
      return r;
    }
    return { lvl, visit, mctx: () => mctx };
  }
  P.lean_instantiate_level_mvars = (mctx, l) => { const I = makeInstantiator(mctx); const r = I.lvl(l); return mkPair(I.mctx(), r); };
  P.lean_instantiate_expr_mvars = (mctx, e) => { const I = makeInstantiator(mctx); const r = I.visit(e); return mkPair(I.mctx(), r); };
}
