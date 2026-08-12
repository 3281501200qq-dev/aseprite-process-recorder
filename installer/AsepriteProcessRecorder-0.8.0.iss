#define AppName "Aseprite 绘画过程记录器"
#define AppVersion "0.8.0"
#define AppPublisher "Aseprite Process Recorder Contributors"
#define AppId "AsepriteProcessRecorder"

#ifdef ValidationBuild
#define InstallRoot "{src}\validation-install\app"
#define PluginRoot "{src}\validation-install\plugin"
#define SetupFilename "aseprite-process-recorder-0.8.0-validation-setup"
#else
#define InstallRoot "{localappdata}\Programs\Aseprite Process Recorder"
#define PluginRoot "{userappdata}\Aseprite\extensions\aseprite-process-recorder"
#define SetupFilename "aseprite-process-recorder-0.8.0-windows-x64-cn-setup"
#endif

[Setup]
#ifdef ValidationBuild
AppId={{B1083B88-0631-4AB7-8342-4409BE5F87E4}
#else
AppId={{6D7FD86F-BCE9-4D13-A9B8-4D50E1B59075}
#endif
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={#InstallRoot}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=build
OutputBaseFilename={#SetupFilename}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
UninstallDisplayName={#AppName} {#AppVersion}
UninstallDisplayIcon={app}\FFmpeg\ffmpeg.exe
LicenseFile=licenses\GPL-3.0.txt
InfoBeforeFile=README-安装说明.txt
VersionInfoVersion=0.8.0.0
VersionInfoCompany={#AppPublisher}
VersionInfoDescription={#AppName} Windows 安装程序
VersionInfoProductName={#AppName}
VersionInfoProductVersion={#AppVersion}
VersionInfoCopyright=MIT plug-in; FFmpeg GPLv3
CloseApplications=yes
RestartApplications=no
ChangesEnvironment=no
#ifdef ValidationBuild
UsePreviousAppDir=no
CreateUninstallRegKey=no
#endif

[Languages]
Name: "chinesesimplified"; MessagesFile: "inno-setup-source\Files\Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Types]
Name: "full"; Description: "完整安装（推荐）"; Flags: iscustom

[Components]
Name: "plugin"; Description: "Aseprite 绘画过程记录器插件"; Types: full; Flags: fixed
Name: "ffmpeg"; Description: "FFmpeg 2026-08-06 essentials build + libx264 视频编码器"; Types: full; Flags: fixed

[Files]
Source: "..\plugin\*"; DestDir: "{#PluginRoot}"; Flags: ignoreversion recursesubdirs createallsubdirs; Components: plugin
Source: "ffmpeg\ffmpeg.exe"; DestDir: "{app}\FFmpeg"; Flags: ignoreversion; Components: ffmpeg
Source: "licenses\GPL-3.0.txt"; DestDir: "{app}\Licenses\FFmpeg"; DestName: "GPL-3.0.txt"; Flags: ignoreversion; Components: ffmpeg
Source: "licenses\FFMPEG-BUILD-README.txt"; DestDir: "{app}\Licenses\FFmpeg"; DestName: "BUILD-README.txt"; Flags: ignoreversion; Components: ffmpeg
Source: "licenses\THIRD-PARTY-NOTICES.txt"; DestDir: "{app}\Licenses"; Flags: ignoreversion; Components: ffmpeg
Source: "README-安装说明.txt"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\安装说明"; Filename: "{app}\README-安装说明.txt"
Name: "{group}\第三方许可说明"; Filename: "{app}\Licenses\THIRD-PARTY-NOTICES.txt"
Name: "{group}\卸载 {#AppName}"; Filename: "{uninstallexe}"

[InstallDelete]
Type: filesandordirs; Name: "{#PluginRoot}\docs"
Type: filesandordirs; Name: "{#PluginRoot}\native\bin"
Type: filesandordirs; Name: "{#PluginRoot}\native\src"
Type: filesandordirs; Name: "{#PluginRoot}\third_party\ffmpeg"
Type: filesandordirs; Name: "{app}\FFmpeg"
Type: filesandordirs; Name: "{app}\Licenses"

[UninstallDelete]
Type: files; Name: "{#PluginRoot}\journal.lua"
Type: files; Name: "{#PluginRoot}\LICENSE.txt"
Type: files; Name: "{#PluginRoot}\main.lua"
Type: files; Name: "{#PluginRoot}\package.json"
Type: files; Name: "{#PluginRoot}\recorder.lua"
Type: files; Name: "{#PluginRoot}\__info.json"
Type: filesandordirs; Name: "{#PluginRoot}\docs"
Type: filesandordirs; Name: "{#PluginRoot}\native"
Type: filesandordirs; Name: "{#PluginRoot}\third_party"
Type: dirifempty; Name: "{#PluginRoot}"
Type: filesandordirs; Name: "{app}\FFmpeg"
Type: filesandordirs; Name: "{app}\Licenses"
Type: files; Name: "{app}\README-安装说明.txt"

[Code]
function IsAsepriteRunning: Boolean;
var
  ResultCode: Integer;
begin
  Result := Exec(
    ExpandConstant('{cmd}'),
    '/C tasklist /FI "IMAGENAME eq Aseprite.exe" /NH | find /I "Aseprite.exe" >nul',
    '',
    SW_HIDE,
    ewWaitUntilTerminated,
    ResultCode) and (ResultCode = 0);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
#ifndef ValidationBuild
  if IsAsepriteRunning then
    Result := '检测到 Aseprite 正在运行。请完全退出 Aseprite 后，再点击“重试”。';
#endif
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    Log('Plug-in installed to ' + ExpandConstant('{#PluginRoot}'));
    Log('FFmpeg installed to ' + ExpandConstant('{app}\FFmpeg\ffmpeg.exe'));
  end;
end;
