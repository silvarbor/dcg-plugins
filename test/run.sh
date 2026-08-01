#!/usr/bin/env bash
# Case-matrix runner for the silvarbor dcg packs.
#
#   test/run.sh                     run every suite
#   test/run.sh process_hygiene     run one suite
#   test/run.sh -v                  print every case, not just failures
#
# Exits non-zero if any case disagrees with its expectation. Run this after
# ANY edit to a pack — a regex that stops matching still validates clean, so
# `dcg pack validate` alone proves nothing about behaviour.
#
# Why the cases live in TSV files rather than inline in this script: dcg hooks
# the agent's shell, so a command line containing `git worktree remove` or a
# poll loop is itself blocked. Test data must stay in files and reach dcg only
# through a variable. This is the same constraint the packs document for prose.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
CASES="$HERE/cases"

VERBOSE=0
SUITES=()
for arg in "$@"; do
  case "$arg" in
    -v | --verbose) VERBOSE=1 ;;
    -*) echo "unknown option: $arg" >&2; exit 2 ;;
    *) SUITES+=("$arg") ;;
  esac
done
if [ ${#SUITES[@]} -eq 0 ]; then
  SUITES=(worktree_isolated shared_checkout process_hygiene)
fi

command -v dcg >/dev/null 2>&1 || { echo "dcg not on PATH" >&2; exit 2; }

TMPDIR_RUN="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_RUN"' EXIT

# The shared-checkout pack is not loaded by the normal config — it sits in
# packs/disabled/ and carries the same pack id as the active pack. Give it a
# throwaway config of its own so the two can never be loaded together.
disabled_config() {
  local cfg="$TMPDIR_RUN/shared_checkout.toml"
  cat > "$cfg" <<EOF
[packs]
custom_paths = ["$ROOT/packs/disabled/*.yaml"]
enabled = []
EOF
  printf '%s' "$cfg"
}

total_pass=0
total_fail=0

for suite in "${SUITES[@]}"; do
  tsv="$CASES/$suite.tsv"
  if [ ! -f "$tsv" ]; then
    echo "no such suite: $suite (looked for $tsv)" >&2
    exit 2
  fi

  cfg=""
  [ "$suite" = "shared_checkout" ] && cfg="$(disabled_config)"

  pass=0
  fail=0
  while IFS=$'\t' read -r expected label command; do
    case "$expected" in '' | '#'*) continue ;; esac

    # A literal \n in the TSV becomes a real newline (multi-line cases).
    command="$(printf '%b' "${command//\\n/$'\n'}")"

    if [ -n "$cfg" ]; then
      out="$(DCG_CONFIG="$cfg" dcg explain -- "$command" 2>&1)"
    else
      out="$(dcg explain -- "$command" 2>&1)"
    fi
    got="$(printf '%s' "$out" | grep -m1 'Decision:' | awk '{print $2}')"
    rule="$(printf '%s' "$out" | grep -m1 'Rule ID:' | awk '{print $3}')"

    if [ "$got" = "$expected" ]; then
      pass=$((pass + 1))
      [ "$VERBOSE" -eq 1 ] && printf '  ok   %-24s %-5s %s\n' "$label" "$got" "$rule"
    else
      fail=$((fail + 1))
      printf '  FAIL %-24s expected=%-5s got=%-5s %s\n' "$label" "$expected" "$got" "$rule"
      printf '       %s\n' "$command"
    fi
  done < "$tsv"

  printf '%-20s %2d passed' "$suite" "$pass"
  [ "$fail" -gt 0 ] && printf ', %d FAILED' "$fail"
  printf '\n'

  total_pass=$((total_pass + pass))
  total_fail=$((total_fail + fail))
done

echo "---"
if [ "$total_fail" -gt 0 ]; then
  echo "$total_pass passed, $total_fail FAILED"
  exit 1
fi
echo "$total_pass passed, 0 failed"
