# 与其他 Aseprite 延时录制插件的架构对照

以下内容基于 2026-08-12 对公开仓库的检查。其他项目可能在此后更新；本对照只描述公开代码和 README 中可核实的默认实现，不评价作者或项目质量。

## 核心定位

本项目优先解决两个彼此冲突的问题：

1. 小画布快速像素画需要尽量保留每个中间状态。
2. 大画布、长时间记录不能在每个密集事件上都执行整画布合成和完整帧写盘。

因此本项目把“何时进行昂贵的整画布采集”和“采集后如何保存帧”分开处理：前者由三种模式控制，后者使用磁盘图块差分日志。

## 项目对照

| 项目 | 公开实现中的主要方式 | 与本项目的主要区别 |
| --- | --- | --- |
| [luciopaiva/aseprite-timelapse](https://github.com/luciopaiva/aseprite-timelapse) | 每次变化保存一个 PNG，undo/redo 也记录；视频需后续工具处理 | 本项目不生成图片序列，按图块写差分日志，并能直接流式导出 MP4 |
| [zarstensen/aselapse](https://github.com/zarstensen/aselapse) | 变化时复制完整 `Image` 到 Lua 列表，之后生成并保存 lapse sprite | 本项目不把全部完整帧长期留在 Lua 内存中，使用可续录的磁盘分段日志 |
| [CertifiedHabibi/Automated-Timelapse-for-Aseprite](https://github.com/CertifiedHabibi/Automated-Timelapse-for-Aseprite) | 将记录帧存入另一个 `.aseprite` 文件 | 本项目录制期间先写紧凑差分日志，停止时由 helper 流式重建过程文件，并支持分卷 |
| [SalvaPixel/aseprite-timelapse](https://github.com/SalvaPixel/aseprite-timelapse) | Aseprite 内生成 GIF；MP4 可选且要求 FFmpeg 位于 PATH | 本项目的 Windows 安装器自动部署独立 FFmpeg，并从差分日志直接输出 H.264 MP4 |

## 本项目特有的组合

### 1. 三档、自适应采集

- 自动模式对 ≤65,536 像素画布逐变化记录。
- 中大型画布仅合并很短时间内连续到来的密集事件。
- 性能模式提供更积极的合并窗口。
- 完整模式保留逐变化行为，供用户明确选择最高细节。

这与固定“每 N 次变化保留一帧”不同：如果事件之间有足够间隔，自动模式仍会分别采集。

### 2. 图块差分日志

- 画面按 64×64 图块比较。
- 只写变化图块。
- 每个图块在像素 RLE 和原始 RGBA 之间选择更小者。
- 定期写检查点，避免回放必须从无限久以前开始。
- 使用分段清单支持续录和恢复。

### 3. 录制与视频编码解耦

录制阶段不运行 FFmpeg。停止或导出时，原生 helper 才会读取差分日志：

```text
Aseprite 变化事件
  → 自适应采集
  → 图块差分日志
  → 原生 helper 逐帧重建
  → Aseprite 过程文件 / RGBA 管道
  → 独立 FFmpeg + libx264 MP4
```

因此“安装器是否包含 FFmpeg”不会改变绘画时的编码负载；它主要改变安装体验和导出阶段。

### 4. 面向长记录的边界

- 可配置 Lua 写入内存预算。
- 原生重建支持最大帧数和最大文件体积分卷。
- 不需要打开超大的 `_timelapse.aseprite` 才能导出视频。
- 保存真实时间戳，可调整播放速度而不是只能固定 FPS 抽帧。

## 不应被理解为

- 不代表本项目在所有画布、电脑和绘画习惯下都更快。
- 自动/性能模式可能合并持续时间极短的中间状态。
- 完整模式在大画布上仍会承担逐变化整画布合成成本。
- Windows helper 当前以预编译二进制发布，尚未在本仓库提供其源码。
