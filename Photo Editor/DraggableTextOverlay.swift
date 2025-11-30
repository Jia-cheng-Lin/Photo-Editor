import SwiftUI

struct DraggableTextOverlay: View {
    @Binding var overlay: TextOverlay
    var isSelected: Bool
    var onTap: () -> Void

    @State private var dragOffset: CGSize = .zero

    private let cornerRadius: CGFloat = 8

    var body: some View {
        textView
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.2, dash: [6, 4]))
                }
            }
            .offset(x: overlay.position.width + dragOffset.width,
                    y: overlay.position.height + dragOffset.height)
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
            .onTapGesture {
                onTap()
            }
            .animation(.snappy, value: overlay.position)
    }

    private var textView: some View {
        var font: Font
        if let name = overlay.fontName, !name.isEmpty {
            font = .custom(name, size: overlay.fontSize).weight(overlay.fontWeight)
        } else {
            font = .system(size: overlay.fontSize, weight: overlay.fontWeight)
        }

        return Text(overlay.text)
            .font(font)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(overlay.hasBackground ? overlay.backgroundColor : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(overlay.hasBackground ? Color.black.opacity(0.2) : Color.clear, lineWidth: 1)
            )
            .foregroundStyle(overlay.textColor)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
