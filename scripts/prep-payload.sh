#!/usr/bin/env bash
# Assemble the server payload for a NON-Flatpak bundle (cargo tauri build → deb/
# AppImage/dmg/msi), which reads it from src-tauri/resources/chronicle.
#
# The Flatpak build does NOT use this — it builds core in-manifest and points
# CHRONICLE_RESOURCE_DIR at /app/chronicle instead.
#
#   scripts/prep-payload.sh /path/to/chronicle/checkout
#
# Builds core there, then copies the runtime payload + node binary + seed plugins
# into src-tauri/resources/chronicle.
set -euo pipefail
cd "$(dirname "$0")/.."

core="${1:-}"
[ -d "$core" ] || { echo "usage: scripts/prep-payload.sh /path/to/chronicle" >&2; exit 1; }

dest="src-tauri/resources/chronicle"
rm -rf "$dest"; mkdir -p "$dest"

( cd "$core" && npm ci && npm run build && npm prune --omit=dev )
cp -r "$core/dist" "$core/node_modules" "$core/package.json" "$dest/"

# Empty core seed + our desktop seed plugins.
mkdir -p "$dest/plugins-seed"
cp -r "$core/plugins-seed/." "$dest/plugins-seed/" 2>/dev/null || true
cp -r plugins-seed/. "$dest/plugins-seed/"

# Bundle a node binary matching the target (this host's node here).
install -Dm755 "$(command -v node)" "$dest/node"

echo "payload assembled at $dest"
