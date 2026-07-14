#!/usr/bin/env bash
#
# Build the Chronicle desktop Flatpak on a real host and produce a single-file
# bundle you can install or host anywhere.
#
#   scripts/build-flatpak.sh [options]
#
# Options:
#   --install        also `flatpak install` the result for the current user
#   --gen-sources    regenerate the offline npm/cargo source manifests first
#                    (needs flatpak-builder-tools; do this after bumping core)
#   --sign KEYID     GPG-sign the OSTree repo + bundle with this key
#   --repo DIR       OSTree repo dir       (default: ./build/repo)
#   --bundle FILE    output bundle path    (default: ./ink.chronicler.Chronicle.flatpak)
#   -h | --help      show this help
#
# Requirements (a NORMAL Linux host or VM — NOT an unprivileged LXC container):
#   * flatpak, flatpak-builder
#   * a writable /proc/sys/user/max_user_namespaces (bubblewrap needs it)
#   * for --gen-sources: flatpak-node-generator + flatpak-cargo-generator on PATH
# The runtime/SDK/extensions the manifest pins are installed automatically
# (--install-deps-from=flathub). See README.md for the why behind all of this.
set -euo pipefail

cd "$(dirname "$0")/.."
APP_ID="ink.chronicler.Chronicle"
MANIFEST="flatpak/${APP_ID}.yml"

REPO="build/repo"
BUILD="build/builddir"
BUNDLE="${APP_ID}.flatpak"
DO_INSTALL=0
DO_GEN=0
SIGN_KEY=""

while [ $# -gt 0 ]; do
  case "$1" in
    --install) DO_INSTALL=1 ;;
    --gen-sources) DO_GEN=1 ;;
    --sign) SIGN_KEY="${2:?--sign needs a GPG key id}"; shift ;;
    --repo) REPO="${2:?}"; shift ;;
    --bundle) BUNDLE="${2:?}"; shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

die() { echo "error: $*" >&2; exit 1; }

# --- Preflight ---------------------------------------------------------------
command -v flatpak >/dev/null        || die "flatpak not found. Install it (e.g. 'sudo apt install flatpak' / 'sudo dnf install flatpak' / 'sudo pacman -S flatpak')."
command -v flatpak-builder >/dev/null || die "flatpak-builder not found. Install it (e.g. 'sudo apt install flatpak-builder')."
[ -f "$MANIFEST" ] || die "manifest not found at $MANIFEST (run from the repo root)."

# bubblewrap needs a writable /proc/sys/user/max_user_namespaces; an unprivileged
# LXC mounts it read-only and the per-module sandbox will fail. Warn early.
if ! flatpak run --command=true org.gnome.Sdk//50 >/dev/null 2>&1; then
  echo "note: a trivial flatpak sandbox failed to launch. If you see"
  echo "      'bwrap: cannot open /proc/sys/user/max_user_namespaces' you are in an"
  echo "      unprivileged container — build on a real host/VM or a --privileged one."
fi

# rofiles-fuse needs /dev/fuse; skip it when absent (a build hardening feature only).
ROFILES=()
[ -e /dev/fuse ] || { ROFILES=(--disable-rofiles-fuse); echo "note: /dev/fuse absent → --disable-rofiles-fuse"; }

# --- Flathub remote (user scope) ---------------------------------------------
flatpak --user remote-add --if-not-exists flathub \
  https://flathub.org/repo/flathub.flatpakrepo

# --- Optional: regenerate offline sources ------------------------------------
if [ "$DO_GEN" -eq 1 ]; then
  echo "==> regenerating offline sources"
  scripts/gen-sources.sh
fi
[ -f flatpak/node-sources.json ]  || die "flatpak/node-sources.json missing — run with --gen-sources."
[ -f flatpak/cargo-sources.json ] || die "flatpak/cargo-sources.json missing — run with --gen-sources."

# --- Build -------------------------------------------------------------------
SIGN=()
[ -n "$SIGN_KEY" ] && SIGN=(--gpg-sign="$SIGN_KEY")

INSTALL=()
[ "$DO_INSTALL" -eq 1 ] && INSTALL=(--install)

echo "==> flatpak-builder ($APP_ID)"
flatpak-builder --user --force-clean \
  --install-deps-from=flathub \
  "${ROFILES[@]}" "${INSTALL[@]}" "${SIGN[@]}" \
  --repo="$REPO" "$BUILD" "$MANIFEST"

# --- Export a single-file bundle + checksum ----------------------------------
echo "==> exporting bundle → $BUNDLE"
flatpak build-bundle "${SIGN[@]}" "$REPO" "$BUNDLE" "$APP_ID"
sha256sum "$BUNDLE" > "$BUNDLE.sha256"

echo
echo "Built $BUNDLE ($(du -h "$BUNDLE" | cut -f1))"
echo "  checksum: $(cut -d' ' -f1 "$BUNDLE.sha256")"
echo
echo "Distribute it however you like:"
echo "  • install locally:   flatpak install --user $BUNDLE"
echo "  • run:               flatpak run $APP_ID"
echo "  • host an OSTree repo (for 'flatpak remote-add'): serve $REPO over HTTP"
echo "  • or just upload $BUNDLE + $BUNDLE.sha256 as a release artifact"
