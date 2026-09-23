; Inno Setup 单文件安装包配置 - 将 Flutter Windows Release 打成一个 Setup.exe
; 在 Windows 上执行: iscc windows/installer.iss
#define MyAppName "QuizBank"
#define MyAppVersion "1.2.2"
#define MyAppPublisher "QuizBank"
#define MyAppExeName "quiz_bank.exe"

[Setup]
AppId={{3B2F9A1A-QuizBank-Windows-SingleExe}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
OutputDir=..\build\windows-installer
OutputBaseFilename=QuizBank-Setup-{#MyAppVersion}-x64
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=lowest
SetupIconFile=runner\resources\app_icon.ico

[Languages]
Name: "chinese"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Flutter 打包产物 - Release 文件夹下全部文件
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
