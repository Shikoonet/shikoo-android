// `fix-proxy` runs from a logon Run entry, which shows a console program's window.
#![cfg_attr(all(windows, not(test)), windows_subsystem = "windows")]
#[cfg(not(any(
    all(feature = "windows-service", target_os = "windows"),
    target_os = "linux"
)))]
use crate::service::hub::run_service;
#[cfg(not(any(
    all(feature = "windows-service", target_os = "windows"),
    target_os = "linux"
)))]
use tokio::runtime::Runtime;

mod service;

#[cfg(all(feature = "windows-service", target_os = "windows"))]
pub fn main() -> anyhow::Result<()> {
    service::windows::main()
}

#[cfg(target_os = "linux")]
pub fn main() -> anyhow::Result<()> {
    service::linux::main()
}

#[cfg(not(any(
    all(feature = "windows-service", target_os = "windows"),
    target_os = "linux"
)))]
fn main() {
    if let Ok(rt) = Runtime::new() {
        rt.block_on(async {
            let _ = run_service().await;
        });
    }
}
