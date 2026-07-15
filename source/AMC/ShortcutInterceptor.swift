import CoreGraphics
import Foundation

final class ShortcutInterceptor {
  enum InterceptorEvent: Equatable {
    case commandTab(SwitchDirection)
    case commandReleased
    case pointerMoved
    case pointerClicked
    case tapRecovered
  }

  private enum KeyCode {
    static let tab: Int64 = 48
  }

  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var isHandlingShortcut = false
  private var isTabPressed = false
  private var commandWasReleased = false
  private let eventHandler: (InterceptorEvent) -> Void

  init(eventHandler: @escaping (InterceptorEvent) -> Void) {
    self.eventHandler = eventHandler
  }

  deinit {
    stop()
  }

  var isRunning: Bool {
    guard let eventTap else { return false }
    return CGEvent.tapIsEnabled(tap: eventTap)
  }

  @discardableResult
  func start() -> Bool {
    if isRunning { return true }
    stop()

    let eventMask = [
      CGEventType.keyDown,
      .keyUp,
      .flagsChanged,
      .mouseMoved,
      .leftMouseDown,
    ].reduce(CGEventMask(0)) { partialResult, eventType in
      partialResult | (CGEventMask(1) << eventType.rawValue)
    }

    let pointer = Unmanaged.passUnretained(self).toOpaque()
    guard
      let eventTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: eventMask,
        callback: shortcutEventTapCallback,
        userInfo: pointer
      )
    else {
      return false
    }

    let runLoopSource = CFMachPortCreateRunLoopSource(
      kCFAllocatorDefault,
      eventTap,
      0
    )
    CFRunLoopAddSource(
      CFRunLoopGetMain(),
      runLoopSource,
      .commonModes
    )
    CGEvent.tapEnable(tap: eventTap, enable: true)

    self.eventTap = eventTap
    self.runLoopSource = runLoopSource
    return true
  }

  func stop() {
    if isHandlingShortcut {
      finishShortcut()
    }

    if let eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: false)
      CFMachPortInvalidate(eventTap)
    }
    if let runLoopSource {
      CFRunLoopRemoveSource(
        CFRunLoopGetMain(),
        runLoopSource,
        .commonModes
      )
    }

    eventTap = nil
    runLoopSource = nil
  }

  func process(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let eventTap {
        CGEvent.tapEnable(tap: eventTap, enable: true)
        eventHandler(.tapRecovered)
      }
      return Unmanaged.passUnretained(event)
    }

    if event.getIntegerValueField(.eventSourceUserData)
      == MissionControlDriver.syntheticEventTag
    {
      return Unmanaged.passUnretained(event)
    }

    if type == .mouseMoved, isHandlingShortcut {
      finishPointerInteraction(with: .pointerMoved)
      return Unmanaged.passUnretained(event)
    }

    if type == .leftMouseDown {
      // Keep the real click untouched so Mission Control can activate the
      // window under the user's pointer. Report it even just after Command
      // was released, while a delayed Mission Control commit may still exist.
      if isHandlingShortcut {
        finishPointerInteraction(with: .pointerClicked)
      } else {
        eventHandler(.pointerClicked)
      }
      return Unmanaged.passUnretained(event)
    }

    let flags = event.flags
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

    if type == .keyDown, keyCode == KeyCode.tab, flags.contains(.maskCommand) {
      isHandlingShortcut = true
      isTabPressed = true
      commandWasReleased = false
      let direction: SwitchDirection =
        flags.contains(.maskShift)
        ? .backward
        : .forward
      eventHandler(.commandTab(direction))
      return nil
    }

    if type == .keyUp, keyCode == KeyCode.tab, isHandlingShortcut {
      // Swallow the matching key-up so the original shortcut never leaks
      // into the frontmost application or native app switcher.
      isTabPressed = false
      if commandWasReleased || !flags.contains(.maskCommand) {
        finishShortcut()
      }
      return nil
    }

    if type == .flagsChanged,
      isHandlingShortcut,
      !flags.contains(.maskCommand)
    {
      commandWasReleased = true
      if !isTabPressed {
        finishShortcut()
      }
    }

    return Unmanaged.passUnretained(event)
  }

  private func finishPointerInteraction(with event: InterceptorEvent) {
    guard isHandlingShortcut else { return }
    isHandlingShortcut = false
    isTabPressed = false
    commandWasReleased = false
    eventHandler(event)
  }

  private func finishShortcut() {
    guard isHandlingShortcut else { return }
    isHandlingShortcut = false
    isTabPressed = false
    commandWasReleased = false
    eventHandler(.commandReleased)
  }
}

private let shortcutEventTapCallback: CGEventTapCallBack = {
  _, type, event, userInfo in
  guard let userInfo else {
    return Unmanaged.passUnretained(event)
  }

  let interceptor = Unmanaged<ShortcutInterceptor>
    .fromOpaque(userInfo)
    .takeUnretainedValue()
  return interceptor.process(type: type, event: event)
}
