import { definePlugin, PLUGIN_API_VERSION } from '@chronicle/plugin-api';
import { BackupSettings } from './components/BackupSettings';

/**
 * Backup & Restore.
 *
 * Exports the whole library to a single compressed `.chron` file and restores
 * (or bootstraps) an install from one. This is the localhost/desktop answer to
 * "there's no server admin here" — the user owns their data and needs to move,
 * back up, and revert it from the UI.
 *
 * The plugin is deliberately thin: it only moves bytes to and from the server's
 * local-admin routes (POST /api/backup/export | import). Those routes exist ONLY
 * where `LOCAL_ADMIN` is set (the desktop build) — a shared multi-user server
 * never exposes whole-database export/import, so the panel probes GET
 * /api/backup/status and shows a "local installs only" message when it's absent.
 *
 * It declares no npm dependencies on purpose: the desktop build seeds it into
 * an OFFLINE Flatpak, where first-boot compilation cannot run `npm install`.
 * Everything it needs is in src/.
 */
export default definePlugin({
  apiVersion: PLUGIN_API_VERSION,
  id: 'chronicle.backup',
  name: 'Backup & Restore',
  description:
    'Export your whole library to a .chron file and restore or bootstrap from one. Local/desktop installs only.',
  contributes: {
    settingsPanel: BackupSettings,
  },
});
