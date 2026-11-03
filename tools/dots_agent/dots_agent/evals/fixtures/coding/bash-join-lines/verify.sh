#!/usr/bin/env bash
set -euo pipefail
out=$(printf 'a\nb\nc\n' | bash join.sh)
[[ "$out" == "a,b,c" ]]
