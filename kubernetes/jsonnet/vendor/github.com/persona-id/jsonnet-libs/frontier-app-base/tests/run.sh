#!/bin/sh
# Renders every tests/cases/*.jsonnet and compares it with the .json next to it,
# and checks every tests/errors/*.jsonnet fails with the message on its
# `// expect:` line. UPDATE=1 rewrites the .json files from the current output.
#
# Needs `jb install` to have been run in the library directory.
set -eu

cd "$(dirname "$0")/.."
rendered="$(mktemp)"
trap 'rm -f "$rendered"' EXIT
failed=0

for case in tests/cases/*.jsonnet; do
  golden="${case%.jsonnet}.json"
  if [ "${UPDATE:-}" = 1 ]; then
    jsonnet -J vendor "$case" >"$golden"
    echo "updated $golden"
  elif jsonnet -J vendor "$case" >"$rendered" && diff -u "$golden" "$rendered"; then
    echo "ok   $case"
  else
    echo "FAIL $case (rerun with UPDATE=1 if the change is intended)"
    failed=1
  fi
done

for case in tests/errors/*.jsonnet; do
  expected="$(sed -n 's#^// expect: ##p' "$case")"
  if output="$(jsonnet -J vendor "$case" 2>&1)"; then
    echo "FAIL $case rendered, expected an error containing: $expected"
    failed=1
  else
    case "$output" in
      *"$expected"*) echo "ok   $case" ;;
      *)
        echo "FAIL $case expected an error containing: $expected"
        echo "$output" | head -5
        failed=1
        ;;
    esac
  fi
done

exit "$failed"
