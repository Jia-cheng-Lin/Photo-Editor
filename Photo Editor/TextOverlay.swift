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

    // 動態量測尺寸（隨輸入更新）
    var measuredSize: CGSize = .zero

    // 確認後凍結的背景尺寸（有值時以此為準，不再隨輸入變動）
    var fixedBackgroundSize: CGSize? = nil

    init(
        text: String,
        position: CGSize = .zero,
        fontSize: CGFloat = 22,
        fontWeight: Font.Weight = .bold,
        fontName: String? = nil,
        textColor: Color = .primary,
        hasBackground: Bool = false,
        backgroundColor: Color = Color.black.opacity(0.6),
        measuredSize: CGSize = .zero,
        fixedBackgroundSize: CGSize? = nil
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
        self.fixedBackgroundSize = fixedBackgroundSize
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
