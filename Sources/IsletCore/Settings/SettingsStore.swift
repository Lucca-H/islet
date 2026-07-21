import Foundation
import SwiftUI
import Combine

/// Which screens Islet should attach a notch surface to.
enum ScreenTargeting: String, CaseIterable, Identifiable {
    case builtInOnly     // only the screen that physically has a notch (or the main screen)
    case primaryOnly     // the main screen, notch or not
    case allScreens      // every connected screen

    var id: String { rawValue }

    var label: String {
        switch self {
        case .builtInOnly: return "Built-in display"
        case .primaryOnly: return "Primary display"
        case .allScreens:  return "All displays"
        }
    }
}

/// How the notch reacts to the pointer.
enum ExpandTrigger: String, CaseIterable, Identifiable {
    case hover
    case click

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hover: return "Hover"
        case .click: return "Click"
        }
    }
}

/// Central, observable, persisted configuration for the whole app.
///
/// Every property mirrors a `UserDefaults` key so settings survive relaunches.
/// Views observe this object; changing a value updates the live notch instantly.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private let defaults: UserDefaults
    private var isLoading = false

    // MARK: Feature toggles
    @Published var nowPlayingEnabled: Bool { didSet { persist(oldValue, nowPlayingEnabled, "nowPlayingEnabled") } }
    @Published var dropShelfEnabled: Bool  { didSet { persist(oldValue, dropShelfEnabled, "dropShelfEnabled") } }
    @Published var clipboardEnabled: Bool  { didSet { persist(oldValue, clipboardEnabled, "clipboardEnabled") } }

    // MARK: Notch behavior
    @Published var expandTrigger: ExpandTrigger { didSet { persistRaw(oldValue.rawValue, expandTrigger.rawValue, "expandTrigger") } }
    @Published var hoverOpenDelay: Double  { didSet { persist(oldValue, hoverOpenDelay, "hoverOpenDelay") } }
    @Published var hoverCloseDelay: Double { didSet { persist(oldValue, hoverCloseDelay, "hoverCloseDelay") } }
    @Published var hapticFeedback: Bool    { didSet { persist(oldValue, hapticFeedback, "hapticFeedback") } }
    @Published var peekMediaArt: Bool      { didSet { persist(oldValue, peekMediaArt, "peekMediaArt") } }

    // MARK: Notch size / shape
    @Published var expandedWidth: Double   { didSet { persist(oldValue, expandedWidth, "expandedWidth") } }
    @Published var expandedHeight: Double  { didSet { persist(oldValue, expandedHeight, "expandedHeight") } }
    @Published var cornerRadius: Double    { didSet { persist(oldValue, cornerRadius, "cornerRadius") } }
    @Published var closedHeightBoost: Double { didSet { persist(oldValue, closedHeightBoost, "closedHeightBoost") } }

    // MARK: Screens
    @Published var screenTargeting: ScreenTargeting { didSet { persistRaw(oldValue.rawValue, screenTargeting.rawValue, "screenTargeting") } }

    // MARK: Clipboard
    @Published var clipboardLimit: Int      { didSet { persist(oldValue, clipboardLimit, "clipboardLimit") } }
    @Published var clipboardStoreImages: Bool { didSet { persist(oldValue, clipboardStoreImages, "clipboardStoreImages") } }
    @Published var clipboardIgnoreConcealed: Bool { didSet { persist(oldValue, clipboardIgnoreConcealed, "clipboardIgnoreConcealed") } }

    // MARK: General
    @Published var launchAtLogin: Bool {
        didSet {
            guard !isLoading else { return }
            defaults.set(launchAtLogin, forKey: "launchAtLogin")
            LaunchAtLogin.isEnabled = launchAtLogin
        }
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isLoading = true

        nowPlayingEnabled = defaults.object(forKey: "nowPlayingEnabled") as? Bool ?? true
        dropShelfEnabled  = defaults.object(forKey: "dropShelfEnabled")  as? Bool ?? true
        clipboardEnabled  = defaults.object(forKey: "clipboardEnabled")  as? Bool ?? true

        let trigger = defaults.string(forKey: "expandTrigger").flatMap(ExpandTrigger.init) ?? .hover
        expandTrigger = trigger
        hoverOpenDelay  = defaults.object(forKey: "hoverOpenDelay")  as? Double ?? 0.05
        hoverCloseDelay = defaults.object(forKey: "hoverCloseDelay") as? Double ?? 0.35
        hapticFeedback  = defaults.object(forKey: "hapticFeedback")  as? Bool ?? true
        peekMediaArt    = defaults.object(forKey: "peekMediaArt")    as? Bool ?? true

        expandedWidth   = defaults.object(forKey: "expandedWidth")   as? Double ?? 640
        expandedHeight  = defaults.object(forKey: "expandedHeight")  as? Double ?? 210
        cornerRadius    = defaults.object(forKey: "cornerRadius")    as? Double ?? 22
        closedHeightBoost = defaults.object(forKey: "closedHeightBoost") as? Double ?? 0

        let targeting = defaults.string(forKey: "screenTargeting").flatMap(ScreenTargeting.init) ?? .builtInOnly
        screenTargeting = targeting

        clipboardLimit = defaults.object(forKey: "clipboardLimit") as? Int ?? 50
        clipboardStoreImages = defaults.object(forKey: "clipboardStoreImages") as? Bool ?? true
        clipboardIgnoreConcealed = defaults.object(forKey: "clipboardIgnoreConcealed") as? Bool ?? true

        launchAtLogin = defaults.object(forKey: "launchAtLogin") as? Bool ?? false

        isLoading = false
    }

    /// Restore every value to its shipped default.
    func resetToDefaults() {
        nowPlayingEnabled = true
        dropShelfEnabled = true
        clipboardEnabled = true
        expandTrigger = .hover
        hoverOpenDelay = 0.05
        hoverCloseDelay = 0.35
        hapticFeedback = true
        peekMediaArt = true
        expandedWidth = 640
        expandedHeight = 210
        cornerRadius = 22
        closedHeightBoost = 0
        screenTargeting = .builtInOnly
        clipboardLimit = 50
        clipboardStoreImages = true
        clipboardIgnoreConcealed = true
    }

    private func persist<T: Equatable>(_ old: T, _ new: T, _ key: String) {
        guard !isLoading, old != new else { return }
        defaults.set(new, forKey: key)
    }

    private func persistRaw(_ old: String, _ new: String, _ key: String) {
        guard !isLoading, old != new else { return }
        defaults.set(new, forKey: key)
    }
}
