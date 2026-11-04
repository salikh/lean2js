#!/bin/sh
# End-to-end differential tests: native `lean --run` vs. lean2js + node.
# Usage: tests/e2e/run.sh [NAME...]     (default: all tests/e2e/*.lean)
cd "$(dirname "$0")/../.." || exit 1
lake build lean2js >/dev/null 2>&1 || { echo "build failed"; exit 1; }
mkdir -p out
cp runtime/lean_runtime.js runtime/lean_rt.js out/
backend=${BACKEND:-ir}
names="$*"
[ -z "$names" ] && names=$(ls tests/e2e/*.lean | sed 's|.*/||; s|\.lean$||')
fail=0; pass=0
for n in $names; do
  src=tests/e2e/$n.lean
  args=""; [ -f tests/e2e/$n.args ] && args=$(cat tests/e2e/$n.args)
  lake env lean --run "$src" $args > out/$n.expected 2>/dev/null; erc=$?
  if ! lake exe lean2js "$src" --backend $backend --run --out out/$n.js 2> out/$n.transpile.err; then
    echo "FAIL (transpile): $n: $(head -c 300 out/$n.transpile.err)"; fail=$((fail+1)); continue
  fi
  node out/$n.js $args > out/$n.actual 2> out/$n.stderr; arc=$?
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
