#!/usr/bin/env bash
# CI guard: fail if the vendored npm sources no longer match the pinned core
# commit's lockfile — i.e. someone bumped the commit without regenerating. This
# is what keeps the offline Flatpak build from silently breaking.
set -euo pipefail
cd "$(dirname "$0")/.."

CORE_URL="${CORE_URL:-https://forgejo.lan/protoman/chronicle.git}"
COMMIT="$(sed -n 's/^ *commit: *//p' flatpak/ink.chronicler.Chronicle.yml | head -1)"
recorded="$(cat flatpak/core-lock.sha256 2>/dev/null || true)"
[ -n "$recorded" ] || { echo "flatpak/core-lock.sha256 missing — run scripts/gen-sources.sh" >&2; exit 1; }

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
git clone --quiet "$CORE_URL" "$work/core"
git -C "$work/core" checkout --quiet "$COMMIT"
actual="$(sha256sum "$work/core/package-lock.json" | awk '{print $1}')"

if [ "$actual" != "$recorded" ]; then
  echo "STALE: core@$COMMIT lockfile ($actual) != recorded ($recorded)." >&2
  echo "Run scripts/gen-sources.sh and commit the result." >&2
  exit 1
fi
echo "sources are fresh for core@$COMMIT"
