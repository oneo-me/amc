import Foundation

enum NavigationMethod: String, CaseIterable, Identifiable {
  case arrowKeys
  case tabKey

  var id: String { rawValue }

  var title: String {
    switch self {
    case .arrowKeys:
      return "左右方向键"
    case .tabKey:
      return "Tab / Shift-Tab"
    }
  }

  var help: String {
    switch self {
    case .arrowKeys:
      return "逐个移动 Mission Control 的窗口选择。"
    case .tabKey:
      return "按应用组移动选择，可用于方向键无效的系统版本。"
    }
  }
}

enum PreferenceKey {
  static let isEnabled = "isEnabled"
  static let navigationMethod = "navigationMethod"
  static let openingDelay = "openingDelay"
}

struct SwitcherPreferences: Equatable {
  var isEnabled: Bool
  var navigationMethod: NavigationMethod
  var openingDelay: TimeInterval

  static func load(from defaults: UserDefaults = .standard) -> Self {
    defaults.register(defaults: [
      PreferenceKey.isEnabled: true,
      PreferenceKey.navigationMethod: NavigationMethod.arrowKeys.rawValue,
      PreferenceKey.openingDelay: 0.22,
    ])

    return Self(
      isEnabled: defaults.bool(forKey: PreferenceKey.isEnabled),
      navigationMethod: NavigationMethod(
        rawValue: defaults.string(forKey: PreferenceKey.navigationMethod) ?? ""
      ) ?? .arrowKeys,
      openingDelay: min(
        max(defaults.double(forKey: PreferenceKey.openingDelay), 0.08),
        0.60
      )
    )
  }

  func save(to defaults: UserDefaults = .standard) {
    defaults.set(isEnabled, forKey: PreferenceKey.isEnabled)
    defaults.set(navigationMethod.rawValue, forKey: PreferenceKey.navigationMethod)
    defaults.set(openingDelay, forKey: PreferenceKey.openingDelay)
  }
}
