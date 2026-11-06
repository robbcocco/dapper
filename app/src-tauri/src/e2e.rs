//! Debug-only end-to-end harness (see `app/e2e/`). With `DAPPER_E2E_SCRIPT=<file.js>`
//! the prelude plus that scenario are evaluated in the main webview once it has
//! loaded. The script reports over plain Tauri events: `e2e:log` lines are printed
//! as `E2E: ...`, `e2e:shot` captures the window to `$DAPPER_E2E_SHOTS/<name>.png`,
//! `e2e:sh` runs a host shell command, `e2e:exit` ends the app with the given code.

use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use tauri::webview::PageLoadEvent;
use tauri::{AppHandle, Builder, Listener, Manager, Webview, Wry};

const PRELUDE: &str = include_str!("../../e2e/prelude.js");
const ENV_SCRIPT: &str = "DAPPER_E2E_SCRIPT";
const ENV_SHOTS: &str = "DAPPER_E2E_SHOTS";
const ENV_TIMEOUT: &str = "DAPPER_E2E_TIMEOUT";

pub fn install(builder: Builder<Wry>) -> Builder<Wry> {
    let Some(path) = std::env::var_os(ENV_SCRIPT) else {
        return builder;
    };
    let scenario = std::fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("{ENV_SCRIPT}={}: {e}", PathBuf::from(&path).display()));
    let started = AtomicBool::new(false);
    builder.on_page_load(move |webview, payload| {
        if payload.event() != PageLoadEvent::Finished || started.swap(true, Ordering::SeqCst) {
            return;
        }
        start(webview, &scenario);
    })
}

fn start(webview: &Webview, scenario: &str) {
    let app = webview.app_handle().clone();
    app.listen_any("e2e:log", |e| {
        // Every line prefixed so `grep '^E2E:'` keeps multi-line messages.
        for line in payload_str(e.payload()).lines() {
            println!("E2E: {line}");
        }
    });
    let shot_app = app.clone();
    app.listen_any("e2e:shot", move |e| {
        let app = shot_app.clone();
        let name = payload_str(e.payload());
        // Off the event thread: screencapture blocks for a moment.
        std::thread::spawn(move || {
            screenshot(&app, &name);
            if let Some(w) = app.get_webview_window("main") {
                let _ = w.eval("window.__e2e && window.__e2e.shotDone()");
            }
        });
    });
    // Scenario-driven host setup (disk images, file checks). Debug builds with an
    // explicit scenario only; the result goes back through `__e2e.shDone`.
    let sh_app = app.clone();
    app.listen_any("e2e:sh", move |e| {
        let app = sh_app.clone();
        let cmd = payload_str(e.payload());
        std::thread::spawn(move || {
            let (code, out) = match std::process::Command::new("sh").arg("-c").arg(&cmd).output() {
                Ok(o) => (
                    o.status.code().unwrap_or(-1),
                    format!("{}{}", String::from_utf8_lossy(&o.stdout), String::from_utf8_lossy(&o.stderr)),
                ),
                Err(e) => (-1, e.to_string()),
            };
            let result = serde_json::json!({ "code": code, "out": out });
            if let Some(w) = app.get_webview_window("main") {
                let _ = w.eval(format!("window.__e2e && window.__e2e.shDone({result})"));
            }
        });
    });
    let exit_app = app.clone();
    app.listen_any("e2e:exit", move |e| {
        let code = e.payload().trim().parse().unwrap_or(1);
        println!("E2E: exit {code}");
        exit_app.exit(code);
    });
    let timeout = std::env::var(ENV_TIMEOUT).ok().and_then(|t| t.parse().ok()).unwrap_or(900);
    let watchdog = app.clone();
    std::thread::spawn(move || {
        std::thread::sleep(Duration::from_secs(timeout));
        println!("E2E: FAIL watchdog timeout after {timeout}s");
        watchdog.exit(3);
    });

    if let Some(w) = app.get_webview_window("main") {
        let _ = w.set_always_on_top(true);
        let _ = w.set_focus();
    }
    let js = format!(
        "{PRELUDE}\n;(async () => {{\n{scenario}\n}})().then(() => __e2e.done(), (e) => __e2e.crash(e));"
    );
    if let Err(e) = webview.eval(js) {
        println!("E2E: FAIL eval: {e}");
        app.exit(1);
    }
}

/// Event payloads arrive JSON-encoded.
fn payload_str(raw: &str) -> String {
    serde_json::from_str::<String>(raw).unwrap_or_else(|_| raw.to_owned())
}

fn screenshot(app: &AppHandle, name: &str) {
    let Some(w) = app.get_webview_window("main") else {
        return;
    };
    let dir = std::env::var_os(ENV_SHOTS).map_or_else(|| PathBuf::from("/tmp/dapper-e2e"), PathBuf::from);
    let _ = std::fs::create_dir_all(&dir);
    let file = dir.join(format!("{name}.png"));
    let (Ok(pos), Ok(size), Ok(scale)) = (w.outer_position(), w.outer_size(), w.scale_factor()) else {
        return;
    };
    let pos = pos.to_logical::<f64>(scale);
    let size = size.to_logical::<f64>(scale);
    let rect = format!("{},{},{},{}", pos.x, pos.y, size.width, size.height);
    match std::process::Command::new("screencapture").args(["-x", "-R", &rect]).arg(&file).status() {
        Ok(s) if s.success() => println!("E2E: shot {}", file.display()),
        other => println!("E2E: shot failed {}: {other:?}", file.display()),
    }
}
