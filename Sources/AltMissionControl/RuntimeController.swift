import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Foundation

@MainActor
final class RuntimeController: ObservableObject {
  @Published private(set) var isCapturing = false
  @Published private(set) var isSwitching = false
  @Published private(set) var accessibilityGranted = false
  @Published private(set) var inputMonitoringGranted = false
  @Published private(set) var lastError: String?

  @Published var preferences: SwitcherPreferences {
    didSet {
      preferences.save()
      applyEnabledPreference()
    }
  }

  private var stateMachine = ShortcutStateMachine()
  private let driver = MissionControlDriver()
  private var interceptor: ShortcutInterceptor?
  private var missionControlReadyTask: Task<Void, Never>?
  private var permissionTimer: Timer?

  init() {
    preferences = .load()
  }

  deinit {
    permissionTimer?.invalidate()
    missionControlReadyTask?.cancel()
  }

  func start() {
    refreshPermissionState()
    if preferences.isEnabled {
      startCapture()
    }

    permissionTimer = Timer.scheduledTimer(
      withTimeInterval: 1.5,
      repeats: true
    ) { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        self.refreshPermissionState()
        if self.preferences.isEnabled, !self.isCapturing {
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

  func restartCapture() {
    interceptor?.stop()
    interceptor = nil
    isCapturing = false
    cancelCurrentSwitchIfNeeded()
    refreshPermissionState()
    startCapture()
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

  private func applyEnabledPreference() {
    if preferences.isEnabled {
      startCapture()
    } else {
      interceptor?.stop()
      interceptor = nil
      isCapturing = false
      cancelCurrentSwitchIfNeeded()
    }
  }

  private func startCapture() {
    guard preferences.isEnabled, interceptor == nil else { return }

    let interceptor = ShortcutInterceptor { [weak self] event in
      DispatchQueue.main.async {
        self?.handleInterceptorEvent(event)
      }
    }

    guard interceptor.start() else {
      lastError = "无法创建全局按键监听。请授予“辅助功能”和“输入监控”权限。"
      isCapturing = false
      return
    }

    self.interceptor = interceptor
    isCapturing = true
    lastError = nil
  }

  private func handleInterceptorEvent(_ event: ShortcutInterceptor.InterceptorEvent) {
    switch event {
    case .commandTab(let direction):
      apply(stateMachine.handle(.commandTab(direction)))
    case .commandReleased:
      apply(stateMachine.handle(.commandReleased))
    case .tapRecovered:
      lastError = nil
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

    driver.perform(
      syntheticActions,
      navigationMethod: preferences.navigationMethod
    )
  }

  private func scheduleMissionControlReady() {
    missionControlReadyTask?.cancel()
    let delay = UInt64(preferences.openingDelay * 1_000_000_000)
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
