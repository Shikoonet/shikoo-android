use super::hub::log_message;
use anyhow::{bail, Result};
use std::ffi::{c_void, OsStr, OsString};
use std::net::{SocketAddr, TcpStream};
use std::os::windows::ffi::{OsStrExt, OsStringExt};
use std::path::{Path, PathBuf};
use std::sync::{Mutex, PoisonError};
use std::time::{Duration, Instant};
use std::{io, mem, ptr, thread};
use windows_sys::Win32::Foundation::{CloseHandle, GlobalFree, HANDLE, INVALID_HANDLE_VALUE};
use windows_sys::Win32::NetworkManagement::Rras::{
    RasEnumEntriesW, ERROR_BUFFER_TOO_SMALL, RASENTRYNAMEW,
};
use windows_sys::Win32::Networking::WinInet::{
    InternetQueryOptionW, InternetSetOptionW, INTERNET_OPTION_PER_CONNECTION_OPTION,
    INTERNET_OPTION_REFRESH, INTERNET_OPTION_SETTINGS_CHANGED, INTERNET_PER_CONN_FLAGS,
    INTERNET_PER_CONN_OPTIONW, INTERNET_PER_CONN_OPTIONW_0, INTERNET_PER_CONN_OPTION_LISTW,
    INTERNET_PER_CONN_PROXY_SERVER, PROXY_TYPE_DIRECT, PROXY_TYPE_PROXY,
};
use windows_sys::Win32::System::Diagnostics::ToolHelp::{
    CreateToolhelp32Snapshot, Process32FirstW, Process32NextW, PROCESSENTRY32W, TH32CS_SNAPPROCESS,
};
use windows_sys::Win32::System::Environment::{CreateEnvironmentBlock, DestroyEnvironmentBlock};
use windows_sys::Win32::System::RemoteDesktop::{ProcessIdToSessionId, WTSQueryUserToken};
use windows_sys::Win32::System::Threading::{
    CreateProcessAsUserW, GetCurrentProcessId, OpenProcess, QueryFullProcessImageNameW,
    WaitForSingleObject, CREATE_UNICODE_ENVIRONMENT, INFINITE, PROCESS_ACCESS_RIGHTS,
    PROCESS_INFORMATION, PROCESS_NAME_WIN32, PROCESS_QUERY_LIMITED_INFORMATION,
    PROCESS_SYNCHRONIZE, STARTUPINFOW,
};

/// `shikooDesktopPort` of `lib/shikoo/engine/mode.dart`: the port the app sets as Windows' proxy.
const PROXY_PORT: u16 = if cfg!(shikoo_staging) { 17471 } else { 17470 };
const APP_EXE: &str = "ShikooNet.exe";
/// The Core closes its port within the 3 s exit cleanup of `core/exit.go` once the app is gone.
const PORT_GRACE: Duration = Duration::from_secs(5);

struct Handle(HANDLE);

impl Drop for Handle {
    fn drop(&mut self) {
        // SAFETY: the handle is owned here and closed once.
        unsafe { CloseHandle(self.0) };
    }
}

/// `fix-proxy`, as the user: off with the system proxy the app left on its port with nothing behind
/// it, as FlClash's `stopProxy` does; the app's next launch puts the setting from before it back.
pub fn fix_proxy() -> Result<()> {
    let app = std::env::current_exe()?.with_file_name(APP_EXE);
    if should_clear(lan_proxy(), || app_alive(&app), port_answers) && !set_direct() {
        bail!("could not turn Windows' proxy off");
    }
    Ok(())
}

static GUARDED: Mutex<Vec<u32>> = Mutex::new(Vec::new());

/// `POST /guard`: once this install's app at `pid` exits, `fix-proxy` runs as the user of its
/// session, since WinINet is not for services. Any other process is refused.
pub(super) fn guard(pid: u32) -> bool {
    let Ok(helper) = std::env::current_exe() else {
        return false;
    };
    let (Some(process), Some(session)) = (
        open_app(pid, &helper.with_file_name(APP_EXE)),
        session_of(pid),
    ) else {
        return false;
    };
    let mut guarded = GUARDED.lock().unwrap_or_else(PoisonError::into_inner);
    if guarded.contains(&pid) {
        return true;
    }
    guarded.push(pid);
    thread::spawn(move || {
        // SAFETY: the open handle keeps the pid from being reused until the wait ends.
        unsafe { WaitForSingleObject(process.0, INFINITE) };
        GUARDED
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .retain(|&other| other != pid);
        if let Err(error) = run_in_session(session, &helper) {
            log_message(format!("Helper could not run fix-proxy: {error}"));
        }
    });
    true
}

