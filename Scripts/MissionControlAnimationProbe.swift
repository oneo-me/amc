import AppKit
import CoreGraphics
import Darwin
import Foundation

/// A small, standalone diagnostic for measuring the Mission Control transition.
///
/// Build and run it outside SwiftPM so it has its own regular app windows:
///
///   xcrun swiftc -framework AppKit -framework CoreGraphics \
///     -framework ApplicationServices \
///     Scripts/MissionControlAnimationProbe.swift \
///     -o /tmp/mission-control-animation-probe
///   /tmp/mission-control-animation-probe
///
/// The probe opens two overlapping windows, launches Mission Control through the
/// same NSWorkspace path used by Alt Mission Control, and polls their Window
/// Server bounds until the entry transition settles. It then toggles Mission
/// Control off and measures the exit transition. The default mode is read-only;
/// research flags can temporarily change Reduce Motion and restore it on exit.
@MainActor
private final class ProbeDelegate: NSObject, NSApplicationDelegate {
  private typealias ReduceMotionGetter = @convention(c) () -> Bool
  private typealias ReduceMotionSetter = @convention(c) (Bool) -> Void

  private enum Phase: String {
    case entering = "entry"
    case exiting = "exit"
  }

  private struct Sample {
    let elapsed: TimeInterval
    let bounds: [CGWindowID: CGRect]
  }

  private let launcherURL = URL(
    fileURLWithPath: "/System/Applications/Mission Control.app",
    isDirectory: true
  )
  private let useProcessReduceMotionOverride = CommandLine.arguments.contains(
    "--temporary-reduce-motion-override"
  )
  private let useTemporaryReduceMotion = CommandLine.arguments.contains(
    "--temporary-reduce-motion"
  ) || CommandLine.arguments.contains("--temporary-reduce-motion-override")
  private let reduceMotionLeadTime: TimeInterval = {
    let prefix = "--reduce-motion-lead-ms="
    guard
      let argument = CommandLine.arguments.first(where: { $0.hasPrefix(prefix) }),
      let milliseconds = Double(argument.dropFirst(prefix.count))
    else { return 0.6 }
    return max(0, milliseconds / 1_000)
  }()
  private let restoreAfterEntryDelay: TimeInterval? = {
    let prefix = "--restore-reduce-motion-after-entry-ms="
    guard
      let argument = CommandLine.arguments.first(where: { $0.hasPrefix(prefix) }),
      let milliseconds = Double(argument.dropFirst(prefix.count))
    else { return nil }
    return max(0, milliseconds / 1_000)
  }()
  private var windows: [NSWindow] = []
  private var baseline: [CGWindowID: CGRect] = [:]
  private var phase = Phase.entering
  private var phaseBaseline: [CGWindowID: CGRect] = [:]
  private var samples: [Sample] = []
  private var timer: Timer?
  private var phaseStartedAt: ContinuousClock.Instant?
  private var firstChangeElapsed: TimeInterval?
  private var stableSampleCount = 0
  private var didObserveTransition = false
  private var originalReduceMotion: Bool?
  private var reduceMotionSetter: ReduceMotionSetter?
  private let clock = ContinuousClock()

  func applicationDidFinishLaunching(_ notification: Notification) {
    createWindows()
    NSApp.activate(ignoringOtherApps: true)

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
      guard let self else { return }
      self.configureTemporaryReduceMotionIfRequested()
      let leadTime = self.useTemporaryReduceMotion ? self.reduceMotionLeadTime : 0
      DispatchQueue.main.asyncAfter(deadline: .now() + leadTime) { [weak self] in
        self?.startProbe()
      }
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    restoreTemporaryReduceMotion()
  }

  private func createWindows() {
    let frames = [
      CGRect(x: 160, y: 180, width: 760, height: 500),
      CGRect(x: 420, y: 320, width: 700, height: 460),
    ]

    for (index, frame) in frames.enumerated() {
      let window = NSWindow(
        contentRect: frame,
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
      )
      window.title = "Mission Control animation probe \(index + 1)"
      window.contentView?.wantsLayer = true
      window.contentView?.layer?.backgroundColor = [
        NSColor.systemBlue,
        NSColor.systemOrange,
      ][index].cgColor
      window.makeKeyAndOrderFront(nil)
      windows.append(window)
    }
  }

