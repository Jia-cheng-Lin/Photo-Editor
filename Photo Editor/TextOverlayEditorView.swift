import SwiftUI

struct TextOverlayEditorView: View {
    @Binding var overlay: TextOverlay
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("文字") {
                    TextField("內容", text: $overlay.text, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section("字體") {
                    Picker("字重", selection: $overlay.fontWeight) {
                        ForEach(TextOverlay.weights, id: \.name) { item in
                            Text(item.name).tag(item.weight)
                        }
                    }

                    Picker("字體", selection: Binding<String>(
                        get: { overlay.fontName ?? "" },
                        set: { overlay.fontName = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("系統預設").tag("")
                        ForEach(TextOverlay.systemFontOptions, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }

                    HStack {
                        Text("大小 \(Int(overlay.fontSize))")
                        Slider(value: $overlay.fontSize, in: 12...64, step: 1)
                    }
                }

                Section("顏色") {
                    VStack(alignment: .leading) {
                        Text("文字顏色")
                        ColorPaletteView(selection: $overlay.textColor)
                    }
                    Toggle("背景", isOn: $overlay.hasBackground)
                    if overlay.hasBackground {
                        VStack(alignment: .leading) {
                            Text("背景顏色")
                            ColorPaletteView(selection: $overlay.backgroundColor)
                        }
                    }
                }
            }
            .navigationTitle("編輯文字")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

private struct ColorPaletteView: View {
    @Binding var selection: Color

    private let colors = TextOverlay.palette

    var body: some View {
        HStack {
            ForEach(colors.indices, id: \.self) { idx in
                let color = colors[idx]
                ZStack {
                    Circle()
                        .fill(color)
                        .frame(width: 28, height: 28)
                        .overlay(Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                    if color.isApproximatelyEqual(to: selection) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.white)
                            .shadow(radius: 1)
                    }
                }
                .onTapGesture { selection = color }
            }
        }
    }
}

private extension Color {
    func isApproximatelyEqual(to other: Color) -> Bool {
        // 簡易比較：將兩個 Color 轉為 UIColor 再比較 RGBA
        let u1 = UIColor(self)
        let u2 = UIColor(other)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        u1.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        u2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return abs(r1 - r2) < 0.01 && abs(g1 - g2) < 0.01 && abs(b1 - b2) < 0.01 && abs(a1 - a2) < 0.01
    }
}
