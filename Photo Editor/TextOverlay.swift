import SwiftUI

struct TextOverlay: Identifiable, Equatable {
    let id: UUID = UUID()
    var text: String

    // 位置（相對偏移）
    var position: CGSize

    // 文字樣式
    var fontSize: CGFloat       // 12...64
    var fontWeight: Font.Weight // regular, semibold, bold
    var fontName: String?       // 額外可選字體名稱（可為 nil 代表系統預設）

    // 顏色
    var textColor: Color
    var hasBackground: Bool
    var backgroundColor: Color

    // 新增：量測後的實際呈現尺寸（含內距），預設為 .zero
    var measuredSize: CGSize = .zero

    init(
        text: String,
        position: CGSize = .zero,
        fontSize: CGFloat = 22,
        fontWeight: Font.Weight = .bold,
        fontName: String? = nil,
        textColor: Color = .primary,
        hasBackground: Bool = false,
        backgroundColor: Color = Color.black.opacity(0.6),
        measuredSize: CGSize = .zero
    ) {
        self.text = text
        self.position = position
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.fontName = fontName
        self.textColor = textColor
        self.hasBackground = hasBackground
        self.backgroundColor = backgroundColor
        self.measuredSize = measuredSize
    }
}

extension TextOverlay {
    static let palette: [Color] = [
        .black, .white, .red, .orange, .yellow, .green, .blue, .purple
    ]

    static let systemFontOptions: [String] = [
        "SF Pro", "Helvetica Neue", "Avenir Next", "Georgia", "Times New Roman", "Courier New"
    ]

    static let weights: [(name: String, weight: Font.Weight)] = [
        ("Regular", .regular), ("Semibold", .semibold), ("Bold", .bold)
    ]
}
