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
    .defaultSize(width: 560, height: 500)
    .windowResizability(.contentSize)
  }
}

private struct MainWindow: View {
  @EnvironmentObject private var runtime: RuntimeController
  @EnvironmentObject private var localization: LocalizationController

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      HStack(spacing: 16) {
        Image(systemName: "rectangle.3.group.fill")
          .font(.system(size: 34, weight: .semibold))
          .foregroundStyle(.tint)
          .frame(width: 58, height: 58)
          .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))

        VStack(alignment: .leading, spacing: 4) {
          Text(localization.string("app.full_name"))
            .font(.title2.weight(.semibold))
          Text(localization.string("app.subtitle"))
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
            title: localization.string("permission.accessibility"),
            isGranted: runtime.accessibilityGranted,
            requestPermission: runtime.requestAccessibilityPermission,
            openSettings: runtime.openAccessibilitySettings
          )

          PermissionRow(
            title: localization.string("permission.input_monitoring"),
            isGranted: runtime.inputMonitoringGranted,
            requestPermission: runtime.requestInputMonitoringPermission,
            openSettings: runtime.openInputMonitoringSettings
          )

          if let lastErrorKey = runtime.lastErrorKey {
            Divider()
            HStack(alignment: .firstTextBaseline, spacing: 10) {
              Text(localization.string(lastErrorKey))
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
              Spacer(minLength: 8)
              Button(localization.string("action.retry")) {
                runtime.restartCapture()
              }
            }
          }
        }
        .padding(6)
      } label: {
        Text(localization.string("status.section"))
          .font(.headline)
      }

      GroupBox {
        VStack(alignment: .leading, spacing: 10) {
          Toggle(
            localization.string("login.launch_at_login"),
            isOn: Binding(
              get: { runtime.isLaunchAtLoginEnabled },
              set: { runtime.setLaunchAtLoginEnabled($0) }
            )
          )
          .toggleStyle(.switch)

          Divider()

          HStack {
            Text(localization.string("language.label"))
            Spacer()
            Picker("", selection: $localization.language) {
              ForEach(AppLanguage.allCases) { language in
                Text(localization.title(for: language))
                  .tag(language)
              }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(minWidth: 150)
          }

          if runtime.launchAtLoginNeedsApproval {
            HStack(alignment: .firstTextBaseline) {
              Text(localization.string("login.needs_approval"))
                .font(.caption)
                .foregroundStyle(.secondary)
              Spacer()
              Button(localization.string("action.open_system_settings")) {
                runtime.openLoginItemsSettings()
              }
            }
          }

          if let errorDescription = runtime.launchAtLoginErrorDescription {
            Text(
              localization.string("error.launch_at_login", errorDescription)
            )
            .font(.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
          }
        }
        .padding(6)
      } label: {
        Text(localization.string("general.section"))
          .font(.headline)
      }

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
    .padding(24)
    .frame(width: 560)
    .background(
      MainWindowInstaller(title: localization.string("app.full_name"))
    )
  }

  private var statusTitle: String {
    if runtime.isCapturing {
      return localization.string("status.running")
    }
    return localization.string("status.waiting_for_permissions")
  }

  private var statusDetail: String {
    if runtime.isCapturing {
      return localization.string("status.command_tab_active")
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
  let requestPermission: () -> Void
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
          localization.string("permission.request"),
          action: requestPermission
        )
        Button(
          localization.string("action.open_system_settings"),
          action: openSettings
        )
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
