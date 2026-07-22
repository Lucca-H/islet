import SwiftUI
import AppKit

/// Expanded Quick Note panel: one plain text scratchpad, autosaved as you type.
struct QuickNoteView: View {
    @EnvironmentObject var vm: NotchViewModel
    @State private var isFocused = false

    private static let fontSize: CGFloat = 13

    /// The same typeface in both AppKit and SwiftUI terms, so the placeholder and
    /// the real text share identical metrics as well as an identical origin.
    private static var editorFont: NSFont {
        let base = NSFont.systemFont(ofSize: fontSize)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded),
              let rounded = NSFont(descriptor: descriptor, size: fontSize) else { return base }
        return rounded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            editor
            footer
        }
    }

    /// Placeholder and text view are both top-leading in the same `ZStack` with no
    /// padding of their own, and `PlainTextView` zeroes its insets — so they render
    /// from the exact same origin rather than from hand-matched padding.
    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if vm.quickNote.text.isEmpty && !isFocused {
                Text("Jot something down…")
                    .font(.system(size: Self.fontSize, design: .rounded))
                    .foregroundStyle(.white.opacity(0.3))
                    .allowsHitTesting(false)
            }
            PlainTextView(text: noteBinding,
                          isFocused: $isFocused,
                          font: Self.editorFont,
                          textColor: NSColor.white.withAlphaComponent(0.9))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// `quickNote` is a reference type held on `vm`; `$vm.quickNote.text` can't form
    /// a binding through it directly, so bridge one by hand.
    private var noteBinding: Binding<String> {
        Binding(get: { vm.quickNote.text }, set: { vm.quickNote.text = $0 })
    }

    private var footer: some View {
        HStack {
            if let edited = vm.quickNote.lastEditedAt {
                Text("Edited \(edited, style: .relative) ago")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
            }
            Spacer()
            Button("Clear") { vm.quickNote.clear() }
                .buttonStyle(.outlineText)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .disabled(vm.quickNote.text.isEmpty)
        }
    }
}
