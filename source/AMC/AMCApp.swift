import AppKit
import SwiftUI

@main
struct AMCApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    Window(L10n.string("app.full_name"), id: "main") {
      MainWindow()
        .environmentObject(appDelegate.runtime)
        .environmentObject(appDelegate.localization)
    }
    .defaultSize(width: 500, height: 340)
    .windowResizability(.contentSize)
  }
}

private struct MainWindow: View {
  @EnvironmentObject private var runtime: RuntimeController
  @EnvironmentObject private var localization: LocalizationController

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      settingsBar
      statusPanel

      HStack {
        Text(localization.string("window.background_hint"))
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer(minLength: 16)
        Button(localization.string("app.quit_completely"), role: .destructive) {
          NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
      }
    }
    .padding(20)
    .frame(width: 500)
    .background(
      MainWindowInstaller(title: localization.string("app.full_name"))
    )
  }

  private var settingsBar: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 20) {
        HStack(spacing: 8) {
          Text(localization.string("language.label"))
            .foregroundStyle(.secondary)

          Picker("", selection: $localization.language) {
            ForEach(AppLanguage.allCases) { language in
              Text(localization.title(for: language))
                .tag(language)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .frame(width: 124)
          .accessibilityLabel(localization.string("language.label"))
        }

        Spacer(minLength: 8)

        Toggle(
          localization.string("login.launch_at_login"),
          isOn: Binding(
            get: { runtime.isLaunchAtLoginEnabled },
            set: { runtime.setLaunchAtLoginEnabled($0) }
          )
        )
        .toggleStyle(.switch)
      }

      if runtime.launchAtLoginNeedsApproval {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
          Text(localization.string("login.needs_approval"))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 8)
          Button(localization.string("action.open_settings_short")) {
            runtime.openLoginItemsSettings()
          }
          .controlSize(.small)
        }
      }

      if let errorDescription = runtime.launchAtLoginErrorDescription {
        Text(localization.string("error.launch_at_login", errorDescription))
          .font(.caption)
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var statusPanel: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 12) {
        Image(systemName: statusIcon)
          .font(.system(size: 20, weight: .semibold))
          .foregroundStyle(statusColor)
          .frame(width: 38, height: 38)
          .background(statusColor.opacity(0.13), in: Circle())

        VStack(alignment: .leading, spacing: 2) {
          Text(statusTitle)
            .font(.title3.weight(.semibold))
          Text(statusDetail)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      Divider()

      HStack(spacing: 12) {
        Text("⌘ Tab")
          .font(.system(.callout, design: .rounded).weight(.semibold))
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

        VStack(alignment: .leading, spacing: 2) {
          Text(localization.string("instruction.primary"))
            .fontWeight(.medium)
          Text(localization.string("instruction.reverse"))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      if !hasAllPermissions {
        Divider()

        VStack(spacing: 10) {
          PermissionRow(
            title: localization.string("permission.accessibility"),
            isGranted: runtime.accessibilityGranted,
            openSettings: runtime.openAccessibilitySettings
          )

          PermissionRow(
            title: localization.string("permission.input_monitoring"),
            isGranted: runtime.inputMonitoringGranted,
            openSettings: runtime.openInputMonitoringSettings
          )
        }
      }

      if hasAllPermissions,
        !runtime.isCapturing,
        let lastErrorKey = runtime.lastErrorKey
      {
        Text(localization.string(lastErrorKey))
          .font(.caption)
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(16)
    .background(
      Color(nsColor: .controlBackgroundColor),
      in: RoundedRectangle(cornerRadius: 12)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
    }
  }

  private var hasAllPermissions: Bool {
    runtime.accessibilityGranted && runtime.inputMonitoringGranted
  }

  private var statusTitle: String {
    if runtime.isCapturing {
      return localization.string("status.running")
    }
    if hasAllPermissions {
      return localization.string("status.enabling")
    }
    return localization.string("status.waiting_for_permissions")
  }

  private var statusDetail: String {
    if runtime.isCapturing {
      return localization.string("status.command_tab_active")
    }
    if hasAllPermissions {
      return localization.string("status.enabling_hint")
    }
    return localization.string("status.permission_hint")
  }

  private var statusIcon: String {
    runtime.isCapturing ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
  }

  private var statusColor: Color {
    runtime.isCapturing ? .green : .orange
  }
}

private struct PermissionRow: View {
  @EnvironmentObject private var localization: LocalizationController

  let title: String
  let isGranted: Bool
  let openSettings: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: isGranted ? "checkmark.circle.fill" : "circle")
        .foregroundStyle(isGranted ? .green : .secondary)
      Text(title)
      Spacer()

      if isGranted {
        Text(localization.string("permission.granted"))
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        Button(
          localization.string("action.open_settings_short"),
          action: openSettings
        )
        .controlSize(.small)
      }
    }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  let runtime = RuntimeController()
  let localization = LocalizationController()
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
    NSApplication.shared.setActivationPolicy(.accessory)
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
    NSApplication.shared.setActivationPolicy(.regular)
    NSApplication.shared.activate(ignoringOtherApps: true)
    mainWindow.makeKeyAndOrderFront(nil)
  }
}

private struct MainWindowInstaller: NSViewRepresentable {
  let title: String

  func makeNSView(context: Context) -> NSView {
    let view = MainWindowReferenceView()
    view.title = title
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    guard let referenceView = nsView as? MainWindowReferenceView else { return }
    referenceView.title = title
    referenceView.window?.title = title
  }
}

private final class MainWindowReferenceView: NSView {
  var title = ""

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    guard let window else { return }

    Task { @MainActor in
      window.title = title
      (NSApplication.shared.delegate as? AppDelegate)?.installMainWindow(window)
    }
  }
}
