import AppKit
import SwiftUI

@main
struct AltMissionControlApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    MenuBarExtra {
      RuntimeMenu()
        .environmentObject(appDelegate.runtime)
    } label: {
      Image(systemName: "rectangle.3.group.fill")
    }
  }
}

private struct RuntimeMenu: View {
  @EnvironmentObject private var runtime: RuntimeController

  @ViewBuilder
  var body: some View {
    Label(
      runtime.isCapturing ? "Command + Tab 已接管" : "等待系统权限",
      systemImage: runtime.isCapturing ? "checkmark.circle.fill" : "exclamationmark.circle"
    )
    .disabled(true)

    if !runtime.accessibilityGranted {
      Button("授予辅助功能权限") {
        runtime.requestAccessibilityPermission()
      }
      Button("打开辅助功能设置") {
        runtime.openAccessibilitySettings()
      }
    }

    if !runtime.inputMonitoringGranted {
      Button("授予输入监控权限") {
        runtime.requestInputMonitoringPermission()
      }
      Button("打开输入监控设置") {
        runtime.openInputMonitoringSettings()
      }
    }

    if runtime.lastError != nil {
      Button("重新启用按键监听") {
        runtime.restartCapture()
      }
    }

    Divider()
    Button("退出 Alt Mission Control") {
      NSApplication.shared.terminate(nil)
    }
    .keyboardShortcut("q")
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let runtime = RuntimeController()

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApplication.shared.setActivationPolicy(.accessory)
    runtime.start()

    if !runtime.accessibilityGranted || !runtime.inputMonitoringGranted {
      runtime.requestAccessibilityPermission()
      runtime.requestInputMonitoringPermission()
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    runtime.stop()
  }
}
