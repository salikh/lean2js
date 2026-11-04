#!/bin/sh
# Walks through the lean2js pipeline on the small programs in demo/:
#   1. show the Lean source, 2. run it with the Lean interpreter (`lean --run`), 3. compile it to a native binary (Lean -> C -> machine code)
#   and run that, 4. compile it to JavaScript and run it with node.
# Every step prints the command and how long it took.   Usage: ./demo.sh [demo/NAME.lean ...]
cd "$(dirname "$0")" || exit 1

lake build lean2js >/dev/null 2>&1 || { echo "build failed (lake build lean2js)"; exit 1; }
mkdir -p out/demo && cp runtime/*.js out/demo/

now() { date +%s.%N; }
# timed CMD...  : prints the command, its output and the elapsed time
timed() {
  printf '\n$ %s\n' "$*"
  t0=$(now)
  "$@" < /dev/null
  rc=$?
  t1=$(now)
  awk -v a="$t0" -v b="$t1" -v rc="$rc" 'BEGIN { printf "[%.2fs%s]\n", b - a, (rc ? ", exit code " rc : "") }'
  return $rc
}

programs="$*"
[ -z "$programs" ] && programs=$(ls demo/*.lean)
total=$(echo $programs | wc -w); i=0
for src in $programs; do
  i=$((i + 1)); name=$(basename "$src" .lean)
  printf '\n==================== %s/%s: %s ====================\n' "$i" "$total" "$src"
  printf '\n--- 1. Lean source\n'
  cat "$src"
  printf '\n--- 2. Run with the Lean interpreter'
  timed lake env lean --run "$src"
  printf '\n--- 3. Compile to a native binary: Lean -> C -> machine code'
  timed lake env lean -c "out/demo/$name.c" "$src"
  timed lake env leanc -O3 -o "out/demo/$name.bin" "out/demo/$name.c"
  printf '\n--- 4. Run the native binary'
  timed "out/demo/$name.bin"
  printf '\n--- 5. Compile to JavaScript'
  timed lake exe lean2js "$src" --run --out "out/demo/$name.js"
  printf '    (%s bytes of JavaScript)\n' "$(wc -c < "out/demo/$name.js")"
  printf '\n--- 6. Run the JavaScript with node'
  timed node "out/demo/$name.js"
done
