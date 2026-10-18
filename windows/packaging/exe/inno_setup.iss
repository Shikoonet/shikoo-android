; SHIKOO_FLAVOR=staging in the environment of the build makes the test build: its own id, name, folders
; and helper service, as the Helper built with build_config.yaml flavor: staging names it.
#if GetEnv("SHIKOO_FLAVOR") == "staging"
#define Title "ShikooNet Test"
#define Id "D6F866A6-CE01-4C34-A9C5-C49D6D030A27"
#define Service "ShikooNetTestHelperService"
#else
#define Title "{{DISPLAY_NAME}}"
#define Id "{{APP_ID}}"
#define Service "ShikooNetHelperService"
#endif
#pragma message "ShikooNet installer: " + Title + ", id " + Id + ", service " + Service
[Setup]
AppId={#Id}
AppVersion={{APP_VERSION}}
AppName={#Title}
AppPublisher={{PUBLISHER_NAME}}
AppPublisherURL={{PUBLISHER_URL}}
AppSupportURL={{PUBLISHER_URL}}
AppUpdatesURL={{PUBLISHER_URL}}
DefaultDirName={autopf64}\{#Title}
DisableProgramGroupPage=yes
DisableDirPage=yes
DisableReadyPage=yes
OutputDir=.
OutputBaseFilename={{OUTPUT_BASE_FILENAME}}
Compression=lzma
SolidCompression=yes
SetupIconFile={{SETUP_ICON_FILE}}
UninstallDisplayIcon={app}\{{EXECUTABLE_NAME}}
UninstallDisplayName={#Title}
WizardStyle=modern
PrivilegesRequired={{PRIVILEGES_REQUIRED}}
ArchitecturesAllowed={{ARCH}}
ArchitecturesInstallIn64BitMode={{ARCH}}

[Code]
// Only this install's three programs: the other flavor runs the same names from its own folder,
// and the uninstaller's first copy runs from this folder too.
procedure KillProcesses;
var
  ResultCode: Integer;
begin
  Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    '-NoProfile -NonInteractive -Command "Get-Process ShikooNet,ShikooNetCore,ShikooNetHelperService -ErrorAction SilentlyContinue | Where-Object { $_.Path -like ''' +
    ExpandConstant('{app}') + '\*'' } | Stop-Process -Force"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

procedure UnregisterHelperService;
var
  HelperPath: String;
  ResultCode: Integer;
begin
  HelperPath := ExpandConstant('{app}\\ShikooNetHelperService.exe');
  if FileExists(HelperPath) then
  begin
    Exec(HelperPath, 'uninstall', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end
  else
    // An antivirus may have taken the file and left its AutoStart service registered.
    Exec(ExpandConstant('{sys}\sc.exe'), 'delete {#Service}', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  UnregisterHelperService;
  KillProcesses;
  Exec(ExpandConstant('{app}\ShikooNet.exe'), '--restore-proxy', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Result := '';
end;

// With DisableReadyPage the tasks page still says Next; Install starts the install from there.
procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpSelectTasks then
    WizardForm.NextButton.Caption := SetupMessage(msgButtonInstall);
end;

function InitializeUninstall(): Boolean;
begin
  UnregisterHelperService;
  KillProcesses;
  Result := True;
end;

[Languages]
{% for locale in LOCALES %}
{% if locale.lang == 'en' %}Name: "english"; MessagesFile: "compiler:Default.isl"{% endif %}
{% if locale.lang == 'hy' %}Name: "armenian"; MessagesFile: "compiler:Languages\\Armenian.isl"{% endif %}
{% if locale.lang == 'bg' %}Name: "bulgarian"; MessagesFile: "compiler:Languages\\Bulgarian.isl"{% endif %}
{% if locale.lang == 'ca' %}Name: "catalan"; MessagesFile: "compiler:Languages\\Catalan.isl"{% endif %}
{% if locale.lang == 'zh' %}
Name: "chineseSimplified"; MessagesFile: {% if locale.file %}{{ locale.file }}{% else %}"compiler:Languages\\ChineseSimplified.isl"{% endif %}
{% endif %}
{% if locale.lang == 'co' %}Name: "corsican"; MessagesFile: "compiler:Languages\\Corsican.isl"{% endif %}
{% if locale.lang == 'cs' %}Name: "czech"; MessagesFile: "compiler:Languages\\Czech.isl"{% endif %}
{% if locale.lang == 'da' %}Name: "danish"; MessagesFile: "compiler:Languages\\Danish.isl"{% endif %}
{% if locale.lang == 'nl' %}Name: "dutch"; MessagesFile: "compiler:Languages\\Dutch.isl"{% endif %}
{% if locale.lang == 'fi' %}Name: "finnish"; MessagesFile: "compiler:Languages\\Finnish.isl"{% endif %}
{% if locale.lang == 'fr' %}Name: "french"; MessagesFile: "compiler:Languages\\French.isl"{% endif %}
{% if locale.lang == 'de' %}Name: "german"; MessagesFile: "compiler:Languages\\German.isl"{% endif %}
{% if locale.lang == 'he' %}Name: "hebrew"; MessagesFile: "compiler:Languages\\Hebrew.isl"{% endif %}
{% if locale.lang == 'is' %}Name: "icelandic"; MessagesFile: "compiler:Languages\\Icelandic.isl"{% endif %}
{% if locale.lang == 'it' %}Name: "italian"; MessagesFile: "compiler:Languages\\Italian.isl"{% endif %}
{% if locale.lang == 'ja' %}Name: "japanese"; MessagesFile: "compiler:Languages\\Japanese.isl"{% endif %}
{% if locale.lang == 'no' %}Name: "norwegian"; MessagesFile: "compiler:Languages\\Norwegian.isl"{% endif %}
{% if locale.lang == 'pl' %}Name: "polish"; MessagesFile: "compiler:Languages\\Polish.isl"{% endif %}
{% if locale.lang == 'pt' %}Name: "portuguese"; MessagesFile: "compiler:Languages\\Portuguese.isl"{% endif %}
{% if locale.lang == 'ru' %}Name: "russian"; MessagesFile: "compiler:Languages\\Russian.isl"{% endif %}
{% if locale.lang == 'sk' %}Name: "slovak"; MessagesFile: "compiler:Languages\\Slovak.isl"{% endif %}
{% if locale.lang == 'sl' %}Name: "slovenian"; MessagesFile: "compiler:Languages\\Slovenian.isl"{% endif %}
{% if locale.lang == 'es' %}Name: "spanish"; MessagesFile: "compiler:Languages\\Spanish.isl"{% endif %}
{% if locale.lang == 'tr' %}Name: "turkish"; MessagesFile: "compiler:Languages\\Turkish.isl"{% endif %}
{% if locale.lang == 'uk' %}Name: "ukrainian"; MessagesFile: "compiler:Languages\\Ukrainian.isl"{% endif %}
{% endfor %}

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: {% if CREATE_DESKTOP_ICON != true %}unchecked{% else %}checkedonce{% endif %}
[Files]
Source: "{{SOURCE_DIR}}\\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; NOTE: Don't use "Flags: ignoreversion" on any shared system files

[Icons]
Name: "{autoprograms}\{#Title}"; Filename: "{app}\\{{EXECUTABLE_NAME}}"
Name: "{autodesktop}\{#Title}"; Filename: "{app}\\{{EXECUTABLE_NAME}}"; Tasks: desktopicon
[Messages]
SelectTasksLabel2=Select the additional tasks you would like Setup to perform while installing [name], then click Install.

[Run]
; Installed here, with the rights Setup already has, so the first tunnel asks for none. PrepareToInstall removed it.
Filename: "{app}\ShikooNetHelperService.exe"; Parameters: "install"; StatusMsg: "Starting the {#Title} service..."; Flags: runhidden
Filename: "{app}\\{{EXECUTABLE_NAME}}"; Description: "{cm:LaunchProgram,{#Title}}"; Flags: runasoriginaluser nowait postinstall skipifsilent
Filename: "{app}\\{{EXECUTABLE_NAME}}"; Flags: runasoriginaluser nowait skipifnotsilent
[UninstallRun]
; The first step of the uninstall, after InitializeUninstall closed the app and before [UninstallDelete],
; the last step, deletes the data it reads Windows' earlier proxy from.
Filename: "{app}\ShikooNet.exe"; Parameters: "--restore-proxy"; Flags: runhidden waituntilterminated; RunOnceId: "ShikooRestoreProxy"
[UninstallDelete]
; The app's data: path_provider_windows names it CompanyName\ProductName of windows/runner/Runner.rc.
Type: filesandordirs; Name: "{userappdata}\ShikooNet\{#Title}"
Type: dirifempty; Name: "{userappdata}\ShikooNet"
Type: filesandordirs; Name: "{localappdata}\ShikooNet\{#Title}"
Type: dirifempty; Name: "{localappdata}\ShikooNet"
