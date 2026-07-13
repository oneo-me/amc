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

  func testLanguageCanBeSelectedWithoutChangingSystemPreferences() {
    XCTAssertEqual(
      L10n.string("general.section", language: .english),
      "General"
    )
    XCTAssertEqual(
      L10n.string("general.section", language: .simplifiedChinese),
      "通用"
    )
    XCTAssertEqual(
      L10n.string("app.quit_completely", language: .simplifiedChinese),
      "彻底退出"
    )
  }

  @MainActor
  func testLanguagePreferenceIsPersisted() throws {
    let suiteName = "LocalizationTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let controller = LocalizationController(defaults: defaults)
    XCTAssertEqual(controller.language, .system)

    controller.language = .simplifiedChinese

    XCTAssertEqual(
      LocalizationController(defaults: defaults).language,
      .simplifiedChinese
    )
    XCTAssertEqual(controller.string("general.section"), "通用")
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
