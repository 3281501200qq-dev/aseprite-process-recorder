# Aseprite 绘画过程记录器 v0.8.2

## 下载

- `aseprite-process-recorder-0.8.2-windows-x64-cn-setup.exe`：推荐。单个安装程序会自动安装插件和独立 FFmpeg，用户不需要另行下载或配置 FFmpeg。
- `aseprite-process-recorder-0.8.2-windows-x64-cn.aseprite-extension`：仅插件本体，供手动安装或已有 FFmpeg 环境的用户使用，不包含 FFmpeg。

## 新增

- 在“绘画过程记录器”菜单中增加“打开画布时自动开始记录”勾选按钮。
- 设置会永久保存到插件偏好，重启 Aseprite 后仍然有效。
- 设置窗口同步提供“打开或切换画布时自动开始记录”选项。

## 行为

- 默认开启，升级后保持原有自动记录行为。
- 关闭后不会因打开、切换画布或重启 Aseprite 自动开始记录。
- 手动点击“开始记录”仍可正常使用。
- 关闭开关不会强制停止当前记录；再次开启时，如果当前画布没有记录，会立即开始自动记录。

本版本同时保留 v0.8.1 的 Windows 后台导出和卡顿修复。完整模式、自动模式和性能模式的采样规则不变。

## SHA-256

```text
8F87715027EEB137F940468876D242BCD46F77C98609A2A19CD3F2E24087BF68  aseprite-process-recorder-0.8.2-windows-x64-cn-setup.exe
08BD599FC8A4B331386B0EBB787994A6D486A31D08324851951777F744D4F86F  aseprite-process-recorder-0.8.2-windows-x64-cn.aseprite-extension
```
