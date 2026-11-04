#!/bin/sh
# Runs all tests:
#   1. lcnf-dump golden tests              (tests/run.sh)
#   2. demo programs: `lean --run` vs. the native binary vs. the compiled JavaScript under node (stdout and exit code must be identical)
#   3. end-to-end differential tests       (tests/e2e/run.sh; programs in tests/e2e/*.lean)
# Usage: ./test.sh [--quick] [--update]
#   --quick   skip the slow e2e tests that transpile all of `Lean` (those with a .flags file, e.g. mvars, import)
#   --update  regenerate the lcnf-dump golden files
cd "$(dirname "$0")" || exit 1
quick=0; update=""
for a in "$@"; do
  case "$a" in
    --quick) quick=1 ;;
    --update) update="--update" ;;
    *) echo "usage: $0 [--quick] [--update]"; exit 2 ;;
  esac
done
status=0

echo "== lcnf-dump golden tests"
tests/run.sh $update || status=1

echo "== demo programs: lean --run vs node"
lake build lean2js >/dev/null 2>&1 || { echo "build failed"; exit 1; }
mkdir -p out/demo && cp runtime/*.js out/demo/
for src in demo/*.lean; do
  n=$(basename "$src" .lean)
  lake env lean --run "$src" < /dev/null > "out/demo/$n.expected" 2>/dev/null; erc=$?
  lake exe lean2js "$src" --run --out "out/demo/$n.js" 2> "out/demo/$n.err" || { echo "FAIL (transpile): $src"; status=1; continue; }
  node "out/demo/$n.js" < /dev/null > "out/demo/$n.actual" 2>> "out/demo/$n.err"; arc=$?
  # also the native binary (Lean -> C -> machine code) must agree
  lake env lean -c "out/demo/$n.c" "$src" 2>/dev/null && lake env leanc -O3 -o "out/demo/$n.bin" "out/demo/$n.c" 2>/dev/null \
    && "out/demo/$n.bin" < /dev/null > "out/demo/$n.native" 2>/dev/null; nrc=$?
  if [ $erc -eq $arc ] && cmp -s "out/demo/$n.expected" "out/demo/$n.actual" && [ $erc -eq $nrc ] && cmp -s "out/demo/$n.expected" "out/demo/$n.native"; then echo "ok: $src"
  else echo "FAIL: $src (exit interpreter=$erc js=$arc binary=$nrc)"; diff "out/demo/$n.expected" "out/demo/$n.actual" | head -5; status=1; fi
done

echo "== end-to-end tests (native lean vs. compiled JavaScript)"
names=""
if [ $quick -eq 1 ]; then
  for f in tests/e2e/*.lean; do
    n=$(basename "$f" .lean)
    [ -f "tests/e2e/$n.flags" ] || names="$names $n"
  done
fi
tests/e2e/run.sh $names || status=1

if [ $status -eq 0 ]; then echo "ALL TESTS PASSED"; else echo "SOME TESTS FAILED"; fi
exit $status
