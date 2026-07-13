# Mission Control 动画控制研究

更新日期：2026-07-13

## 结论

macOS 没有公开 API 可以只为 Alt Mission Control 的一次快捷键调用关闭
Mission Control 动画。`NSWorkspace.OpenConfiguration` 只能控制应用启动和激活，
没有动画时长或禁用动画参数。

系统“减少动态效果”会显著缩短 Mission Control 动画，但它是全局辅助功能设置，
不是调用级选项。在本机 macOS 27.0（26A5378j）上，三组测量的平均结果是：

| 状态 | 进入动画 | 退出动画 | 进入缩短 | 退出缩短 |
| --- | ---: | ---: | ---: | ---: |
| 正常 | 485.9 ms | 475.7 ms | — | — |
| 减少动态效果 | 113.8 ms | 109.0 ms | 76.6% | 77.1% |

因此目前有三个产品方向：

1. 保持全公开 API：尊重用户现有的“减少动态效果”设置，并用窗口几何稳定检测
   替代固定等待。这个方向安全，但不能由快捷键单独关闭动画。
2. 提供明确标记的实验选项：调用系统设置使用的私有全局 setter，触发
   Mission Control 后约 250 ms 恢复原值。实测可把单次进入压到约 108 ms，
   但会短暂修改全局设置，存在系统升级、崩溃恢复和偏好竞争风险。
3. 完全自绘窗口切换界面：不进入系统 Mission Control，因此可以做到真正无动画；
   代价是需要自行实现布局、窗口预览、Space 和全屏窗口等行为。

不建议把 Raycast 的私有手势事件直接移植到 Mission Control。Raycast 的开关控制的是
相邻 Space 切换，并非 Mission Control 进入或退出动画。

## Raycast 逆向结果

检查对象是本机 `/Applications/Raycast Beta.app` 0.68.0.0。只分析了应用二进制和
打包的前端资源，没有启动或修改 Raycast，也没有读取其用户数据库。

### “Animate Switching”实际控制什么

Raycast 的 Window Management 只在以下两个命令上提供该设置：

- `Switch to Previous Space`
- `Switch to Next Space`

设置默认值为 `false`，说明文字是使用系统默认的 Space 切换动画。前端读取该值后调用：

```text
virtualDesktops.switch({ index, animated })
```

原生二进制中对应的实现名称包括：

```text
setCurrentSpace(at:animated:)
setCurrentSpaceWithoutAnimation(at:)
```

无动画分支创建并投递一组 `CGEvent`，写入字段 55、110、115、119、123–126、
129–130、132、134–135、138–139 和 169。除 123
（公开的 scroll-wheel momentum phase）外，多数字段没有公开的 `CGEventField`
定义。这是一套版本敏感的私有手势协议，用于模拟完成的横向 Space 滑动。

### 它没有给 Mission Control 传无动画参数

Raycast 调用 `_CoreDockSendNotification` 时使用的通知包括：

```text
com.apple.expose.awake
com.apple.expose.front.awake
com.apple.showdesktop.awake
com.apple.launchpad.toggle
```

这些调用的第二个参数都是 `0`。本机系统的 Mission Control launcher 同样只发送
`com.apple.expose.awake`，没有动画参数。Raycast 因而没有一条可以直接复用的
“无动画 Mission Control”调用。

Raycast 的普通窗口移动和缩放则主要通过 Accessibility 的 `AXPosition`、`AXSize`
直接设置窗口几何，所以这些操作可以立即完成；这同样不会控制由 Dock/WindowManager
渲染的 Mission Control 动画。

## macOS 接口调查

### 公开接口

- [`NSWorkspace.accessibilityDisplayShouldReduceMotion`](https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayshouldreducemotion)
  只能读取用户的全局辅助功能选择。
