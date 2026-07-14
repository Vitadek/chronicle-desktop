#!/usr/bin/env bash
# Regenerate the offline source manifests flatpak-builder needs (it builds with
# no network). Run after bumping the pinned core commit or changing Cargo.lock.
#
# Requires flatpak-builder-tools on PATH:
#   flatpak-node-generator   (npm)   — https://github.com/flatpak/flatpak-builder-tools
#   flatpak-cargo-generator  (cargo)
#
# Produces (committed to the repo):
#   flatpak/node-sources.json    vendored npm tarballs + offline cache
#   flatpak/cargo-sources.json   vendored crates + .cargo/config.toml
#   flatpak/core-lock.sha256     hash of the core lockfile the npm sources match
set -euo pipefail
cd "$(dirname "$0")/.."

CORE_URL="${CORE_URL:-https://forgejo.lan/protoman/chronicle.git}"
COMMIT="$(sed -n 's/^ *commit: *//p' flatpak/ink.chronicler.Chronicle.yml | head -1)"
[ -n "$COMMIT" ] || { echo "no pinned commit in the manifest" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "→ fetching core @ $COMMIT"
git clone --quiet "$CORE_URL" "$work/core"
git -C "$work/core" checkout --quiet "$COMMIT"

echo "→ npm sources (flatpak-node-generator)"
flatpak-node-generator npm "$work/core/package-lock.json" -o flatpak/node-sources.json
sha256sum "$work/core/package-lock.json" | awk '{print $1}' > flatpak/core-lock.sha256

echo "→ cargo sources (flatpak-cargo-generator)"
flatpak-cargo-generator src-tauri/Cargo.lock -o flatpak/cargo-sources.json

echo "done. Commit flatpak/node-sources.json, flatpak/cargo-sources.json, flatpak/core-lock.sha256."
