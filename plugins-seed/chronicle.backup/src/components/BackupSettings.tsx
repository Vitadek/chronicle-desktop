// Backup & Restore — the plugin's section inside Global Settings.
//
// It is a thin client over the server's local-admin routes (POST
// /api/backup/export | import, GET /api/backup/status). The server does all the
// database work; this panel only moves bytes and states consequences clearly.
//
// Styling note (the platform footgun): Tailwind never scans plugin source, so a
// utility class exists at runtime only if the host app already uses it. Anything
// load-bearing here is either a class the app is known to use (flex, text-xs,
// rounded-xl, opacity-*, bg-black/5, border-black/12 …) or an inline style. The
// two buttons carry their geometry/colour inline so they can't render invisible.

import React, { useEffect, useRef, useState } from 'react';
import { Download, Upload, Loader2, ShieldAlert } from 'lucide-react';
import type { PluginContext } from '@chronicle/plugin-api';
import { authFetch } from '../lib/api';

type Availability = 'checking' | 'available' | 'unavailable';
type Busy = null | 'exporting' | 'importing';

const PRIMARY_BTN: React.CSSProperties = {
  display: 'inline-flex', alignItems: 'center', gap: 8,
  padding: '10px 16px', borderRadius: 12, border: '1px solid transparent',
  fontSize: 11, fontWeight: 800, letterSpacing: '0.08em', textTransform: 'uppercase',
  cursor: 'pointer', background: '#3b82f6', color: '#fff',
};
const GHOST_BTN: React.CSSProperties = {
  ...PRIMARY_BTN, background: 'transparent', color: 'inherit',
  border: '1px solid rgba(128,128,128,0.4)',
};

export const BackupSettings: React.FC<PluginContext> = () => {
  const [avail, setAvail] = useState<Availability>('checking');
  const [busy, setBusy] = useState<Busy>(null);
  const [notice, setNotice] = useState<{ kind: 'info' | 'error'; text: string } | null>(null);
  const fileInput = useRef<HTMLInputElement>(null);

  // Probe once: the routes exist only on a single-user local/desktop instance.
  useEffect(() => {
    let cancelled = false;
    authFetch('/api/backup/status')
      .then((r) => { if (!cancelled) setAvail(r.ok ? 'available' : 'unavailable'); })
      .catch(() => { if (!cancelled) setAvail('unavailable'); });
    return () => { cancelled = true; };
  }, []);

  const runExport = async () => {
    if (busy) return;
    setBusy('exporting');
    setNotice(null);
    try {
      const res = await authFetch('/api/backup/export', { method: 'POST' });
      if (!res.ok) throw new Error((await res.json().catch(() => ({}))).error || `Export failed (${res.status})`);
      const blob = await res.blob();
      const name = /filename="([^"]+)"/.exec(res.headers.get('content-disposition') || '')?.[1]
        || `chronicle-${new Date().toISOString().slice(0, 10)}.chron`;
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = name;
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(url);
      setNotice({ kind: 'info', text: `Exported ${name}.` });
    } catch (err) {
      setNotice({ kind: 'error', text: err instanceof Error ? err.message : 'Export failed.' });
    } finally {
      setBusy(null);
    }
  };

  const onFilePicked = async (file: File) => {
    // Destructive: this replaces the entire library. Confirm explicitly.
    const ok = window.confirm(
      `Restore from “${file.name}”?\n\n` +
      `This REPLACES your entire current library with the contents of this file. ` +
      `A safety backup of your current data is saved first, and the change takes ` +
      `effect after Chronicle restarts.`,
    );
    if (!ok) return;
    setBusy('importing');
    setNotice(null);
    try {
      const bytes = await file.arrayBuffer();
      const res = await authFetch('/api/backup/import', {
        method: 'POST',
        headers: { 'Content-Type': 'application/octet-stream' },
        body: bytes,
      });
      const body = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(body.error || `Import failed (${res.status})`);
      setNotice({
        kind: 'info',
        text: 'Backup staged. Restart Chronicle to load it — a safety backup of your previous data was saved.',
      });
    } catch (err) {
      setNotice({ kind: 'error', text: err instanceof Error ? err.message : 'Import failed.' });
    } finally {
      setBusy(null);
      if (fileInput.current) fileInput.current.value = '';
    }
  };

  if (avail === 'checking') {
    return (
      <div className="flex items-center gap-2 text-[11px] opacity-50">
        <Loader2 className="w-3.5 h-3.5 animate-spin" /> Checking availability…
      </div>
    );
  }

  if (avail === 'unavailable') {
    return (
      <div className="flex items-start gap-3 text-[11px] leading-relaxed opacity-70">
        <ShieldAlert className="w-4 h-4 mt-0.5 flex-shrink-0 opacity-60" />
        <p>
          Backup &amp; Restore is available only on local and desktop installs, where a single user
          owns the whole library. On a shared server, whole-database export/import is disabled by
          design — use the server’s replica/backup tooling instead.
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-5">
      <p className="text-[11px] leading-relaxed opacity-60">
        A <span className="font-bold">.chron</span> file is a complete, compressed snapshot of your
        library. Export one to keep a copy or move to another machine; import one to restore or
        bootstrap this install from it.
      </p>

      <div className="space-y-3">
        <div className="rounded-xl border border-black/12 dark:border-white/15 p-4">
          <p className="text-xs font-bold mb-1">Export</p>
          <p className="text-[10px] leading-relaxed opacity-60 mb-3">
            Compresses your whole library and downloads it. Compression runs only when you press this.
          </p>
          <button style={PRIMARY_BTN} onClick={runExport} disabled={!!busy}>
            {busy === 'exporting'
              ? <><Loader2 className="w-3.5 h-3.5 animate-spin" /> Compressing…</>
              : <><Download className="w-3.5 h-3.5" /> Compress &amp; export</>}
          </button>
        </div>

        <div className="rounded-xl border border-black/12 dark:border-white/15 p-4">
          <p className="text-xs font-bold mb-1">Import / restore</p>
          <p className="text-[10px] leading-relaxed opacity-60 mb-3">
            Replaces your current library with a <span className="font-bold">.chron</span> file.
            Destructive — a safety backup of your current data is saved first, and it applies after a
            restart.
          </p>
          <input
            ref={fileInput}
            type="file"
            accept=".chron,application/octet-stream"
            style={{ display: 'none' }}
            onChange={(e) => { const f = e.target.files?.[0]; if (f) void onFilePicked(f); }}
          />
          <button style={GHOST_BTN} onClick={() => fileInput.current?.click()} disabled={!!busy}>
            {busy === 'importing'
              ? <><Loader2 className="w-3.5 h-3.5 animate-spin" /> Importing…</>
              : <><Upload className="w-3.5 h-3.5" /> Choose a .chron file…</>}
          </button>
        </div>
      </div>

      {notice && (
        <p
          className="text-[11px] leading-relaxed"
          style={{ color: notice.kind === 'error' ? '#ef4444' : undefined, opacity: notice.kind === 'error' ? 1 : 0.7 }}
        >
          {notice.text}
        </p>
      )}
    </div>
  );
};
