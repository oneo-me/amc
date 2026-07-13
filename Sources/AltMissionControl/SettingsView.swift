import SwiftUI

struct SettingsView: View {
  @EnvironmentObject private var runtime: RuntimeController

  var body: some View {
    Form {
      Section {
        Toggle("接管 Command + Tab", isOn: enabledBinding)
        statusRow
      }

      Section("Mission Control 导航") {
        Picker("导航按键", selection: navigationBinding) {
          ForEach(NavigationMethod.allCases) { method in
            Text(method.title).tag(method)
          }
        }

        Text(runtime.preferences.navigationMethod.help)
          .font(.caption)
          .foregroundStyle(.secondary)

        HStack {
          Text("进入等待")
          Slider(value: openingDelayBinding, in: 0.08...0.60, step: 0.01)
          Text("\(Int(runtime.preferences.openingDelay * 1_000)) ms")
            .monospacedDigit()
            .frame(width: 58, alignment: .trailing)
        }
        Text("若首次切换发生在动画完成前，请适当增大等待时间。")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section("系统权限") {
        permissionRow(
          title: "辅助功能",
          granted: runtime.accessibilityGranted,
          request: runtime.requestAccessibilityPermission,
          openSettings: runtime.openAccessibilitySettings
        )
        permissionRow(
          title: "输入监控",
          granted: runtime.inputMonitoringGranted,
          request: runtime.requestInputMonitoringPermission,
          openSettings: runtime.openInputMonitoringSettings
        )
      }

      if let lastError = runtime.lastError {
        Section {
          Label(lastError, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
          Button("重新启用监听") {
            runtime.restartCapture()
          }
        }
      }

      Section {
        Text("用法：按住 ⌘ 并连续按 Tab 切换，松开 ⌘ 后进入选中的窗口；⌘⇧Tab 反向切换。")
          .font(.callout)
      }
    }
    .formStyle(.grouped)
    .frame(width: 520, height: 500)
  }

  private var statusRow: some View {
    HStack {
      Text("运行状态")
      Spacer()
      Circle()
        .fill(statusColor)
        .frame(width: 8, height: 8)
      Text(statusText)
        .foregroundStyle(.secondary)
    }
  }

  private var statusColor: Color {
    if runtime.isSwitching { return .blue }
    if runtime.isCapturing { return .green }
    return .orange
  }

  private var statusText: String {
    if runtime.isSwitching {
      return "正在切换"
    }
    if runtime.isCapturing { return "监听中" }
    return "未监听"
  }

  @ViewBuilder
  private func permissionRow(
    title: String,
    granted: Bool,
    request: @escaping () -> Void,
    openSettings: @escaping () -> Void
  ) -> some View {
    HStack {
      Label(
        granted ? "\(title)已授权" : "需要\(title)权限",
        systemImage: granted ? "checkmark.circle.fill" : "circle.dashed"
      )
      .foregroundStyle(granted ? .green : .secondary)

      Spacer()
      if !granted {
        Button("请求权限", action: request)
        Button("打开设置", action: openSettings)
      }
    }
  }

  private var enabledBinding: Binding<Bool> {
    Binding(
      get: { runtime.preferences.isEnabled },
      set: { value in
        var preferences = runtime.preferences
        preferences.isEnabled = value
        runtime.preferences = preferences
      }
    )
  }

  private var navigationBinding: Binding<NavigationMethod> {
    Binding(
      get: { runtime.preferences.navigationMethod },
      set: { value in
        var preferences = runtime.preferences
        preferences.navigationMethod = value
        runtime.preferences = preferences
      }
    )
  }

  private var openingDelayBinding: Binding<Double> {
    Binding(
      get: { runtime.preferences.openingDelay },
      set: { value in
        var preferences = runtime.preferences
        preferences.openingDelay = value
        runtime.preferences = preferences
      }
    )
  }
}
