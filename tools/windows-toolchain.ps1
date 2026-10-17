# Windows build tools for ShikooNet beside D:\dev\android-toolchain; re-runnable. Usage: SHIKOO_PATCHES.md, «ساختن اپ شیکو».
$ErrorActionPreference = 'Stop'

$Root = 'D:\dev\windows-toolchain'
$InnoVersion = '6.7.3'
$InnoSha256 = '9c73c3bae7ed48d44112a0f48e66742c00090bdb5bef71d9d3c056c66e97b732'
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
$lock = [IO.File]::Open("$Root\.install.lock", 'OpenOrCreate', 'ReadWrite', 'None')
$start = Get-Date

if (-not $env:HTTPS_PROXY) {
  $is = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
  if ($is.ProxyEnable) { $env:HTTPS_PROXY = $env:HTTP_PROXY = "http://$($is.ProxyServer)" }
}

function Fetch([string]$Url, [string]$Name, [string]$Sha256) {
  $out = "$Dl\$Name"
  if ((Test-Path $out) -and (Get-FileHash $out).Hash -eq $Sha256) { Log "cached $Name"; return $out }
  Log "download $Name"
  for ($i = 1; $i -le 40; $i++) {
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

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
function VsPath { if (Test-Path $vswhere) { & $vswhere -products * -version '[17.0,18.0)' -requires $VsComponents -property installationPath -latest } }
if (-not (VsPath)) {
  # Microsoft publishes no fixed sum for the bootstrapper, so its signature is checked instead
  $exe = "$Dl\vs_BuildTools.exe"
  curl.exe -fL --connect-timeout 30 --speed-limit 10240 --speed-time 30 -sS -o $exe https://aka.ms/vs/17/release/vs_BuildTools.exe
  if ($LASTEXITCODE) { throw "vs_BuildTools.exe: download failed ($LASTEXITCODE)" }
  $sig = Get-AuthenticodeSignature $exe
  if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notlike 'CN=Microsoft Corporation,*') {
    throw "vs_BuildTools.exe: signature $($sig.Status) by $($sig.SignerCertificate.Subject)"
  }
  Log 'VS Build Tools: asks for admin once (UAC), then downloads and installs; a progress window shows'
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

# Flutter's build hooks get only allowlisted variables (hooks_runner 1.5.0): USERPROFILE, APPDATA and TEMP, but not
# RUSTUP_HOME, CARGO_HOME or GOCACHE. Hence the junctions from the default Rust homes, go env -w, and TEMP in env.sh.
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
Push-Location "$PSScriptRoot\..\plugins\rust_api\rust"
rustup toolchain install
if ($LASTEXITCODE) { throw "rustup toolchain install exit $LASTEXITCODE" }
rustup default ((rustup show active-toolchain) -split ' ')[0] | Out-Null
Pop-Location

$inno = "$Root\inno-setup"
if (-not (Test-Path "$inno\ISCC.exe")) {
  $tag = 'is-' + ($InnoVersion -replace '\.', '_')
  $is = Fetch "https://github.com/jrsoftware/issrc/releases/download/$tag/innosetup-$InnoVersion.exe" "innosetup-$InnoVersion.exe" $InnoSha256
  $p = Start-Process $is -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CURRENTUSER', '/NOICONS', "/DIR=$inno" -Wait -PassThru
  if ($p.ExitCode) { throw "Inno Setup installer exit $($p.ExitCode)" }
}

& $Go env -w "GOMODCACHE=$Root\go-mod" "GOCACHE=$Root\go-build"

New-Item -ItemType Directory -Force "$Root\tmp" | Out-Null
$envSh = @"
# written by tools/windows-toolchain.ps1; source it after /d/dev/android-toolchain/env.sh
export RUSTUP_HOME='$Root\rustup' CARGO_HOME='$Root\cargo' INNO_SETUP_PATH='$inno'
export TEMP='$Root\tmp' TMP='$Root\tmp'
export PATH="/d/dev/windows-toolchain/cargo/bin:`$PATH"
"@
[IO.File]::WriteAllText("$Root\env.sh", ($envSh -replace "`r", '') + "`n")

$devMode = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -ErrorAction SilentlyContinue).AllowDevelopmentWithoutDevLicense
$kits = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows Kits\Installed Roots').KitsRoot10
Log "vs build tools: $(& $vswhere -path $vs -property catalog_productDisplayVersion)"
Log "msvc: $(Get-Content "$vs\VC\Auxiliary\Build\Microsoft.VCToolsVersion.default.txt")"
Log "cmake: $((& "$vs\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" --version)[0])"
Log "windows sdk: $((Get-ChildItem "$kits\Include" -Directory).Name -join ' ') in $kits"
Log "rust: $(rustc --version); $(cargo --version); rustup $((rustup --version 2>$null) -split ' ' | Select-Object -Index 1)"
Log "rust targets: $((rustup target list --installed) -join ' ')"
Log "inno setup: $((Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 6_is1').DisplayVersion) in $inno"
Log "go: $(& $Go version); GOMODCACHE=$(& $Go env GOMODCACHE) GOCACHE=$(& $Go env GOCACHE)"
Log "flutter: $((& D:\dev\android-toolchain\flutter\bin\flutter.bat --version)[0])"
if ($devMode -eq 1) { Log 'developer mode: on' } else { Log 'developer mode: OFF - Flutter links plugins with symlinks; turn it on (Settings > System > For developers)' }
Log "done in $([int]((Get-Date) - $start).TotalMinutes) min. Git Bash: source /d/dev/android-toolchain/env.sh && source /d/dev/windows-toolchain/env.sh"
$lock.Dispose()
