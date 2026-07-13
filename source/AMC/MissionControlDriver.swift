import AppKit
import CoreGraphics
import Foundation

struct WindowSwitchingScope {
  let displayBounds: CGRect

  func containsHoverPoint(_ point: CGPoint) -> Bool {
    point.x >= displayBounds.minX
      && point.x < displayBounds.maxX
      && point.y >= displayBounds.minY
      && point.y < displayBounds.maxY
  }
}

final class MissionControlDriver: @unchecked Sendable {
  static let syntheticEventTag: Int64 = 0x414D_4301

  private enum KeyCode {
    static let escape: CGKeyCode = 53
    static let upArrow: CGKeyCode = 126
  }

  private struct HoverTarget {
    let windowID: CGWindowID
    let point: CGPoint
  }

  private let eventQueue = DispatchQueue(
    label: "me.oneo.AMC.synthetic-events",
    qos: .userInteractive
  )
  private var originalPointerLocation: CGPoint?
  private var focusedWindowID: CGWindowID?
  private var excludedProcessIdentifiers: Set<pid_t> = []
  private var switchingScope: WindowSwitchingScope?
  private var hoverTargets: [HoverTarget] = []
  private var selectedTargetIndex: Int?

  /// Opens Apple's Mission Control launcher. Control-Up is retained as a
  /// fallback for systems where the launcher cannot be found.
  @MainActor
  func enterMissionControl() {
    let pointerLocation = CGEvent(source: nil)?.location
    prepareHoverSession(
      pointerLocation: pointerLocation,
      focusedWindowID: Self.copyFrontmostWindowID(),
      excludedProcessIdentifiers: Self.systemOverlayProcessIdentifiers(),
      switchingScope: pointerLocation.flatMap(Self.copySwitchingScope)
    )

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

  func perform(_ actions: [SwitcherAction]) {
    guard !actions.isEmpty else { return }

    eventQueue.async { [weak self] in
      guard let self else { return }

      for (index, action) in actions.enumerated() {
        switch action {
        case .enterMissionControl:
          // Entry is performed on MainActor by the coordinator.
          break
        case .navigate(let direction):
          self.movePointer(direction)
        case .commitSelection:
          self.activateHoveredWindow()
        case .cancelSelection:
          self.cancelMissionControl()
        }

        if index < actions.count - 1 {
          Thread.sleep(forTimeInterval: 0.035)
        }
      }
    }
  }

  private func prepareHoverSession(
    pointerLocation: CGPoint?,
    focusedWindowID: CGWindowID?,
    excludedProcessIdentifiers: Set<pid_t>,
    switchingScope: WindowSwitchingScope?
  ) {
    eventQueue.async { [weak self] in
      guard let self else { return }
      self.originalPointerLocation = pointerLocation
      self.focusedWindowID = focusedWindowID
      self.excludedProcessIdentifiers = excludedProcessIdentifiers
      self.switchingScope = switchingScope
      self.hoverTargets = []
      self.selectedTargetIndex = nil
    }
  }

  private func movePointer(_ direction: SwitchDirection) {
    refreshHoverTargets()
    if hoverTargets.isEmpty {
      Thread.sleep(forTimeInterval: 0.12)
      refreshHoverTargets()
    }

    guard !hoverTargets.isEmpty else { return }

    let initialIndex = selectedTargetIndex ?? focusedTargetIndex()
    switch direction {
    case .forward:
      selectedTargetIndex = ((initialIndex ?? -1) + 1) % hoverTargets.count
    case .backward:
      let base = initialIndex ?? 0
      selectedTargetIndex = (base - 1 + hoverTargets.count) % hoverTargets.count
    }

    guard let selectedTargetIndex else { return }
    postMouseMove(to: hoverTargets[selectedTargetIndex].point)
  }

  private func focusedTargetIndex() -> Int? {
    guard let focusedWindowID else { return nil }
    return hoverTargets.firstIndex { $0.windowID == focusedWindowID }
  }

  private func refreshHoverTargets() {
    let selectedWindowID = selectedTargetIndex.flatMap { index in
      hoverTargets.indices.contains(index) ? hoverTargets[index].windowID : nil
    }
    let latestTargets = discoverHoverTargets()
    guard !latestTargets.isEmpty else { return }

    hoverTargets = latestTargets
    if let selectedWindowID {
      selectedTargetIndex = hoverTargets.firstIndex { $0.windowID == selectedWindowID }
    }
  }

  private func activateHoveredWindow() {
    guard
      let selectedTargetIndex,
      hoverTargets.indices.contains(selectedTargetIndex)
    else {
      cancelMissionControl()
      return
    }

    let selectedWindowID = hoverTargets[selectedTargetIndex].windowID
    let target =
      discoverHoverTargets()
      .first { $0.windowID == selectedWindowID }?.point
      ?? hoverTargets[selectedTargetIndex].point
    postMouseMove(to: target)
    Thread.sleep(forTimeInterval: 0.045)
    postMouseButton(.leftMouseDown, at: target)
    Thread.sleep(forTimeInterval: 0.015)
    postMouseButton(.leftMouseUp, at: target)
    Thread.sleep(forTimeInterval: 0.08)
    restorePointerLocation()
    resetHoverSession()
  }

  private func cancelMissionControl() {
    postKey(KeyCode.escape)
    Thread.sleep(forTimeInterval: 0.04)
    restorePointerLocation()
    resetHoverSession()
  }

  private func resetHoverSession() {
    originalPointerLocation = nil
    focusedWindowID = nil
    excludedProcessIdentifiers = []
    switchingScope = nil
    hoverTargets = []
    selectedTargetIndex = nil
  }

  private func restorePointerLocation() {
    guard let originalPointerLocation else { return }
    postMouseMove(to: originalPointerLocation)
  }

  /// During Mission Control, Quartz reports the original application window
  /// IDs with bounds transformed to their thumbnail positions. This gives us
  /// stable hit points without screenshot access or private Dock APIs.
  private func discoverHoverTargets() -> [HoverTarget] {
    guard
      let windowInfo = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
      ) as? [[String: Any]]
    else { return [] }

    return windowInfo.compactMap { info -> HoverTarget? in
      guard
        let windowNumber = info[kCGWindowNumber as String] as? NSNumber,
        let ownerPID = info[kCGWindowOwnerPID as String] as? NSNumber,
        let ownerName = info[kCGWindowOwnerName as String] as? String,
        let layer = info[kCGWindowLayer as String] as? NSNumber,
        let alpha = info[kCGWindowAlpha as String] as? NSNumber,
        let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
        let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
      else { return nil }

      let processIdentifier = pid_t(ownerPID.int32Value)
      guard layer.intValue == 0,
        alpha.doubleValue > 0,
        processIdentifier != getpid(),
        !excludedProcessIdentifiers.contains(processIdentifier),
        ownerName != "WindowManager",
        bounds.width >= 80,
        bounds.height >= 60,
        switchingScope?.containsHoverPoint(
          CGPoint(x: bounds.midX, y: bounds.midY)
        ) != false
      else { return nil }

      return HoverTarget(
        windowID: windowNumber.uint32Value,
        point: CGPoint(x: bounds.midX, y: bounds.midY)
      )
    }.sorted {
      if abs($0.point.y - $1.point.y) > 48 {
        return $0.point.y < $1.point.y
      }
      return $0.point.x < $1.point.x
    }
  }

