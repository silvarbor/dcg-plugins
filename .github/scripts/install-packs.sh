#!/usr/bin/env bash
# Install this checkout's packs into a dcg config, the way README.md documents,
# then assert that dcg actually loaded them.
#
#   .github/scripts/install-packs.sh [repo-root]
#
# The assertion is the point. A custom_paths glob that matches nothing is a
# silent, total loss of protection: dcg reports healthy, `dcg doctor` says OK,
# and every rule is gone. AGENTS.md records that failure. CI must never report
# a green suite that ran against zero packs.

set -euo pipefail

root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cfg_dir="${DCG_CONFIG_DIR:-$HOME/.config/dcg}"

mkdir -p "$cfg_dir"

# custom_paths points at this checkout only. The `enabled` list is copied
# verbatim out of example/config.toml so the policy cases run against the same
# built-in packs they were recorded against, and so a change to the example is
# a change to what CI evaluates.
{
  printf '[packs]\ncustom_paths = ["%s/packs/*.yaml"]\n' "$root"
  awk '/^enabled = \[/,/^\]/' "$root/example/config.toml"
} > "$cfg_dir/config.toml"

if ! grep -q '^enabled = \[' "$cfg_dir/config.toml"; then
  echo "failed to extract the enabled pack list from example/config.toml" >&2
  exit 1
fi

# Not optional. silvarbor.git_safety permits reset, path checkout, restore and
# branch deletion, but core.git blocks all four and a custom pack cannot
# un-block another pack's rule. Without this file a third of the policy cases
# assert the wrong thing.
cp "$root/example/allowlist.toml" "$cfg_dir/allowlist.toml"

# DCG_CONFIG names the file just written. In CI that is the same file dcg finds
# on its own; passing it explicitly also lets this script be tested on a machine
# that already has a live config it must not touch.
listing="$(DCG_CONFIG="$cfg_dir/config.toml" dcg packs 2>&1)"
missing=0
for id in silvarbor.git_safety silvarbor.process_hygiene silvarbor.access_boundary; do
  if ! printf '%s' "$listing" | grep -qF "✓ $id "; then
    echo "pack not loaded or not enabled: $id" >&2
    missing=1
  fi
done

if [ "$missing" -ne 0 ]; then
  printf '%s\n' "$listing" >&2
  exit 1
fi

echo "3 silvarbor packs loaded from $root/packs"
