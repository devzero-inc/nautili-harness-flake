#!/usr/bin/env bash
# Bump nix/cli.nix and nix/desktop.nix to the latest stable Nautili releases.
#
#   CLI:     version from npm's `latest` tag of @nautili/tui, hashes from each
#            @nautili/nt-<platform> tarball's dist.integrity.
#   Desktop: version from https://releases.nautili.ai/stable/latest.json,
#            hashes from that version's SHA256SUMS.
#
# The systems to update are read from the nix files themselves (each
# `npmName = ...` / `file = ...` line and the `hash = ...` line after it), so
# adding a system there needs no change here. Needs bash, curl, jq, GNU sed,
# xxd and base64.
set -euo pipefail

cd "$(dirname "$0")/.."

cli=nix/cli.nix
desktop=nix/desktop.nix
npm=https://registry.npmjs.org
releases=https://releases.nautili.ai/stable

fetch() { curl -fsSL --retry 3 "$@"; }

current_version() { sed -n 's/^  version = "\(.*\)";$/\1/p' "$1"; }

set_version() {
  sed -i "s/^  version = \".*\";$/  version = \"$2\";/" "$1"
  [[ $(current_version "$1") == "$2" ]] || { echo "could not set the version in $1" >&2; exit 1; }
}

# set_hash FILE KEY NAME HASH: set the hash on the line after `KEY = "NAME";`.
set_hash() {
  sed -i "/^ *$2 = \"$3\";$/{n;s|^\( *hash = \"\).*\";$|\1$4\";|}" "$1"
  grep -A1 "^ *$2 = \"$3\";$" "$1" | grep -qF "hash = \"$4\";" \
    || { echo "could not set the hash for $3 in $1" >&2; exit 1; }
}

hex_to_sri() { echo "sha256-$(xxd -r -p <<<"$1" | base64 -w0)"; }

# --- CLI ---------------------------------------------------------------------
old=$(current_version "$cli")
new=$(fetch "$npm/@nautili%2ftui" | jq -er '."dist-tags".latest')
if [[ $old == "$new" ]]; then
  echo "nautili: $old is current"
else
  echo "nautili: $old -> $new"
  for name in $(sed -n 's/^ *npmName = "\(.*\)";$/\1/p' "$cli"); do
    integrity=$(fetch "$npm/@nautili/$name/$new" | jq -er .dist.integrity) \
      || { echo "@nautili/$name@$new is not on npm (yet)" >&2; exit 1; }
    set_hash "$cli" npmName "$name" "$integrity"
  done
  set_version "$cli" "$new"
fi

# --- Desktop -----------------------------------------------------------------
old=$(current_version "$desktop")
new=$(fetch "$releases/latest.json" | jq -er .version)
if [[ $old == "$new" ]]; then
  echo "nautili-desktop: $old is current"
else
  echo "nautili-desktop: $old -> $new"
  sums=$(fetch "$releases/desktop/$new/SHA256SUMS")
  for file in $(sed -n 's/^ *file = "\(.*\)";$/\1/p' "$desktop"); do
    hex=$(awk -v f="$file" '$2 == f { print $1 }' <<<"$sums")
    [[ $hex =~ ^[0-9a-f]{64}$ ]] \
      || { echo "$file is not in $releases/desktop/$new/SHA256SUMS" >&2; exit 1; }
    set_hash "$desktop" file "$file" "$(hex_to_sri "$hex")"
  done
  set_version "$desktop" "$new"
fi
