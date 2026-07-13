# Alt Mission Control

[English](README.md) | [简体中文](README.zh-CN.md)

Alt Mission Control (AMC) is a native macOS utility that replaces the standard Command-Tab application switcher with a Mission Control-based window switcher. Hold `Command` and press `Tab` to move between windows, or add `Shift` to move in reverse.

AMC can launch at login, supports English and Simplified Chinese, and automatically resumes after the required system permissions are granted.

### Requirements

- macOS 13.0 or later
- Accessibility and Input Monitoring permissions

## Usage

1. Download the latest DMG from the repository's Releases page.
2. Open the DMG and drag `AMC.app` into `Applications`.
3. Launch AMC and grant Accessibility and Input Monitoring access when prompted. You can also enable these permissions under **System Settings > Privacy & Security**.
4. Hold `Command` and press `Tab` to switch windows. Hold `Shift` as well to switch in reverse.

Closing the main window leaves AMC running in the background. Use **Quit Completely** in the app to stop it. The app can also be configured to launch at login.

## License

Alt Mission Control is available under the [MIT License](LICENSE).
