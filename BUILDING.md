# 构建 Windows 安装器

## 依赖

- Windows 10/11 x64。
- [Inno Setup 6](https://jrsoftware.org/isdl.php)。
- Gyan.dev FFmpeg `2026-08-06-git-95c43d7df7-essentials_build` 中的 `ffmpeg.exe`。

FFmpeg 不提交到 Git 历史。把对应的 `ffmpeg.exe` 放到：

```text
installer\ffmpeg\ffmpeg.exe
```

预期 SHA-256：

```text
39F77E5E1D297B0C75653A93EBBBD3A718923BDA7CD621369F4F25154128E6C8
```

FFmpeg 构建来源、GPLv3 全文和确切源码提交见 `installer/licenses/`。

## 编译

在仓库根目录运行：

```powershell
& "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe" `
  ".\installer\AsepriteProcessRecorder-0.8.0.iss"
```

生成文件：

```text
installer\build\aseprite-process-recorder-0.8.0-windows-x64-cn-setup.exe
```

正式 v0.8.0 安装器 SHA-256：

```text
EAE5AB48D37365C0B2A9B5F1A38DF3EB813B49159CCD1F4E8D55B2BB76FAAE50
```

## 运行模式测试

根据本机 Aseprite 路径运行：

```powershell
& 'D:\steam\steamapps\common\Aseprite\Aseprite.exe' `
  -b --script '.\tests\test-recorder-modes.lua'
```

测试输出会写入仓库的 `test-output/`，该目录不会提交。

## 发布说明

Git 仓库保留 Lua 源码、安装脚本、预编译 helper 和许可文件。约 100MB 的 FFmpeg 不进入 Git 历史，只随 Windows 安装器 Release 附件分发。
