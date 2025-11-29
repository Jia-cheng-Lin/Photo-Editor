import SwiftUI

struct AddTextAltView: View {
    // 初始參數（可選）
    var initialText: String
    var initialPosition: CGSize
    var initialFontSize: CGFloat
    var initialFontWeight: Font.Weight
    var initialFontName: String?
    var initialTextColor: Color
    var initialHasBackground: Bool
    var initialBackgroundColor: Color

    // 完成/取消回呼
    var onDone: (TextOverlay) -> Void
    var onCancel: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var draft: TextOverlay

    init(
        initialText: String = "輸入文字",
        initialPosition: CGSize = .zero,
        initialFontSize: CGFloat = 22,
        initialFontWeight: Font.Weight = .bold,
        initialFontName: String? = nil,
        initialTextColor: Color = .primary,
        initialHasBackground: Bool = false,
        initialBackgroundColor: Color = Color.black.opacity(0.6),
        onDone: @escaping (TextOverlay) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.initialText = initialText
        self.initialPosition = initialPosition
        self.initialFontSize = initialFontSize
        self.initialFontWeight = initialFontWeight
        self.initialFontName = initialFontName
        self.initialTextColor = initialTextColor
        self.initialHasBackground = initialHasBackground
        self.initialBackgroundColor = initialBackgroundColor
        self.onDone = onDone
        self.onCancel = onCancel

        _draft = State(initialValue: TextOverlay(
            text: initialText,
            position: initialPosition,
            fontSize: initialFontSize,
            fontWeight: initialFontWeight,
            fontName: initialFontName,
            textColor: initialTextColor,
            hasBackground: initialHasBackground,
            backgroundColor: initialBackgroundColor
        ))
    }

    var body: some View {
        // 注意：這裡不要再包 NavigationStack，避免雙層導航造成外層 path 被影響
        TextOverlayEditorView(overlay: $draft)
            .navigationTitle("新增文字")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        onCancel?()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        onDone(draft)
                        dismiss()
                    }
                }
            }
    }
}


