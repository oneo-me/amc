import AppKit
import CoreGraphics
import Foundation

final class MissionControlDriver: @unchecked Sendable {
  static let syntheticEventTag: Int64 = 0x414D_4301

  private enum KeyCode {
    static let tab: CGKeyCode = 48
    static let returnKey: CGKeyCode = 36
    static let escape: CGKeyCode = 53
    static let leftArrow: CGKeyCode = 123
    static let rightArrow: CGKeyCode = 124
    static let upArrow: CGKeyCode = 126
  }

  private let eventQueue = DispatchQueue(
    label: "dev.oneo.AltMissionControl.synthetic-events",
    qos: .userInteractive
  )

  /// Opens Apple's Mission Control launcher. Control-Up is retained as a
  /// fallback for systems where the launcher cannot be found.
  @MainActor
  func enterMissionControl() {
    let applicationURL = URL(
      fileURLWithPath: "/System/Applications/Mission Control.app",
      isDirectory: true
    )

    if FileManager.default.fileExists(atPath: applicationURL.path) {
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.activates = true
      NSWorkspace.shared.openApplication(
        at: applicationURL,
        configuration: configuration
      ) { [weak self] _, error in
        if error != nil {
          self?.postControlUp()
        }
      }
    } else {
      postControlUp()
    }
  }

  func perform(_ actions: [SwitcherAction], navigationMethod: NavigationMethod) {
    guard !actions.isEmpty else { return }

    eventQueue.async { [weak self] in
      guard let self else { return }

      for (index, action) in actions.enumerated() {
        switch action {
        case .enterMissionControl:
          // Entry is performed on MainActor by the coordinator.
          break
        case .navigate(let direction):
          self.postNavigation(direction, method: navigationMethod)
        case .commitSelection:
          self.postKey(KeyCode.returnKey)
        case .cancelSelection:
          self.postKey(KeyCode.escape)
        }

        if index < actions.count - 1 {
          Thread.sleep(forTimeInterval: 0.035)
        }
      }
    }
  }

  private func postNavigation(_ direction: SwitchDirection, method: NavigationMethod) {
    switch (method, direction) {
    case (.arrowKeys, .forward):
      postKey(KeyCode.rightArrow)
    case (.arrowKeys, .backward):
      postKey(KeyCode.leftArrow)
    case (.tabKey, .forward):
      postKey(KeyCode.tab)
    case (.tabKey, .backward):
      postKey(KeyCode.tab, flags: .maskShift)
    }
  }

  private func postControlUp() {
    eventQueue.async { [weak self] in
      self?.postKey(KeyCode.upArrow, flags: .maskControl)
    }
  }

  private func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags = []) {
    guard
      let source = CGEventSource(stateID: .combinedSessionState),
      let keyDown = CGEvent(
        keyboardEventSource: source,
        virtualKey: keyCode,
        keyDown: true
      ),
      let keyUp = CGEvent(
        keyboardEventSource: source,
        virtualKey: keyCode,
        keyDown: false
      )
    else { return }

    for event in [keyDown, keyUp] {
      event.flags = flags
      event.setIntegerValueField(
        .eventSourceUserData,
        value: Self.syntheticEventTag
      )
      event.post(tap: .cghidEventTap)
    }
  }
}
