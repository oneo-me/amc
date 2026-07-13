import Foundation

enum SwitchDirection: Equatable, Sendable {
  case forward
  case backward
}

enum ShortcutInput: Equatable, Sendable {
  case commandTab(SwitchDirection)
  case missionControlReady
  case commandReleased
  case cancel
}

enum SwitcherAction: Equatable, Sendable {
  case enterMissionControl
  case navigate(SwitchDirection)
  case commitSelection
  case cancelSelection
}

/// A small deterministic state machine kept separate from the event tap so the
/// timing-sensitive keyboard behavior can be unit tested without UI automation.
struct ShortcutStateMachine: Equatable, Sendable {
  enum Phase: Equatable, Sendable {
    case idle
    case opening(pending: [SwitchDirection], commitWhenReady: Bool)
    case navigating
  }

  private(set) var phase: Phase = .idle

  var isActive: Bool {
    phase != .idle
  }

  @discardableResult
  mutating func handle(_ input: ShortcutInput) -> [SwitcherAction] {
    switch (phase, input) {
    case (.idle, .commandTab(let direction)):
      // The first press enters Mission Control and is queued as the first
      // move. This deliberately skips the currently focused window.
      phase = .opening(pending: [direction], commitWhenReady: false)
      return [.enterMissionControl]

    case (.opening(let pending, let commit), .commandTab(let direction)):
      phase = .opening(
        pending: pending + [direction],
        commitWhenReady: commit
      )
      return []

    case (.opening(let pending, let commit), .missionControlReady):
      var actions = pending.map(SwitcherAction.navigate)
      if commit {
        actions.append(.commitSelection)
        phase = .idle
      } else {
        phase = .navigating
      }
      return actions

    case (.opening(let pending, _), .commandReleased):
      // A quick tap may release Command before the Mission Control
      // animation ends. Preserve the first move and commit afterwards.
      phase = .opening(pending: pending, commitWhenReady: true)
      return []

    case (.navigating, .commandTab(let direction)):
      return [.navigate(direction)]

    case (.navigating, .commandReleased):
      phase = .idle
      return [.commitSelection]

    case (.opening, .cancel), (.navigating, .cancel):
      phase = .idle
      return [.cancelSelection]

    case (.idle, .cancel):
      return []

    case (.idle, .missionControlReady),
      (.idle, .commandReleased),
      (.navigating, .missionControlReady):
      return []
    }
  }
}
