import CoreGraphics
import XCTest

@testable import AMC

final class MissionControlDriverTests: XCTestCase {
  func testSwitchingScopeKeepsHoverPointsOnItsDisplay() {
    let scope = WindowSwitchingScope(
      displayBounds: CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080)
    )

    XCTAssertTrue(scope.containsHoverPoint(CGPoint(x: -960, y: 540)))
    XCTAssertFalse(scope.containsHoverPoint(CGPoint(x: 960, y: 540)))
  }

  func testSwitchingScopeUsesHalfOpenDisplayEdges() {
    let scope = WindowSwitchingScope(
      displayBounds: CGRect(x: 0, y: -1_080, width: 1_920, height: 1_080)
    )

    XCTAssertTrue(scope.containsHoverPoint(CGPoint(x: 0, y: -1_080)))
    XCTAssertTrue(scope.containsHoverPoint(CGPoint(x: 1_919, y: -1)))
    XCTAssertFalse(scope.containsHoverPoint(CGPoint(x: 1_920, y: -1)))
    XCTAssertFalse(scope.containsHoverPoint(CGPoint(x: 1_919, y: 0)))
  }
}
