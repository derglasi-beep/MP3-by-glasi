#ifndef MyAppVersion
  #define MyAppVersion "0.3.0"
#endif

#define MyAppName "MP3 by Glasi"
#define MyAppExeName "mp3_by_glasi.exe"

[Setup]
AppId={{E248A4A9-23C1-4D42-9C8D-CFAE1E9D5F2D}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=MP3 by Glasi
DefaultDirName={localappdata}\Programs\MP3 by Glasi
DefaultGroupName=MP3 by Glasi
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\..\dist
OutputBaseFilename=MP3-by-Glasi-Setup-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#MyAppExeName}

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\MP3 by Glasi"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\MP3 by Glasi"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Desktop-Verknüpfung erstellen"; GroupDescription: "Zusätzliche Verknüpfungen:"; Flags: unchecked

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "MP3 by Glasi starten"; Flags: nowait postinstall skipifsilent
