// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Panel section with one brightness slider per adjustable display. Values
/// refresh whenever the section appears, so changes made with the keyboard,
/// in System Settings or on the monitor itself are picked up.
struct BrightnessSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = BrightnessService.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var xdrService = XDRBoostService.shared
    @ObservedObject private var extraBrightnessService = ExtraBrightnessService.shared
    @AppStorage(DefaultsKey.brightnessOSDEnabled) private var brightnessOSDEnabled = false
    @AppStorage(DefaultsKey.brightnessKeysEnabled) private var brightnessKeysEnabled = false
    @AppStorage(DefaultsKey.extraBrightnessEnabled) private var extraBrightnessEnabled = false
    @AppStorage(DefaultsKey.extraBrightnessLevel) private var extraBrightnessLevel = 100
    @State private var optionsExpanded = false
    var collapsible = true

    private var strings: BrightnessFeatureStrings { FeatureStrings.brightness(l10n.language) }

    var body: some View {
        PanelSection(.brightness, title: strings.pageTitle, collapsible: collapsible) {
            VStack(alignment: .leading, spacing: 10) {
                if service.displays.isEmpty {
                    Text(strings.noDisplays)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(service.displays) { display in
                        row(display)
                    }
                }
                if let failure = service.displayControlFailure {
                    Text(displayControlFailureText(failure, strings: strings))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.red)
                }
                if service.brightnessOSDSupported {
                    Divider()
                    Toggle(strings.osdToggle, isOn: $brightnessOSDEnabled)
                        .font(.system(size: 10.5, weight: .medium))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .help(strings.osdCaption)
                        .onChange(of: brightnessOSDEnabled) { _, isOn in
                            if isOn { permissions.requestAccessibility() }
                            service.syncWithPreferences()
                        }
                }

                Divider()
                optionsDisclosure
            }
            .panelCard()
            .onAppear { service.refresh() }
        }
    }

    private var optionsDisclosure: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                optionsExpanded.toggle()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                        .rotationEffect(.degrees(optionsExpanded ? 90 : 0))
                    Text(l10n.s.keepAwakeOptions)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if optionsExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(strings.keysToggle, isOn: $brightnessKeysEnabled)
                        .onChange(of: brightnessKeysEnabled) { _, isOn in
                            if isOn { permissions.requestAccessibility() }
                            service.syncWithPreferences()
                        }
                    Text(strings.keysCaption)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if brightnessKeysEnabled, !permissions.accessibility {
                        Button {
                            permissions.openAccessibilitySettings()
                        } label: {
                            Label(l10n.s.permissionOpenSettings, systemImage: "hand.raised")
                        }
                        .buttonStyle(.link)
                    }
                    DisplayBrightnessShortcutControls()
                }
                .font(.system(size: 11.5, weight: .medium))
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .padding(.leading, 19)
            }
        }
    }

    private func isEDRSupported(for display: BrightnessDisplay) -> Bool {
        AppFeature.extraBrightness.isAvailable && xdrService.isEDRSupported(for: display.id)
    }

    private func isOverdrive(for display: BrightnessDisplay) -> Bool {
        guard isEDRSupported(for: display) else { return false }
        if display.isBuiltIn {
            return extraBrightnessEnabled || xdrService.isEnabled(for: display.id)
        }
        return xdrService.isEnabled(for: display.id)
    }

    private func maxHeadroom(for display: BrightnessDisplay) -> Double {
        min(XDRBoostService.maxBoost, max(XDRBoostService.minBoost, xdrService.maximumHeadroom(for: display.id)))
    }

    private func sliderMax(for display: BrightnessDisplay) -> Double {
        isOverdrive(for: display) ? maxHeadroom(for: display) : 1.0
    }

    private func unifiedBrightness(for display: BrightnessDisplay) -> Double {
        guard isOverdrive(for: display) else {
            return display.brightness
        }

        let boost: Double
        if display.isBuiltIn {
            boost = 1.0 + (Double(extraBrightnessLevel) / 100.0)
        } else {
            boost = xdrService.currentMultiplier(for: display.id)
        }

        if boost > 1.001 && display.brightness >= 0.999 {
            return min(maxHeadroom(for: display), max(1.0, boost))
        } else {
            return display.brightness
        }
    }

    private func percentText(for display: BrightnessDisplay) -> String {
        let val = unifiedBrightness(for: display)
        return "\(Int((val * 100).rounded()))%"
    }

    private func toggleXDROverdrive(for display: BrightnessDisplay) {
        let currentlyActive = isOverdrive(for: display)
        let targetActive = !currentlyActive

        if targetActive {
            service.setBrightness(1.0, for: display.id, showOSD: false)
            if display.isBuiltIn {
                extraBrightnessEnabled = true
                if extraBrightnessLevel <= 0 {
                    extraBrightnessLevel = 50
                }
                extraBrightnessService.syncWithPreferences()
            }
            let mult = display.isBuiltIn ? (1.0 + Double(extraBrightnessLevel) / 100.0) : 1.5
            xdrService.setEDRBoost(displayID: display.id, enabled: true, multiplier: mult)
        } else {
            if display.isBuiltIn {
                extraBrightnessEnabled = false
                extraBrightnessService.syncWithPreferences()
            }
            xdrService.setEDRBoost(displayID: display.id, enabled: false)
            if display.brightness >= 0.999 {
                service.setBrightness(1.0, for: display.id, showOSD: false)
            }
        }
    }

    private func unifiedBrightnessBinding(_ display: BrightnessDisplay) -> Binding<Double> {
        Binding(
            get: { unifiedBrightness(for: display) },
            set: { newValue in
                guard newValue.isFinite else { return }
                if isOverdrive(for: display) {
                    if newValue <= 1.0 {
                        service.setBrightness(newValue, for: display.id, showOSD: brightnessOSDEnabled)
                        if display.isBuiltIn {
                            extraBrightnessLevel = 0
                            extraBrightnessService.levelDidChange()
                        }
                        xdrService.setMultiplier(1.0, for: display.id)
                    } else {
                        if display.brightness < 0.999 {
                            service.setBrightness(1.0, for: display.id, showOSD: false)
                        }
                        let clampedMult = min(maxHeadroom(for: display), max(1.0, newValue))
                        if display.isBuiltIn {
                            extraBrightnessEnabled = true
                            extraBrightnessLevel = Int(((clampedMult - 1.0) * 100).rounded())
                            extraBrightnessService.levelDidChange()
                            extraBrightnessService.syncWithPreferences()
                        }
                        xdrService.setMultiplier(clampedMult, for: display.id)
                    }
                } else {
                    service.setBrightness(newValue, for: display.id, showOSD: brightnessOSDEnabled)
                }
            }
        )
    }

    private func xdrPillButton(display: BrightnessDisplay, active: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                toggleXDROverdrive(for: display)
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: active ? "sun.max.fill" : "sun.max")
                    .font(.system(size: 8, weight: .bold))
                Text("XDR")
                    .font(.system(size: 8.5, weight: .bold))
            }
            .foregroundStyle(active ? Color.white : Color.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(active ? Color.orange : Color.primary.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .help(active ? l10n.s.extraBrightnessCaption : l10n.s.xdrBoostCaption)
    }

    private func row(_ display: BrightnessDisplay) -> some View {
        let hasEDR = isEDRSupported(for: display)
        let activeOverdrive = isOverdrive(for: display)
        let val = unifiedBrightness(for: display)
        let isBoosting = activeOverdrive && val > 1.001

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(display.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if hasEDR && display.isActive {
                    xdrPillButton(display: display, active: activeOverdrive)
                }
                if display.isActive, display.method != nil {
                    Text(percentText(for: display))
                        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(isBoosting ? Color.orange : Color.secondary)
                } else if !display.isActive {
                    Text(strings.displayOff)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                DisplayPowerButton(display: display, compact: true)
            }
            if display.isActive, display.method != nil {
                Slider(value: unifiedBrightnessBinding(display), in: 0...sliderMax(for: display))
                    .tint(isBoosting ? Color.orange : nil)
                    .controlSize(.small)
                    .disabled(service.isDisplayPending(display.id))
                    .accessibilityLabel(display.name)
            }
            if display.isActive {
                DisplayResolutionRow(displayID: display.id)
            }
            SoftwareDimmingButton(display: display, compact: true)
        }
    }
}

