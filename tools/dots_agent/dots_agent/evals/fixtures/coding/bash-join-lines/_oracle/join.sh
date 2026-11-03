#!/usr/bin/env bash
first=1
while IFS= read -r line; do
  if [[ $first -eq 1 ]]; then
    printf '%s' "$line"
    first=0
  else
    printf ',%s' "$line"
  fi
done
