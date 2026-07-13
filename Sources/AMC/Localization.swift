import Foundation

enum L10n {
  static let bundle: Bundle = {
    if
      let resourceURL = Bundle.main.resourceURL,
      let appBundle = Bundle(
        url: resourceURL.appendingPathComponent("AMC_AMC.bundle")
      )
    {
      return appBundle
    }

    return Bundle.module
  }()

  static func string(_ key: String, _ arguments: CVarArg...) -> String {
    let format = bundle.localizedString(
      forKey: key,
      value: nil,
      table: "Localizable"
    )

    guard !arguments.isEmpty else { return format }
    return String(format: format, locale: Locale.current, arguments: arguments)
  }
}
