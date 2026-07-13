import AppKit
import SwiftUI

@main
struct AltMissionControlApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    MenuBarExtra {
      menuContent
        .environmentObject(appDelegate.runtime)
    } label: {
      Image(
        systemName: appDelegate.runtime.isCapturing
          ? "rectangle.3.group.fill"
          : "rectangle.3.group")
    }

    Settings {
      SettingsView()
        .environmentObject(appDelegate.runtime)
    }
  }

  @ViewBuilder
  private var menuContent: some View {
    Toggle("接管 Command + Tab", isOn: menuEnabledBinding)
    Divider()
    Button {
      NSApplication.shared.sendAction(
        Selector(("showSettingsWindow:")),
        to: nil,
        from: nil
      )
    } label: {
      Label("设置…", systemImage: "gearshape")
    }
    Button("退出 Alt Mission Control") {
      NSApplication.shared.terminate(nil)
    }
    .keyboardShortcut("q")
  }

  private var menuEnabledBinding: Binding<Bool> {
    Binding(
      get: { appDelegate.runtime.preferences.isEnabled },
      set: { value in
        var preferences = appDelegate.runtime.preferences
        preferences.isEnabled = value
        appDelegate.runtime.preferences = preferences
      }
    )
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
