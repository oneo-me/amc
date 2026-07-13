import AppKit
import XCTest

@testable import AMC

@MainActor
final class AppDelegateTests: XCTestCase {
  func testClosingWindowHidesDockIconAndReopenRestoresIt() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    delegate.installMainWindow(window)
    window.orderFront(nil)
    _ = app.setActivationPolicy(.regular)

    XCTAssertFalse(delegate.windowShouldClose(window))
    XCTAssertFalse(window.isVisible)
    XCTAssertEqual(app.activationPolicy(), .accessory)

    XCTAssertTrue(
      delegate.applicationShouldHandleReopen(
        app,
        hasVisibleWindows: false
      )
    )
    XCTAssertTrue(window.isVisible)
    XCTAssertEqual(app.activationPolicy(), .regular)

    window.orderOut(nil)
  }
}
