import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Foundation
import ServiceManagement

@MainActor
final class RuntimeController: ObservableObject {
  @Published private(set) var isCapturing = false
  @Published private(set) var isSwitching = false
  @Published private(set) var accessibilityGranted = false
  @Published private(set) var inputMonitoringGranted = false
  @Published private(set) var lastErrorKey: String?
  @Published private(set) var isLaunchAtLoginEnabled = false
  @Published private(set) var launchAtLoginNeedsApproval = false
  @Published private(set) var launchAtLoginErrorDescription: String?

  private var stateMachine = ShortcutStateMachine()
  private let driver = MissionControlDriver()
  private var interceptor: ShortcutInterceptor?
  private var missionControlReadyTask: Task<Void, Never>?
  private var permissionTimer: Timer?

  deinit {
    permissionTimer?.invalidate()
    missionControlReadyTask?.cancel()
  }

  func start() {
    refreshPermissionState()
    refreshLaunchAtLoginState()
    startCapture()

    permissionTimer = Timer.scheduledTimer(
      withTimeInterval: 1.5,
      repeats: true
    ) { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        self.refreshPermissionState()
        self.refreshLaunchAtLoginState()
        if !self.isCapturing {
          self.startCapture()
        }
      }
    }
  }

  func stop() {
    permissionTimer?.invalidate()
    permissionTimer = nil
    missionControlReadyTask?.cancel()
    missionControlReadyTask = nil
    interceptor?.stop()
    interceptor = nil
    isCapturing = false
    cancelCurrentSwitchIfNeeded()
  }

  func requestAccessibilityPermission() {
    let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    let options = [promptKey: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
    _ = CGRequestPostEventAccess()
    refreshPermissionState()
  }

  func requestInputMonitoringPermission() {
    _ = CGRequestListenEventAccess()
    refreshPermissionState()
  }

  func openAccessibilitySettings() {
    openPrivacySettings(pane: "Privacy_Accessibility")
  }

  func openInputMonitoringSettings() {
    openPrivacySettings(pane: "Privacy_ListenEvent")
  }

  func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
    launchAtLoginErrorDescription = nil

    do {
      if isEnabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      launchAtLoginErrorDescription = error.localizedDescription
    }

    refreshLaunchAtLoginState()
  }

  func openLoginItemsSettings() {
    SMAppService.openSystemSettingsLoginItems()
  }

  private func openPrivacySettings(pane: String) {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?\(pane)"
      )
    else { return }
    NSWorkspace.shared.open(url)
  }

  private func refreshPermissionState() {
    accessibilityGranted = AXIsProcessTrusted() || CGPreflightPostEventAccess()
    inputMonitoringGranted = CGPreflightListenEventAccess()
  }

  private func refreshLaunchAtLoginState() {
    switch SMAppService.mainApp.status {
    case .enabled:
      isLaunchAtLoginEnabled = true
      launchAtLoginNeedsApproval = false
    case .requiresApproval:
      isLaunchAtLoginEnabled = true
      launchAtLoginNeedsApproval = true
    case .notRegistered, .notFound:
      isLaunchAtLoginEnabled = false
      launchAtLoginNeedsApproval = false
    @unknown default:
      isLaunchAtLoginEnabled = false
      launchAtLoginNeedsApproval = false
    }
  }

  private func startCapture() {
    guard interceptor == nil else { return }

    let driver = self.driver
    let interceptor = ShortcutInterceptor { [weak self] event in
      if event == .pointerClicked {
        // This runs inside the event-tap callback, before macOS delivers the
        // click. Invalidate pending activation synchronously; UI state follows
        // on MainActor without delaying the click itself.
        driver.interruptForUserPointerInteraction()
      }
      DispatchQueue.main.async {
        self?.handleInterceptorEvent(event)
      }
    }

    guard interceptor.start() else {
      lastErrorKey = "error.global_keyboard_monitor"
      isCapturing = false
      return
    }

    self.interceptor = interceptor
    isCapturing = true
    lastErrorKey = nil
  }

  private func handleInterceptorEvent(_ event: ShortcutInterceptor.InterceptorEvent) {
    switch event {
    case .commandTab(let direction):
      apply(stateMachine.handle(.commandTab(direction)))
    case .commandReleased:
      apply(stateMachine.handle(.commandReleased))
    case .pointerClicked:
      missionControlReadyTask?.cancel()
      missionControlReadyTask = nil
      apply(stateMachine.handle(.pointerClicked))
    case .tapRecovered:
      lastErrorKey = nil
    }
    isSwitching = stateMachine.isActive
  }

  private func apply(_ actions: [SwitcherAction]) {
    guard !actions.isEmpty else { return }

    var syntheticActions: [SwitcherAction] = []
    for action in actions {
      if action == .enterMissionControl {
        driver.enterMissionControl()
        scheduleMissionControlReady()
      } else {
        syntheticActions.append(action)
      }
    }

    driver.perform(syntheticActions)
  }

  private func scheduleMissionControlReady() {
    missionControlReadyTask?.cancel()
    let delay: UInt64 = 120_000_000
    missionControlReadyTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: delay)
      guard !Task.isCancelled, let self else { return }
      self.apply(self.stateMachine.handle(.missionControlReady))
      self.isSwitching = self.stateMachine.isActive
      self.missionControlReadyTask = nil
    }
  }

  private func cancelCurrentSwitchIfNeeded() {
    missionControlReadyTask?.cancel()
    missionControlReadyTask = nil
    apply(stateMachine.handle(.cancel))
    isSwitching = false
  }
}
