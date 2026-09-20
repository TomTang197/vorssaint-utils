// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum GameModeFanTarget: Equatable, Sendable {
    case performance
    case systemAuto
}

enum GameModeLinkageAction: Equatable, Sendable {
    case none
    case switchTarget(GameModeFanTarget)
}

struct GameModeLinkageDecision: Equatable, Sendable {
    let action: GameModeLinkageAction
    let remainingCooldown: TimeInterval?
    let isGamingActive: Bool
    let isCooldownActive: Bool

    init(
        action: GameModeLinkageAction,
        remainingCooldown: TimeInterval? = nil,
        isGamingActive: Bool = false,
        isCooldownActive: Bool = false
    ) {
        self.action = action
        self.remainingCooldown = remainingCooldown
        self.isGamingActive = isGamingActive
        self.isCooldownActive = isCooldownActive
    }
}

struct GameModeFanLinkagePolicy: Equatable, Sendable {
    private(set) var isGamingActive: Bool = false
    private(set) var cooldownStartedAt: Date? = nil
    private(set) var isUserOverridden: Bool = false

    init(
        isGamingActive: Bool = false,
        cooldownStartedAt: Date? = nil,
        isUserOverridden: Bool = false
    ) {
        self.isGamingActive = isGamingActive
        self.cooldownStartedAt = cooldownStartedAt
        self.isUserOverridden = isUserOverridden
    }

    mutating func handleGameModeChange(
        isActive: Bool,
        now: Date,
        enabled: Bool,
        exitDelay: TimeInterval
    ) -> GameModeLinkageDecision {
        if isActive {
            isGamingActive = true
            cooldownStartedAt = nil
            isUserOverridden = false

            guard enabled else {
                return GameModeLinkageDecision(
                    action: .none,
                    remainingCooldown: nil,
                    isGamingActive: true,
                    isCooldownActive: false
                )
            }

            return GameModeLinkageDecision(
                action: .switchTarget(.performance),
                remainingCooldown: nil,
                isGamingActive: true,
                isCooldownActive: false
            )
        } else {
            isGamingActive = false

            guard enabled else {
                cooldownStartedAt = nil
                return GameModeLinkageDecision(
                    action: .none,
                    remainingCooldown: nil,
                    isGamingActive: false,
                    isCooldownActive: false
                )
            }

            if isUserOverridden {
                cooldownStartedAt = nil
                return GameModeLinkageDecision(
                    action: .none,
                    remainingCooldown: nil,
                    isGamingActive: false,
                    isCooldownActive: false
                )
            }

            let effectiveDelay = max(0, exitDelay)
            if effectiveDelay <= 0 {
                cooldownStartedAt = nil
                return GameModeLinkageDecision(
                    action: .switchTarget(.systemAuto),
                    remainingCooldown: nil,
                    isGamingActive: false,
                    isCooldownActive: false
                )
            }

            cooldownStartedAt = now
            return GameModeLinkageDecision(
                action: .none,
                remainingCooldown: effectiveDelay,
                isGamingActive: false,
                isCooldownActive: true
            )
        }
    }

    mutating func handleTimerTick(
        now: Date,
        enabled: Bool,
        exitDelay: TimeInterval
    ) -> GameModeLinkageDecision {
        guard enabled, !isGamingActive, let startedAt = cooldownStartedAt, !isUserOverridden else {
            return GameModeLinkageDecision(
                action: .none,
                remainingCooldown: nil,
                isGamingActive: isGamingActive,
                isCooldownActive: false
            )
        }

        let effectiveDelay = max(0, exitDelay)
        let elapsed = max(0, now.timeIntervalSince(startedAt))

        if elapsed >= effectiveDelay {
            cooldownStartedAt = nil
            return GameModeLinkageDecision(
                action: .switchTarget(.systemAuto),
                remainingCooldown: nil,
                isGamingActive: false,
                isCooldownActive: false
            )
        } else {
            let remaining = max(0, effectiveDelay - elapsed)
            return GameModeLinkageDecision(
                action: .none,
                remainingCooldown: remaining,
                isGamingActive: false,
                isCooldownActive: true
            )
        }
    }

    mutating func handleUserManualOverride() {
        if isGamingActive || cooldownStartedAt != nil {
            isUserOverridden = true
            cooldownStartedAt = nil
        }
    }

    mutating func resumeGameLinkage(enabled: Bool) -> GameModeLinkageDecision {
        isUserOverridden = false
        guard isGamingActive, enabled else {
            return GameModeLinkageDecision(
                action: .none,
                remainingCooldown: nil,
                isGamingActive: isGamingActive,
                isCooldownActive: false
            )
        }
        return GameModeLinkageDecision(
            action: .switchTarget(.performance),
            remainingCooldown: nil,
            isGamingActive: true,
            isCooldownActive: false
        )
    }

    mutating func handleSettingsChanged(
        enabled: Bool,
        exitDelay: TimeInterval,
        now: Date
    ) -> GameModeLinkageDecision {
        if !enabled {
            cooldownStartedAt = nil
            isUserOverridden = false
            return GameModeLinkageDecision(
                action: .none,
                remainingCooldown: nil,
                isGamingActive: isGamingActive,
                isCooldownActive: false
            )
        }

        if isGamingActive && !isUserOverridden {
            return GameModeLinkageDecision(
                action: .switchTarget(.performance),
                remainingCooldown: nil,
                isGamingActive: true,
                isCooldownActive: false
            )
        }

        let effectiveDelay = max(0, exitDelay)
        let remaining: TimeInterval? = cooldownStartedAt.flatMap { startedAt in
            let elapsed = max(0, now.timeIntervalSince(startedAt))
            return elapsed < effectiveDelay ? (effectiveDelay - elapsed) : nil
        }

        if cooldownStartedAt != nil && remaining == nil {
            cooldownStartedAt = nil
        }

        return GameModeLinkageDecision(
            action: .none,
            remainingCooldown: remaining,
            isGamingActive: isGamingActive,
            isCooldownActive: remaining != nil
        )
    }

    mutating func reset() {
        isGamingActive = false
        cooldownStartedAt = nil
        isUserOverridden = false
    }
}