  private static func copySwitchingScope(at point: CGPoint) -> WindowSwitchingScope? {
    var displayID = CGDirectDisplayID()
    var displayCount: UInt32 = 0
    guard
      CGGetDisplaysWithPoint(point, 1, &displayID, &displayCount) == .success,
      displayCount > 0
    else { return nil }

    return WindowSwitchingScope(displayBounds: CGDisplayBounds(displayID))
  }

  @MainActor
  private static func copyFrontmostWindowID() -> CGWindowID? {
    guard let processIdentifier = NSWorkspace.shared.frontmostApplication?.processIdentifier,
      let windowInfo = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
      ) as? [[String: Any]]
    else { return nil }

    for info in windowInfo {
      guard
        let ownerPID = info[kCGWindowOwnerPID as String] as? NSNumber,
        ownerPID.int32Value == processIdentifier,
        let layer = info[kCGWindowLayer as String] as? NSNumber,
        layer.intValue == 0,
        let windowNumber = info[kCGWindowNumber as String] as? NSNumber
      else { continue }
      return windowNumber.uint32Value
    }
    return nil
  }

  @MainActor
  private static func systemOverlayProcessIdentifiers() -> Set<pid_t> {
    let bundleIdentifiers = ["com.apple.dock", "com.apple.WindowManager"]
    return Set(
      bundleIdentifiers.flatMap { bundleIdentifier in
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
          .map(\.processIdentifier)
      })
  }

  private func postControlUp() {
    eventQueue.async { [weak self] in
      self?.postKey(KeyCode.upArrow, flags: .maskControl)
    }
  }

  private func postMouseMove(to point: CGPoint) {
    guard
      let source = CGEventSource(stateID: .privateState),
      let event = CGEvent(
        mouseEventSource: source,
        mouseType: .mouseMoved,
        mouseCursorPosition: point,
        mouseButton: .left
      )
    else { return }
    tagAndPost(event)
  }

  private func postMouseButton(_ type: CGEventType, at point: CGPoint) {
    guard
      let source = CGEventSource(stateID: .privateState),
      let event = CGEvent(
        mouseEventSource: source,
        mouseType: type,
        mouseCursorPosition: point,
        mouseButton: .left
      )
    else { return }
    tagAndPost(event)
  }

  private func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags = []) {
    guard
      let source = CGEventSource(stateID: .privateState),
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
      tagAndPost(event)
    }
  }

  private func tagAndPost(_ event: CGEvent) {
    event.setIntegerValueField(
      .eventSourceUserData,
      value: Self.syntheticEventTag
    )
    event.post(tap: .cgSessionEventTap)
  }
}
