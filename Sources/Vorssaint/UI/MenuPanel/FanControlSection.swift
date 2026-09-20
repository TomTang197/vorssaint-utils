// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct FanControlSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = FanControlService.shared
    @AppStorage(DefaultsKey.fanControlMode) private var modeRaw = FanControlMode.system.rawValue
    @AppStorage(DefaultsKey.fanControlCoolingLevel) private var coolingLevel =
        FanControlPolicy.defaultCoolingLevel
    @AppStorage(DefaultsKey.fanControlCurves) private var curvesStorage =
        FanControlConfiguration.defaultCurvesStorage
    @AppStorage(DefaultsKey.temperatureUnit) private var temperatureUnit =
        TemperatureUnit.celsius.rawValue
    @AppStorage(DefaultsKey.fanControlGameModeLinkageEnabled) private var gameModeLinkageEnabled = false
    @AppStorage(DefaultsKey.fanControlDownshiftDelayEnabled) private var downshiftDelayEnabled = true
    @AppStorage(DefaultsKey.fanControlDownshiftDelaySeconds) private var downshiftDelaySeconds = 10
    var collapsible = true

    private var strings: FanControlFeatureStrings {
        FeatureStrings.fanControl(l10n.language)
    }

    var body: some View {
        PanelSection(.fanControl, title: strings.title, collapsible: collapsible) {
            FanControlCardContent(strings: strings,
                                  betaLabel: l10n.s.betaBadge,
                                  snapshot: service.snapshot,
                                  accessState: service.accessState,
                                  error: service.error,
                                  isWorking: service.isWorking,
                                  mode: modeBinding,
                                  coolingLevel: $coolingLevel,
                                  curves: curvesBinding,
                                  temperatureUnit: displayTemperatureUnit,
                                  gameModeLinkageEnabled: Binding(
                                      get: { gameModeLinkageEnabled },
                                      set: {
                                          gameModeLinkageEnabled = $0
                                          service.gameModeSettingsChanged()
                                      }
                                  ),
                                  downshiftDelayEnabled: $downshiftDelayEnabled,
                                  downshiftDelaySeconds: $downshiftDelaySeconds,
                                  isGameModeActive: service.isGameModeActive,
                                  isGameModeUserOverridden: service.isGameModeUserOverridden,
                                  gameModeCooldownRemainingSeconds: service.gameModeCooldownRemainingSeconds,
                                  authorize: service.authorize,
                                  applyConfiguration: service.applyConfiguration,
                                  stopCooling: service.restoreAutomatic,
                                  resumeGameModeLinkage: service.resumeGameModeLinkage,
                                  skipGameModeCooldown: service.skipGameModeCooldown)
                .panelCard()
                .onAppear { service.panelDidAppear() }
                .onDisappear { service.panelDidDisappear() }
        }
    }

    private var modeBinding: Binding<FanControlMode> {
        Binding(
            get: { FanControlMode(rawValue: modeRaw) ?? .system },
            set: { modeRaw = $0.rawValue }
        )
    }

    private var curvesBinding: Binding<[FanControlCurve]> {
        Binding(
            get: {
                FanControlConfiguration.decodeCurves(curvesStorage)
                    ?? [FanControlConfiguration.defaultCurve]
            },
            set: { curves in
                if let encoded = FanControlConfiguration.encodeCurves(curves) {
                    curvesStorage = encoded
                }
            }
        )
    }

    private var displayTemperatureUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnit) ?? .celsius
    }
}

struct FanControlCardContent: View {
    let strings: FanControlFeatureStrings
    let betaLabel: String
    let snapshot: FanControlSnapshot
    let accessState: FanControlService.AccessState
    let error: FanControlErrorCode?
    let isWorking: Bool
    @Binding var mode: FanControlMode
    @Binding var coolingLevel: Int
    @Binding var curves: [FanControlCurve]
    let temperatureUnit: TemperatureUnit
    @Binding var gameModeLinkageEnabled: Bool
    @Binding var downshiftDelayEnabled: Bool
    @Binding var downshiftDelaySeconds: Int
    let isGameModeActive: Bool
    let isGameModeUserOverridden: Bool
    let gameModeCooldownRemainingSeconds: Int?
    let authorize: () -> Void
    let applyConfiguration: (FanControlConfiguration) -> Void
    let stopCooling: () -> Void
    let resumeGameModeLinkage: () -> Void
    let skipGameModeCooldown: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusHeader

            gameModeBanner

            if !snapshot.fans.isEmpty { fanRows }

            if let message = stateMessage {
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(messageIsError ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if canConfigure {
                modePicker
                switch mode {
                case .system:
                    EmptyView()
                case .manual:
                    manualControl
                case .curve:
                    FanControlCurveEditor(strings: strings,
                                          curves: $curves,
                                          temperatures: snapshot.temperatures ?? [],
                                          temperatureUnit: temperatureUnit,
                                          disabled: controlsDisabled)
                    if !curveCanRun {
                        Text(strings.curveUnavailable)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .fullBlast:
                    EmptyView()
                }

                optionsSection
            }

            action

            if controlsCanAppear {
                Text(strings.safetyCaption)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.secondary.opacity(0.84))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var gameModeBanner: some View {
        if isGameModeActive || gameModeCooldownRemainingSeconds != nil {
            HStack(spacing: 8) {
                Image(systemName: isGameModeActive ? "gamecontroller.fill" : "timer")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isGameModeActive ? Color.green : Color.orange)

                VStack(alignment: .leading, spacing: 1) {
                    if isGameModeActive {
                        Text(strings.gameModeActive)
                            .font(.system(size: 10.5, weight: .medium))
                    } else if let remaining = gameModeCooldownRemainingSeconds {
                        Text(String(format: strings.gameModeCooldownFormat, remaining))
                            .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                    }
                }

                Spacer()

                if isGameModeActive && isGameModeUserOverridden {
                    Button(strings.resumeLinkage) {
                        resumeGameModeLinkage()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                } else if gameModeCooldownRemainingSeconds != nil {
                    Button(strings.skipCooldown) {
                        skipGameModeCooldown()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.04))
            )
        }
    }

    @ViewBuilder
    private var optionsSection: some View {
        if mode == .curve {
            VStack(alignment: .leading, spacing: 5) {
                Toggle(isOn: $gameModeLinkageEnabled) {
                    Text(strings.gameModeLinkage)
                        .font(.system(size: 10))
                }
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .disabled(controlsDisabled)

                Toggle(isOn: $downshiftDelayEnabled) {
                    Text(strings.downshiftDelay)
                        .font(.system(size: 10))
                }
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .disabled(controlsDisabled)
            }
        }
    }

    private var modePicker: some View {
        Picker(strings.mode, selection: $mode) {
            Text(strings.systemControl).tag(FanControlMode.system)
            Text(strings.manualControl).tag(FanControlMode.manual)
            Text(strings.customCurve).tag(FanControlMode.curve)
            Text(strings.modeFullBlast).tag(FanControlMode.fullBlast)
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .disabled(controlsDisabled)
    }

    private var manualControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(strings.coolingIntensity)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(selectedCoolingLevel)%")
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
            }
            Slider(value: coolingLevelBinding,
                   in: Double(FanControlPolicy.minimumCoolingLevel)...Double(FanControlPolicy.maximumCoolingLevel),
                   step: Double(FanControlPolicy.coolingLevelStep))
                .controlSize(.small)
                .disabled(controlsDisabled)
        }
    }

    private var statusHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: snapshot.isCooling ? "fanblades.fill" : "fanblades")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(snapshot.isCooling ? AnyShapeStyle(Color.cyan)
                                                     : AnyShapeStyle(Color.secondary))
                .symbolEffect(.variableColor.iterative, options: .repeating,
                              isActive: snapshot.isCooling)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(strings.title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(betaLabel)
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor))
                }
                Text(statusText)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(snapshot.isCooling ? Color.cyan : Color.secondary)
            }
            Spacer()
            if isWorking { ProgressView().controlSize(.small) }
        }
    }

    private var fanRows: some View {
        VStack(spacing: 5) {
            ForEach(snapshot.fans) { fan in
                HStack(spacing: 6) {
                    Text(String(format: strings.fanNameFormat, fan.index + 1))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(String(format: strings.currentRPMFormat,
                                    Int(fan.actualRPM.rounded())))
                            .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                        if fan.isManuallyControlled {
                            Text(String(format: strings.targetRPMFormat,
                                        Int(fan.targetRPM.rounded())))
                                .font(.system(size: 9.5).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private var action: some View {
        if error == .noFans || error == .unsupportedHardware || error == .alreadyControlled {
            EmptyView()
        } else if error == .helperUnavailable, !snapshot.fans.isEmpty {
            Button(strings.allowControl, action: authorize)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
        } else if accessState == .notRegistered, !snapshot.fans.isEmpty {
            Button(strings.allowControl, action: authorize)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
        } else if accessState == .requiresApproval, !snapshot.fans.isEmpty {
            Button(strings.openSettings, action: authorize)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
        } else if accessState == .enabled, controlsCanAppear {
            switch mode {
            case .system:
                if snapshot.isCooling {
                    Button(strings.returnToSystem, action: stopCooling)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isWorking)
                        .frame(maxWidth: .infinity)
                }
            case .manual:
                Button(strings.applyManual) {
                    coolingLevel = selectedCoolingLevel
                    applyConfiguration(.manual(level: selectedCoolingLevel))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isWorking)
                .frame(maxWidth: .infinity)
            case .curve:
                Button(strings.applyCurve) {
                    applyConfiguration(
                        .curve(
                            curves,
                            downshiftDelayEnabled: downshiftDelayEnabled,
                            downshiftDelaySeconds: Double(downshiftDelaySeconds)
                        )
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isWorking || !curveCanRun)
                .frame(maxWidth: .infinity)
            case .fullBlast:
                Button(strings.modeFullBlast) {
                    applyConfiguration(.fullBlast())
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isWorking)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var statusText: String {
        guard snapshot.isCooling else { return strings.systemControl }
        let level = snapshot.coolingLevel ?? FanControlPolicy.defaultCoolingLevel
        switch snapshot.configuration?.mode ?? .manual {
        case .system:
            return strings.systemControl
        case .manual:
            return "\(strings.manualControl) · \(level)%"
        case .curve:
            let activeCurves = snapshot.configuration?.curves ?? []
            let temperature = activeCurves.count == 1
                ? snapshot.temperatures?.first { $0.source == activeCurves[0].sensor }?.celsius
                : nil
            if let temperature {
                return "\(strings.customCurve) · \(MetricFormat.temperature(temperature, unit: temperatureUnit)) · \(level)%"
            }
            return "\(strings.customCurve) · \(level)%"
        case .fullBlast:
            return "\(strings.modeFullBlast) · 100%"
        }
    }

    private var stateMessage: String? {
        if error == .noFans { return strings.noFans }
        if accessState == .unavailable { return strings.unsupported }
        switch error {
        case .alreadyControlled: return strings.alreadyControlled
        case .unsupportedHardware: return strings.unsupported
        case .helperUnavailable: return strings.helperUnavailable
        case .controlFailed: return strings.failed
        case .authorizationRequired: return strings.approvalCaption
        case .noFans, .none: break
        }
        if accessState == .notRegistered, !snapshot.fans.isEmpty { return strings.approvalCaption }
        if accessState == .requiresApproval { return strings.approvalCaption }
        switch snapshot.stopReason {
        case .temperatureUnavailable: return strings.temperatureUnavailable
        case .timeLimit, .appDisconnected, .heartbeatLost, .hardwareChanged,
             .thermalPressure, .recovery:
            return strings.safetyStopped
        case .none:
            return nil
        }
    }

    private var messageIsError: Bool {
        switch error {
        case .alreadyControlled, .unsupportedHardware, .helperUnavailable, .controlFailed:
            return true
        default:
            return false
        }
    }

    private var controlsCanAppear: Bool {
        !snapshot.fans.isEmpty
            && error != .noFans
            && error != .unsupportedHardware
            && error != .alreadyControlled
    }

    private var canConfigure: Bool {
        controlsCanAppear
    }

    private var controlsDisabled: Bool {
        isWorking || accessState != .enabled || error == .helperUnavailable
    }

    private var selectedCoolingLevel: Int {
        let clamped = min(max(coolingLevel, FanControlPolicy.minimumCoolingLevel),
                          FanControlPolicy.maximumCoolingLevel)
        let remainder = clamped % FanControlPolicy.coolingLevelStep
        return remainder == 0 ? clamped : clamped + FanControlPolicy.coolingLevelStep - remainder
    }

    private var coolingLevelBinding: Binding<Double> {
        Binding(
            get: { Double(selectedCoolingLevel) },
            set: { coolingLevel = Int($0.rounded()) }
        )
    }

    private var curveCanRun: Bool {
        guard FanControlPolicy.validCurves(curves) else { return false }
        let available = Set((snapshot.temperatures ?? []).map(\.source))
        return curves.allSatisfy { available.contains($0.sensor) }
    }
}