fn open_app(pid: u32, app: &Path) -> Option<Handle> {
    let process = open(pid, PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_SYNCHRONIZE)?;
    image_path(&process)
        .is_some_and(|image| is_app(&image, app))
        .then_some(process)
}

fn run_in_session(session: u32, helper: &Path) -> io::Result<()> {
    let wide = |text: &OsStr| -> Vec<u16> { text.encode_wide().chain([0]).collect() };
    let application = wide(helper.as_os_str());
    let mut command = OsString::from("\"");
    command.push(helper);
    command.push("\" fix-proxy");
    let mut command = wide(&command);
    let mut desktop = wide(OsStr::new(r"winsta0\default"));
    // SAFETY: LocalSystem holds the SE_TCB_NAME WTSQueryUserToken needs; every buffer outlives the
    // calls, and each handle and the environment block is released once.
    unsafe {
        let mut token = 0;
        if WTSQueryUserToken(session, &mut token) == 0 {
            return Err(io::Error::last_os_error());
        }
        let token = Handle(token);
        let mut environment = ptr::null_mut();
        if CreateEnvironmentBlock(&mut environment, token.0, 0) == 0 {
            return Err(io::Error::last_os_error());
        }
        let mut startup: STARTUPINFOW = mem::zeroed();
        startup.cb = mem::size_of::<STARTUPINFOW>() as u32;
        startup.lpDesktop = desktop.as_mut_ptr();
        let mut created: PROCESS_INFORMATION = mem::zeroed();
        let started = CreateProcessAsUserW(
            token.0,
            application.as_ptr(),
            command.as_mut_ptr(),
            ptr::null(),
            ptr::null(),
            0,
            CREATE_UNICODE_ENVIRONMENT,
            environment,
            ptr::null(),
            &startup,
            &mut created,
        );
        let error = io::Error::last_os_error();
        DestroyEnvironmentBlock(environment);
        if started == 0 {
            return Err(error);
        }
        drop((Handle(created.hProcess), Handle(created.hThread)));
        Ok(())
    }
}

fn should_clear(
    lan: Option<(u32, String)>,
    app_alive: impl FnOnce() -> bool,
    port_answers: impl FnOnce() -> bool,
) -> bool {
    lan.is_some_and(|(flags, server)| {
        flags & PROXY_TYPE_PROXY != 0 && server == format!("127.0.0.1:{PROXY_PORT}")
    }) && !app_alive()
        && !port_answers()
}

fn option(id: u32, value: u32) -> INTERNET_PER_CONN_OPTIONW {
    INTERNET_PER_CONN_OPTIONW {
        dwOption: id,
        Value: INTERNET_PER_CONN_OPTIONW_0 { dwValue: value },
    }
}

fn option_list(options: &mut [INTERNET_PER_CONN_OPTIONW]) -> INTERNET_PER_CONN_OPTION_LISTW {
    INTERNET_PER_CONN_OPTION_LISTW {
        dwSize: mem::size_of::<INTERNET_PER_CONN_OPTION_LISTW>() as u32,
        pszConnection: ptr::null_mut(),
        dwOptionCount: options.len() as u32,
        dwOptionError: 0,
        pOptions: options.as_mut_ptr(),
    }
}

fn lan_proxy() -> Option<(u32, String)> {
    let mut options = [
        option(INTERNET_PER_CONN_FLAGS, 0),
        option(INTERNET_PER_CONN_PROXY_SERVER, 0),
    ];
    let mut list = option_list(&mut options);
    let mut size = list.dwSize;
    // SAFETY: the list points at `options`, which outlives the call; WinINet hands the server string
    // over to this process, which frees it with GlobalFree.
    unsafe {
        if InternetQueryOptionW(
            ptr::null(),
            INTERNET_OPTION_PER_CONNECTION_OPTION,
            &mut list as *mut _ as *mut c_void,
            &mut size,
        ) == 0
        {
            return None;
        }
        let text = options[1].Value.pszValue;
        let mut server = String::new();
        if !text.is_null() {
            let length = (0..).take_while(|&i| *text.add(i) != 0).count();
            server = String::from_utf16_lossy(std::slice::from_raw_parts(text, length));
            GlobalFree(text as _);
        }
        Some((options[0].Value.dwValue, server))
    }
}

