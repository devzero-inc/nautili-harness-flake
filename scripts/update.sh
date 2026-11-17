#!/usr/bin/env bash
# Bump nix/cli.nix and nix/desktop.nix to the latest stable Nautili releases.
#
#   ./scripts/update.sh [cli] [desktop]     (both by default)
#
#   cli:     version from npm's `latest` tag of @nautili/tui, hashes from each
#            @nautili/nt-<platform> tarball's dist.integrity.
#   desktop: version from https://releases.nautili.ai/stable/latest.json,
#            hashes from that version's SHA256SUMS.
#
# Each package is updated on its own: if one fails (say a platform tarball is
# not on npm yet), the other is still updated and the script exits 1 at the
# end. A failed package's file is left untouched. A version older than the
# pinned one is reported and skipped, never written; one that isn't a plain
# release (a prerelease, or anything else) is reported as a failure.
#
# The systems to update are read from the nix files themselves (each
# `npmName = ...` / `file = ...` line and the `hash = ...` line after it), so
# adding a system there needs no change here. Needs bash, curl, jq, GNU sed,
# xxd and base64.
set -euo pipefail

self=$(realpath "$0")
cd "$(dirname "$self")/.."

# Run each package in its own process, so one's failure can't stop the other.
if (($# != 1)); then
  (($#)) || set -- cli desktop
  rc=0
  for package; do
    "$self" "$package" || rc=1
  done
  exit "$rc"
fi

npm=https://registry.npmjs.org
releases=https://releases.nautili.ai/stable

fetch() { curl -fsSL --retry 3 "$@"; }

current_version() { sed -n 's/^  version = "\(.*\)";$/\1/p' "$1"; }

set_version() {
  sed -i "s/^  version = \".*\";$/  version = \"$2\";/" "$1"
  [[ $(current_version "$1") == "$2" ]] || { echo "could not set the version in $3" >&2; exit 1; }
}

# set_hash FILE KEY NAME HASH: set the hash on the line after `KEY = "NAME";`.
set_hash() {
  sed -i "/^ *$2 = \"$3\";$/{n;s|^\( *hash = \"\).*\";$|\1$4\";|}" "$1"
  [[ $(grep -A1 -x " *$2 = \"$3\";" "$1" | sed -n '2s/^ *//p') == "hash = \"$4\";" ]] \
    || { echo "could not set the hash for $3 in $5" >&2; exit 1; }
}

hex_to_sri() { echo "sha256-$(xxd -r -p <<<"$1" | base64 -w0)"; }

# newer OLD NEW: is NEW a later version than OLD?
newer() { [[ $1 != "$2" && $(printf '%s\n' "$1" "$2" | sort -V | tail -n1) == "$2" ]]; }

package=$1
case $package in
  cli) file=nix/cli.nix name=nautili ;;
  desktop) file=nix/desktop.nix name=nautili-desktop ;;
  *) echo "unknown package: $package (expected cli or desktop)" >&2; exit 2 ;;
esac

old=$(current_version "$file")
if [[ $package == cli ]]; then
  new=$(fetch "$npm/@nautili%2ftui" | jq -er '."dist-tags".latest')
else
  new=$(fetch "$releases/latest.json" | jq -er .version)
fi

# Only plain releases: a prerelease (0.0.8-rc.1) would sort after its final
# release, and the version is also pasted into a sed program below.
if [[ ! $new =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
  echo "$name: upstream's latest is \"$new\", not a plain release version; leaving it" >&2
  exit 1
fi

if [[ $old == "$new" ]]; then
  echo "$name: $old is current"
  exit 0
fi
if ! newer "$old" "$new"; then
  echo "$name: upstream's latest is $new, older than the pinned $old; leaving it" >&2
  exit 0
fi
echo "$name: $old -> $new"

# Edit a copy, so a failure halfway leaves the real file as it was.
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
cp "$file" "$tmp"

if [[ $package == cli ]]; then
  for npmName in $(sed -n 's/^ *npmName = "\(.*\)";$/\1/p' "$file"); do
    integrity=$(fetch "$npm/@nautili/$npmName/$new" | jq -er .dist.integrity) \
      || { echo "@nautili/$npmName@$new is not on npm (yet)" >&2; exit 1; }
    set_hash "$tmp" npmName "$npmName" "$integrity" "$file"
  done
else
  sums=$(fetch "$releases/desktop/$new/SHA256SUMS") \
    || { echo "$releases/desktop/$new/SHA256SUMS is not published (yet)" >&2; exit 1; }
  for asset in $(sed -n 's/^ *file = "\(.*\)";$/\1/p' "$file"); do
    hex=$(awk -v f="$asset" '$2 == f { print $1 }' <<<"$sums")
    [[ $hex =~ ^[0-9a-f]{64}$ ]] \
      || { echo "$asset is not (exactly once) in $releases/desktop/$new/SHA256SUMS" >&2; exit 1; }
    set_hash "$tmp" file "$asset" "$(hex_to_sri "$hex")" "$file"
  done
fi
set_version "$tmp" "$new" "$file"

cp "$tmp" "$file"
