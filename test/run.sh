#!/usr/bin/env bash
# Full verification for the silvarbor dcg packs.
#
#   test/run.sh              corpus + effective-policy suite
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
#
#   test/cases/    - run by the loops below against `dcg explain` and an
#                    isolated `dcg test --config`. Asserts EFFECTIVE POLICY
#                    and custom-pack rule attribution.
#
# The split is forced, not stylistic. `dcg corpus` does not apply
# allowlist.toml and has no --config flag (and ignores DCG_CONFIG), so it
# cannot express allowlist-dependent ALLOWs or isolated attribution. Verified
# against dcg 0.10.0. The runner also checks rule IDs independently because
# dcg 0.10 can mark a wrong-rule denial as passed.
#
# Test data lives in files rather than inline because dcg hooks the shell it
# protects: a command line containing a guarded command is blocked even when
# you are only testing the rule that blocks it. `dcg test --stdin` exists for
# the same reason.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
CASES="$HERE/cases"
FIXTURES="$HERE/fixtures"
CORPUS="$ROOT/tests/corpus"
BASELINE="$ROOT/tests/baseline.json"
CUSTOM_CONFIG="$HERE/config.custom-only.toml"
PERFORMANCE_CASES="$CASES/performance.tsv"
RULE_ID_CHECK="$HERE/check-rule-ids.sh"
WRONG_RULE_FIXTURE="$HERE/fixtures/wrong-rule.json"

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

  current_corpus="$(mktemp "${TMPDIR:-/tmp}/dcg-corpus.XXXXXX")"
  if ! dcg corpus -d "$CORPUS" --format json --output "$current_corpus"; then
    echo "  failed to produce current corpus rule attribution"
    rc_total=1
  elif ! mismatches="$($RULE_ID_CHECK "$current_corpus")"; then
    printf '%s\n' "$mismatches" | sed 's/^/  live rule mismatch: /'
    rc_total=1
  fi
  rm -f "$current_corpus"

  if "$RULE_ID_CHECK" "$WRONG_RULE_FIXTURE" >/dev/null; then
    echo "  wrong-rule checker accepted its rejection fixture"
    rc_total=1
  fi
fi

# ---------------------------------------------------------------- policy ----
if [ "$WHICH" = all ] || [ "$WHICH" = policy ]; then
  for suite in worktree_isolated known_limits; do
    tsv="$CASES/$suite.tsv"
    [ -f "$tsv" ] || { echo "missing suite file: $tsv" >&2; exit 2; }

    pass=0; fail=0
    while IFS=$'\t' read -r expected label command; do
      case "$expected" in '' | '#'*) continue ;; esac
      case "$command" in
        @fixture:*)
          fixture="$FIXTURES/${command#@fixture:}"
          if [ ! -f "$fixture" ]; then
            echo "missing command fixture: $fixture" >&2
            exit 2
          fi
          command="$(<"$fixture")"
          ;;
        *) command="$(printf '%b' "${command//\\n/$'\n'}")" ;;
      esac

      out="$(dcg explain --dialect posix -- "$command" 2>&1)"
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

  tsv="$CASES/custom_pack.tsv"
  pass=0; fail=0
  while IFS=$'\t' read -r expected label expected_rule command; do
    case "$expected" in '' | '#'*) continue ;; esac
    command="$(printf '%b' "${command//\\n/$'\n'}")"

    out="$(cd "$ROOT" && dcg test --config "$CUSTOM_CONFIG" --explain --dialect posix -- "$command" 2>&1)"
    got="$(printf '%s' "$out" | grep -m1 'Decision:' | awk '{print $2}')"
    rule="$(printf '%s' "$out" | grep -m1 'Rule ID:' | awk '{print $3}')"

    if [ "$got" = "$expected" ] && [ "$rule" = "$expected_rule" ]; then
      pass=$((pass + 1))
      [ "$VERBOSE" -eq 1 ] && printf '  ok   %-24s %-5s %s\n' "$label" "$got" "$rule"
    else
      fail=$((fail + 1))
      printf '  FAIL %-24s expected=%-5s got=%-5s expected_rule=%s got_rule=%s\n' \
        "$label" "$expected" "$got" "$expected_rule" "$rule"
      printf '       %s\n' "$command"
    fi
  done < "$tsv"

  printf '%-20s %2d passed' "policy:custom_pack" "$pass"
  [ "$fail" -gt 0 ] && { printf ', %d FAILED' "$fail"; rc_total=1; }
  printf '\n'

  long_env=""
  long_wrappers=""
  long_git_options=""
  for ((i = 1; i <= 65; i++)); do
    long_env+="DCG_PERF_${i}=x "
    long_wrappers+="command "
    long_git_options+="-c dcg.perf${i}=x "
  done

  budget_canary="${long_env}${long_wrappers}git gc --prune=now"
  out="$(printf '%s' "$budget_canary" | DCG_HOOK_TIMEOUT_MS=1 dcg test \
    --stdin --enforce-budget --dialect posix --format json 2>&1)"
  got="$(printf '%s' "$out" | awk -F'"' '/"decision":/ {print $4; exit}')"
  if [ "$got" != indeterminate ]; then
    echo "  evaluation-budget canary did not exhaust its 1 ms deadline"
    rc_total=1
  fi

  pass=0; fail=0
  while IFS=$'\t' read -r expected label expected_rule prefix_kind suffix; do
    case "$expected" in '' | '#'*) continue ;; esac
    case "$suffix" in
      @fixture:*)
        fixture="$FIXTURES/${suffix#@fixture:}"
        if [ ! -f "$fixture" ]; then
          echo "missing command fixture: $fixture" >&2
          exit 2
        fi
        suffix="$(<"$fixture")"
        ;;
      *) suffix="$(printf '%b' "${suffix//\\n/$'\n'}")" ;;
    esac

    case "$prefix_kind" in
      env) command="${long_env}${suffix}" ;;
      wrappers) command="${long_wrappers}${suffix}" ;;
      git-options) command="git ${long_git_options}${suffix}" ;;
      *) echo "unknown performance prefix: $prefix_kind" >&2; exit 2 ;;
    esac

    out="$(printf '%s' "$command" | DCG_HOOK_TIMEOUT_MS=200 dcg test \
      --stdin --enforce-budget --dialect posix --format json 2>&1)"
    got="$(printf '%s' "$out" | awk -F'"' '/"decision":/ {print $4; exit}')"
    rule="$(printf '%s' "$out" | awk -F'"' '/"rule_id":/ {print $4; exit}')"

    if [ "$got" = "${expected,,}" ] && \
       { [ "$expected_rule" = - ] || [ "$rule" = "$expected_rule" ]; }; then
      pass=$((pass + 1))
      [ "$VERBOSE" -eq 1 ] && printf '  ok   %-24s %-5s %s\n' "$label" "$got" "$rule"
    else
      fail=$((fail + 1))
      printf '  FAIL %-24s expected=%-5s got=%-13s expected_rule=%s got_rule=%s\n' \
        "$label" "$expected" "$got" "$expected_rule" "$rule"
    fi
  done < "$PERFORMANCE_CASES"

  printf '%-20s %2d passed' "policy:performance" "$pass"
  [ "$fail" -gt 0 ] && { printf ', %d FAILED' "$fail"; rc_total=1; }
  printf '\n'
fi

echo "---"
if [ "$rc_total" -ne 0 ]; then
  echo "FAILURES"
  exit 1
fi
echo "all suites green"
