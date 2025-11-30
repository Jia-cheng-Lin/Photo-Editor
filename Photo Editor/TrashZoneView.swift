import SwiftUI

struct TrashZoneView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "trash")
                .font(.system(size: 18, weight: .semibold))
            Text("拖曳到此刪除")
                .font(.footnote)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(Color.red.opacity(0.35), lineWidth: 1)
        )
    }
}

