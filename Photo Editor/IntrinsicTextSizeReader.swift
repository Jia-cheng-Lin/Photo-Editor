import SwiftUI

// Measures the intrinsic size of a piece of text rendered with a specific Font.
// It ignores padding and returns the raw text size, which you can then augment
// with your own insets for backgrounds.
struct IntrinsicTextSizeReader: View {
    let text: String
    let font: Font
    var onChange: (CGSize) -> Void

    var body: some View {
        Text(text.isEmpty ? "" : text)
            .font(font)
            .lineLimit(1...3)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(key: IntrinsicTextSizePreferenceKey.self, value: geo.size)
                }
            )
            .hidden()
            .onPreferenceChange(IntrinsicTextSizePreferenceKey.self) { size in
                onChange(size)
            }
    }
}

private struct IntrinsicTextSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
