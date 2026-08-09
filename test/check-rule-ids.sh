#!/usr/bin/env bash
# Fail when a dcg corpus JSON result attributes a denial to the wrong rule.

set -uo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 CORPUS_RESULT.json" >&2
  exit 2
fi

awk '
  function check_case() {
    if (expected == "") {
      return
    }
    if (actual == "") {
      print "missing actual rule for " expected
      mismatches = 1
    } else if (expected != actual) {
      print expected " != " actual
      mismatches = 1
    }
    expected = ""
    actual = ""
  }

  /"expected_rule_id":/ {
    check_case()
    expected = $0
    sub(/^.*"expected_rule_id": "/, "", expected)
    sub(/".*$/, "", expected)
  }

  /"actual_rule_id":/ {
    actual = $0
    sub(/^.*"actual_rule_id": "/, "", actual)
    sub(/".*$/, "", actual)
  }

  END {
    check_case()
    exit mismatches
  }
' "$1"
