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
            sliderRow("Expanded width", value: $settings.expandedWidth, range: 420...900, unit: "pt", step: 10)
            sliderRow("Expanded height", value: $settings.expandedHeight, range: 140...340, unit: "pt", step: 10)
            sliderRow("Corner radius", value: $settings.cornerRadius, range: 8...40, unit: "pt")
            sliderRow("Closed height boost", value: $settings.closedHeightBoost, range: 0...16, unit: "pt")
            Toggle("Peek album art when playing", isOn: $settings.peekMediaArt)
        }
        .formStyle(.grouped)
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
    VStack(alignment: .leading, spacing: 2) {
        HStack {
            Text(title)
            Spacer()
            Text("\(value.wrappedValue, specifier: step < 1 ? "%.2f" : "%.0f")\(unit)")
                .foregroundStyle(.secondary).monospacedDigit()
        }
        Slider(value: value, in: range, step: step)
    }
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
