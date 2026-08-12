# Aseprite 绘画过程记录器 v0.8.0

这是首个公开 GitHub Release，提供 Windows 10/11 x64 单文件安装器。

## 本版重点

- 三种录制模式：完整 / 自动 / 性能。
- 自动模式下，小画布（≤65,536 像素）逐变化记录，避免快速像素画细节被固定限频大量合并。
- 中大型画布仅合并很短时间内连续到来的密集事件，降低整画布采集和差分写盘压力。
- 停止记录时始终补录最终画面。
- 磁盘图块差分日志，不生成 PNG/JPG 序列。
- 原生 helper 流式重建过程文件，并直接通过 RGBA 管道交给独立 FFmpeg。
- 安装器自动部署插件和 FFmpeg，用户无需另行下载或配置。

## 与常见插件的区别

常见实现会为每次变化保存 PNG、把完整帧长期留在 Lua 内存，或要求用户单独配置 FFmpeg。本项目组合了自适应三档采集、64×64 图块差分日志、分段续录、过程文件分卷和直接 MP4 流式导出。

详细、带参考链接的对照见仓库中的 `docs/COMPARISON.md`。

## 安装

1. 保存文件并完全退出 Aseprite。
2. 下载并运行 `aseprite-process-recorder-0.8.0-windows-x64-cn-setup.exe`。
3. 安装完成后重新启动 Aseprite。

## 校验值

```text
aseprite-process-recorder-0.8.0-windows-x64-cn-setup.exe
SHA-256: EAE5AB48D37365C0B2A9B5F1A38DF3EB813B49159CCD1F4E8D55B2BB76FAAE50
Size: 29,104,438 bytes

Aseprite.-Windows.-v0.8.0.md（GitHub 附件名限制；页面标签为“中文安装器使用指南”）
SHA-256: DDE95265C78B20E7511AF0BE21505D71CA82770CC40699199A91C0968834F15C

ffmpeg-95c43d7df7-source.zip
Full commit: 95c43d7df7b72e3a4e8dce8c6718cffedb32211d
SHA-256: 0087D7C3151A5C7C7D669DF23CEA086DD2AE441AC72E5B2345616F1148541655
Size: 23,952,983 bytes
```

安装器未签名，Windows SmartScreen 可能显示“未知发布者”。

## 许可

插件代码使用 MIT License。安装器中的 FFmpeg 为独立 GPLv3 第三方程序；本 Release 同时附带对应 FFmpeg 提交的完整源码快照。Gyan.dev 构建来源和确切配置见仓库 `installer/licenses/`。
