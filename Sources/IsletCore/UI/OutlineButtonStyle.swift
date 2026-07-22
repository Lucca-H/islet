import SwiftUI

/// A button drawn as a thin outline rather than a filled shape.
///
/// The system `.glass` style fills its whole background, which reads as heavy on
/// the notch's dark surface — the fill competes with the album art next to it. This
/// keeps the control legible with just a stroke, brightening the outline on hover
/// and dimming briefly on press instead of swapping the background colour.
struct OutlineButtonStyle: ButtonStyle {
    var diameter: CGFloat
    /// Circular for transport controls; rounded-rect reads better for wider buttons.
    var isCircular: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        OutlineButton(configuration: configuration, diameter: diameter, isCircular: isCircular)
    }

    private struct OutlineButton: View {
        let configuration: Configuration
        let diameter: CGFloat
        let isCircular: Bool
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .frame(width: diameter, height: diameter)
                .background {
                    // A barely-there fill keeps the glyph readable over bright
                    // artwork without becoming a solid button.
                    shape.fill(Color.white.opacity(configuration.isPressed ? 0.18 : (isHovering ? 0.10 : 0.04)))
                }
                .overlay {
                    shape.stroke(Color.white.opacity(isHovering ? 0.55 : 0.28), lineWidth: 1)
                }
                .foregroundStyle(.white.opacity(configuration.isPressed ? 0.7 : 1))
                .scaleEffect(configuration.isPressed ? 0.94 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.12), value: isHovering)
                .onHover { isHovering = $0 }
                .contentShape(shape)
        }

        private var shape: AnyShape {
            isCircular ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

extension ButtonStyle where Self == OutlineButtonStyle {
    static func outline(diameter: CGFloat, isCircular: Bool = true) -> OutlineButtonStyle {
        OutlineButtonStyle(diameter: diameter, isCircular: isCircular)
    }
}

/// The same outlined treatment for text buttons, which need to size to their label
/// rather than to a fixed square.
struct OutlineTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        OutlineTextButton(configuration: configuration)
    }

    private struct OutlineTextButton: View {
        let configuration: Configuration
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background {
                    Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.16 : (isHovering ? 0.09 : 0.03)))
                }
                .overlay {
                    Capsule().stroke(Color.white.opacity(isHovering ? 0.5 : 0.25), lineWidth: 1)
                }
                .foregroundStyle(.white.opacity(configuration.isPressed ? 0.7 : 0.85))
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.12), value: isHovering)
                .onHover { isHovering = $0 }
                .contentShape(Capsule())
        }
    }
}

extension ButtonStyle where Self == OutlineTextButtonStyle {
    static var outlineText: OutlineTextButtonStyle { OutlineTextButtonStyle() }
}