/// `stopProxy` of `plugins/proxy/windows/proxy_plugin.cpp`: DIRECT alone, on the LAN and every dial-up entry.
fn set_direct() -> bool {
    let mut options = [option(INTERNET_PER_CONN_FLAGS, PROXY_TYPE_DIRECT)];
    let mut list = option_list(&mut options);
    let mut set = |connection: *mut u16| {
        list.pszConnection = connection;
        // SAFETY: the list and the connection name outlive the call.
        unsafe {
            InternetSetOptionW(
                ptr::null(),
                INTERNET_OPTION_PER_CONNECTION_OPTION,
                &list as *const _ as *const c_void,
                list.dwSize,
            ) != 0
        }
    };
    let mut applied = set(ptr::null_mut());
    match ras_entries() {
        Some(mut entries) => {
            for entry in &mut entries {
                applied &= set(entry.szEntryName.as_mut_ptr());
            }
        }
        None => applied = false,
    }
    // SAFETY: two notifications without a buffer.
    unsafe {
        let changed = InternetSetOptionW(
            ptr::null(),
            INTERNET_OPTION_SETTINGS_CHANGED,
            ptr::null(),
            0,
        );
        let refreshed = InternetSetOptionW(ptr::null(), INTERNET_OPTION_REFRESH, ptr::null(), 0);
        applied && changed != 0 && refreshed != 0
    }
}

fn ras_entries() -> Option<Vec<RASENTRYNAMEW>> {
    let (mut size, mut count) = (0u32, 0u32);
    // SAFETY: the sizes are this function's; the second call gets a buffer of `count` entries.
    unsafe {
        match RasEnumEntriesW(
            ptr::null(),
            ptr::null(),
            ptr::null_mut(),
            &mut size,
            &mut count,
        ) {
            0 => return Some(Vec::new()),
            ERROR_BUFFER_TOO_SMALL if count > 0 => {}
            _ => return None,
        }
        let mut entries = vec![mem::zeroed::<RASENTRYNAMEW>(); count as usize];
        for entry in &mut entries {
            entry.dwSize = mem::size_of::<RASENTRYNAMEW>() as u32;
        }
        if RasEnumEntriesW(
            ptr::null(),
            ptr::null(),
            entries.as_mut_ptr(),
            &mut size,
            &mut count,
        ) != 0
        {
            return None;
        }
        entries.truncate(count as usize);
        Some(entries)
    }
}

fn open(pid: u32, access: PROCESS_ACCESS_RIGHTS) -> Option<Handle> {
    // SAFETY: a plain kernel32 call; the handle is closed by Handle.
    let process = unsafe { OpenProcess(access, 0, pid) };
    (process != 0).then_some(Handle(process))
}

fn image_path(process: &Handle) -> Option<PathBuf> {
    let mut buffer = [0u16; 1024];
    let mut size = buffer.len() as u32;
    // SAFETY: the buffer and its size are this function's.
    let read = unsafe {
        QueryFullProcessImageNameW(
            process.0,
            PROCESS_NAME_WIN32,
            buffer.as_mut_ptr(),
            &mut size,
        )
    };
    (read != 0).then(|| OsString::from_wide(&buffer[..size as usize]).into())
}

fn is_app(image: &Path, app: &Path) -> bool {
    image
        .to_string_lossy()
        .eq_ignore_ascii_case(&app.to_string_lossy())
}

fn session_of(pid: u32) -> Option<u32> {
    let mut session = 0;
    // SAFETY: a plain kernel32 call writing to a local.
    (unsafe { ProcessIdToSessionId(pid, &mut session) } != 0).then_some(session)
}

/// Both builds run a ShikooNet.exe, each from its own folder; one that cannot be read counts as alive.
fn app_alive(app: &Path) -> bool {
    // SAFETY: plain toolhelp calls on a snapshot this function owns, reading an entry of its own.
    unsafe {
        let Some(session) = session_of(GetCurrentProcessId()) else {
            return true;
        };
        let snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
        if snapshot == INVALID_HANDLE_VALUE {
            return true;
        }
        let snapshot = Handle(snapshot);
        let mut entry: PROCESSENTRY32W = mem::zeroed();
        entry.dwSize = mem::size_of::<PROCESSENTRY32W>() as u32;
        let mut more = Process32FirstW(snapshot.0, &mut entry) != 0;
        while more {
            let length = entry.szExeFile.iter().position(|&c| c == 0).unwrap_or(0);
            let name = String::from_utf16_lossy(&entry.szExeFile[..length]);
            if name.eq_ignore_ascii_case(APP_EXE)
                && session_of(entry.th32ProcessID) == Some(session)
                && open(entry.th32ProcessID, PROCESS_QUERY_LIMITED_INFORMATION)
                    .and_then(|process| image_path(&process))
                    .is_none_or(|image| is_app(&image, app))
            {
                return true;
            }
            more = Process32NextW(snapshot.0, &mut entry) != 0;
        }
        false
    }
}

