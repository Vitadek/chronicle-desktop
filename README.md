# Chronicle Desktop

A self-contained desktop build of [Chronicle](https://github.com/Vitadek/chronicle) — the whole
app, running privately on your machine, in a native window instead of a browser tab.

It's a [Tauri](https://tauri.app) shell that launches Chronicle's own Node server on a loopback port
and points the system webview at it. Nothing is re-implemented: it's the exact code the server runs,
so the desktop app never drifts from the web app. Choosing Tauri (over a Linux-only shell) means the
same code targets **macOS (Homebrew)** and **Windows** later without a rewrite.

**Homepage:** https://chronicler.ink · **App ID:** `ink.chronicler.Chronicle`

## How it works

```
┌─ Tauri shell (Rust, src-tauri/) ─────────────────────────────┐
│  1. pick a free 127.0.0.1 port                               │
│  2. spawn the bundled `node dist/server.cjs`                 │
│       HOST=127.0.0.1  AUTH_MODE=none  LOCAL_ADMIN=true        │
│  3. poll /readyz, then open a WebView at http://127.0.0.1:…  │
│  4. on quit → SIGTERM the server (clean WAL checkpoint)      │
└──────────────────────────────────────────────────────────────┘
```

- **Single-user & private.** `AUTH_MODE=none` bound to loopback is the server's intended secure
  single-user path (no insecure flag needed). Your library is one local SQLite database under the
  app's data dir; nothing leaves your machine.
- **Backup built in.** `LOCAL_ADMIN=true` enables the `.chron` backup/restore routes, and the
  **Backup & Restore** plugin is seeded (`plugins-seed/chronicle.backup`) so export/import is in the
  UI out of the box.
- **No LanguageTool** in this build — grammar squiggles are simply quiet, and grammar-dependent
  plugins say so. LanguageTool may ship later as an optional add-on.

## Repository layout

| Path | What |
|---|---|
| `src-tauri/` | the Tauri shell — `src/main.rs`, `Cargo.toml`, `tauri.conf.json` |
| `flatpak/` | the `flatpak-builder` manifest + `.desktop` + AppStream metainfo |
| `plugins-seed/` | desktop-only seed plugins (Backup & Restore) |
| `splash/` | placeholder frontend (the real UI is the sidecar) |
| `scripts/` | `gen-sources.sh`, `update-core.sh`, `check-sources-fresh.sh`, `prep-payload.sh` |

The Chronicle core is **not** vendored — the Flatpak pulls it at a **pinned commit** and builds it
in-manifest.

## Building the Flatpak

Requires `flatpak`, `flatpak-builder`, and
[`flatpak-builder-tools`](https://github.com/flatpak/flatpak-builder-tools) on PATH.

**Build environment:** flatpak-builder sandboxes each module with bubblewrap, which needs
a **writable `/proc/sys/user/max_user_namespaces`** and (by default) **`/dev/fuse`**. A normal
Linux host or VM has both. An *unprivileged* LXC container (e.g. the default on Proxmox) has
`/proc/sys` mounted read-only and no `/dev/fuse`, so the build fails with
`bwrap: cannot open /proc/sys/user/max_user_namespaces` — build on a real host/VM or a privileged
container. Pass `--disable-rofiles-fuse` when `/dev/fuse` is unavailable (the CI job and the
example below already do). The CI container runs `--privileged` for exactly this reason.

```bash
# 1. (first time / after a core bump) vendor the offline sources
scripts/gen-sources.sh                 # → flatpak/{node,cargo}-sources.json

# 2. build + install locally (--disable-rofiles-fuse if /dev/fuse is absent)
flatpak-builder --user --install --force-clean --disable-rofiles-fuse build-dir \
  flatpak/ink.chronicler.Chronicle.yml

# 3. run
flatpak run ink.chronicler.Chronicle
```

`flatpak-builder` builds **offline**, so the npm tree and Rust crates are vendored into
`flatpak/node-sources.json` and `flatpak/cargo-sources.json`. `better-sqlite3` is compiled from
source against the GNOME runtime's Node 22 + glibc (the published musl image can't be reused). The
**GNOME** runtime is required (not freedesktop) because it ships `webkit2gtk-4.1`, which Tauri's
Linux webview needs.

The manifest targets the current **GNOME 50** runtime (freedesktop 25.08 base). When bumping the
runtime, move all four in lockstep — `org.gnome.Platform`, `org.gnome.Sdk`, and both
`sdk-extensions` — to the runtime whose freedesktop base matches (Flathub only serves supported
pairs), so the app never ships on an EOL engine.

### Updating to a newer core

```bash
scripts/update-core.sh <core-commit-sha>   # re-pins + regenerates sources
```

CI runs `scripts/check-sources-fresh.sh` to fail the build if the pinned commit's lockfile ever
drifts from the vendored sources.

## Other Linux/desktop targets (later)

`cargo tauri build` produces `.deb` / AppImage (and `.dmg` / `.msi` on their platforms). For those,
`scripts/prep-payload.sh <core-checkout>` assembles the server payload into
`src-tauri/resources/chronicle` first. Flatpak is the first supported target.

## Licence

MIT (the shell). Chronicle core is under its own licence.
