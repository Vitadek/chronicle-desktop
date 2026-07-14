// Chronicle desktop shell.
//
// Chronicle is a Node server that serves its own SPA + API + collab websocket on
// one port; the browser client talks to it same-origin. This shell just gives it
// a native window: it launches the bundled server on a loopback port, waits for
// it to become healthy, and points a webview at it. Nothing about the app is
// re-implemented here — it's the exact same code the Docker server runs.
//
// Tauri (rather than a Linux-only GJS shell) is deliberate: the same shell builds
// for macOS (WKWebView) and Windows (WebView2) later, so Homebrew/Windows become
// distribution targets, not rewrites.
//
// NOTE: build this on a machine with the Rust toolchain + Tauri v2 system deps
// (WebKitGTK on Linux). It is not compiled in the plan's authoring environment.

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::net::TcpListener;
use std::path::PathBuf;
use std::process::{Child, Command};
use std::sync::Mutex;
use std::time::{Duration, Instant};

use tauri::{Manager, RunEvent, WebviewUrl, WebviewWindowBuilder};

/// The spawned Node server, kept so we can shut it down gracefully on exit.
struct Server(Mutex<Option<Child>>);

/// Ask the OS for a free loopback port by binding :0 and reading it back, then
/// dropping the listener so Node can take it. Small TOCTOU window, acceptable
/// for a single-user desktop app.
fn free_loopback_port() -> u16 {
    TcpListener::bind("127.0.0.1:0")
        .expect("bind loopback")
        .local_addr()
        .expect("read local addr")
        .port()
}

/// Resolve the bundled server entry + the `node` binary.
///
/// The server payload (node binary + dist/ + node_modules/ + plugins-seed/)
/// lives at `$CHRONICLE_RESOURCE_DIR` when set — the Flatpak points this at
/// `/app/chronicle`, decoupling it from Tauri's resource resolution — otherwise
/// under the bundle's resource dir (the deb/AppImage/macOS/Windows path).
fn resource_paths(app: &tauri::AppHandle) -> (PathBuf, PathBuf) {
    let res = match std::env::var_os("CHRONICLE_RESOURCE_DIR") {
        Some(dir) => PathBuf::from(dir),
        None => app
            .path()
            .resource_dir()
            .expect("resource dir")
            .join("chronicle"),
    };
    // On Windows the bundled runtime is node.exe; elsewhere a bare `node`.
    let node = if cfg!(windows) {
        res.join("node.exe")
    } else {
        res.join("node")
    };
    (node, res.join("dist").join("server.cjs"))
}

/// Block until GET /readyz answers 200, or give up after ~30s.
fn wait_for_ready(port: u16) -> bool {
    let url = format!("http://127.0.0.1:{port}/readyz");
    let deadline = Instant::now() + Duration::from_secs(30);
    while Instant::now() < deadline {
        if let Ok(resp) = ureq::get(&url).timeout(Duration::from_millis(800)).call() {
            if resp.status() == 200 {
                return true;
            }
        }
        std::thread::sleep(Duration::from_millis(200));
    }
    false
}

fn main() {
    let port = free_loopback_port();

    tauri::Builder::default()
        .manage(Server(Mutex::new(None)))
        .setup(move |app| {
            let handle = app.handle().clone();

            // A splash window while the server boots (data: URL — no bundled
            // frontend needed; the real UI is served by the sidecar).
            let splash = WebviewWindowBuilder::new(
                &handle,
                "splash",
                WebviewUrl::External(
                    "data:text/html,<html><body style='margin:0;display:flex;align-items:center;justify-content:center;height:100vh;background:%23f6f3ec;font-family:Georgia,serif;color:%23333'><div style='text-align:center'><div style='font-size:22px;margin-bottom:8px'>Chronicle</div><div style='font-size:12px;opacity:.6'>Starting…</div></div></body></html>"
                        .parse()
                        .unwrap(),
                ),
            )
            .title("Chronicle")
            .inner_size(420.0, 280.0)
            .center()
            .resizable(false)
            .build()?;

            // Spawn the bundled Node server on the loopback port. Single-user,
            // so AUTH_MODE=none + HOST=127.0.0.1 is the intended secure path
            // (passes the server's fail-closed loopback check with no insecure
            // flag). LOCAL_ADMIN=true enables the .chron backup/restore routes.
            let (node, server_cjs) = resource_paths(&handle);
            let data_dir = app.path().app_data_dir().expect("app data dir");
            std::fs::create_dir_all(&data_dir).ok();

            let child = Command::new(&node)
                .arg(&server_cjs)
                .env("NODE_ENV", "production")
                .env("HOST", "127.0.0.1")
                .env("PORT", port.to_string())
                .env("DATA_DIR", &data_dir)
                .env("AI_UI", "off")
                .env("LOCAL_ADMIN", "true")
                .spawn()
                .expect("spawn chronicle server");
            app.state::<Server>().0.lock().unwrap().replace(child);

            // Off the UI thread: wait for health, then swap splash → app window.
            std::thread::spawn(move || {
                let ok = wait_for_ready(port);
                let handle2 = handle.clone();
                handle
                    .run_on_main_thread(move || {
                        if !ok {
                            eprintln!("chronicle server did not become ready");
                            return;
                        }
                        let url = format!("http://127.0.0.1:{port}/");
                        let _ = WebviewWindowBuilder::new(
                            &handle2,
                            "main",
                            WebviewUrl::External(url.parse().unwrap()),
                        )
                        .title("Chronicle")
                        .inner_size(1200.0, 800.0)
                        .min_inner_size(720.0, 480.0)
                        .center()
                        .build();
                        if let Some(s) = handle2.get_webview_window("splash") {
                            let _ = s.close();
                        }
                    })
                    .ok();
            });

            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("build tauri app")
        .run(|app, event| {
            // Graceful shutdown: SIGTERM the server so it checkpoints the WAL and
            // closes SQLite cleanly (a hard kill would skip that). Then wait.
            if let RunEvent::ExitRequested { .. } = event {
                if let Some(mut child) = app.state::<Server>().0.lock().unwrap().take() {
                    #[cfg(unix)]
                    unsafe {
                        libc::kill(child.id() as i32, libc::SIGTERM);
                    }
                    #[cfg(not(unix))]
                    {
                        let _ = child.kill();
                    }
                    let _ = child.wait();
                }
            }
        });
}
