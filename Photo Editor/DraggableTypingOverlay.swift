import SwiftUI

struct DraggableTypingOverlay: View {
    @Binding var overlay: TextOverlay
    var isSelected: Bool
    var onBeginDrag: () -> Void
    var onEndDrag: (CGRect) -> Void
    @FocusState var textFieldFocused: Bool

    @State private var dragOffset: CGSize = .zero
    @State private var frameInCanvas: CGRect = .zero

    private let horizontalPadding: CGFloat = 10
    private let verticalPadding: CGFloat = 6
    private let cornerRadius: CGFloat = 8

    var body: some View {
        ZStack {
            if overlay.hasBackground, let size = contentSize() {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(overlay.backgroundColor)
                    .frame(width: size.width + horizontalPadding * 2,
                           height: size.height + verticalPadding * 2)
            }

            TextField("Type here", text: Binding(
                get: { overlay.text },
                set: { overlay.text = $0 }
            ), axis: .vertical)
            .lineLimit(1...3)
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            .focused($textFieldFocused, equals: true)
            .font(fontForOverlay())
            .foregroundStyle(overlay.textColor)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                IntrinsicTextSizeReader(text: overlay.text, font: fontForOverlay()) { size in
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
        .offset(x: overlay.position.width + dragOffset.width,
                y: overlay.position.height + dragOffset.height)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { updateFrame(geo: geo) }
                    .onChange(of: geo.size) { _, _ in updateFrame(geo: geo) }
                    .onChange(of: overlay.position) { _, _ in updateFrame(geo: geo) }
            }
        )
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
    }

    private func contentSize() -> CGSize? {
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

    private func updateFrame(geo: GeometryProxy) {
        let size = geo.size
        let origin = CGPoint(
            x: overlay.position.width - size.width / 2,
            y: overlay.position.height - size.height / 2
        )
        frameInCanvas = CGRect(origin: origin, size: size)
    }
}
