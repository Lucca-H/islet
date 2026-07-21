import SwiftUI
import UniformTypeIdentifiers

/// Expanded shelf: a grid of files you've dropped, each draggable back out.
struct DropShelfView: View {
    @EnvironmentObject var vm: NotchViewModel

    private var items: [ShelfItem] { vm.shelf.items }

    private let columns = [GridItem(.adaptive(minimum: 84, maximum: 110), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            if items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(items) { item in
                            ShelfTile(item: item)
                                .environmentObject(vm)
                        }
                    }
                    .padding(.vertical, 4)
                }
                footer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 28)).foregroundStyle(.white.opacity(0.35))
            Text("Drop files here")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.6))
            Text("Drag anything onto the notch to stash it")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .foregroundStyle(.white.opacity(vm.isDropTargeted ? 0.5 : 0.15))
        )
    }

    private var footer: some View {
        HStack {
            Text("^[\(items.count) item](inflect: true)")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
            Spacer()
            Button("Clear All") { vm.shelf.clear() }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.top, 6)
    }
}

private struct ShelfTile: View {
    let item: ShelfItem
    @EnvironmentObject var vm: NotchViewModel
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: item.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 44, height: 44)
            Text(item.name)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(width: 92, height: 84)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(hovering ? 0.1 : 0.05)))
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button {
                    vm.shelf.remove(item)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.8), .black.opacity(0.5))
                }
                .buttonStyle(.plain)
                .padding(4)
            }
        }
        .onHover { hovering = $0 }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .onTapGesture(count: 2) { vm.shelf.revealInFinder(item) }
        .help(item.name)
    }
}
