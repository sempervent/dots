#!/usr/bin/env bash
# broken: prints trailing comma
while IFS= read -r line; do
  printf '%s,' "$line"
done
