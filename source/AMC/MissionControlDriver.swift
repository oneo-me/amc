import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct WindowSwitchingScope {
  let displayBounds: CGRect

  func contains(_ point: CGPoint) -> Bool {
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

  private struct WindowIdentity {
    let windowID: CGWindowID
    let processIdentifier: pid_t
    let title: String?
    let bounds: CGRect
  }

  private struct SelectionTarget {
    let identity: WindowIdentity
    let thumbnailBounds: CGRect
  }

  private struct InitialWindowState {
    let focusedWindowID: CGWindowID?
    let identities: [CGWindowID: WindowIdentity]
    let switchingScope: WindowSwitchingScope
  }

  private let eventQueue = DispatchQueue(
    label: "me.oneo.AMC.synthetic-events",
    qos: .userInteractive
  )
  private let sessionLock = NSLock()
  private let selectionOverlay = MissionControlSelectionOverlay()
  private var nextSessionID: UInt64 = 0
  private var activeSessionID: UInt64?

  // These properties are confined to eventQueue.
  private var preparedSessionID: UInt64?
  private var focusedWindowID: CGWindowID?
  private var excludedProcessIdentifiers: Set<pid_t> = []
  private var switchingScope: WindowSwitchingScope?
  private var originalWindowIdentities: [CGWindowID: WindowIdentity] = [:]
  private var selectionTargets: [SelectionTarget] = []
  private var selectedTargetIndex: Int?
  private var hasStableMissionControlLayout = false

  /// Opens Apple's Mission Control launcher. Control-Up is retained as a
  /// fallback for systems where the launcher cannot be found.
  @MainActor
  func enterMissionControl() {
    let sessionID = beginSession()
    let initialState = Self.copyInitialWindowState()
    prepareSelectionSession(
      sessionID: sessionID,
      focusedWindowID: initialState.focusedWindowID,
      identities: initialState.identities,
      excludedProcessIdentifiers: Self.systemOverlayProcessIdentifiers(),
      switchingScope: initialState.switchingScope
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
          self?.postControlUp(sessionID: sessionID)
        }
      }
    } else {
      postControlUp(sessionID: sessionID)
    }
  }

  func perform(_ actions: [SwitcherAction]) {
    guard !actions.isEmpty, let sessionID = copyActiveSessionID() else { return }

    eventQueue.async { [weak self] in
      guard let self else { return }

      for (index, action) in actions.enumerated() {
        guard self.isSessionActive(sessionID) else { return }

        switch action {
        case .enterMissionControl:
          // Entry is performed on MainActor by the coordinator.
          break
        case .navigate(let direction):
          self.moveSelection(direction, sessionID: sessionID)
        case .commitSelection:
          self.activateSelectedWindow(sessionID: sessionID)
        case .cancelSelection:
          self.cancelMissionControl(sessionID: sessionID)
        }

        if index < actions.count - 1 {
          Thread.sleep(forTimeInterval: 0.015)
        }
      }
    }
  }

  /// Called synchronously from the event tap before a real click is delivered.
  /// Invalidating the session first guarantees that queued synthetic work can
  /// never override the window chosen by the user.
  func interruptForUserPointerInteraction() {
    let interruptedSessionID: UInt64? = withSessionLock {
      guard let activeSessionID else { return nil }
      self.activeSessionID = nil
      return activeSessionID
    }
    guard let interruptedSessionID else { return }

    eventQueue.async { [weak self] in
      self?.resetSelectionState(sessionID: interruptedSessionID)
    }
    hideSelectionFrame()
  }

  private func beginSession() -> UInt64 {
    let sessionID = withSessionLock {
      nextSessionID &+= 1
      activeSessionID = nextSessionID
      return nextSessionID
    }
    hideSelectionFrame()
    return sessionID
  }

  private func finishSession(_ sessionID: UInt64) {
    withSessionLock {
      if activeSessionID == sessionID {
        activeSessionID = nil
      }
    }
  }

  private func copyActiveSessionID() -> UInt64? {
    withSessionLock { activeSessionID }
  }

  private func isSessionActive(_ sessionID: UInt64) -> Bool {
    withSessionLock { activeSessionID == sessionID }
  }

  private func withActiveSession(
    _ sessionID: UInt64,
    perform work: () -> Void
  ) {
    sessionLock.lock()
    defer { sessionLock.unlock() }
    guard activeSessionID == sessionID else { return }
    work()
  }

  private func withSessionLock<T>(_ work: () -> T) -> T {
    sessionLock.lock()
    defer { sessionLock.unlock() }
    return work()
  }

  private func prepareSelectionSession(
    sessionID: UInt64,
    focusedWindowID: CGWindowID?,
    identities: [CGWindowID: WindowIdentity],
    excludedProcessIdentifiers: Set<pid_t>,
    switchingScope: WindowSwitchingScope
  ) {
    eventQueue.async { [weak self] in
      guard let self, self.isSessionActive(sessionID) else { return }
      self.preparedSessionID = sessionID
      self.focusedWindowID = focusedWindowID
      self.originalWindowIdentities = identities
      self.excludedProcessIdentifiers = excludedProcessIdentifiers
      self.switchingScope = switchingScope
      self.selectionTargets = []
      self.selectedTargetIndex = nil
      self.hasStableMissionControlLayout = false
    }
  }

  private func moveSelection(_ direction: SwitchDirection, sessionID: UInt64) {
    if !hasStableMissionControlLayout {
      guard waitForStableMissionControlLayout(sessionID: sessionID) else { return }
      hasStableMissionControlLayout = true
    }

    refreshSelectionTargets()
    if selectionTargets.isEmpty {
      Thread.sleep(forTimeInterval: 0.12)
      guard isSessionActive(sessionID) else { return }
      refreshSelectionTargets()
    }

    guard !selectionTargets.isEmpty else { return }

    let initialIndex = selectedTargetIndex ?? focusedTargetIndex()
    switch direction {
    case .forward:
      selectedTargetIndex = ((initialIndex ?? -1) + 1) % selectionTargets.count
    case .backward:
      let base = initialIndex ?? 0
      selectedTargetIndex = (base - 1 + selectionTargets.count) % selectionTargets.count
    }

    guard let selectedTargetIndex else { return }
    showSelectionFrame(
      around: selectionTargets[selectedTargetIndex].thumbnailBounds,
      sessionID: sessionID
    )
  }

  private func waitForStableMissionControlLayout(sessionID: UInt64) -> Bool {
    var previousLayout: [CGWindowID: CGRect]?
    var stableSampleCount = 0

    for _ in 0..<45 {
      guard isSessionActive(sessionID) else { return false }
      let targets = discoverSelectionTargets()
      let currentLayout = Dictionary(
        uniqueKeysWithValues: targets.map {
          ($0.identity.windowID, $0.thumbnailBounds)
        }
      )

      if isMissionControlLayout(targets),
        let previousLayout,
        layoutsMatch(previousLayout, currentLayout)
      {
        stableSampleCount += 1
        if stableSampleCount >= 2 {
          selectionTargets = targets
          return true
        }
      } else {
        stableSampleCount = 0
      }

      previousLayout = currentLayout
      Thread.sleep(forTimeInterval: 0.016)
    }

    // The timeout is only a safety valve for unusual system animations. Use
    // the latest complete layout instead of leaving the shortcut unresponsive.
    refreshSelectionTargets()
    return isSessionActive(sessionID) && !selectionTargets.isEmpty
  }

  private func isMissionControlLayout(_ targets: [SelectionTarget]) -> Bool {
    targets.contains { target in
      Self.boundsDifference(
        target.thumbnailBounds,
        target.identity.bounds
      ) > 16
    }
  }

  private func layoutsMatch(
    _ lhs: [CGWindowID: CGRect],
    _ rhs: [CGWindowID: CGRect]
  ) -> Bool {
    guard lhs.count == rhs.count else { return false }
    return lhs.allSatisfy { windowID, bounds in
      guard let otherBounds = rhs[windowID] else { return false }
      return Self.boundsDifference(bounds, otherBounds) < 1
    }
  }

  private static func boundsDifference(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
    abs(lhs.minX - rhs.minX)
      + abs(lhs.minY - rhs.minY)
      + abs(lhs.width - rhs.width)
      + abs(lhs.height - rhs.height)
  }

  private func focusedTargetIndex() -> Int? {
    guard let focusedWindowID else { return nil }
    return selectionTargets.firstIndex { $0.identity.windowID == focusedWindowID }
  }

  private func refreshSelectionTargets() {
    let selectedWindowID = selectedTargetIndex.flatMap { index in
      selectionTargets.indices.contains(index)
        ? selectionTargets[index].identity.windowID
        : nil
    }
    let latestTargets = discoverSelectionTargets()
    guard !latestTargets.isEmpty else { return }

    selectionTargets = latestTargets
    if let selectedWindowID {
      selectedTargetIndex = selectionTargets.firstIndex {
        $0.identity.windowID == selectedWindowID
      }
    }
  }

  private func activateSelectedWindow(sessionID: UInt64) {
    guard
      let selectedTargetIndex,
      selectionTargets.indices.contains(selectedTargetIndex)
    else {
      cancelMissionControl(sessionID: sessionID)
      return
    }

    let selectedWindowID = selectionTargets[selectedTargetIndex].identity.windowID
    let target =
      discoverSelectionTargets()
      .first { $0.identity.windowID == selectedWindowID }
      ?? selectionTargets[selectedTargetIndex]

    hideSelectionFrame()
    DispatchQueue.main.async { [weak self] in
      guard let self, self.isSessionActive(sessionID) else { return }
      // Activate first so Mission Control exits toward the selected window,
      // rather than restoring the window currently underneath the pointer.
      Self.focusWindow(target.identity)
      self.scheduleMissionControlExit(
        target.identity,
        sessionID: sessionID
      )
    }
  }

  private func scheduleMissionControlExit(
    _ identity: WindowIdentity,
    sessionID: UInt64
  ) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
      guard let self, self.isSessionActive(sessionID) else { return }

      if !Self.hasReturnedToDesktop(identity) {
        self.eventQueue.async { [weak self] in
          guard let self else { return }
          self.withActiveSession(sessionID) {
            self.postKey(KeyCode.escape)
          }
        }
      }

      self.scheduleWindowActivationConfirmation(
        identity,
        sessionID: sessionID,
        pollCount: 0
      )
    }
  }

  private func scheduleWindowActivationConfirmation(
    _ identity: WindowIdentity,
    sessionID: UInt64,
    pollCount: Int
  ) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { [weak self] in
      guard let self, self.isSessionActive(sessionID) else { return }
      if !Self.hasReturnedToDesktop(identity), pollCount < 32 {
        self.scheduleWindowActivationConfirmation(
          identity,
          sessionID: sessionID,
          pollCount: pollCount + 1
        )
        return
      }

      Self.focusWindow(identity)
      self.finishSession(sessionID)
      self.eventQueue.async { [weak self] in
        self?.resetSelectionState(sessionID: sessionID)
      }
    }
  }

  private func cancelMissionControl(sessionID: UInt64) {
    hideSelectionFrame()
    withActiveSession(sessionID) {
      postKey(KeyCode.escape)
    }
    finishSession(sessionID)
    resetSelectionState(sessionID: sessionID)
  }

  private func resetSelectionState(sessionID: UInt64) {
    guard preparedSessionID == sessionID else { return }
    preparedSessionID = nil
    focusedWindowID = nil
    excludedProcessIdentifiers = []
    switchingScope = nil
    originalWindowIdentities = [:]
    selectionTargets = []
    selectedTargetIndex = nil
    hasStableMissionControlLayout = false
  }

  private func showSelectionFrame(around bounds: CGRect, sessionID: UInt64) {
    DispatchQueue.main.async { [weak self] in
      guard let self, self.isSessionActive(sessionID) else { return }
      self.selectionOverlay.show(aroundQuartzBounds: bounds)
    }
  }

  private func hideSelectionFrame() {
    DispatchQueue.main.async { [weak self] in
      self?.selectionOverlay.hide()
    }
  }

  /// Mission Control keeps the original application window IDs while
  /// transforming their bounds to thumbnail positions. The IDs connect each
  /// visible thumbnail to the public Accessibility window activated on commit.
  private func discoverSelectionTargets() -> [SelectionTarget] {
    guard
      let windowInfo = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
      ) as? [[String: Any]]
    else { return [] }

    var seenWindowIDs: Set<CGWindowID> = []
    return windowInfo.compactMap { info -> SelectionTarget? in
      guard
        let windowNumber = info[kCGWindowNumber as String] as? NSNumber,
        let ownerPID = info[kCGWindowOwnerPID as String] as? NSNumber,
        let ownerName = info[kCGWindowOwnerName as String] as? String,
        let layer = info[kCGWindowLayer as String] as? NSNumber,
        let alpha = info[kCGWindowAlpha as String] as? NSNumber,
        let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
        let thumbnailBounds = CGRect(dictionaryRepresentation: boundsDictionary)
      else { return nil }

      let windowID = windowNumber.uint32Value
      let processIdentifier = pid_t(ownerPID.int32Value)
      guard seenWindowIDs.insert(windowID).inserted,
        layer.intValue == 0,
        alpha.doubleValue > 0,
        processIdentifier != getpid(),
        !excludedProcessIdentifiers.contains(processIdentifier),
        ownerName != "WindowManager",
        thumbnailBounds.width >= 80,
        thumbnailBounds.height >= 60,
        switchingScope?.contains(
          CGPoint(x: thumbnailBounds.midX, y: thumbnailBounds.midY)
        ) != false
      else { return nil }

      let identity = originalWindowIdentities[windowID] ?? WindowIdentity(
        windowID: windowID,
        processIdentifier: processIdentifier,
        title: info[kCGWindowName as String] as? String,
        bounds: thumbnailBounds
      )
      return SelectionTarget(identity: identity, thumbnailBounds: thumbnailBounds)
    }.sorted {
      if abs($0.thumbnailBounds.midY - $1.thumbnailBounds.midY) > 48 {
        return $0.thumbnailBounds.midY < $1.thumbnailBounds.midY
      }
      return $0.thumbnailBounds.midX < $1.thumbnailBounds.midX
    }
  }

  @MainActor
  private static func copyInitialWindowState() -> InitialWindowState {
    let fallbackScope = WindowSwitchingScope(
      displayBounds: CGDisplayBounds(CGMainDisplayID())
    )
    // Read the pointer once only to choose the display. AMC never posts a
    // mouse event, warps the cursor, or restores a stale pointer position.
    let pointerLocation = CGEvent(source: nil)?.location
    let pointerScope = pointerLocation.flatMap(copySwitchingScope)
    guard
      let windowInfo = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
      ) as? [[String: Any]]
    else {
      return InitialWindowState(
        focusedWindowID: nil,
        identities: [:],
        switchingScope: pointerScope ?? fallbackScope
      )
    }

    let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
    var focusedWindowID: CGWindowID?
    var identities: [CGWindowID: WindowIdentity] = [:]

    for info in windowInfo {
      guard
        let windowNumber = info[kCGWindowNumber as String] as? NSNumber,
        let ownerPID = info[kCGWindowOwnerPID as String] as? NSNumber,
        let layer = info[kCGWindowLayer as String] as? NSNumber,
        layer.intValue == 0,
        let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
        let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
      else { continue }

      let windowID = windowNumber.uint32Value
      let processIdentifier = pid_t(ownerPID.int32Value)
      identities[windowID] = WindowIdentity(
        windowID: windowID,
        processIdentifier: processIdentifier,
        title: info[kCGWindowName as String] as? String,
        bounds: bounds
      )
      if focusedWindowID == nil, processIdentifier == frontmostPID {
        focusedWindowID = windowID
      }
    }

    let focusedWindowScope: WindowSwitchingScope?
    if let focusedWindowID,
      let focusedBounds = identities[focusedWindowID]?.bounds,
      let scope = copySwitchingScope(
        at: CGPoint(x: focusedBounds.midX, y: focusedBounds.midY)
      )
    {
      focusedWindowScope = scope
    } else {
      focusedWindowScope = nil
    }

    return InitialWindowState(
      focusedWindowID: focusedWindowID,
      identities: identities,
      switchingScope: pointerScope ?? focusedWindowScope ?? fallbackScope
    )
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
  private static func systemOverlayProcessIdentifiers() -> Set<pid_t> {
    let bundleIdentifiers = ["com.apple.dock", "com.apple.WindowManager"]
    return Set(
      bundleIdentifiers.flatMap { bundleIdentifier in
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
          .map(\.processIdentifier)
      })
  }

  @MainActor
  private static func focusWindow(_ identity: WindowIdentity) {
    let application = NSRunningApplication(
      processIdentifier: identity.processIdentifier
    )
    let accessibilityApplication = AXUIElementCreateApplication(
      identity.processIdentifier
    )
    guard let window = bestAccessibilityWindow(
      in: accessibilityApplication,
      matching: identity
    ) else {
      application?.activate(options: [.activateIgnoringOtherApps])
      return
    }

    AXUIElementSetAttributeValue(
      window,
      kAXMinimizedAttribute as CFString,
      kCFBooleanFalse
    )
    AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    application?.unhide()
    application?.activate(options: [.activateIgnoringOtherApps])
    AXUIElementSetAttributeValue(
      accessibilityApplication,
      kAXFrontmostAttribute as CFString,
      kCFBooleanTrue
    )
    AXUIElementSetAttributeValue(
      accessibilityApplication,
      kAXFocusedWindowAttribute as CFString,
      window
    )
    AXUIElementSetAttributeValue(
      window,
      kAXMainAttribute as CFString,
      kCFBooleanTrue
    )
    AXUIElementSetAttributeValue(
      window,
      kAXFocusedAttribute as CFString,
      kCFBooleanTrue
    )
    AXUIElementPerformAction(window, kAXRaiseAction as CFString)
  }

  private static func hasReturnedToDesktop(_ identity: WindowIdentity) -> Bool {
    guard
      let windowInfo = CGWindowListCopyWindowInfo(
        [.optionIncludingWindow, .excludeDesktopElements],
        identity.windowID
      ) as? [[String: Any]],
      let info = windowInfo.first,
      let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
      let currentBounds = CGRect(dictionaryRepresentation: boundsDictionary)
    else {
      // If Quartz can no longer report the window, let Accessibility attempt
      // the activation rather than leaving the switcher stuck.
      return true
    }

    let difference = abs(currentBounds.minX - identity.bounds.minX)
      + abs(currentBounds.minY - identity.bounds.minY)
      + abs(currentBounds.width - identity.bounds.width)
      + abs(currentBounds.height - identity.bounds.height)
    return difference < 8
  }

  private static func bestAccessibilityWindow(
    in application: AXUIElement,
    matching identity: WindowIdentity
  ) -> AXUIElement? {
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        application,
        kAXWindowsAttribute as CFString,
        &value
      ) == .success,
      let windows = value as? [AXUIElement],
      !windows.isEmpty
    else { return nil }

    return windows.max { lhs, rhs in
      accessibilityMatchScore(lhs, identity: identity)
        < accessibilityMatchScore(rhs, identity: identity)
    }
  }

  private static func accessibilityMatchScore(
    _ window: AXUIElement,
    identity: WindowIdentity
  ) -> Double {
    var score = 0.0
    if let title = copyStringAttribute(window, kAXTitleAttribute as CFString),
      let expectedTitle = identity.title,
      !expectedTitle.isEmpty,
      title == expectedTitle
    {
      score += 1_000
    }

    if let position = copyPointAttribute(window, kAXPositionAttribute as CFString),
      let size = copySizeAttribute(window, kAXSizeAttribute as CFString)
    {
      let distance = abs(position.x - identity.bounds.minX)
        + abs(position.y - identity.bounds.minY)
        + abs(size.width - identity.bounds.width)
        + abs(size.height - identity.bounds.height)
      score += max(0, 800 - distance)
    }
    return score
  }

  private static func copyStringAttribute(
    _ element: AXUIElement,
    _ attribute: CFString
  ) -> String? {
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(element, attribute, &value) == .success
    else { return nil }
    return value as? String
  }

  private static func copyPointAttribute(
    _ element: AXUIElement,
    _ attribute: CFString
  ) -> CGPoint? {
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
      let value,
      CFGetTypeID(value) == AXValueGetTypeID()
    else { return nil }
    let axValue = value as! AXValue
    guard
      AXValueGetType(axValue) == .cgPoint
    else { return nil }
    var point = CGPoint.zero
    guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
    return point
  }

  private static func copySizeAttribute(
    _ element: AXUIElement,
    _ attribute: CFString
  ) -> CGSize? {
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
      let value,
      CFGetTypeID(value) == AXValueGetTypeID()
    else { return nil }
    let axValue = value as! AXValue
    guard
      AXValueGetType(axValue) == .cgSize
    else { return nil }
    var size = CGSize.zero
    guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
    return size
  }

  private func postControlUp(sessionID: UInt64) {
    eventQueue.async { [weak self] in
      guard let self else { return }
      self.withActiveSession(sessionID) {
        self.postKey(KeyCode.upArrow, flags: .maskControl)
      }
    }
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

private final class MissionControlSelectionOverlay {
  private let panel: NSPanel

  init() {
    panel = NSPanel(
      contentRect: .zero,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = false
    panel.ignoresMouseEvents = true
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.animationBehavior = .none
    panel.collectionBehavior = [
      .canJoinAllSpaces,
      .fullScreenAuxiliary,
      .stationary,
      .ignoresCycle,
    ]
    panel.level = NSWindow.Level(
      rawValue: Int(CGWindowLevelForKey(.screenSaverWindow))
    )
    panel.contentView = MissionControlSelectionFrameView()
    panel.setAccessibilityElement(false)
  }

  func show(aroundQuartzBounds bounds: CGRect) {
    guard let primaryScreen = NSScreen.screens.first else { return }
    let inset: CGFloat = 7
    let appKitFrame = NSRect(
      x: bounds.minX - inset,
      y: primaryScreen.frame.maxY - bounds.maxY - inset,
      width: bounds.width + inset * 2,
      height: bounds.height + inset * 2
    )
    panel.setFrame(appKitFrame, display: true)
    panel.orderFrontRegardless()
  }

  func hide() {
    panel.orderOut(nil)
  }
}

private final class MissionControlSelectionFrameView: NSView {
  override var isOpaque: Bool { false }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }

    // Match Mission Control's thumbnail selection: one solid system-blue
    // stroke sitting just outside the thumbnail, without a second halo.
    let path = NSBezierPath(
      roundedRect: bounds.insetBy(dx: 3.5, dy: 3.5),
      xRadius: 14,
      yRadius: 14
    )
    path.lineWidth = 5
    path.lineJoinStyle = .round
    NSColor.systemBlue.withAlphaComponent(1).setStroke()
    path.stroke()
  }
}
