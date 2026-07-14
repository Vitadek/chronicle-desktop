# Backup & Restore

Export your whole [Chronicle](https://github.com/Vitadek/chronicle) library to a single compressed
`.chron` file, and restore or bootstrap an install from one — all from the UI.

This is the answer to "a localhost/desktop install has no server admin or CLI." The user owns their
data, so they get first-class backup and revert without a terminal.

```
Settings → Plugins → Install from git
https://git.example.com/protoman/chronicle-plugin-backup
```

## What it does

- **Export** — compresses the entire library into a `<name>.chron` file and downloads it.
  Compression runs *only* when you press the button (no idle/background work).
- **Import / restore** — replaces the current library with a `.chron` file. It's destructive, so it
  asks first, saves a safety backup of your current data, and applies on the next restart.

A `.chron` is just an **xz-compressed SQLite snapshot** of the database — portable, inspectable, and
restorable with the server's own tooling if you ever need to.

## Local / desktop only

Whole-database export/import is unreasonable on a shared multi-user server (one user could dump or
overwrite everyone's data), so the server exposes the routes this plugin calls **only when
`LOCAL_ADMIN` is set** — which the single-user desktop build does. On a shared server the plugin
detects the missing routes (`GET /api/backup/status`) and shows a short "local installs only"
message instead of dead buttons.

It ships pre-installed in the Chronicle desktop app; you can also install it on any single-user
self-hosted instance that sets `LOCAL_ADMIN=true`.

## How it works

The plugin is intentionally thin — it only moves bytes:

| Action | Call |
|---|---|
| Availability probe | `GET /api/backup/status` |
| Export | `POST /api/backup/export` → streamed `.chron` |
| Import | `POST /api/backup/import` (raw bytes) → `{ restartRequired }` |

The server does the real work: a consistent snapshot (SQLite online backup, safe against the live
WAL), `xz` compression on export, and — on import — validation, a pre-restore safety backup, and a
**boot-time atomic swap** (the staged database replaces the live one before any connection opens,
never a live hot-swap). See core's `server/lib/localBackup.ts` and `server/routes/backup.ts`.

## Development

```bash
ln -s ../chronicle/node_modules node_modules   # types only; nothing here is built locally
npx tsx scripts/backup-plugin.test.ts
```

No build step — Chronicle's server compiles the plugin with esbuild on install. It declares **no npm
dependencies** on purpose, so it can be seeded into an offline desktop build where first-boot
compilation can't reach the network.

## Licence

MIT.
