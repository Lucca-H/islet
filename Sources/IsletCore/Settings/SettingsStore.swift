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

/// The notch's surface material — kept identical across collapsed, peek, and
/// expanded states, so nothing changes color when the notch resizes.
enum NotchMaterial: String, CaseIterable, Identifiable {
    case liquidGlass
    case solid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .liquidGlass: return "Liquid Glass"
        case .solid:       return "Solid"
        }
    }

    /// The material Islet ships with when it has a choice. Glass is the whole point
    /// of the notch's look, so it wins wherever the OS can actually draw it.
    static var preferredDefault: NotchMaterial {
        SystemCapabilities.supportsLiquidGlass ? .liquidGlass : .solid
    }

    /// The materials this Mac can offer. Below macOS 26 there is no real Liquid
    /// Glass, so the picker collapses to a single choice rather than showing an
    /// option that would quietly render as something else.
    static var available: [NotchMaterial] {
        SystemCapabilities.supportsLiquidGlass ? allCases : [.solid]
    }

    /// Coerce a material to one this Mac can render.
    ///
    /// A stored `liquidGlass` can arrive on a pre-26 Mac in ordinary ways — an
    /// iCloud-synced defaults domain, or a disk moved to older hardware — and it
    /// would otherwise leave the picker with no selected row and the notch drawing
    /// a material the user never chose.
    var supported: NotchMaterial {
        Self.available.contains(self) ? self : .solid
    }
}

/// Which way the collapsed pill grows when a live activity peeks.
///
/// `.down` keeps the pill centered on the notch and grows past the notch band so
/// its text clears the camera housing. `.left` and `.right` instead pin the pill's
/// opposite edge and extend it sideways into the menu-bar strip flanking the notch —
/// real, displayable pixels, so the row needs no vertical growth at all.
enum PeekDirection: String, CaseIterable, Identifiable {
    case down
    case left
    case right

    var id: String { rawValue }

    var label: String {
        switch self {
        case .down:  return "Down"
        case .left:  return "Left"
        case .right: return "Right"
        }
    }

    /// Sideways growth keeps the pill inside the menu-bar band; `.down` leaves it.
    var isLateral: Bool { self != .down }

    /// Which way the pill's extra width extends: -1 leftward, +1 rightward, 0 for
    /// a downward peek that stays centered on the notch.
    var lateralSign: CGFloat {
        switch self {
        case .down:  return 0
        case .left:  return -1
        case .right: return 1
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
    @Published var quickNoteEnabled: Bool  { didSet { persist(oldValue, quickNoteEnabled, "quickNoteEnabled") } }

    // MARK: Notch behavior
    @Published var expandTrigger: ExpandTrigger { didSet { persistRaw(oldValue.rawValue, expandTrigger.rawValue, "expandTrigger") } }
    @Published var hoverOpenDelay: Double  { didSet { persist(oldValue, hoverOpenDelay, "hoverOpenDelay") } }
    @Published var hoverCloseDelay: Double { didSet { persist(oldValue, hoverCloseDelay, "hoverCloseDelay") } }
    @Published var hapticFeedback: Bool    { didSet { persist(oldValue, hapticFeedback, "hapticFeedback") } }
    @Published var peekMediaArt: Bool      { didSet { persist(oldValue, peekMediaArt, "peekMediaArt") } }
    @Published var peekDirection: PeekDirection { didSet { persistRaw(oldValue.rawValue, peekDirection.rawValue, "peekDirection") } }
    /// Off by default: this requires granting Screen & System Audio Recording
    /// permission, a materially heavier ask than anything else Islet does.
    @Published var audioVisualizerEnabled: Bool { didSet { persist(oldValue, audioVisualizerEnabled, "audioVisualizerEnabled") } }

    // MARK: Notch size / shape
    @Published var notchMaterial: NotchMaterial { didSet { persistRaw(oldValue.rawValue, notchMaterial.rawValue, "notchMaterial") } }
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
        quickNoteEnabled  = defaults.object(forKey: "quickNoteEnabled")  as? Bool ?? true

        let trigger = defaults.string(forKey: "expandTrigger").flatMap(ExpandTrigger.init) ?? .hover
        expandTrigger = trigger
        hoverOpenDelay  = defaults.object(forKey: "hoverOpenDelay")  as? Double ?? 0.05
        hoverCloseDelay = defaults.object(forKey: "hoverCloseDelay") as? Double ?? 0.35
        hapticFeedback  = defaults.object(forKey: "hapticFeedback")  as? Bool ?? true
        peekMediaArt    = defaults.object(forKey: "peekMediaArt")    as? Bool ?? true
        peekDirection   = defaults.string(forKey: "peekDirection").flatMap(PeekDirection.init) ?? .down
        audioVisualizerEnabled = defaults.object(forKey: "audioVisualizerEnabled") as? Bool ?? false

        let material = defaults.string(forKey: "notchMaterial").flatMap(NotchMaterial.init)
            ?? NotchMaterial.preferredDefault
        notchMaterial = material.supported
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
        quickNoteEnabled = true
        expandTrigger = .hover
        hoverOpenDelay = 0.05
        hoverCloseDelay = 0.35
        hapticFeedback = true
        peekMediaArt = true
        peekDirection = .down
        audioVisualizerEnabled = false
        notchMaterial = .preferredDefault
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
