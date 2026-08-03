#!/usr/bin/env bash
# Full verification for the silvarbor dcg packs.
#
#   test/run.sh              corpus + policy suites
#   test/run.sh -v           show every case
#   test/run.sh corpus       only the official corpus
#   test/run.sh policy       only the effective-policy cases
#
# Exits non-zero if anything disagrees with expectation or baseline.
#
# TWO SUITES, BECAUSE ONE TOOL CANNOT EXPRESS BOTH
#
#   tests/corpus/  - run by `dcg corpus`, the official harness. Asserts pack
#                    MATCHING, with rule_id per case and a diffable baseline.
#                    61 cases.
#
#   test/cases/    - run by the loop below against `dcg explain`. Asserts
#                    EFFECTIVE POLICY: what the live guard actually decides,
#                    with allowlist.toml applied. 43 cases.
#
# The split is forced, not stylistic. `dcg corpus` does not apply
# allowlist.toml and has no --config flag (and ignores DCG_CONFIG), so it
# cannot express either the allowlist-dependent ALLOWs or the shared_checkout
# pack, which needs an isolated config because it shares a pack id with the
# active one. Verified against dcg 0.9.0.
#
# Test data lives in files rather than inline because dcg hooks the shell it
# protects: a command line containing a guarded command is blocked even when
# you are only testing the rule that blocks it. `dcg test --stdin` exists for
# the same reason.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
CASES="$HERE/cases"
CORPUS="$ROOT/tests/corpus"
BASELINE="$ROOT/tests/baseline.json"

VERBOSE=0
WHICH=all
for arg in "$@"; do
  case "$arg" in
    -v | --verbose) VERBOSE=1 ;;
    corpus | policy) WHICH="$arg" ;;
    -*) echo "unknown option: $arg" >&2; exit 2 ;;
    *) echo "unknown suite: $arg (expected 'corpus' or 'policy')" >&2; exit 2 ;;
  esac
done

command -v dcg >/dev/null 2>&1 || { echo "dcg not on PATH" >&2; exit 2; }

rc_total=0

# ---------------------------------------------------------------- corpus ----
if [ "$WHICH" = all ] || [ "$WHICH" = corpus ]; then
  if [ -f "$BASELINE" ]; then
    out="$(dcg corpus -d "$CORPUS" --baseline "$BASELINE" --format pretty 2>&1)"
  else
    out="$(dcg corpus -d "$CORPUS" --format pretty 2>&1)"
  fi
  rc=$?
  line="$(printf '%s' "$out" | grep -m1 -E '^Total:')"
  printf '%-20s %s\n' "corpus" "${line:-no output}"
  if [ "$rc" -ne 0 ]; then
    printf '%s\n' "$out" | grep -E 'FAIL|Command:|expected|actual' | head -20 | sed 's/^/  /'
    rc_total=1
  elif [ "$VERBOSE" -eq 1 ]; then
    printf '%s\n' "$out" | sed 's/^/  /'
  fi
fi

# ---------------------------------------------------------------- policy ----
if [ "$WHICH" = all ] || [ "$WHICH" = policy ]; then
  TMPDIR_RUN="$(mktemp -d)"
  trap 'rm -rf "$TMPDIR_RUN"' EXIT

  # shared_checkout shares a pack id with the active pack, so it gets a
  # throwaway config that loads only packs/disabled/.
  disabled_config() {
    local cfg="$TMPDIR_RUN/shared_checkout.toml"
    cat > "$cfg" <<EOF
[packs]
custom_paths = ["$ROOT/packs/disabled/*.yaml"]
enabled = []
EOF
    printf '%s' "$cfg"
  }

  for suite in worktree_isolated shared_checkout; do
    tsv="$CASES/$suite.tsv"
    [ -f "$tsv" ] || { echo "missing suite file: $tsv" >&2; exit 2; }

    cfg=""
    [ "$suite" = shared_checkout ] && cfg="$(disabled_config)"

    pass=0; fail=0
    while IFS=$'\t' read -r expected label command; do
      case "$expected" in '' | '#'*) continue ;; esac
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

    printf '%-20s %2d passed' "policy:$suite" "$pass"
    [ "$fail" -gt 0 ] && { printf ', %d FAILED' "$fail"; rc_total=1; }
    printf '\n'
  done
fi

echo "---"
if [ "$rc_total" -ne 0 ]; then
  echo "FAILURES"
  exit 1
fi
echo "all suites green"
