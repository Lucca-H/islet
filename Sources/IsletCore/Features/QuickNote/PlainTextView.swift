import AppKit
import SwiftUI

/// An `NSTextView` with **all** built-in insets zeroed, so its first glyph sits at
/// the view's exact origin.
///
/// SwiftUI's `TextEditor` applies its own `textContainerInset` and
/// `lineFragmentPadding`, whose values aren't publicly specified. Overlaying a
/// placeholder on top means hand-guessing padding to match, which is what made the
/// Quick Note placeholder sit slightly off from the real cursor. With both insets at
/// zero, placeholder and text can share one origin by construction instead of by
/// approximation — whatever padding the caller applies lands on both equally.
struct PlainTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var font: NSFont
    var textColor: NSColor

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        // The two insets that would otherwise offset text from the view origin.
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.font = font
        textView.textColor = textColor
        textView.insertionPointColor = textColor
        textView.string = text
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Only write back when genuinely different, or we'd stomp the insertion point
        // on every keystroke.
        if textView.string != text { textView.string = text }
        textView.font = font
        textView.textColor = textColor
        textView.insertionPointColor = textColor
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let parent: PlainTextView

        init(_ parent: PlainTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.isFocused = true
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.isFocused = false
        }
    }
}
