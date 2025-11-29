import SwiftUI

struct AddTextAltView: View {
    // 建立中的暫存 TextOverlay
    @State private var draft = TextOverlay(text: "輸入文字")

    // 新增完成時回傳建立好的 TextOverlay
    var onDone: (TextOverlay) -> Void
    // 取消時回呼（可選），若不需要可以拿掉
    var onCancel: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            // 直接重用你現有的文字編輯器
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
}
