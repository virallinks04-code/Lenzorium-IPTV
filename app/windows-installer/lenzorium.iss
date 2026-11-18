; Inno Setup script — builds Lenzorium-Player-Setup.exe from the Flutter Release folder.
#define AppVersion GetEnv("APP_VERSION")
#if AppVersion == ""
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{6B5BFF10-4C7A-4E1B-9A3D-1E2A7C3B5D01}
AppName=Lenzorium Player
AppVersion={#AppVersion}
AppPublisher=Lenzorium Technologies
DefaultDirName={autopf}\Lenzorium Player
DefaultGroupName=Lenzorium Player
DisableProgramGroupPage=yes
OutputDir=..\..\out
OutputBaseFilename=Lenzorium-Player-Setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\lenzorium_player.exe
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
PrivilegesRequiredOverridesAllowed=dialog

[Tasks]
Name: "desktopicon"; Description: "Create a desktop icon"; GroupDescription: "Additional icons:"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Lenzorium Player"; Filename: "{app}\lenzorium_player.exe"
Name: "{group}\Uninstall Lenzorium Player"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Lenzorium Player"; Filename: "{app}\lenzorium_player.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\lenzorium_player.exe"; Description: "Start Lenzorium Player"; Flags: nowait postinstall skipifsilent
