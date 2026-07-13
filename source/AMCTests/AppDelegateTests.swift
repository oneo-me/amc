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
    XCTAssertEqual(window.level, .floating)

    window.orderFront(nil)
    _ = app.setActivationPolicy(.regular)

    XCTAssertFalse(delegate.windowShouldClose(window))
    XCTAssertFalse(window.isVisible)
    XCTAssertEqual(app.activationPolicy(), .accessory)

    _ = app.setActivationPolicy(.regular)
    let policyWasReasserted = expectation(description: "Dock policy was reasserted")
    DispatchQueue.main.async {
      policyWasReasserted.fulfill()
    }
    wait(for: [policyWasReasserted], timeout: 1)
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

  func testDirectWindowCloseHidesDockIcon() {
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
    window.close()

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
