import Foundation
import XCTest
@testable import AMC

final class LocalizationTests: XCTestCase {
  func testEnglishAndSimplifiedChineseTranslationsAreAvailable() throws {
    let english = try localizedBundle(named: "en")
    let simplifiedChinese = try localizedBundle(named: "zh-Hans")

    XCTAssertEqual(
      english.localizedString(forKey: "general.section", value: nil, table: nil),
      "General"
    )
    XCTAssertEqual(
      simplifiedChinese.localizedString(
        forKey: "general.section",
        value: nil,
        table: nil
      ),
      "通用"
    )
  }

  private func localizedBundle(named localization: String) throws -> Bundle {
    let stringsURL = try XCTUnwrap(
      L10n.bundle.url(
        forResource: "Localizable",
        withExtension: "strings",
        subdirectory: nil,
        localization: localization
      )
    )
    return try XCTUnwrap(Bundle(url: stringsURL.deletingLastPathComponent()))
  }
}