/// Shared routing choice, on every surface that shows the display rows: the
/// slider is just as dead on the Energy page as in the panel, so the way out
/// has to be there too.
///
/// Offered only where the routing is genuinely ambiguous: a channel that takes
/// writes and answers no reads either drives the panel or swallows everything,
/// and the bus cannot tell which (issue #1589). Stays visible once chosen, or
/// there would be no way back to DDC.
struct SoftwareDimmingButton: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = BrightnessService.shared
    let display: BrightnessDisplay
    var compact = false

    private var strings: BrightnessFeatureStrings { FeatureStrings.brightness(l10n.language) }
    private var chosen: Bool { service.softwareDimmingPreferred.contains(display.id) }

    private var offered: Bool {
        guard display.isActive, !display.isBuiltIn else { return false }
        if chosen { return true }
        return display.method == .ddc && !display.readable
    }

    var body: some View {
        if offered {
            Button {
                service.setSoftwareDimmingPreferred(!chosen, for: display.id)
            } label: {
                HStack(spacing: compact ? 4 : 5) {
                    Image(systemName: chosen ? "checkmark.circle.fill" : "circle.lefthalf.filled")
                        .font(.system(size: compact ? 9.5 : 11, weight: .semibold))
                    Text(strings.softwareDimming)
                        .font(.system(size: compact ? 10 : 12, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(chosen ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(service.isDisplayPending(display.id))
            .accessibilityLabel("\(display.name): \(strings.softwareDimming)")
        }
    }
}

/// Shared power affordance used by Settings and the menu bar panel. It stays
/// icon-only in the row, with a localized tooltip and accessibility label.
struct DisplayPowerButton: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = BrightnessService.shared
    let display: BrightnessDisplay
    var compact = false

    private var strings: BrightnessFeatureStrings { FeatureStrings.brightness(l10n.language) }
    private var pending: Bool { service.isDisplayPending(display.id) }
    private var enabled: Bool { service.canToggleDisplay(display) }

    private var label: String {
        if !service.displaySwitchingAvailable { return strings.switchUnavailable }
        if display.isActive, !enabled { return strings.lastDisplayCaption }
        return display.isActive ? strings.turnOffDisplay : strings.turnOnDisplay
    }

    var body: some View {
        Group {
            if pending {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: compact ? 16 : 20, height: 18)
                    .accessibilityLabel(label)
            } else {
                Button {
                    service.toggleDisplay(display)
                } label: {
                    Image(systemName: display.isActive ? "power" : "power.circle.fill")
                        .font(.system(size: compact ? 10.5 : 12, weight: .semibold))
                        .foregroundStyle(display.isActive ? AnyShapeStyle(.secondary)
                                                         : AnyShapeStyle(.green))
                        .frame(width: compact ? 16 : 20, height: 18)
                }
                .buttonStyle(.plain)
                .disabled(!enabled)
                .help(label)
                .accessibilityLabel(label)
            }
        }
    }
}

func displayControlFailureText(_ failure: BrightnessService.DisplayControlFailure,
                               strings: BrightnessFeatureStrings) -> String {
    switch failure {
    case .unavailable: return strings.switchUnavailable
    case .lastActive: return strings.lastDisplayCaption
    case .failed: return strings.switchFailed
    case .closedLid: return strings.openLidToEnable
    }
}

// MARK: - Display Resolution & HiDPI Controls

struct DisplayResolutionRow: View {
    @ObservedObject private var resolutionService = DisplayResolutionService.shared
    @ObservedObject private var l10n = L10n.shared
    let displayID: CGDirectDisplayID

    private var currentMode: DisplayResolutionMode? {
        resolutionService.currentModePerDisplay[displayID]
    }

    private var modes: [DisplayResolutionMode] {
        resolutionService.modesPerDisplay[displayID] ?? []
    }

    private var status: HiDPIStatus {
        resolutionService.hiDPIStatusPerDisplay[displayID] ?? .none
    }

    var body: some View {
        if let current = currentMode {
            HStack(spacing: 6) {
                // Resolution & Refresh rate menu
                Menu {
                    ForEach(modes) { mode in
                        Button {
                            resolutionService.applyMode(mode, for: displayID)
                        } label: {
                            HStack {
                                if mode.id == current.id {
                                    Image(systemName: "checkmark")
                                }
                                Text("\(mode.width) × \(mode.height)  ·  \(Int(mode.refreshRate.rounded())) Hz\(mode.isHiDPI ? " (HiDPI)" : "")")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text("\(current.width) × \(current.height)")
                            .font(.system(size: 10, weight: .medium).monospacedDigit())
                        Text("· \(Int(current.refreshRate.rounded())) Hz")
                            .font(.system(size: 9.5).monospacedDigit())
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Spacer(minLength: 4)

                // HiDPI Status Badge
                statusBadge(status)

                // Quick HiDPI Toggle Button
                Button {
                    resolutionService.toggleHiDPI(for: displayID)
                } label: {
                    Image(systemName: status != .none ? "sparkles.tv" : "tv")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(status != .none ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(l10n.s.toggleHiDPICaption)
            }
            .padding(.leading, 22)
            .padding(.top, 1)
            .onAppear {
                resolutionService.refresh()
            }
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: HiDPIStatus) -> some View {
        switch status {
        case .native:
            Text(l10n.s.nativeHiDPI)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Capsule().fill(Color.accentColor))
        case .virtualMirror:
            Text(l10n.s.virtualHiDPI)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Capsule().fill(Color.purple))
        case .none:
            Text(l10n.s.standardResolution)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
        }
    }
}

