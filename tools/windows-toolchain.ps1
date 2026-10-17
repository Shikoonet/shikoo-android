# Windows toolchain that builds ShikooNet (the FlClash fork) for Windows x64. Flutter, Go and the JDK
# come from D:\dev\android-toolchain (its env.sh); this adds what `flutter build windows` and the Go/Rust
# build hook need on top: VS 2022 Build Tools (MSVC, CMake, Windows SDK), Rust, and Inno Setup 6 for
# the installer `dart setup.dart windows` packs.
#
# Versions: Rust from plugins/rust_api/rust/rust-toolchain.toml, Flutter and Go as .github/workflows/build.yaml.
# Re-runnable: each step skips what is already in place, and the versions are printed at the end.
#   pwsh -File tools/windows-toolchain.ps1                 # into D:\dev\windows-toolchain (-Root to move it)
#   Git Bash: source /d/dev/android-toolchain/env.sh && source /d/dev/windows-toolchain/env.sh
#
# Admin: the VS step raises one UAC prompt. Rust and Inno Setup install for this user only.
# By hand, once: Developer Mode (Settings > System > For developers). Flutter links every plugin with a
# symlink, which Windows lets a non-admin make only in Developer Mode; this script only checks it.
# What lands on C (measured 2026-10-17): the Visual Studio Installer (~145 MB) and the MSI caches in
# ProgramData\Package Cache and Windows\Installer (~0.5 GB). The Windows SDK went to D:\Windows Kits\10
# (the installer's choice; the registry's KitsRoot10 says where).
# Remove: VS Installer > Build Tools 2022 > Uninstall; Inno Setup from Settings > Apps;
#         rmdir %USERPROFILE%\.rustup %USERPROFILE%\.cargo (junctions); go env -u GOMODCACHE GOCACHE;
#         then delete the -Root folder. Builds made without env.sh leave %TEMP%\frb_native_assets_*.
param([string]$Root = 'D:\dev\windows-toolchain')
$ErrorActionPreference = 'Stop'

$RustVersion = '1.95.0'
# every target in rust-toolchain.toml: rustup adds a missing one the first time the hook runs there
$RustTargets = 'aarch64-linux-android,armv7-linux-androideabi,x86_64-linux-android,aarch64-apple-darwin,x86_64-apple-darwin,aarch64-pc-windows-msvc,x86_64-pc-windows-msvc,aarch64-unknown-linux-gnu,x86_64-unknown-linux-gnu'
$InnoVersion = '6.7.3'
$InnoSha256 = '9c73c3bae7ed48d44112a0f48e66742c00090bdb5bef71d9d3c056c66e97b732' # GitHub release digest, is-6_7_3
# what flutter doctor asks of a Build Tools install (it looks for the workload too), plus a Windows SDK
# for MSVC and Rust to link against
$VsComponents = @(
  'Microsoft.VisualStudio.Workload.VCTools',
  'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
  'Microsoft.VisualStudio.Component.VC.CMake.Project',
  'Microsoft.VisualStudio.Component.Windows11SDK.26100'
)
$Go = 'D:\dev\android-toolchain\go\bin\go.exe'
$Dl = "$Root\_downloads"

function Log([string]$m) { Write-Host "[$(Get-Date -Format HH:mm:ss)] $m" }

New-Item -ItemType Directory -Force $Dl | Out-Null
# one run at a time: two curls resuming one .part once corrupted a download on this machine
$lock = [IO.File]::Open("$Root\.install.lock", 'OpenOrCreate', 'ReadWrite', 'None')
$start = Get-Date

# curl and rustup read the proxy from the environment, which a fresh terminal lacks; Windows' own setting has it
if (-not $env:HTTPS_PROXY) {
  $is = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
  if ($is.ProxyEnable) { $env:HTTPS_PROXY = $env:HTTP_PROXY = "http://$($is.ProxyServer)" }
}

