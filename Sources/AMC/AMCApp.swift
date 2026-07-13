import AppKit
import SwiftUI

@main
struct AMCApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    Window("Alt Mission Control", id: "main") {
      MainWindow()
        .environmentObject(appDelegate.runtime)
        .background(MainWindowInstaller())
    }
    .defaultSize(width: 560, height: 500)
    .windowResizability(.contentSize)
  }
}

private struct MainWindow: View {
  @EnvironmentObject private var runtime: RuntimeController

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      HStack(spacing: 16) {
        Image(systemName: "rectangle.3.group.fill")
          .font(.system(size: 34, weight: .semibold))
          .foregroundStyle(.tint)
          .frame(width: 58, height: 58)
          .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))

        VStack(alignment: .leading, spacing: 4) {
          Text("Alt Mission Control")
            .font(.title2.weight(.semibold))
          Text("使用 Command + Tab 在 Mission Control 中逐窗口切换")
            .foregroundStyle(.secondary)
        }
      }

      GroupBox {
        VStack(alignment: .leading, spacing: 14) {
          Label {
            VStack(alignment: .leading, spacing: 2) {
              Text(statusTitle)
                .fontWeight(.medium)
              Text(statusDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          } icon: {
            Image(systemName: statusIcon)
              .foregroundStyle(statusColor)
          }

          Divider()

          PermissionRow(
            title: "辅助功能",
            isGranted: runtime.accessibilityGranted,
            requestPermission: runtime.requestAccessibilityPermission,
            openSettings: runtime.openAccessibilitySettings
          )

          PermissionRow(
            title: "输入监控",
            isGranted: runtime.inputMonitoringGranted,
            requestPermission: runtime.requestInputMonitoringPermission,
            openSettings: runtime.openInputMonitoringSettings
          )

          if let lastError = runtime.lastError {
            Divider()
            HStack(alignment: .firstTextBaseline, spacing: 10) {
              Text(lastError)
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
              Spacer(minLength: 8)
              Button("重新启用") {
                runtime.restartCapture()
              }
            }
          }
        }
        .padding(6)
      } label: {
        Text("运行状态")
          .font(.headline)
      }

      GroupBox {
        VStack(alignment: .leading, spacing: 10) {
          Toggle(
            "登录时自动启动",
            isOn: Binding(
              get: { runtime.isLaunchAtLoginEnabled },
              set: { runtime.setLaunchAtLoginEnabled($0) }
            )
          )
          .toggleStyle(.switch)

          if runtime.launchAtLoginNeedsApproval {
            HStack(alignment: .firstTextBaseline) {
              Text("需要在系统设置的“登录项”中允许本程序在后台运行。")
                .font(.caption)
                .foregroundStyle(.secondary)
              Spacer()
              Button("打开系统设置") {
                runtime.openLoginItemsSettings()
              }
            }
          }

          if let error = runtime.launchAtLoginError {
            Text(error)
              .font(.caption)
              .foregroundStyle(.red)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .padding(6)
      } label: {
        Text("通用")
          .font(.headline)
      }

      HStack {
        Text("关闭此窗口后，程序仍会在后台运行。点击 Dock 图标可重新打开。")
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer(minLength: 16)
        Button("退出程序", role: .destructive) {
          NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
      }
    }
    .padding(24)
    .frame(width: 560)
  }

  private var statusTitle: String {
    if runtime.isCapturing {
      return "正在后台运行"
    }
    return "等待系统权限"
  }

  private var statusDetail: String {
    if runtime.isCapturing {
      return "Command + Tab 已接管"
    }
    return "完成下方授权后会自动启用按键监听"
  }

  private var statusIcon: String {
    runtime.isCapturing ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
  }

  private var statusColor: Color {
    runtime.isCapturing ? .green : .orange
  }
}

private struct PermissionRow: View {
  let title: String
  let isGranted: Bool
  let requestPermission: () -> Void
  let openSettings: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: isGranted ? "checkmark.circle.fill" : "circle")
        .foregroundStyle(isGranted ? .green : .secondary)
      Text(title)
      Spacer()

      if isGranted {
        Text("已授权")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        Button("请求授权", action: requestPermission)
        Button("打开系统设置", action: openSettings)
      }
    }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  let runtime = RuntimeController()
  private weak var mainWindow: NSWindow?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApplication.shared.setActivationPolicy(.regular)
    runtime.start()

    if !runtime.accessibilityGranted || !runtime.inputMonitoringGranted {
      runtime.requestAccessibilityPermission()
      runtime.requestInputMonitoringPermission()
    }

    DispatchQueue.main.async { [weak self] in
      self?.showMainWindow()
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    showMainWindow()
    return true
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    sender.orderOut(nil)
    return false
  }

  func applicationWillTerminate(_ notification: Notification) {
    runtime.stop()
  }

  func installMainWindow(_ window: NSWindow) {
    mainWindow = window
    window.delegate = self
    window.identifier = NSUserInterfaceItemIdentifier("AMCMainWindow")
    window.isReleasedWhenClosed = false
  }

  private func showMainWindow() {
    guard let mainWindow else { return }
    NSApplication.shared.activate(ignoringOtherApps: true)
    mainWindow.makeKeyAndOrderFront(nil)
  }
}

private struct MainWindowInstaller: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView {
    MainWindowReferenceView()
  }

  func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class MainWindowReferenceView: NSView {
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    guard let window else { return }

    Task { @MainActor in
      (NSApplication.shared.delegate as? AppDelegate)?.installMainWindow(window)
    }
  }
}
