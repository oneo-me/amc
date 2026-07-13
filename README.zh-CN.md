# Alt Mission Control

[English](README.md) | [简体中文](README.zh-CN.md)

Alt Mission Control（AMC）是一款原生 macOS 工具，它使用基于“调度中心”的窗口切换方式替代系统默认的 Command-Tab 应用切换器。按住 `Command` 并按 `Tab` 可在窗口间切换，同时按住 `Shift` 可反向切换。

AMC 支持登录时自动启动、英文与简体中文界面，并会在获得必要的系统权限后自动恢复运行。

### 系统要求

- macOS 13.0 或更高版本
- “辅助功能”和“输入监控”权限

## 使用方法

1. 从仓库的 Releases 页面下载最新的 DMG。
2. 打开 DMG，将 `AMC.app` 拖入“应用程序”文件夹。
3. 启动 AMC，并按提示授予“辅助功能”和“输入监控”权限。也可以前往 **系统设置 > 隐私与安全性** 手动启用这些权限。
4. 按住 `Command` 并按 `Tab` 切换窗口；同时按住 `Shift` 可反向切换。

关闭主窗口后，AMC 仍会在后台运行。若要停止程序，请点击应用内的“彻底退出”。你也可以在应用中启用“登录时自动启动”。

## 授权

Alt Mission Control 基于 [MIT License](LICENSE) 授权。
