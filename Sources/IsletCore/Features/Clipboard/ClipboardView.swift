import SwiftUI

/// Expanded clipboard history: a scrollable list; click an entry to re-copy it.
struct ClipboardView: View {
    @EnvironmentObject var vm: NotchViewModel

    private var items: [ClipItem] { vm.clipboard.items }

    var body: some View {
        VStack(spacing: 0) {
            if items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(items) { item in
                            ClipRow(item: item).environmentObject(vm)
                        }
                    }
                }
                footer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 26)).foregroundStyle(.white.opacity(0.35))
            Text("No clipboard history yet")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.6))
            Text("Copy some text or an image to get started")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            Text("^[\(items.count) item](inflect: true)")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
            Spacer()
            Button("Clear") { vm.clipboard.clear() }
                .buttonStyle(.outlineText)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.top, 6)
    }
}

private struct ClipRow: View {
    let item: ClipItem
    @EnvironmentObject var vm: NotchViewModel
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))

            preview
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)

            Spacer(minLength: 0)

            if hovering {
                Button {
                    vm.clipboard.delete(item)
                } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(hovering ? 0.1 : 0.04)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { vm.clipboard.copyToPasteboard(item) }
        .help("Click to copy")
    }

    @ViewBuilder
    private var icon: some View {
        switch item.kind {
        case .text:
            Image(systemName: "text.alignleft").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
        case let .image(image):
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch item.kind {
        case let .text(value):
            Text(value.trimmingCharacters(in: .whitespacesAndNewlines))
        case .image:
            Text("Image").foregroundStyle(.white.opacity(0.6))
        }
    }
}
