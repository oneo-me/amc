# Alt Mission Control

一个使用 Swift、SwiftUI 和标准 Swift Package 构建的 macOS 菜单栏程序。它接管
`Command + Tab`，借助系统 Mission Control 实现接近 Windows `Alt + Tab` 的逐窗口切换体验。

## 行为

- 按下 `Command + Tab`：打开 Mission Control，并在动画完成后自动选择下一个窗口。
- 按住 `Command` 连续按 `Tab`：继续移动选择。
- 松开 `Command`：按 Return 确认当前窗口并退出 Mission Control。
- `Command + Shift + Tab`：反向移动选择。
- 原始 `Command + Tab` 事件会被拦截，因此不会同时出现 macOS 原生应用切换器。

## 构建与运行

要求 macOS 13 或更新版本，以及 Xcode 15 或更新版本。

```sh
swift test
chmod +x Scripts/build-app.sh
Scripts/build-app.sh
open .build/AltMissionControl.app
```

也可以在开发期间直接执行 `swift run AltMissionControl`，但建议使用 `.app` 包运行：
macOS 的隐私授权会绑定到应用身份，临时 SwiftPM 可执行文件在重新构建后可能需要重新授权。

首次运行时需要在“系统设置 → 隐私与安全性”中授予：

1. **辅助功能**：发送 Mission Control 导航事件，并拦截原始快捷键。
2. **输入监控**：接收全局键盘事件。

修改权限后如果状态没有自动刷新，可从菜单栏打开“设置”，点击“重新启用监听”，或重启程序。

## 调整手感

默认用左右方向键在 Mission Control 中移动选中窗口，并等待 220ms 再进行首次移动。
不同系统版本、显示器数量和“减弱动态效果”设置会影响动画时间，可在设置中调整：

- 首次移动太早或没有选中窗口：增加“进入等待”。
- 左右方向键不能移动选择：把“导航按键”改为 `Tab / Shift-Tab`；此模式通常按应用组切换。

## 系统边界

macOS 没有公开的 Mission Control 窗口选择 API。本程序只使用公开的事件监听、事件发送和
`NSWorkspace` API，窗口布局、选择顺序以及 Mission Control 内的键盘导航行为仍由当前 macOS
版本决定。若系统无法启动 Mission Control，程序会回退发送系统默认的 `Control + Up Arrow`。
