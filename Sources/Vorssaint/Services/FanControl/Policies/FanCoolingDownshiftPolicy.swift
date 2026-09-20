// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct FanCoolingDownshiftPolicy: Sendable, Equatable {
    private(set) var currentLevel: Int
    private(set) var pendingDownshiftStartedAt: Date?

    init(initialLevel: Int = 0) {
        self.currentLevel = initialLevel
        self.pendingDownshiftStartedAt = nil
    }

    mutating func decision(
        requestedLevel: Int,
        now: Date,
        delayEnabled: Bool,
        delaySeconds: TimeInterval
    ) -> (level: Int, remainingDelay: TimeInterval?) {
        guard requestedLevel < currentLevel,
              delayEnabled,
              delaySeconds > 0 else {
            currentLevel = requestedLevel
            pendingDownshiftStartedAt = nil
            return (level: currentLevel, remainingDelay: nil)
        }

        let startedAt = pendingDownshiftStartedAt ?? now
        pendingDownshiftStartedAt = startedAt
        let elapsed = max(0, now.timeIntervalSince(startedAt))

        guard elapsed >= delaySeconds else {
            return (
                level: currentLevel,
                remainingDelay: max(0, delaySeconds - elapsed)
            )
        }

        currentLevel = requestedLevel
        pendingDownshiftStartedAt = nil
        return (level: currentLevel, remainingDelay: nil)
    }

    mutating func cancelPendingDownshift() {
        pendingDownshiftStartedAt = nil
    }

    mutating func reset(to level: Int) {
        currentLevel = level
        pendingDownshiftStartedAt = nil
    }
}
