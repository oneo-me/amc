import Combine
import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
  case system
  case english = "en"
  case simplifiedChinese = "zh-Hans"

  var id: String { rawValue }

  fileprivate var localizationIdentifier: String? {
    switch self {
    case .system:
      nil
    case .english, .simplifiedChinese:
      rawValue
    }
  }

  fileprivate var locale: Locale {
    localizationIdentifier.map(Locale.init(identifier:)) ?? .current
  }
}

@MainActor
final class LocalizationController: ObservableObject {
  @Published var language: AppLanguage {
    didSet {
      defaults.set(language.rawValue, forKey: L10n.languagePreferenceKey)
    }
  }

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    language = L10n.preferredLanguage(in: defaults)
  }

  func string(_ key: String, _ arguments: CVarArg...) -> String {
    L10n.string(key, language: language, arguments: arguments)
  }

  func title(for language: AppLanguage) -> String {
    switch language {
    case .system:
      string("language.system")
    case .english:
      "English"
    case .simplifiedChinese:
      "简体中文"
    }
  }
}

enum L10n {
  static let languagePreferenceKey = "language.preference"

  static let bundle: Bundle = {
    if let resourceURL = Bundle.main.resourceURL,
      let appBundle = Bundle(
        url: resourceURL.appendingPathComponent("AMC_AMC.bundle")
      )
    {
      return appBundle
    }

    return Bundle.module
  }()

  static func string(_ key: String, _ arguments: CVarArg...) -> String {
    string(key, language: preferredLanguage(), arguments: arguments)
  }

  static func string(
    _ key: String,
    language: AppLanguage,
    arguments: [CVarArg] = []
  ) -> String {
    let format = localizedBundle(for: language).localizedString(
      forKey: key,
      value: nil,
      table: "Localizable"
    )

    guard !arguments.isEmpty else { return format }
    return String(format: format, locale: language.locale, arguments: arguments)
  }

  static func preferredLanguage(
    in defaults: UserDefaults = .standard
  ) -> AppLanguage {
    guard
      let value = defaults.string(forKey: languagePreferenceKey),
      let language = AppLanguage(rawValue: value)
    else {
      return .system
    }
    return language
  }

  private static func localizedBundle(for language: AppLanguage) -> Bundle {
    guard
      let identifier = language.localizationIdentifier,
      let resourceURL = bundle.url(
        forResource: "Localizable",
        withExtension: "strings",
        subdirectory: nil,
        localization: identifier
      ),
      let localizedBundle = Bundle(url: resourceURL.deletingLastPathComponent())
    else {
      return bundle
    }
    return localizedBundle
  }
}
