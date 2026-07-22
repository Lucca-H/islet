import SwiftUI

/// The full configuration surface, presented in a standard window with a sidebar.
struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var section: Section = .general

    enum Section: String, CaseIterable, Identifiable {
        case general, appearance, features, clipboard, about
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: return "General"
            case .appearance: return "Notch"
            case .features: return "Features"
            case .clipboard: return "Clipboard"
            case .about: return "About"
            }
        }
        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .appearance: return "macwindow"
            case .features: return "square.grid.2x2"
            case .clipboard: return "doc.on.clipboard"
            case .about: return "info.circle"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $section) { item in
                Label(item.title, systemImage: item.symbol).tag(item)
            }
            .navigationSplitViewColumnWidth(180)
        } detail: {
            ScrollView {
                Group {
                    switch section {
                    case .general: GeneralSettings()
                    case .appearance: NotchSettings()
                    case .features: FeatureSettings()
                    case .clipboard: ClipboardSettings()
                    case .about: AboutSettings()
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(section.title)
        }
        .frame(width: 640, height: 460)
    }
}

// MARK: - Sections

private struct GeneralSettings: View {
    @EnvironmentObject var settings: SettingsStore
    var body: some View {
        Form {
            Toggle("Launch Islet at login", isOn: $settings.launchAtLogin)

            Picker("Expand the notch on", selection: $settings.expandTrigger) {
                ForEach(ExpandTrigger.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            if settings.expandTrigger == .hover {
                sliderRow("Open delay", value: $settings.hoverOpenDelay, range: 0...0.6, unit: "s")
                sliderRow("Close delay", value: $settings.hoverCloseDelay, range: 0...1.2, unit: "s")
            }

            Toggle("Haptic feedback on open", isOn: $settings.hapticFeedback)

            Picker("Show notch on", selection: $settings.screenTargeting) {
                ForEach(ScreenTargeting.allCases) { Text($0.label).tag($0) }
            }
        }
        .formStyle(.grouped)
    }
}

private struct NotchSettings: View {
    @EnvironmentObject var settings: SettingsStore
    var body: some View {
        Form {
            Picker("Notch style", selection: $settings.notchMaterial) {
                ForEach(NotchMaterial.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(settings.notchMaterial == .liquidGlass
                 ? "Translucent, refracts whatever is behind the notch. Requires macOS 26."
                 : "Opaque, matching the physical notch bezel.")
                .font(.footnote).foregroundStyle(.secondary)

            sliderRow("Expanded width", value: $settings.expandedWidth, range: 420...900, unit: "pt", step: 10)
            sliderRow("Expanded height", value: $settings.expandedHeight, range: 140...340, unit: "pt", step: 10)
            sliderRow("Corner radius", value: $settings.cornerRadius, range: 8...40, unit: "pt")
            sliderRow("Closed height boost", value: $settings.closedHeightBoost, range: 0...16, unit: "pt")
            Toggle("Peek album art when playing", isOn: $settings.peekMediaArt)

            Section("Audio visualizer") {
                AudioVisualizerSettingsRow()
            }
        }
        .formStyle(.grouped)
    }
}

/// Real frequency-band audio bars, driven by actual system audio via
/// ScreenCaptureKit — opt-in, since it needs Screen & System Audio Recording
/// permission, the heaviest ask anywhere in Islet.
private struct AudioVisualizerSettingsRow: View {
    @EnvironmentObject var settings: SettingsStore
    @ObservedObject private var engine = AudioVisualizerEngine.shared

    var body: some View {
        Toggle("Real audio visualizer", isOn: $settings.audioVisualizerEnabled)
            .onChange(of: settings.audioVisualizerEnabled) { _, enabled in
                if enabled, !engine.isAuthorized { engine.requestAccess() }
            }

        Text("Replaces the collapsed notch's audio bars with a live frequency visualizer of whatever's actually playing, instead of a decorative animation. This is also the only way Islet can tell that **browser audio** is playing, since Now Playing can't see browsers.\n\nRequires granting **Screen & System Audio Recording** — the same permission Zoom or OBS use — even though only the audio channel is ever read. macOS keeps its screen-recording indicator up for as long as this is switched on.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        if settings.audioVisualizerEnabled {
            HStack {
                statusIndicator
                Text(statusText).font(.footnote).foregroundStyle(.secondary)
                Spacer()
                if !engine.isAuthorized {
                    Button("Open System Settings…") { engine.openSystemSettings() }
                        .controlSize(.small)
                }
            }

            if let error = engine.lastError {
                Text("Last error: \(error)")
                    .font(.footnote)
                    .foregroundStyle(.red.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !engine.isAuthorized {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Already enabled Islet in System Settings but still seeing this? Islet is ad-hoc signed, so its code signature changes every time it's rebuilt — and macOS ties the permission to that signature. The existing “Islet” entry belongs to an older build and can't be fixed by toggling it. Resetting removes it so the next launch can ask again.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Reset Permission & Quit Islet…") { engine.resetPermissionAndQuit() }
                        .controlSize(.small)
                }
            }

            DiagnosticLogDisclosure()
        }
    }

    private var statusIndicator: some View {
        Circle()
            .fill(engine.isCapturing ? Color.green : (engine.isAuthorized ? Color.yellow : Color.red))
            .frame(width: 7, height: 7)
    }

    private var statusText: String {
        if engine.isCapturing {
            return engine.hasSignal ? "Capturing — audio detected" : "Capturing — no audio right now"
        }
        if engine.isAuthorized { return "Authorized — starting…" }
        return "Not authorized — checking again automatically"
    }
}

/// A copyable diagnostic log for the audio capture pipeline. Exists so a debugging
/// round trip is "open Settings, copy, paste" instead of "open Terminal, run
/// `defaults read`" — collapsed by default since it's only useful when something's
/// actually wrong.
private struct DiagnosticLogDisclosure: View {
    @State private var isExpanded = false

    private var entries: [String] {
        UserDefaults.standard.stringArray(forKey: "visualizerDebugLog") ?? []
    }

    var body: some View {
        DisclosureGroup("Diagnostic log (\(entries.count))", isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 4) {
                if entries.isEmpty {
                    Text("No entries yet.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                                Text(entry)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 140)

                    Button("Copy Log") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entries.joined(separator: "\n"), forType: .string)
                    }
                    .controlSize(.small)
                }
            }
            .padding(.top, 4)
        }
        .font(.footnote)
    }
}

private struct FeatureSettings: View {
    @EnvironmentObject var settings: SettingsStore
    var body: some View {
        Form {
            Section("Enabled features") {
                Toggle("Now Playing", isOn: $settings.nowPlayingEnabled)
                Toggle("Drop Shelf", isOn: $settings.dropShelfEnabled)
                Toggle("Clipboard History", isOn: $settings.clipboardEnabled)
                Toggle("Quick Note", isOn: $settings.quickNoteEnabled)
            }
            Text("Disabled features are hidden from the notch tab bar.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct ClipboardSettings: View {
    @EnvironmentObject var settings: SettingsStore
    var body: some View {
        Form {
            Stepper(value: $settings.clipboardLimit, in: 5...200, step: 5) {
                Text("Keep last \(settings.clipboardLimit) items")
            }
            Toggle("Store copied images", isOn: $settings.clipboardStoreImages)
            Toggle("Ignore passwords & transient copies", isOn: $settings.clipboardIgnoreConcealed)
            Text("Concealed items (from password managers) are never recorded when this is on.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct AboutSettings: View {
    @EnvironmentObject var settings: SettingsStore
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 36))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading) {
                    Text("Islet").font(.title2).bold()
                    Text("Version \(AppInfo.version) (\(AppInfo.build)) · Beta")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Text("Islet turns your Mac's notch into a live hub for media, files, and your clipboard.")
                .foregroundStyle(.secondary)
            Divider()
            Button("Reset all settings to defaults") { settings.resetToDefaults() }
            Spacer()
        }
    }
}

// MARK: - Helpers

@ViewBuilder
private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String, step: Double = 0.05) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        HStack {
            Text(title)
            Spacer()
            Text("\(value.wrappedValue, specifier: step < 1 ? "%.2f" : "%.0f")\(unit)")
                .foregroundStyle(.secondary).monospacedDigit()
        }
        GlassSlider(value: value, range: range, step: step)
    }
    .padding(.vertical, 4)
}

/// Bundle-derived app metadata used across the UI.
enum AppInfo {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
