import XCTest

@testable import AMC

final class ShortcutStateMachineTests: XCTestCase {
  func testFirstPressEntersThenAutomaticallyMovesOnce() {
    var machine = ShortcutStateMachine()

    XCTAssertEqual(
      machine.handle(.commandTab(.forward)),
      [.enterMissionControl]
    )
    XCTAssertTrue(machine.isActive)
    XCTAssertEqual(
      machine.handle(.missionControlReady),
      [.navigate(.forward)]
    )
    XCTAssertEqual(machine.phase, .navigating)
  }

  func testRepeatedPressesNavigateAfterOpening() {
    var machine = ShortcutStateMachine()

    _ = machine.handle(.commandTab(.forward))
    _ = machine.handle(.missionControlReady)

    XCTAssertEqual(
      machine.handle(.commandTab(.forward)),
      [.navigate(.forward)]
    )
    XCTAssertEqual(
      machine.handle(.commandTab(.backward)),
      [.navigate(.backward)]
    )
  }

  func testCommandReleaseCommitsSelection() {
    var machine = ShortcutStateMachine()

    _ = machine.handle(.commandTab(.forward))
    _ = machine.handle(.missionControlReady)

    XCTAssertEqual(machine.handle(.commandReleased), [.commitSelection])
    XCTAssertEqual(machine.phase, .idle)
  }

  func testQuickReleaseStillMovesBeforeCommit() {
    var machine = ShortcutStateMachine()

    _ = machine.handle(.commandTab(.forward))
    XCTAssertEqual(machine.handle(.commandReleased), [])
    XCTAssertEqual(
      machine.handle(.missionControlReady),
      [.navigate(.forward), .commitSelection]
    )
    XCTAssertEqual(machine.phase, .idle)
  }

  func testPressesDuringOpeningAreQueuedInOrder() {
    var machine = ShortcutStateMachine()

    _ = machine.handle(.commandTab(.forward))
    XCTAssertEqual(machine.handle(.commandTab(.backward)), [])
    XCTAssertEqual(machine.handle(.commandTab(.forward)), [])

    XCTAssertEqual(
      machine.handle(.missionControlReady),
      [
        .navigate(.forward),
        .navigate(.backward),
        .navigate(.forward),
      ]
    )
  }

  func testCancelExitsAnActiveSession() {
    var machine = ShortcutStateMachine()

    _ = machine.handle(.commandTab(.forward))
    _ = machine.handle(.missionControlReady)

    XCTAssertEqual(machine.handle(.cancel), [.cancelSelection])
    XCTAssertEqual(machine.phase, .idle)
  }
}
