#!/bin/sh
# End-to-end differential tests: native `lean --run` vs. lean2js + node.
# Usage: tests/e2e/run.sh [NAME...]     (default: all tests/e2e/*.lean)
cd "$(dirname "$0")/../.." || exit 1
lake build lean2js >/dev/null 2>&1 || { echo "build failed"; exit 1; }
mkdir -p out
export LEAN_SYSROOT=$(lake env lean --print-prefix)
cp runtime/*.js out/

names="$*"
[ -z "$names" ] && names=$(ls tests/e2e/*.lean | sed 's|.*/||; s|\.lean$||')
fail=0; pass=0
for n in $names; do
  src=tests/e2e/$n.lean
  args=""; [ -f tests/e2e/$n.args ] && args=$(cat tests/e2e/$n.args)
  input=/dev/null; [ -f tests/e2e/$n.stdin ] && input=tests/e2e/$n.stdin   # never inherit the terminal's stdin
  jsenv=""; [ -f tests/e2e/$n.env ] && jsenv=$(cat tests/e2e/$n.env)   # environment variables for the JS run only, e.g. LEAN2JS_STRICT_TASKS=1
  flags=""; [ -f tests/e2e/$n.flags ] && flags=$(cat tests/e2e/$n.flags)   # extra lean2js options, e.g. --init-all
  if [ -f tests/e2e/$n.expected ]; then
    # programs that native `lean --run` cannot run (e.g. `initialize` in the same module): checked-in expected output
    cp tests/e2e/$n.expected out/$n.expected; erc=0
  else
    lake env lean --run "$src" $args < $input > out/$n.expected 2>/dev/null; erc=$?
  fi
  if ! lake exe lean2js "$src" $flags --run --out out/$n.js 2> out/$n.transpile.err; then
    echo "FAIL (transpile): $n: $(head -c 300 out/$n.transpile.err)"; fail=$((fail+1)); continue
  fi
  env $jsenv node out/$n.js $args < $input > out/$n.actual 2> out/$n.stderr; arc=$?
  if [ $erc -eq $arc ] && cmp -s out/$n.expected out/$n.actual; then
    pass=$((pass+1)); echo "ok: $n"
  else
    fail=$((fail+1)); echo "FAIL: $n (exit native=$erc js=$arc)"
    diff out/$n.expected out/$n.actual | head -5
    head -c 400 out/$n.stderr
  fi
done
echo "passed $pass, failed $fail"
[ $fail -eq 0 ]
