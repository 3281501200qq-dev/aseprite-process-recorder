#define AppName "Aseprite Process Recorder"
#define AppVersion "0.8.3"
#define AppPublisher "Aseprite Process Recorder Contributors"
#define AppId "AsepriteProcessRecorder"

#ifdef ValidationBuild
#define InstallRoot "{src}\validation-install\app"
#define PluginRoot "{src}\validation-install\plugin"
#define SetupFilename "aseprite-process-recorder-0.8.3-validation-setup"
#else
#define InstallRoot "{localappdata}\Programs\Aseprite Process Recorder"
#define PluginRoot "{userappdata}\Aseprite\extensions\aseprite-process-recorder"
#define SetupFilename "aseprite-process-recorder-0.8.3-windows-x64-multilingual-setup"
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
VersionInfoVersion=0.8.3.0
VersionInfoCompany={#AppPublisher}
VersionInfoDescription={#AppName} Windows Setup
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
Name: "chinesesimplified"; MessagesFile: "inno-setup-source\Files\Languages\ChineseSimplified.isl"; InfoBeforeFile: "README-安装说明.txt"
Name: "english"; MessagesFile: "compiler:Default.isl"; InfoBeforeFile: "README-Install.en.txt"
Name: "japanese"; MessagesFile: "compiler:Languages\Japanese.isl"; InfoBeforeFile: "README-Install.ja.txt"

[CustomMessages]
chinesesimplified.FullInstall=完整安装（推荐）
english.FullInstall=Complete installation (recommended)
japanese.FullInstall=すべてインストール（推奨）
chinesesimplified.PluginComponent=Aseprite 绘画过程记录器插件
english.PluginComponent=Aseprite Process Recorder extension
japanese.PluginComponent=Aseprite 制作過程レコーダー拡張機能
chinesesimplified.FfmpegComponent=FFmpeg 2026-08-06 essentials build + libx264 视频编码器
english.FfmpegComponent=FFmpeg 2026-08-06 essentials build + libx264 video encoder
japanese.FfmpegComponent=FFmpeg 2026-08-06 essentials build + libx264 動画エンコーダー
chinesesimplified.InstallGuide=安装说明
english.InstallGuide=Installation Guide
japanese.InstallGuide=インストールガイド
chinesesimplified.ThirdPartyLicenses=第三方许可说明
english.ThirdPartyLicenses=Third-party Licenses
japanese.ThirdPartyLicenses=サードパーティーのライセンス
chinesesimplified.UninstallRecorder=卸载 Aseprite Process Recorder
english.UninstallRecorder=Uninstall Aseprite Process Recorder
japanese.UninstallRecorder=Aseprite Process Recorder をアンインストール
chinesesimplified.CloseAseprite=检测到 Aseprite 正在运行。请完全退出 Aseprite 后，再点击“重试”。
english.CloseAseprite=Aseprite is running. Close it completely, then click Retry.
japanese.CloseAseprite=Aseprite が実行中です。完全に終了してから「再試行」をクリックしてください。

[Types]
Name: "full"; Description: "{cm:FullInstall}"; Flags: iscustom

[Components]
Name: "plugin"; Description: "{cm:PluginComponent}"; Types: full; Flags: fixed
Name: "ffmpeg"; Description: "{cm:FfmpegComponent}"; Types: full; Flags: fixed

[Files]
Source: "..\plugin\*"; DestDir: "{#PluginRoot}"; Flags: ignoreversion recursesubdirs createallsubdirs; Components: plugin
Source: "ffmpeg\ffmpeg.exe"; DestDir: "{app}\FFmpeg"; Flags: ignoreversion; Components: ffmpeg
Source: "licenses\GPL-3.0.txt"; DestDir: "{app}\Licenses\FFmpeg"; DestName: "GPL-3.0.txt"; Flags: ignoreversion; Components: ffmpeg
Source: "licenses\FFMPEG-BUILD-README.txt"; DestDir: "{app}\Licenses\FFmpeg"; DestName: "BUILD-README.txt"; Flags: ignoreversion; Components: ffmpeg
Source: "licenses\THIRD-PARTY-NOTICES.txt"; DestDir: "{app}\Licenses"; Flags: ignoreversion; Components: ffmpeg
Source: "README-安装说明.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "README-Install.en.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "README-Install.ja.txt"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{cm:InstallGuide}"; Filename: "{app}\README-安装说明.txt"; Languages: chinesesimplified
Name: "{group}\{cm:InstallGuide}"; Filename: "{app}\README-Install.en.txt"; Languages: english
Name: "{group}\{cm:InstallGuide}"; Filename: "{app}\README-Install.ja.txt"; Languages: japanese
Name: "{group}\{cm:ThirdPartyLicenses}"; Filename: "{app}\Licenses\THIRD-PARTY-NOTICES.txt"
Name: "{group}\{cm:UninstallRecorder}"; Filename: "{uninstallexe}"

[InstallDelete]
Type: filesandordirs; Name: "{#PluginRoot}\docs"
Type: filesandordirs; Name: "{#PluginRoot}\native\bin"
Type: filesandordirs; Name: "{#PluginRoot}\native\src"
Type: filesandordirs; Name: "{#PluginRoot}\third_party\ffmpeg"
Type: filesandordirs; Name: "{app}\FFmpeg"
Type: filesandordirs; Name: "{app}\Licenses"

[UninstallDelete]
Type: files; Name: "{#PluginRoot}\journal.lua"
Type: files; Name: "{#PluginRoot}\i18n.lua"
Type: files; Name: "{#PluginRoot}\background-export.ps1"
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
Type: files; Name: "{app}\README-Install.en.txt"
Type: files; Name: "{app}\README-Install.ja.txt"

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
    Result := CustomMessage('CloseAseprite');
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
