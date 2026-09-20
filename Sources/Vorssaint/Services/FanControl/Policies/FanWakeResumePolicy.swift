// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum FanWakeResumeAction: Equatable, Sendable {
    case none
    case resume(FanControlMode)
    case restoreSystemAuto
}

enum FanSleepWakeState: Equatable, Sendable {
    case active
    case sleeping
    case waking(consecutiveFreshSamples: Int)
}

struct FanWakeResumePolicy: Sendable, Equatable {
    private(set) var state: FanSleepWakeState
    private(set) var targetToResume: FanControlMode?
    let requiredFreshSamples: Int

    init(
        state: FanSleepWakeState = .active,
        targetToResume: FanControlMode? = nil,
        requiredFreshSamples: Int = 2
    ) {
        self.state = state
        self.targetToResume = targetToResume
        self.requiredFreshSamples = max(1, requiredFreshSamples)
    }

    mutating func handleWillSleep(activeMode: FanControlMode) -> FanWakeResumeAction {
        state = .sleeping
        if activeMode != .system {
            targetToResume = activeMode
        } else {
            targetToResume = nil
        }
        return .restoreSystemAuto
    }

    mutating func handleDidWake() {
        if targetToResume != nil {
            state = .waking(consecutiveFreshSamples: 0)
        } else {
            state = .active
        }
    }

    mutating func handleSample(isFresh: Bool) -> FanWakeResumeAction {
        guard case .waking(let currentCount) = state, let target = targetToResume else {
            return .none
        }

        guard isFresh else {
            state = .waking(consecutiveFreshSamples: 0)
            return .none
        }

        let newCount = currentCount + 1
        if newCount >= requiredFreshSamples {
            state = .active
            targetToResume = nil
            return .resume(target)
        } else {
            state = .waking(consecutiveFreshSamples: newCount)
            return .none
        }
    }

    mutating func handleUserOverride() {
        targetToResume = nil
        state = .active
    }
}
