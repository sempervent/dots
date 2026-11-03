#!/usr/bin/env bash
set -euo pipefail
d=$(mktemp -d)
printf 'hello world\n' > "$d/with space.txt"
out=$(bash run.sh "$d/with space.txt")
rm -rf "$d"
[[ "$out" == "hello world" ]]
