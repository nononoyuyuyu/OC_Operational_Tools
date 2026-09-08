; tool/build_windows_installer.ps1からバージョンと検証済み依存ファイルを受け取る。
[Setup]
AppId={{D4EBAB8B-0A55-489B-A9E1-BF65C0C96CD4}
AppName=Open Campus Organizer
AppMutex=Local\OpenCampusOrganizer
AppVersion={#AppVersion}
AppPublisher=nononoyuyuyu
AppPublisherURL=https://github.com/nononoyuyuyu/OC_Operational_Tools
AppSupportURL=https://github.com/nononoyuyuyu/OC_Operational_Tools/issues
AppUpdatesURL=https://github.com/nononoyuyuyu/OC_Operational_Tools/releases
VersionInfoVersion={#AppVersion}.{#AppBuildNumber}
DefaultDirName={autopf}\OpenCampusOrganizer
DisableDirPage=no
UsePreviousAppDir=yes
DefaultGroupName=Open Campus Organizer
DisableProgramGroupPage=no
AllowNoIcons=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=commandline
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.19041
OutputDir={#OutputDirectory}
#ifdef OcoTestDataRoot
OutputBaseFilename=OpenCampusOrganizer-userdata-test-setup
#else
OutputBaseFilename=OpenCampusOrganizer-{#AppVersion}-windows-x64-setup
#endif
SetupIconFile=..\..\windows\runner\resources\app_dark.ico
UninstallDisplayIcon={app}\open_campus_organizer.exe
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern dynamic
CloseApplications=yes
CloseApplicationsFilter=*.exe,*.dll
RestartApplications=no
Uninstallable=yes
UninstallLogMode=append

[Languages]
Name: "japanese"; MessagesFile: "compiler:Languages\Japanese.isl"

[Tasks]
Name: "desktopicon"; Description: "デスクトップにショートカットを作成する"; Flags: unchecked

[Files]
Source: "{#VcRedistPath}"; DestName: "vc_redist.x64.exe"; Flags: dontcopy noencryption
Source: "{#AppBuildDir}\*"; DestDir: "{app}"; Excludes: "*.pdb"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Open Campus Organizer"; Filename: "{app}\open_campus_organizer.exe"; AppUserModelID: "Nononoyuyuyu.OpenCampusOrganizer"
Name: "{autodesktop}\Open Campus Organizer"; Filename: "{app}\open_campus_organizer.exe"; AppUserModelID: "Nononoyuyuyu.OpenCampusOrganizer"; Tasks: desktopicon

[InstallDelete]
Type: files; Name: "{autoprograms}\Open Campus Organizer.lnk"; Check: IsLegacyStartMenuShortcut

[Run]
Filename: "{app}\open_campus_organizer.exe"; Description: "Open Campus Organizerを起動する"; Flags: nowait postinstall skipifsilent unchecked; Check: CanLaunchApplication

[Code]
#include "install_mode.iss"
#include "user_data.iss"
#include "prerequisites.iss"
