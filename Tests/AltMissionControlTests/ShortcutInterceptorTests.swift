import CoreGraphics
import XCTest

@testable import AltMissionControl

final class ShortcutInterceptorTests: XCTestCase {
  func testCommandTabIsSwallowedAndReleaseIsReported() throws {
    var received: [ShortcutInterceptor.InterceptorEvent] = []
    let interceptor = ShortcutInterceptor { received.append($0) }
    let keyDown = try makeKeyEvent(keyCode: 48, keyDown: true, flags: .maskCommand)

    XCTAssertNil(interceptor.process(type: .keyDown, event: keyDown))
    XCTAssertEqual(received, [.commandTab(.forward)])

    let keyUp = try makeKeyEvent(keyCode: 48, keyDown: false, flags: .maskCommand)
    XCTAssertNil(interceptor.process(type: .keyUp, event: keyUp))

    let commandRelease = try makeKeyEvent(keyCode: 55, keyDown: false, flags: [])
    XCTAssertNotNil(interceptor.process(type: .flagsChanged, event: commandRelease))
    XCTAssertEqual(received, [.commandTab(.forward), .commandReleased])
  }

  func testShiftCommandTabReportsBackwardDirection() throws {
    var received: [ShortcutInterceptor.InterceptorEvent] = []
    let interceptor = ShortcutInterceptor { received.append($0) }
    let event = try makeKeyEvent(
      keyCode: 48,
      keyDown: true,
      flags: [.maskCommand, .maskShift]
    )

    XCTAssertNil(interceptor.process(type: .keyDown, event: event))
    XCTAssertEqual(received, [.commandTab(.backward)])
  }

  func testUnrelatedAndSyntheticEventsPassThrough() throws {
    var received: [ShortcutInterceptor.InterceptorEvent] = []
    let interceptor = ShortcutInterceptor { received.append($0) }
    let unrelated = try makeKeyEvent(keyCode: 0, keyDown: true, flags: [])

    XCTAssertNotNil(interceptor.process(type: .keyDown, event: unrelated))

    let synthetic = try makeKeyEvent(
      keyCode: 48,
      keyDown: true,
      flags: .maskCommand
    )
    synthetic.setIntegerValueField(
      .eventSourceUserData,
      value: MissionControlDriver.syntheticEventTag
    )
    XCTAssertNotNil(interceptor.process(type: .keyDown, event: synthetic))
    XCTAssertTrue(received.isEmpty)
  }

  private func makeKeyEvent(
    keyCode: CGKeyCode,
    keyDown: Bool,
    flags: CGEventFlags
  ) throws -> CGEvent {
    let event = try XCTUnwrap(
      CGEvent(
        keyboardEventSource: nil,
        virtualKey: keyCode,
        keyDown: keyDown
      )
    )
    event.flags = flags
    return event
  }
}
