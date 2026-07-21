import SwiftUI

/// Expanded Quick Note panel: one plain text scratchpad, autosaved as you type.
struct QuickNoteView: View {
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            editor
            footer
        }
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if vm.quickNote.text.isEmpty {
                Text("Jot something down…")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
            TextEditor(text: noteBinding)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .scrollContentBackground(.hidden)
                .background(Color.clear)
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
                .buttonStyle(.glass)
                .controlSize(.small)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .disabled(vm.quickNote.text.isEmpty)
        }
    }
}
