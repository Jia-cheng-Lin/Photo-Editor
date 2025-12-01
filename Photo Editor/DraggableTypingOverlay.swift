import SwiftUI

// Draggable typing overlay used in IGTextAddView
struct DraggableTypingOverlay: View {
    @Binding var overlay: TextOverlay
    var isSelected: Bool
    var onBeginDrag: () -> Void
    var onEndDrag: (CGRect) -> Void
    @FocusState var textFieldFocused: Bool

    @State private var dragOffset: CGSize = .zero
    @State private var frameInCanvas: CGRect = .zero

    var body: some View {
        textFieldView
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { updateFrame(geo: geo) }
                        .onChange(of: geo.size) { _, _ in updateFrame(geo: geo) }
                        .onChange(of: overlay.position) { _, _ in updateFrame(geo: geo) }
                }
            )
            .offset(x: overlay.position.width + dragOffset.width,
                    y: overlay.position.height + dragOffset.height)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation
                        onBeginDrag()
                    }
                    .onEnded { value in
                        overlay.position.width += value.translation.width
                        overlay.position.height += value.translation.height
                        dragOffset = .zero
                        onEndDrag(frameInCanvas)
                    }
            )
            .animation(.snappy, value: overlay.position)
    }

    private var textFieldView: some View {
        let font = fontForOverlay()
        return TextField("Type here", text: Binding(
            get: { overlay.text },
            set: { overlay.text = $0 }
        ), axis: .vertical)
        .lineLimit(1...3)
        .textInputAutocapitalization(.never)
        .disableAutocorrection(true)
        .focused($textFieldFocused, equals: true)
        .font(font)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(overlay.hasBackground ? overlay.backgroundColor : Color.clear)
        .foregroundStyle(overlay.textColor)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.2, dash: [6, 4]))
            }
        }
        .onAppear {
            if isSelected {
                DispatchQueue.main.async { self.textFieldFocused = true }
            }
        }
        .onChange(of: isSelected) { _, newValue in
            if newValue {
                DispatchQueue.main.async { self.textFieldFocused = true }
            } else {
                self.textFieldFocused = false
            }
        }
        .background(
            SizeReader { size in
                overlay.measuredSize = size
            }
        )
    }

    private func fontForOverlay() -> Font {
        if let name = overlay.fontName, !name.isEmpty {
            return .custom(name, size: overlay.fontSize).weight(overlay.fontWeight)
        } else {
            return .system(size: overlay.fontSize, weight: overlay.fontWeight)
        }
    }

    private func updateFrame(geo: GeometryProxy) {
        let size = geo.size
        overlay.measuredSize = size
        let origin = CGPoint(x: overlay.position.width, y: overlay.position.height)
        frameInCanvas = CGRect(origin: origin, size: size)
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
