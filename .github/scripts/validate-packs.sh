#!/usr/bin/env bash
# Validate every pack file, including the disabled one, and fail on warnings.
#
# README.md claims all packs validate clean with zero warnings. dcg exits 0 on
# a pack that parses but warns, so the exit code alone does not carry that
# claim — the output is scanned as well.
#
# Validation proves a pack PARSES. It does not prove a rule still matches.
# test/run.sh is what proves that.

set -euo pipefail

root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

rc=0
count=0
for pack in "$root"/packs/*.yaml "$root"/packs/disabled/*.yaml; do
  [ -e "$pack" ] || continue
  count=$((count + 1))
  name="${pack#"$root"/}"

  if ! out="$(dcg pack validate "$pack" 2>&1)"; then
    printf 'FAIL %s\n' "$name"
    printf '%s\n' "$out" | sed 's/^/  /'
    rc=1
    continue
  fi

  if warnings="$(printf '%s' "$out" | grep -iE 'warn|⚠')"; then
    printf 'WARN %s\n' "$name"
    printf '%s\n' "$warnings" | sed 's/^/  /'
    rc=1
    continue
  fi

  printf 'ok   %s\n' "$name"
done

if [ "$count" -eq 0 ]; then
  echo "no pack files found under $root/packs" >&2
  exit 1
fi

exit "$rc"
