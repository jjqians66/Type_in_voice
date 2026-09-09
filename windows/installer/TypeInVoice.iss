#define MyAppName "Type in Voice"
#define MyAppVersion "2.1.0"
#define MyAppPublisher "Junjie Qian"
#define MyAppExeName "TypeInVoice.exe"
#ifndef SourceDir
  #define SourceDir "..\TypeInVoice.Windows\bin\Release\net8.0-windows10.0.19041.0\win-x64\publish"
#endif

[Setup]
AppId={{7A52E3CB-8F2E-4D8A-A305-56408B8F86B8}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\Type in Voice
DefaultGroupName=Type in Voice
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..\dist
OutputBaseFilename=TypeInVoice-Windows-x64-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\{#MyAppExeName}
CloseApplications=yes
RestartApplications=no

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked
Name: "startup"; Description: "Start Type in Voice when I sign in"; GroupDescription: "Startup:"; Flags: unchecked

[Files]
Source: "{#SourceDir}\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Type in Voice"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\Type in Voice"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Registry]
Root: HKA; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "TypeInVoice"; ValueData: """{app}\{#MyAppExeName}"""; Flags: uninsdeletevalue; Tasks: startup

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch Type in Voice"; Flags: nowait postinstall skipifsilent