  private func startProbe() {
    let windowIDs = windows.map { CGWindowID($0.windowNumber) }
    baseline = copyBounds(for: windowIDs)

    print("macOS=\(ProcessInfo.processInfo.operatingSystemVersionString)")
    print("reduceMotion=\(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)")
    print("windowIDs=\(windowIDs.map(String.init).joined(separator: ","))")
    print("baseline=\(format(baseline))")

    guard baseline.count == windowIDs.count else {
      finish(with: "Could not read all probe windows from CGWindowList.")
      return
    }

    resetMeasurements(for: .entering, startingFrom: baseline)

    timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120.0, repeats: true) {
      [weak self] _ in
      MainActor.assumeIsolated {
        self?.takeSample(windowIDs: windowIDs)
      }
    }

    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    NSWorkspace.shared.openApplication(
      at: launcherURL,
      configuration: configuration
    ) { [weak self] _, error in
      if let error {
        Task { @MainActor in
          self?.finish(with: "Mission Control launcher failed: \(error)")
        }
      }
    }

    if let restoreAfterEntryDelay, useTemporaryReduceMotion {
      DispatchQueue.main.asyncAfter(deadline: .now() + restoreAfterEntryDelay) {
        [weak self] in
        self?.restoreTemporaryReduceMotion()
      }
    }
  }

  private func takeSample(windowIDs: [CGWindowID]) {
    guard let phaseStartedAt else { return }

    let elapsed = seconds(from: phaseStartedAt, to: clock.now)
    let bounds = copyBounds(for: windowIDs)
    guard bounds.count == windowIDs.count else {
      if elapsed >= 2.0 {
        finish(with: "Probe windows disappeared before the transition settled.")
      }
      return
    }

    let previousBounds = samples.last?.bounds ?? phaseBaseline
    let changeFromBaseline = maximumDelta(phaseBaseline, bounds)
    let changeFromPrevious = maximumDelta(previousBounds, bounds)
    samples.append(Sample(elapsed: elapsed, bounds: bounds))

    if changeFromBaseline >= 2.0 {
      didObserveTransition = true
      if firstChangeElapsed == nil {
        firstChangeElapsed = elapsed
      }
    }

    if didObserveTransition, changeFromPrevious < 0.5 {
      stableSampleCount += 1
    } else {
      stableSampleCount = 0
    }

    // Twelve quiet 120 Hz samples are enough to avoid declaring the animation
    // complete at a single slow frame. Keep a hard timeout for OS changes.
    if stableSampleCount >= 12 {
      finishPhase(stableElapsed: elapsed, finalBounds: bounds)
    } else if elapsed >= 2.0 {
      finishPhase(stableElapsed: nil, finalBounds: bounds)
    }
  }

  private func finishPhase(
    stableElapsed: TimeInterval?,
    finalBounds: [CGWindowID: CGRect]
  ) {
    phaseStartedAt = nil
    let prefix = phase.rawValue
    if let firstChangeElapsed {
      print(String(
        format: "%@FirstGeometryChangeMs=%.1f",
        prefix,
        firstChangeElapsed * 1_000
      ))
    } else {
      print("\(prefix)FirstGeometryChangeMs=not-observed")
    }

    if let stableElapsed, let firstChangeElapsed {
      print(String(format: "%@StableGeometryMs=%.1f", prefix, stableElapsed * 1_000))
      print(String(
        format: "%@ObservedTransitionMs=%.1f",
        prefix,
        (stableElapsed - firstChangeElapsed) * 1_000
      ))
    } else {
      print("\(prefix)StableGeometryMs=not-observed")
      print("\(prefix)ObservedTransitionMs=not-observed")
    }

    print("\(prefix)Final=\(format(finalBounds))")

    switch phase {
    case .entering:
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
        guard let self else { return }
        self.resetMeasurements(for: .exiting, startingFrom: finalBounds)
        self.toggleMissionControl()
      }
    case .exiting:
      print(String(
        format: "exitBaselineDelta=%.1f",
        maximumDelta(baseline, finalBounds)
      ))
      timer?.invalidate()
      timer = nil
      restoreTemporaryReduceMotion()
      NSApp.terminate(nil)
    }
  }

  private func resetMeasurements(
    for phase: Phase,
    startingFrom bounds: [CGWindowID: CGRect]
  ) {
    self.phase = phase
    phaseBaseline = bounds
    phaseStartedAt = clock.now
    firstChangeElapsed = nil
    stableSampleCount = 0
    didObserveTransition = false
    samples = [Sample(elapsed: 0, bounds: bounds)]
  }

  private func toggleMissionControl() {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    NSWorkspace.shared.openApplication(
      at: launcherURL,
      configuration: configuration,
      completionHandler: nil
    )
  }

  private func finish(with message: String) {
    timer?.invalidate()
    timer = nil
    fputs("error=\(message)\n", stderr)
    if phase == .entering, didObserveTransition {
      toggleMissionControl()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
      self.restoreTemporaryReduceMotion()
      NSApp.terminate(nil)
    }
  }

  /// Research-only access to the same private setter used by System Settings.
  /// This lets the probe compare both states without requiring manual UI work.
  /// Alt Mission Control must not link or ship this private symbol.
  private func configureTemporaryReduceMotionIfRequested() {
    guard useTemporaryReduceMotion else { return }

    let setterName = useProcessReduceMotionOverride
      ? "_AXInterfaceSetReduceMotionEnabledOverride"
      : "_AXInterfaceSetReduceMotionEnabled"

    guard
      let processHandle = dlopen(nil, RTLD_LAZY),
      let getterSymbol = dlsym(processHandle, "_AXInterfaceGetReduceMotionEnabled"),
      let setterSymbol = dlsym(processHandle, setterName)
    else {
      fputs("error=Could not resolve temporary Reduce Motion controls.\n", stderr)
      return
    }

    let getter = unsafeBitCast(getterSymbol, to: ReduceMotionGetter.self)
    let setter = unsafeBitCast(setterSymbol, to: ReduceMotionSetter.self)
    originalReduceMotion = useProcessReduceMotionOverride ? false : getter()
    reduceMotionSetter = setter

    print("reduceMotionControl=\(useProcessReduceMotionOverride ? "process-override" : "global")")
    print("originalReduceMotion=\(getter())")
    if getter() == false {
      setter(true)
    }
  }

  private func restoreTemporaryReduceMotion() {
    guard let originalReduceMotion, let reduceMotionSetter else { return }
    reduceMotionSetter(originalReduceMotion)
    self.originalReduceMotion = nil
    self.reduceMotionSetter = nil
  }

  private func copyBounds(for windowIDs: [CGWindowID]) -> [CGWindowID: CGRect] {
    var result: [CGWindowID: CGRect] = [:]

    for windowID in windowIDs {
      guard
        let windowInfo = CGWindowListCopyWindowInfo(
          [.optionIncludingWindow],
          windowID
        ) as? [[String: Any]],
        let info = windowInfo.first,
        let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
        let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
      else { continue }

      result[windowID] = bounds
    }

    return result
  }

  private func maximumDelta(
    _ lhs: [CGWindowID: CGRect],
    _ rhs: [CGWindowID: CGRect]
  ) -> CGFloat {
    lhs.reduce(CGFloat.zero) { maximum, entry in
      guard let other = rhs[entry.key] else { return maximum }
      let rect = entry.value
      return max(
        maximum,
        abs(rect.minX - other.minX),
        abs(rect.minY - other.minY),
        abs(rect.width - other.width),
        abs(rect.height - other.height)
      )
    }
  }

  private func seconds(
    from start: ContinuousClock.Instant,
    to end: ContinuousClock.Instant
  ) -> TimeInterval {
    let duration = start.duration(to: end)
    let components = duration.components
    return TimeInterval(components.seconds)
      + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
  }

  private func format(_ bounds: [CGWindowID: CGRect]) -> String {
    bounds.keys.sorted().map { windowID in
      let rect = bounds[windowID] ?? .zero
      return String(
        format: "%u:(%.0f,%.0f,%.0f,%.0f)",
        windowID,
        rect.minX,
        rect.minY,
        rect.width,
        rect.height
      )
    }.joined(separator: ";")
  }
}

MainActor.assumeIsolated {
  let application = NSApplication.shared
  let delegate = ProbeDelegate()
  application.delegate = delegate
  application.setActivationPolicy(.regular)
  application.run()
}
