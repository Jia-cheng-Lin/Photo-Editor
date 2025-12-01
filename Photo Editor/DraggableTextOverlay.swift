import SwiftUI

struct DraggableTextOverlay: View {
    @Binding var overlay: TextOverlay
    var isSelected: Bool
    var onTap: () -> Void

    @State private var dragOffset: CGSize = .zero

    // Keep padding in sync with Typing overlay and renderer
    private let horizontalPadding: CGFloat = 10
    private let verticalPadding: CGFloat = 6
    private let cornerRadius: CGFloat = 8

    var body: some View {
        ZStack {
            // Background rect centered at (0,0)
            if overlay.hasBackground, let size = backgroundContentSize() {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(overlay.backgroundColor)
                    .frame(width: size.width + horizontalPadding * 2,
                           height: size.height + verticalPadding * 2)
            }

            // Text centered at (0,0)
            Text(overlay.text)
                .font(fontForOverlay())
                .foregroundStyle(overlay.textColor)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background(
                    SizeReader { size in
                        if overlay.fixedBackgroundSize == nil {
                            overlay.measuredSize = size
                        }
                    }
                )
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.2, dash: [6, 4]))
                    }
                }
        }
        // Place the overlay so that its visual center is at canvasCenter + position
        .offset(x: overlay.position.width + dragOffset.width,
                y: overlay.position.height + dragOffset.height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation
                }
                .onEnded { value in
                    overlay.position.width += value.translation.width
                    overlay.position.height += value.translation.height
                    dragOffset = .zero
                }
        )
        .onTapGesture { onTap() }
        .animation(.snappy, value: overlay.position)
    }

    // Content size without paddings (same rule as Typing overlay)
    private func backgroundContentSize() -> CGSize? {
        if let fixed = overlay.fixedBackgroundSize { return fixed }
        return overlay.measuredSize == .zero ? nil : overlay.measuredSize
    }

    private func fontForOverlay() -> Font {
        if let name = overlay.fontName, !name.isEmpty {
            return .custom(name, size: overlay.fontSize).weight(overlay.fontWeight)
        } else {
            return .system(size: overlay.fontSize, weight: overlay.fontWeight)
        }
    }
}

// Helper to read rendered size of a view
private struct SizeReader: View {
    var onChange: (CGSize) -> Void
    var body: some View {
        GeometryReader { geo in
            Color.clear
                .preference(key: SizePreferenceKey.self, value: geo.size)
        }
        .onPreferenceChange(SizePreferenceKey.self, perform: onChange)
    }
}

private struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
