; Inno Setup script for the vBank Windows installer.
; Built by .github/workflows/release.yml on every v* tag:
;   iscc /DVBankVersion=1.7.0 windows\installer\vbank.iss
; Locally: build first (flutter build windows --release), then run the same
; command from the repository root with Inno Setup 6 installed.

#ifndef VBankVersion
  #define VBankVersion "0.0.0"
#endif
#define VBankName "vBank"
#define VBankExe "vbank.exe"

[Setup]
AppId={{6F2D3B9A-8C41-4B7E-9D2A-3E5F7A1C9B04}
AppName={#VBankName}
AppVersion={#VBankVersion}
AppVerName={#VBankName} {#VBankVersion}
AppPublisher=vBank
AppPublisherURL=https://arthurkay.github.io/vbank/
AppSupportURL=https://arthurkay.github.io/vbank/guide.html
DefaultDirName={autopf}\{#VBankName}
DefaultGroupName={#VBankName}
DisableProgramGroupPage=yes
; Per-user by default (no admin prompt); the dialog lets an admin install for all users.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..\dist
OutputBaseFilename=vbank-{#VBankVersion}-windows-x64-setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#VBankExe}
UninstallDisplayName={#VBankName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; The whole Flutter release bundle: vbank.exe, flutter_windows.dll, plugin DLLs and data\.
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#VBankName}"; Filename: "{app}\{#VBankExe}"
Name: "{autodesktop}\{#VBankName}"; Filename: "{app}\{#VBankExe}"; Tasks: desktopicon

[Registry]
; vbank:// invite links open the app (app_links reads the command line).
Root: HKA; Subkey: "Software\Classes\vbank"; ValueType: string; ValueName: ""; ValueData: "URL:vBank invite"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\vbank"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\vbank\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#VBankExe},0"
Root: HKA; Subkey: "Software\Classes\vbank\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#VBankExe}"" ""%1"""

[Run]
Filename: "{app}\{#VBankExe}"; Description: "{cm:LaunchProgram,{#StringChange(VBankName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
