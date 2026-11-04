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

/* ---------- Nat / Int ---------- */

export const lean_nat_add = (a, b) => a + b;
export const lean_nat_sub = (a, b) => (a > b ? a - b : 0n);
export const lean_nat_mul = (a, b) => a * b;
export const lean_nat_div = (a, b) => (b === 0n ? 0n : a / b);
export const lean_nat_mod = (a, b) => (b === 0n ? a : a % b);
export const lean_nat_dec_eq = (a, b) => bool(a === b);
export const lean_nat_dec_lt = (a, b) => bool(a < b);
export const lean_nat_dec_le = (a, b) => bool(a <= b);

/* ---------- String ---------- */

export const lean_string_append = (a, b) => a + b;
export const lean_string_push = (s, c) => s + String.fromCodePoint(c);

/* ---------- IO ---------- */

let stdoutSink = (s) => {
  if (globalThis.process && globalThis.process.stdout) globalThis.process.stdout.write(s);
  else console.log(s);
};
let stderrSink = (s) => {
  if (globalThis.process && globalThis.process.stderr) globalThis.process.stderr.write(s);
  else console.error(s);
};
export function setStdout(f) { stdoutSink = f; }
export function setStderr(f) { stderrSink = f; }

function mkStream(sink) {
  // IO.FS.Stream.mk flush read write getLine putStr isTty
  const clo = (f, n) => mkClo(f, n);
  return {
    t: 0,
    a0: clo((_w) => okResult(unit), 1),
    a1: clo((_n, _w) => okResult(new Uint8Array(0)), 2),
    a2: clo((_b, _w) => okResult(unit), 2),
    a3: clo((_w) => okResult(""), 1),
    a4: clo((s, _w) => { sink(s); return okResult(unit); }, 2),
    a5: clo((_w) => okResult(0), 1),
  };
}
const stdoutStream = mkStream((s) => stdoutSink(s));
const stderrStream = mkStream((s) => stderrSink(s));
export const lean_get_stdout = (_w) => okResult(stdoutStream);
export const lean_get_stderr = (_w) => okResult(stderrStream);

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