- [Apple 的“减少动态效果”说明](https://support.apple.com/guide/mac-help/customize-onscreen-motion-mchlc03f57a1/mac)
  明确说明该设置会减少切换桌面等系统界面的动态效果。
- [`NSWorkspace.OpenConfiguration`](https://developer.apple.com/documentation/appkit/nsworkspace/openconfiguration)
  没有 Mission Control 动画选项。

在 macOS 26.5 SDK 的 AppKit、CoreGraphics 和 ApplicationServices 公开头文件中，
没有发现 Mission Control/Exposé 的动画时长或无动画调用。

### 私有接口和隐藏偏好

本机 Dock 与 WindowManager 都读取 `_AXInterfaceGetReduceMotionEnabled` 并监听
Reduce Motion 状态通知。System Settings 使用私有的
`_AXInterfaceSetReduceMotionEnabled` 修改全局设置。

还有一个私有 `_AXInterfaceSetReduceMotionEnabledOverride`，但它只覆写当前进程。
实测探针自身读到 `reduceMotion=true` 时，Dock/WindowManager 的进入和退出动画仍为
约 475 ms，所以它不能实现调用级 Mission Control 控制。

旧系统上曾出现过 `com.apple.dock expose-animation-duration` 一类隐藏偏好。本机
macOS 27 的 Dock 和 WindowManager 二进制中已没有该键，当前偏好域中也不存在它。
本次没有为了验证一个已无消费者的键而写入偏好或重启 Dock。

`_CoreDockSendNotification` 和上述 AX setter 都是私有 API。动态查找符号并不会把它们
变成受支持接口；系统更新可能删除或改变语义，Mac App Store 审核也可能拒绝使用。

## 实测方法与数据

诊断程序在 [MissionControlAnimationProbe.swift](../Scripts/MissionControlAnimationProbe.swift)
中。它创建两个重叠窗口，使用与项目相同的 `NSWorkspace` 路径打开 Mission Control，
以 120 Hz 读取 Window Server 中的窗口边界，并在连续 12 个样本变化小于 0.5 px 后
认定动画稳定。随后它关闭 Mission Control 并用相同方法测量退出。

正常状态三组结果：

| 组 | 进入 | 退出 |
| --- | ---: | ---: |
| 1 | 491.1 ms | 474.8 ms |
| 2 | 483.1 ms | 466.4 ms |
| 3 | 483.4 ms | 485.8 ms |

全局 Reduce Motion 三组结果：

| 组 | 进入 | 退出 |
| --- | ---: | ---: |
| 1 | 107.8 ms | 110.0 ms |
| 2 | 124.5 ms | 116.2 ms |
| 3 | 109.1 ms | 100.7 ms |

额外实验：

- 在触发前立即启用全局 Reduce Motion，不额外等待，进入仍约 99.5 ms，说明
  Dock 能及时收到状态通知。
- 触发后立即恢复会得到不稳定的混合动画，本次约 399.3 ms。
- 触发后 250 ms 恢复时，进入为 108.3 ms，退出恢复为 475.0 ms。
- 只启用进程级 override 时，进入为 474.6 ms，退出为 475.5 ms。
- 所有退出测量完成后，窗口边界与初始基线的差值均为 0 px。

当前产品固定等待 420 ms，而正常状态三组从触发到几何稳定平均约 564.5 ms。
因此该等待在本机约早 145 ms；如果后续继续使用系统 Mission Control，应该改为
带超时的几何稳定检测，Reduce Motion 开启时也能自动提前继续。

## 复现

```sh
CLANG_MODULE_CACHE_PATH=/tmp/alt-mission-control-clang-cache \
  xcrun swiftc \
  -module-cache-path /tmp/alt-mission-control-clang-cache \
  -framework AppKit \
  -framework CoreGraphics \
  -framework ApplicationServices \
  Scripts/MissionControlAnimationProbe.swift \
  -o /tmp/mission-control-animation-probe

# 当前设置下测量
/tmp/mission-control-animation-probe

# 研究用途：临时修改全局 Reduce Motion，退出时恢复原值
/tmp/mission-control-animation-probe --temporary-reduce-motion

# 研究用途：只覆写探针进程，验证它不会影响 Dock/WindowManager
/tmp/mission-control-animation-probe \
  --temporary-reduce-motion-override \
  --reduce-motion-lead-ms=100

# 研究用途：模拟单次快捷键方案，触发后 250 ms 恢复全局状态
/tmp/mission-control-animation-probe \
  --temporary-reduce-motion \
  --reduce-motion-lead-ms=0 \
  --restore-reduce-motion-after-entry-ms=250
```

带 `--temporary-reduce-motion` 的路径使用私有 API，只用于本地研究。探针会保存原值并在
正常退出时恢复；强制终止或崩溃仍可能来不及恢复，运行后应确认系统设置保持原样。

## 版本边界

- 二进制逆向结论对应 Raycast Beta 0.68.0.0，后续版本可能改变实现。
- 动画时长和私有接口实验对应 macOS 27.0（26A5378j），不能直接外推到项目支持的
  macOS 13–26。
- “没有公开的调用级动画控制”基于当前 macOS SDK 和 Apple 文档；新增系统版本仍需复查。