# Resumable; a transfer under 10 KB/s for 30 s is cut and resumed.
function Fetch([string]$Url, [string]$Name, [string]$Sha256) {
  $out = "$Dl\$Name"
  if ((Test-Path $out) -and (Get-FileHash $out).Hash -eq $Sha256) { Log "cached $Name"; return $out }
  Log "download $Name"
  for ($i = 1; $i -le 40; $i++) {
    # a complete .part from a cut run needs no request, and would get a 416
    if ((Test-Path "$out.part") -and (Get-FileHash "$out.part").Hash -eq $Sha256) { break }
    curl.exe -fL --connect-timeout 30 --speed-limit 10240 --speed-time 30 -sS -C - -o "$out.part" $Url
    if ($LASTEXITCODE -eq 0) { break }
    Log "  ${Name}: attempt $i stopped at $((Get-Item "$out.part" -ErrorAction SilentlyContinue).Length) bytes, resuming"
    Start-Sleep 5
  }
  $got = (Get-FileHash "$out.part").Hash
  if ($got -ne $Sha256) { Remove-Item "$out.part"; throw "${Name}: sha256 $got, want $Sha256" }
  Move-Item -Force "$out.part" $out
  return $out
}

# 1. Visual Studio 2022 Build Tools, C++ only
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
function VsPath { if (Test-Path $vswhere) { & $vswhere -products * -version '[17.0,18.0)' -requires $VsComponents -property installationPath -latest } }
if (-not (VsPath)) {
  # the bootstrapper changes with every VS release, so there is no fixed sum: Microsoft's signature instead
  $exe = "$Dl\vs_BuildTools.exe"
  curl.exe -fL --connect-timeout 30 --speed-limit 10240 --speed-time 30 -sS -o $exe https://aka.ms/vs/17/release/vs_BuildTools.exe
  if ($LASTEXITCODE) { throw "vs_BuildTools.exe: download failed ($LASTEXITCODE)" }
  $sig = Get-AuthenticodeSignature $exe
  if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notlike 'CN=Microsoft Corporation,*') {
    throw "vs_BuildTools.exe: signature $($sig.Status) by $($sig.SignerCertificate.Subject)"
  }
  Log 'VS Build Tools: asks for admin once (UAC), then downloads and installs; a progress window shows'
  # cache= and shared= take effect only on the first Visual Studio install of this machine
  $vsArgs = if (Test-Path "$Root\vs-buildtools\Common7") { @('modify', '--installPath', "$Root\vs-buildtools") } else {
    @('--installPath', "$Root\vs-buildtools", '--path', "cache=$Root\vs-cache", '--path', "shared=$Root\vs-shared", '--addProductLang', 'en-US')
  }
  $vsArgs += @('--nocache', '--passive', '--norestart', '--wait') + ($VsComponents | ForEach-Object { '--add', $_ })
  $p = Start-Process $exe -ArgumentList $vsArgs -Wait -PassThru
  if ($p.ExitCode -notin 0, 3010) { throw "VS Build Tools: installer exit $($p.ExitCode); logs: $env:TEMP\dd_*.log" }
  if (-not (VsPath)) { throw 'VS Build Tools: installer finished, but vswhere does not find the components' }
}
$vs = VsPath
Log "vs: $vs"

# 2. Rust. Flutter passes its build hooks only allowlisted variables (hooks_runner 1.5.0: PATH, USERPROFILE,
# ...), so RUSTUP_HOME and CARGO_HOME never reach rustup there and it would set up a second Rust under
# %USERPROFILE%. Junctions from those default homes keep a single Rust, on D.
foreach ($d in 'rustup', 'cargo') {
  $link = "$env:USERPROFILE\.$d"
  New-Item -ItemType Directory -Force "$Root\$d" | Out-Null
  if (-not (Test-Path $link)) { New-Item -ItemType Junction -Path $link -Target "$Root\$d" | Out-Null }
  elseif ((Get-Item $link -Force).Target -ne "$Root\$d") { throw "$link exists and is not a junction to $Root\$d; move it away first" }
}
$env:RUSTUP_HOME = "$Root\rustup"; $env:CARGO_HOME = "$Root\cargo"; $env:Path = "$Root\cargo\bin;$env:Path"
if (-not (Test-Path "$Root\cargo\bin\rustup.exe")) {
  $url = 'https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe'
  $init = Fetch $url 'rustup-init.exe' ((curl.exe -fsSL "$url.sha256") -split ' ')[0]
  & $init -y -q --no-modify-path --profile minimal --default-toolchain none --default-host x86_64-pc-windows-msvc
  if ($LASTEXITCODE) { throw "rustup-init exit $LASTEXITCODE" }
}
rustup toolchain install $RustVersion --profile minimal --target $RustTargets
if ($LASTEXITCODE) { throw "rustup toolchain install exit $LASTEXITCODE" }
rustup default $RustVersion | Out-Null

