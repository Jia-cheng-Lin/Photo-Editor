import SwiftUI

// Shared request for navigating from CombinedAdjustView to ExportView
struct ExportRequest: Equatable {
    let filteredBase: UIImage
    let overlays: [TextOverlay]
}

struct ExportRequestKey: PreferenceKey {
    static var defaultValue: ExportRequest? = nil
    static func reduce(value: inout ExportRequest?, nextValue: () -> ExportRequest?) {
        value = nextValue() ?? value
    }
}

struct ExportRequestEmitter: View {
    @Binding var request: ExportRequest?
    var body: some View {
        Color.clear
            .preference(key: ExportRequestKey.self, value: request)
    }
}
