Aseprite 绘画过程记录器 v0.8.0
================================

本版本采用单个 Windows 安装程序，内部包含两个独立组件：

1. Aseprite 插件
   安装到：%APPDATA%\Aseprite\extensions\aseprite-process-recorder

2. FFmpeg 2026-08-06 essentials build（libx264）
   安装到：%LOCALAPPDATA%\Programs\Aseprite Process Recorder\FFmpeg

安装前请完全退出 Aseprite。安装完成后启动 Aseprite，即可自动记录并直接导出 MP4，
不需要另外下载 FFmpeg，也不需要手动选择 ffmpeg.exe。

本版新增三种记录模式：
- 自动模式（新安装默认）：总像素不超过 65,536（相当于 256×256）的小画布逐变化记录；中大型画布
  仅合并很短时间内连续到来的密集事件。
- 完整模式：每次有效画面变化都记录，细节最多，记录压力最高。
- 性能模式：更积极地合并密集事件，适合大画布和长时间记录。

自动和性能模式停止时都会补录最终画面。性能模式可能省略持续时间极短的中间状态。

升级策略：
- 覆盖同名插件和本安装器部署的 FFmpeg。
- 保留 Aseprite 插件偏好，包括模式、速度、内存预算和视频放大设置。
- 旧“每次变化”模式迁移为完整模式；旧“间隔记录”模式迁移为性能模式。
- 保留“文档\Aseprite Process Recordings”中的全部记录和导出文件。
- 如果插件偏好中已经保存了其他有效 FFmpeg 路径，插件仍优先使用该路径。

卸载策略：
- 删除本安装器部署的插件和 FFmpeg。
- 不删除绘画过程记录、视频、原图和 Aseprite 的其他设置。
- 如 Aseprite 已生成插件偏好文件，卸载后会保留该偏好文件，便于以后重新安装。

FFmpeg 是独立的 GPLv3 第三方程序。许可证、构建说明和确切源码版本链接会随程序安装。