# 3. Inno Setup 6, for this user; flutter_distributor finds it through INNO_SETUP_PATH (env.sh)
$inno = "$Root\inno-setup"
if (-not (Test-Path "$inno\ISCC.exe")) {
  $tag = 'is-' + ($InnoVersion -replace '\.', '_')
  $is = Fetch "https://github.com/jrsoftware/issrc/releases/download/$tag/innosetup-$InnoVersion.exe" "innosetup-$InnoVersion.exe" $InnoSha256
  $p = Start-Process $is -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CURRENTUSER', '/NOICONS', "/DIR=$inno" -Wait -PassThru
  if ($p.ExitCode) { throw "Inno Setup installer exit $($p.ExitCode)" }
}

# 4. Go's caches on D. GOPATH would reach the hook but GOCACHE does not; go env -w keeps both for this user.
& $Go env -w "GOMODCACHE=$Root\go-mod" "GOCACHE=$Root\go-build"

New-Item -ItemType Directory -Force "$Root\tmp" | Out-Null
$posix = '/' + $Root.Substring(0, 1).ToLower() + ($Root.Substring(2) -replace '\\', '/')
$envSh = @"
# Windows build tools for ShikooNet, written by tools/windows-toolchain.ps1.
# Use after the Android one: source /d/dev/android-toolchain/env.sh && source $posix/env.sh
export RUSTUP_HOME='$Root\rustup' CARGO_HOME='$Root\cargo' INNO_SETUP_PATH='$inno'
# flutter_rust_bridge_hooks 2.13.0 keeps rust_api's Cargo target (~220 MB per checkout, never removed) in
# %TEMP%\frb_native_assets_<hash>; TEMP and TMP are among the variables Flutter passes to its hooks.
export TEMP='$Root\tmp' TMP='$Root\tmp'
export PATH="$posix/cargo/bin:`$PATH"
"@
[IO.File]::WriteAllText("$Root\env.sh", ($envSh -replace "`r", '') + "`n")

# Versions
$devMode = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -ErrorAction SilentlyContinue).AllowDevelopmentWithoutDevLicense
Log "vs build tools: $(& $vswhere -path $vs -property catalog_productDisplayVersion)"
Log "msvc: $(Get-Content "$vs\VC\Auxiliary\Build\Microsoft.VCToolsVersion.default.txt")"
Log "cmake: $((& "$vs\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" --version)[0])"
$kits = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows Kits\Installed Roots').KitsRoot10
Log "windows sdk: $((Get-ChildItem "$kits\Include" -Directory).Name -join ' ') in $kits"
Log "rust: $(rustc --version); $(cargo --version); rustup $((rustup --version 2>$null) -split ' ' | Select-Object -Index 1)"
Log "inno setup: $((Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 6_is1').DisplayVersion) in $inno"
Log "go: $(& $Go version); GOMODCACHE=$(& $Go env GOMODCACHE) GOCACHE=$(& $Go env GOCACHE)"
Log "flutter: $((& D:\dev\android-toolchain\flutter\bin\flutter.bat --version)[0])"
if ($devMode -eq 1) { Log 'developer mode: on' } else { Log 'developer mode: OFF - turn it on before flutter build windows (Settings > System > For developers)' }
Log "done in $([int]((Get-Date) - $start).TotalMinutes) min. Git Bash: source /d/dev/android-toolchain/env.sh && source $posix/env.sh"
$lock.Dispose()
