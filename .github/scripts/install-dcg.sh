#!/usr/bin/env bash
# Install a pinned dcg release binary.
#
#   DCG_VERSION=v0.10.0 DCG_SHA256=<hex> .github/scripts/install-dcg.sh [dest]
#
# The version is pinned because tests/baseline.json records the binary that
# produced it, and a newer dcg can change a built-in pack's verdict without any
# change in this repo. Bump both the version and the checksum together, then
# regenerate the baseline.

set -euo pipefail

: "${DCG_VERSION:?DCG_VERSION is required}"
: "${DCG_SHA256:?DCG_SHA256 is required}"
: "${DCG_TARGET:=x86_64-unknown-linux-musl}"

dest="${1:-$HOME/.local/bin}"
repo=Dicklesworthstone/destructive_command_guard
tarball="dcg-$DCG_TARGET.tar.xz"
url="https://github.com/$repo/releases/download/$DCG_VERSION/$tarball"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl -fsSL --retry 3 -o "$tmp/$tarball" "$url"

# The checksum is pinned here rather than read from the release's own .sha256
# asset. A checksum served from the same place as the artifact proves transport
# integrity and nothing more.
printf '%s  %s\n' "$DCG_SHA256" "$tmp/$tarball" | sha256sum -c -

tar -xJf "$tmp/$tarball" -C "$tmp"
mkdir -p "$dest"
install -m 0755 "$tmp/dcg" "$dest/dcg"

# `dcg --version` prints the bare version on the first line and then a boxed
# banner, so take the first line only.
got="$("$dest/dcg" --version 2>&1 | head -n 1 | tr -d '[:space:]')"
want="${DCG_VERSION#v}"
if [ "$got" != "$want" ]; then
  echo "expected dcg $want but installed '$got'" >&2
  exit 1
fi

echo "dcg $got installed at $dest/dcg"
