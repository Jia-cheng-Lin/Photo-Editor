import SwiftUI

// Shared request for navigating from CombinedAdjustView to ExportView
struct ExportRequest: Equatable {
    let filteredBase: UIImage
    let overlays: [TextOverlay]

    // New: snapshot of the final composed image (already rendered)
    let finalImage: UIImage?
    let finalName: String?

    static func == (lhs: ExportRequest, rhs: ExportRequest) -> Bool {
        lhs.filteredBase == rhs.filteredBase
        && lhs.overlays == rhs.overlays
        && lhs.finalImage?.pngData() == rhs.finalImage?.pngData()
        && lhs.finalName == rhs.finalName
    }
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
