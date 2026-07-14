#!/usr/bin/env bash
# Bump the pinned Chronicle core commit and regenerate the offline sources.
#
#   scripts/update-core.sh <commit-sha>
#
# Updates the commit in the Flatpak manifest, then re-runs gen-sources.sh so the
# vendored npm tree matches the new lockfile. Commit the result as one change.
set -euo pipefail
cd "$(dirname "$0")/.."

commit="${1:-}"
[ -n "$commit" ] || { echo "usage: scripts/update-core.sh <commit-sha>" >&2; exit 1; }

sed -i "s/^\( *commit: *\).*/\1$commit/" flatpak/ink.chronicler.Chronicle.yml
echo "→ pinned core @ $commit"
scripts/gen-sources.sh
echo "→ done. Review the diff, then: git add -A && git commit"