fn port_answers() -> bool {
    let address = SocketAddr::from(([127, 0, 0, 1], PROXY_PORT));
    let deadline = Instant::now() + PORT_GRACE;
    while TcpStream::connect_timeout(&address, Duration::from_millis(500)).is_ok() {
        if Instant::now() >= deadline {
            return true;
        }
        thread::sleep(Duration::from_millis(250));
    }
    false
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::process::{Child, Command, Stdio};

    const OURS: &str = if cfg!(shikoo_staging) {
        "127.0.0.1:17471"
    } else {
        "127.0.0.1:17470"
    };
    const OTHER_BUILD: &str = if cfg!(shikoo_staging) {
        "127.0.0.1:17470"
    } else {
        "127.0.0.1:17471"
    };
    const ON: u32 = PROXY_TYPE_DIRECT | PROXY_TYPE_PROXY;

    fn clears(flags: u32, server: &str, app_alive: bool, port_answers: bool) -> bool {
        should_clear(
            Some((flags, server.to_string())),
            || app_alive,
            || port_answers,
        )
    }

    #[test]
    fn clears_only_this_builds_proxy_with_no_app_and_nothing_on_its_port() {
        assert!(clears(ON, OURS, false, false));
        assert!(clears(PROXY_TYPE_PROXY | 8, OURS, false, false));
        assert!(!clears(ON, OURS, true, false), "the app is alive");
        assert!(!clears(ON, OURS, false, true), "the port answers");
        assert!(!clears(ON, OTHER_BUILD, false, false), "the other build's");
        assert!(!clears(PROXY_TYPE_DIRECT, OURS, false, false));
        for server in ["127.0.0.1:10808", &format!("http={OURS};https={OURS}"), ""] {
            assert!(!clears(ON, server, false, false), "{server}");
        }
        assert!(!should_clear(None, || false, || false));
    }

    #[test]
    fn asks_about_the_app_and_its_port_only_for_this_builds_proxy() {
        let unasked = || -> bool { panic!("asked") };
        assert!(!should_clear(
            Some((ON, OTHER_BUILD.to_string())),
            unasked,
            unasked
        ));
        assert!(!should_clear(
            Some((ON, OURS.to_string())),
            || true,
            unasked
        ));
    }

    #[test]
    fn the_app_is_the_one_exe_beside_the_helper() {
        let app = Path::new(r"C:\Program Files\ShikooNet\ShikooNet.exe");
        assert!(is_app(
            Path::new(r"c:\program files\shikoonet\SHIKOONET.EXE"),
            app
        ));
        for other in [
            r"C:\Program Files\ShikooNet Test\ShikooNet.exe",
            r"C:\Program Files\ShikooNet\ShikooNetCore.exe",
            r"C:\Users\someone\ShikooNet.exe",
        ] {
            assert!(!is_app(Path::new(other), app), "{other}");
        }
    }

    /// Windows' own ping under the app's name, in a folder of its own.
    fn spawn_named_app(folder: &str) -> (Child, PathBuf) {
        let directory = std::env::temp_dir().join(format!("{folder}-{}", std::process::id()));
        std::fs::create_dir_all(&directory).unwrap();
        let app = directory.join(APP_EXE);
        let system = std::env::var_os("SystemRoot").unwrap();
        std::fs::copy(Path::new(&system).join(r"System32\PING.EXE"), &app).unwrap();
        let child = Command::new(&app)
            .args(["-n", "60", "127.0.0.1"])
            .stdout(Stdio::null())
            .spawn()
            .unwrap();
        (child, app)
    }

    #[test]
    fn the_app_is_alive_only_from_its_own_folder() {
        let (mut child, app) = spawn_named_app("shikoo-proxy-guard-alive");
        let alive = app_alive(&app);
        let other = app_alive(&app.with_file_name("Other").join(APP_EXE));
        child.kill().unwrap();
        child.wait().unwrap();
        drop(child);
        assert!(alive);
        assert!(!other);
        assert!(!app_alive(&app));
        std::fs::remove_dir_all(app.parent().unwrap()).unwrap();
    }

    #[test]
    fn guards_only_the_app_beside_the_helper() {
        let (mut child, app) = spawn_named_app("shikoo-proxy-guard-open");
        let opened = open_app(child.id(), &app).is_some();
        let elsewhere = open_app(child.id(), &app.with_file_name("Other").join(APP_EXE)).is_some();
        child.kill().unwrap();
        child.wait().unwrap();
        assert!(opened);
        assert!(!elsewhere);
        let beside_the_test = std::env::current_exe().unwrap().with_file_name(APP_EXE);
        assert!(open_app(std::process::id(), &beside_the_test).is_none());
        assert!(!guard(std::process::id()));
        assert!(!guard(0));
        std::fs::remove_dir_all(app.parent().unwrap()).unwrap();
    }
}
