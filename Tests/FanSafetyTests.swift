// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum FanSafetyTests {
    static func run(_ suite: TestSuite) {
        func expect(_ condition: Bool, _ message: @autoclosure () -> String,
                    file: StaticString = #filePath, line: UInt = #line) {
            suite.expect(condition, message(), file: file, line: line)
        }
        func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String,
                                       file: StaticString = #filePath, line: UInt = #line) {
            suite.expect(actual == expected, "\(label): got \(actual), expected \(expected)",
                         file: file, line: line)
        }
        func expectClose(_ actual: Double, _ expected: Double, _ label: String,
                         tol: Double = 0.001, file: StaticString = #filePath, line: UInt = #line) {
            suite.expectClose(actual, expected, label, tol: tol, file: file, line: line)
        }

        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

        // MARK: - Game Mode Linkage Policy Tests

        // 1. Game mode enter switches to performance when enabled
        do {
            var policy = GameModeFanLinkagePolicy()
            let decision = policy.handleGameModeChange(
                isActive: true,
                now: baseDate,
                enabled: true,
                exitDelay: 60
            )
            expectEqual(decision.action, .switchTarget(.performance), "game mode enter switches to performance")
            expect(decision.isGamingActive, "gaming is active")
            expect(!decision.isCooldownActive, "cooldown is not active on enter")
            expect(decision.remainingCooldown == nil, "remaining cooldown is nil on enter")
        }

        // 2. Game mode enter does not switch when linkage is disabled
        do {
            var policy = GameModeFanLinkagePolicy()
            let decision = policy.handleGameModeChange(
                isActive: true,
                now: baseDate,
                enabled: false,
                exitDelay: 60
            )
            expectEqual(decision.action, .none, "disabled policy does not switch mode on game enter")
            expect(decision.isGamingActive, "gaming is active even when disabled")
            expect(!decision.isCooldownActive, "cooldown is not active")
        }

        // 3. Game mode exit enters cooldown for delay seconds
        do {
            var policy = GameModeFanLinkagePolicy()
            _ = policy.handleGameModeChange(isActive: true, now: baseDate, enabled: true, exitDelay: 60)

            let exitDate = baseDate.addingTimeInterval(300)
            let exitDecision = policy.handleGameModeChange(
                isActive: false,
                now: exitDate,
                enabled: true,
                exitDelay: 60
            )
            expectEqual(exitDecision.action, .none, "game mode exit starts cooldown without immediate switch")
            expect(!exitDecision.isGamingActive, "gaming is no longer active")
            expect(exitDecision.isCooldownActive, "cooldown is active on exit")
            expectEqual(exitDecision.remainingCooldown, 60, "remaining cooldown matches exit delay")
        }

        // 4. Game mode exit with zero delay switches immediately to auto
        do {
            var policy = GameModeFanLinkagePolicy()
            _ = policy.handleGameModeChange(isActive: true, now: baseDate, enabled: true, exitDelay: 0)

            let exitDate = baseDate.addingTimeInterval(300)
            let exitDecision = policy.handleGameModeChange(
                isActive: false,
                now: exitDate,
                enabled: true,
                exitDelay: 0
            )
            expectEqual(exitDecision.action, .switchTarget(.systemAuto), "zero delay exit switches immediately to auto")
            expect(!exitDecision.isGamingActive, "gaming is inactive")
            expect(!exitDecision.isCooldownActive, "cooldown is inactive")
        }

        // 5. Cooldown timer tick completes and switches to auto
        do {
            var policy = GameModeFanLinkagePolicy()
            _ = policy.handleGameModeChange(isActive: true, now: baseDate, enabled: true, exitDelay: 60)

            let exitDate = baseDate.addingTimeInterval(100)
            _ = policy.handleGameModeChange(isActive: false, now: exitDate, enabled: true, exitDelay: 60)

            // Tick at 30 seconds (midway)
            let tick1 = policy.handleTimerTick(
                now: exitDate.addingTimeInterval(30),
                enabled: true,
                exitDelay: 60
            )
            expectEqual(tick1.action, .none, "tick before expiration does not switch")
            expect(tick1.isCooldownActive, "cooldown remains active")
            expectEqual(tick1.remainingCooldown, 30, "remaining cooldown decreases to 30")

            // Tick at 60 seconds (expired)
            let tick2 = policy.handleTimerTick(
                now: exitDate.addingTimeInterval(60),
                enabled: true,
                exitDelay: 60
            )
            expectEqual(tick2.action, .switchTarget(.systemAuto), "cooldown expiration switches to auto")
            expect(!tick2.isCooldownActive, "cooldown ends")
            expect(tick2.remainingCooldown == nil, "remaining cooldown cleared on expiration")
        }

        // 6. User manual override disables auto-switch
        do {
            var policy = GameModeFanLinkagePolicy()
            _ = policy.handleGameModeChange(isActive: true, now: baseDate, enabled: true, exitDelay: 60)

            // User overrides during gaming
            policy.handleUserManualOverride()
            expect(policy.isUserOverridden, "policy records user manual override")

            let exitDate = baseDate.addingTimeInterval(100)
            let exitDecision = policy.handleGameModeChange(
                isActive: false,
                now: exitDate,
                enabled: true,
                exitDelay: 60
            )
            expectEqual(exitDecision.action, .none, "manual override prevents cooldown on game exit")
            expect(!exitDecision.isCooldownActive, "cooldown is not active after manual override")

            let tick = policy.handleTimerTick(
                now: exitDate.addingTimeInterval(60),
                enabled: true,
                exitDelay: 60
            )
            expectEqual(tick.action, .none, "manual override prevents timer tick auto switch")
        }

        // 7. Manual override during cooldown cancels cooldown
        do {
            var policy = GameModeFanLinkagePolicy()
            _ = policy.handleGameModeChange(isActive: true, now: baseDate, enabled: true, exitDelay: 60)

            let exitDate = baseDate.addingTimeInterval(100)
            _ = policy.handleGameModeChange(isActive: false, now: exitDate, enabled: true, exitDelay: 60)

            policy.handleUserManualOverride()
            expect(policy.isUserOverridden, "user override recorded during cooldown")
            expect(policy.cooldownStartedAt == nil, "cooldown timestamp cleared by manual override")

            let tick = policy.handleTimerTick(
                now: exitDate.addingTimeInterval(70),
                enabled: true,
                exitDelay: 60
            )
            expectEqual(tick.action, .none, "no action on timer tick after override during cooldown")
        }

        // 8. Resume game linkage when game still active
        do {
            var policy = GameModeFanLinkagePolicy()
            _ = policy.handleGameModeChange(isActive: true, now: baseDate, enabled: true, exitDelay: 60)
            policy.handleUserManualOverride()
            expect(policy.isUserOverridden, "policy is overridden")

            let resumeDecision = policy.resumeGameLinkage(enabled: true)
            expect(!policy.isUserOverridden, "override cleared after resume")
            expectEqual(resumeDecision.action, .switchTarget(.performance), "resuming while game active switches to performance")
            expect(resumeDecision.isGamingActive, "gaming is active")

            // Resuming when gaming is not active returns .none
            var inactivePolicy = GameModeFanLinkagePolicy()
            let inactiveResume = inactivePolicy.resumeGameLinkage(enabled: true)
            expectEqual(inactiveResume.action, .none, "resuming when game not active does nothing")

            // Resuming when linkage is disabled returns .none
            var disabledPolicy = GameModeFanLinkagePolicy()
            _ = disabledPolicy.handleGameModeChange(isActive: true, now: baseDate, enabled: false, exitDelay: 60)
            let disabledResume = disabledPolicy.resumeGameLinkage(enabled: false)
            expectEqual(disabledResume.action, .none, "resuming when linkage is disabled does nothing")
        }

        // 9. Re-entering game mode during cooldown cancels cooldown and switches to performance
        do {
            var policy = GameModeFanLinkagePolicy()
            _ = policy.handleGameModeChange(isActive: true, now: baseDate, enabled: true, exitDelay: 60)

            let exitDate = baseDate.addingTimeInterval(100)
            _ = policy.handleGameModeChange(isActive: false, now: exitDate, enabled: true, exitDelay: 60)

            let reenterDate = exitDate.addingTimeInterval(20)
            let reenterDecision = policy.handleGameModeChange(
                isActive: true,
                now: reenterDate,
                enabled: true,
                exitDelay: 60
            )
            expectEqual(reenterDecision.action, .switchTarget(.performance), "re-entering game switches back to performance")
            expect(reenterDecision.isGamingActive, "gaming active on re-enter")
            expect(!reenterDecision.isCooldownActive, "cooldown cancelled on re-enter")
            expect(reenterDecision.remainingCooldown == nil, "cooldown remaining cleared")
        }

        // 10. Disabling linkage during cooldown cancels cooldown
        do {
            var policy = GameModeFanLinkagePolicy()
            _ = policy.handleGameModeChange(isActive: true, now: baseDate, enabled: true, exitDelay: 60)

            let exitDate = baseDate.addingTimeInterval(100)
            _ = policy.handleGameModeChange(isActive: false, now: exitDate, enabled: true, exitDelay: 60)

            let settingsDecision = policy.handleSettingsChanged(
                enabled: false,
                exitDelay: 60,
                now: exitDate.addingTimeInterval(10)
            )
            expectEqual(settingsDecision.action, .none, "disabling linkage yields no switch action")
            expect(!settingsDecision.isCooldownActive, "cooldown cleared when linkage disabled")
            expect(settingsDecision.remainingCooldown == nil, "remaining cooldown is nil")

            // Reset restores all defaults
            policy.reset()
            expect(!policy.isGamingActive && policy.cooldownStartedAt == nil && !policy.isUserOverridden,
                   "reset clears all state machine flags")
        }

        // MARK: - Fan Cooling Downshift Policy Tests

        // 11. Downshift holds speed when temperature drops
        do {
            var policy = FanCoolingDownshiftPolicy(initialLevel: 75)
            let t0 = Date(timeIntervalSinceReferenceDate: 100)

            let initial = policy.decision(
                requestedLevel: 30,
                now: t0,
                delayEnabled: true,
                delaySeconds: 10
            )
            expectEqual(initial.level, 75, "downshift holds current speed at t=0")
            expectClose(initial.remainingDelay ?? -1, 10, "downshift delay starts at 10s")

            let midway = policy.decision(
                requestedLevel: 30,
                now: t0.addingTimeInterval(5),
                delayEnabled: true,
                delaySeconds: 10
            )
            expectEqual(midway.level, 75, "downshift holds current speed midway")
            expectClose(midway.remainingDelay ?? -1, 5, "remaining delay is 5s midway")

            let justBefore = policy.decision(
                requestedLevel: 30,
                now: t0.addingTimeInterval(9.9),
                delayEnabled: true,
                delaySeconds: 10
            )
            expectEqual(justBefore.level, 75, "downshift holds current speed just before deadline")
            expectClose(justBefore.remainingDelay ?? -1, 0.1, "remaining delay is 0.1s")

            let atDeadline = policy.decision(
                requestedLevel: 30,
                now: t0.addingTimeInterval(10),
                delayEnabled: true,
                delaySeconds: 10
            )
            expectEqual(atDeadline.level, 30, "downshift switches to lower level when delay elapsed")
            expect(atDeadline.remainingDelay == nil, "remaining delay is nil after downshift")
        }

        // 12. Downshift delay disabled switches immediately
        do {
            var policy = FanCoolingDownshiftPolicy(initialLevel: 75)
            let decision = policy.decision(
                requestedLevel: 30,
                now: Date(timeIntervalSinceReferenceDate: 100),
                delayEnabled: false,
                delaySeconds: 10
            )
            expectEqual(decision.level, 30, "disabled delay switches immediately")
            expect(decision.remainingDelay == nil, "remaining delay is nil when delay disabled")

            // Also test zero delay seconds
            var zeroDelayPolicy = FanCoolingDownshiftPolicy(initialLevel: 75)
            let zeroDecision = zeroDelayPolicy.decision(
                requestedLevel: 30,
                now: Date(timeIntervalSinceReferenceDate: 100),
                delayEnabled: true,
                delaySeconds: 0
            )
            expectEqual(zeroDecision.level, 30, "zero delay seconds switches immediately")
            expect(zeroDecision.remainingDelay == nil, "zero delay remaining is nil")
        }

        // 13. Higher speed immediately overrides pending downshift
        do {
            var policy = FanCoolingDownshiftPolicy(initialLevel: 50)
            let t0 = Date(timeIntervalSinceReferenceDate: 100)

            _ = policy.decision(
                requestedLevel: 25,
                now: t0,
                delayEnabled: true,
                delaySeconds: 10
            )

            // Speed demand spikes to 85
            let spike = policy.decision(
                requestedLevel: 85,
                now: t0.addingTimeInterval(3),
                delayEnabled: true,
                delaySeconds: 10
            )
            expectEqual(spike.level, 85, "higher speed immediately applies without delay")
            expect(spike.remainingDelay == nil, "spike remaining delay is nil")
            expect(policy.pendingDownshiftStartedAt == nil, "spike clears pending downshift")

            // Drop again at t0 + 5 starts fresh 10s delay
            let dropAgain = policy.decision(
                requestedLevel: 40,
                now: t0.addingTimeInterval(5),
                delayEnabled: true,
                delaySeconds: 10
            )
            expectEqual(dropAgain.level, 85, "subsequent drop holds spiked speed")
            expectClose(dropAgain.remainingDelay ?? -1, 10, "fresh delay starts at 10s")
        }

        // 14. Temperature recovery cancels pending downshift
        do {
            var policy = FanCoolingDownshiftPolicy(initialLevel: 60)
            let t0 = Date(timeIntervalSinceReferenceDate: 100)

            _ = policy.decision(requestedLevel: 30, now: t0, delayEnabled: true, delaySeconds: 10)

            // Temperature recovers back to 60 at t=5
            let recovered = policy.decision(
                requestedLevel: 60,
                now: t0.addingTimeInterval(5),
                delayEnabled: true,
                delaySeconds: 10
            )
            expectEqual(recovered.level, 60, "recovery maintains current level")
            expect(recovered.remainingDelay == nil, "recovery clears remaining delay")
            expect(policy.pendingDownshiftStartedAt == nil, "recovery resets pending timestamp")
        }

        // 15. Further cooling keeps original delay start and applies latest lower target
        do {
            var policy = FanCoolingDownshiftPolicy(initialLevel: 80)
            let t0 = Date(timeIntervalSinceReferenceDate: 100)

            _ = policy.decision(requestedLevel: 50, now: t0, delayEnabled: true, delaySeconds: 10)

            // Further drop to 20 at t=8
            let colder = policy.decision(
                requestedLevel: 20,
                now: t0.addingTimeInterval(8),
                delayEnabled: true,
                delaySeconds: 10
            )
            expectEqual(colder.level, 80, "further cooling keeps current level until initial delay expires")
            expectClose(colder.remainingDelay ?? -1, 2, "further cooling keeps original countdown (2s remaining)")

            // At t=10, latest target 20 is applied
            let atDeadline = policy.decision(
                requestedLevel: 20,
                now: t0.addingTimeInterval(10),
                delayEnabled: true,
                delaySeconds: 10
            )
            expectEqual(atDeadline.level, 20, "downshift applies newest target at initial deadline")
            expect(atDeadline.remainingDelay == nil, "downshift completed")
        }

        // 16. Cancel pending downshift and reset
        do {
            var policy = FanCoolingDownshiftPolicy(initialLevel: 70)
            let t0 = Date(timeIntervalSinceReferenceDate: 100)
            _ = policy.decision(requestedLevel: 30, now: t0, delayEnabled: true, delaySeconds: 10)

            policy.cancelPendingDownshift()
            expect(policy.pendingDownshiftStartedAt == nil, "cancelPendingDownshift clears startedAt")
            expectEqual(policy.currentLevel, 70, "cancel preserves current level")

            policy.reset(to: 45)
            expectEqual(policy.currentLevel, 45, "reset updates current level")
            expect(policy.pendingDownshiftStartedAt == nil, "reset clears pending downshift")
        }

        // MARK: - Fan Wake Resume Policy Tests

        // 17. Sleep restores system auto and records intent
        do {
            var policy = FanWakeResumePolicy()
            let action = policy.handleWillSleep(activeMode: .manual)
            expectEqual(action, .restoreSystemAuto, "sleep returns restoreSystemAuto")
            expectEqual(policy.state, .sleeping, "state becomes sleeping")
            expectEqual(policy.targetToResume, .manual, "manual mode intent is recorded")

            var curvePolicy = FanWakeResumePolicy()
            _ = curvePolicy.handleWillSleep(activeMode: .curve)
            expectEqual(curvePolicy.targetToResume, .curve, "curve mode intent is recorded")

            var fullBlastPolicy = FanWakeResumePolicy()
            _ = fullBlastPolicy.handleWillSleep(activeMode: .fullBlast)
            expectEqual(fullBlastPolicy.targetToResume, .fullBlast, "fullBlast mode intent is recorded")
        }

        // 18. Sleep when already on system mode does not record resume intent
        do {
            var policy = FanWakeResumePolicy()
            let action = policy.handleWillSleep(activeMode: .system)
            expectEqual(action, .restoreSystemAuto, "sleep when in system mode returns restoreSystemAuto")
            expectEqual(policy.state, .sleeping, "state becomes sleeping")
            expect(policy.targetToResume == nil, "system mode does not record resume intent")

            policy.handleDidWake()
            expectEqual(policy.state, .active, "wake without intent transitions directly to active")

            let sampleAction = policy.handleSample(isFresh: true)
            expectEqual(sampleAction, .none, "no resume action after wake without intent")
        }

        // 19. Wake resume requires 2 consecutive fresh samples
        do {
            var policy = FanWakeResumePolicy(requiredFreshSamples: 2)
            _ = policy.handleWillSleep(activeMode: .manual)
            policy.handleDidWake()

            expectEqual(policy.state, .waking(consecutiveFreshSamples: 0), "wake transitions to waking with 0 samples")

            // Sample 1: Fresh
            let sample1 = policy.handleSample(isFresh: true)
            expectEqual(sample1, .none, "first fresh sample does not trigger resume")
            expectEqual(policy.state, .waking(consecutiveFreshSamples: 1), "count is 1")

            // Sample 2: Fresh -> Triggers resume!
            let sample2 = policy.handleSample(isFresh: true)
            expectEqual(sample2, .resume(.manual), "second consecutive fresh sample triggers resume")
            expectEqual(policy.state, .active, "state transitions to active")
            expect(policy.targetToResume == nil, "targetToResume cleared after resume")
        }

        // 20. Stale sample resets consecutive fresh count
        do {
            var policy = FanWakeResumePolicy(requiredFreshSamples: 2)
            _ = policy.handleWillSleep(activeMode: .curve)
            policy.handleDidWake()

            // Sample 1: Fresh
            _ = policy.handleSample(isFresh: true)
            expectEqual(policy.state, .waking(consecutiveFreshSamples: 1), "count is 1")

            // Sample 2: Stale -> resets count
            let staleSample = policy.handleSample(isFresh: false)
            expectEqual(staleSample, .none, "stale sample returns none")
            expectEqual(policy.state, .waking(consecutiveFreshSamples: 0), "stale sample resets count to 0")

            // Sample 3: Fresh -> count is 1
            _ = policy.handleSample(isFresh: true)
            expectEqual(policy.state, .waking(consecutiveFreshSamples: 1), "count back to 1")

            // Sample 4: Fresh -> count is 2 -> Resume!
            let resumeAction = policy.handleSample(isFresh: true)
            expectEqual(resumeAction, .resume(.curve), "consecutive fresh sample after reset triggers resume")
            expectEqual(policy.state, .active, "state is active")
        }

        // 21. User override cancels pending resume
        do {
            var policy = FanWakeResumePolicy(requiredFreshSamples: 2)
            _ = policy.handleWillSleep(activeMode: .manual)
            policy.handleDidWake()

            _ = policy.handleSample(isFresh: true)
            expectEqual(policy.state, .waking(consecutiveFreshSamples: 1), "count is 1")

            policy.handleUserOverride()
            expectEqual(policy.state, .active, "user override sets state to active")
            expect(policy.targetToResume == nil, "user override clears targetToResume")

            let subsequentSample = policy.handleSample(isFresh: true)
            expectEqual(subsequentSample, .none, "samples after user override do nothing")
        }

        // MARK: - Fan Control Configuration & FullBlast Tests

        // 22. Configuration downshift delay and fullBlast
        do {
            let config = FanControlConfiguration.fullBlast()
            expectEqual(config.mode, .fullBlast, "fullBlast mode is fullBlast")
            expectEqual(config.manualLevel, FanControlPolicy.maximumCoolingLevel, "fullBlast manual level is 100")
            expect(FanControlPolicy.validConfiguration(config), "fullBlast configuration is valid")

            let curveConfig = FanControlConfiguration.curve(
                [FanControlConfiguration.defaultCurve],
                downshiftDelayEnabled: true,
                downshiftDelaySeconds: 15
            )
            expect(curveConfig.downshiftDelayEnabled, "downshift delay is enabled")
            expectEqual(curveConfig.downshiftDelaySeconds, 15, "downshift delay seconds is 15")
            expect(FanControlPolicy.validConfiguration(curveConfig), "curve configuration with downshift delay is valid")

            let data = try? JSONEncoder().encode(curveConfig)
            expect(data != nil, "configuration encodes successfully")
            if let data {
                let decoded = try? JSONDecoder().decode(FanControlConfiguration.self, from: data)
                expect(decoded != nil, "configuration decodes successfully")
                expectEqual(decoded?.downshiftDelayEnabled, true, "decoded downshiftDelayEnabled matches")
                expectEqual(decoded?.downshiftDelaySeconds, 15, "decoded downshiftDelaySeconds matches")
            }

            // Backward compatibility: decode legacy JSON lacking downshift fields
            let legacyJSON = "{\"mode\":\"curve\",\"manualLevel\":50,\"curves\":[]}"
            if let legacyData = legacyJSON.data(using: .utf8),
               let legacyDecoded = try? JSONDecoder().decode(FanControlConfiguration.self, from: legacyData) {
                expect(legacyDecoded.downshiftDelayEnabled, "legacy decode defaults downshiftDelayEnabled to true")
                expectEqual(legacyDecoded.downshiftDelaySeconds, 10, "legacy decode defaults downshiftDelaySeconds to 10")
                expectEqual(legacyDecoded.manualLevel, 50, "legacy manualLevel preserved")
            } else {
                expect(false, "legacy JSON must decode successfully")
            }

            // Downshift delay bounds validation
            let negativeDelayConfig = FanControlConfiguration(
                mode: .curve,
                manualLevel: 50,
                curves: [FanControlConfiguration.defaultCurve],
                downshiftDelayEnabled: true,
                downshiftDelaySeconds: -5
            )
            expect(!FanControlPolicy.validConfiguration(negativeDelayConfig), "negative downshift delay is invalid")

            let excessiveDelayConfig = FanControlConfiguration(
                mode: .curve,
                manualLevel: 50,
                curves: [FanControlConfiguration.defaultCurve],
                downshiftDelayEnabled: true,
                downshiftDelaySeconds: 301
            )
            expect(!FanControlPolicy.validConfiguration(excessiveDelayConfig), "downshift delay > 300s is invalid")
        }

        // 23. Feature strings have required localized keys across all 13 languages
        do {
            let en = FeatureStrings.fanControl(.enUS)
            expectEqual(en.modeFullBlast, "Max", "enUS modeFullBlast is Max")
            expectEqual(en.gameModeLinkage, "Game Mode linkage", "enUS gameModeLinkage matches")
            expectEqual(en.resumeLinkage, "Resume linkage", "enUS resumeLinkage matches")
            expectEqual(en.downshiftDelay, "Downshift delay", "enUS downshiftDelay matches")

            let zh = FeatureStrings.fanControl(.zhHans)
            expectEqual(zh.modeFullBlast, "全速", "zhHans modeFullBlast is 全速")
            expectEqual(zh.gameModeLinkage, "游戏模式联动", "zhHans gameModeLinkage matches")
            expectEqual(zh.resumeLinkage, "恢复联动", "zhHans resumeLinkage matches")
            expectEqual(zh.downshiftDelay, "降速延迟防抖", "zhHans downshiftDelay matches")

            let allLanguages: [AppLanguage] = [
                .enUS, .ptBR, .tr, .ru, .es, .de, .fr, .it, .ja, .ko, .zhHans, .zhTW, .zhHK
            ]
            for lang in allLanguages {
                let s = FeatureStrings.fanControl(lang)
                expect(!s.modeFullBlast.isEmpty, "\(lang.rawValue) modeFullBlast is not empty")
                expect(!s.gameModeLinkage.isEmpty, "\(lang.rawValue) gameModeLinkage is not empty")
                expect(!s.gameModeActive.isEmpty, "\(lang.rawValue) gameModeActive is not empty")
                expect(!s.gameModeCooldownFormat.isEmpty, "\(lang.rawValue) gameModeCooldownFormat is not empty")
                expect(!s.resumeLinkage.isEmpty, "\(lang.rawValue) resumeLinkage is not empty")
                expect(!s.downshiftDelay.isEmpty, "\(lang.rawValue) downshiftDelay is not empty")
                expect(!s.downshiftDelaySecondsFormat.isEmpty, "\(lang.rawValue) downshiftDelaySecondsFormat is not empty")
                expect(!s.skipCooldown.isEmpty, "\(lang.rawValue) skipCooldown is not empty")
            }
        }
    }
}
