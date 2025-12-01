import SwiftUI

struct CombinedAdjustView: View {
    let baseImage: UIImage
    let overlays: [TextOverlay]

    @State private var workingFilter: FilterKind
    @State private var workingBrightness: Double
    @State private var workingContrast: Double

    let onNext: (FilterKind, Double, Double) -> Void
    let onExport: (UIImage, [TextOverlay]) -> Void

    private let service = FilterService()
    @State private var exportRequest: ExportRequest? = nil

    // Snapshot anchor
    @Namespace private var snapshotSpace
    @State private var snapshotViewID = UUID()

    init(
        baseImage: UIImage,
        overlays: [TextOverlay],
        initialFilter: FilterKind = .none,
        initialBrightness: Double = 0,
        initialContrast: Double = 1,
        onNext: @escaping (FilterKind, Double, Double) -> Void,
        onExport: @escaping (UIImage, [TextOverlay]) -> Void
    ) {
        self.baseImage = baseImage
        self.overlays = overlays
        self._workingFilter = State(initialValue: initialFilter)
        self._workingBrightness = State(initialValue: initialBrightness)
        self._workingContrast = State(initialValue: initialContrast)
        self.onNext = onNext
        self.onExport = onExport
    }

    var body: some View {
        VStack(spacing: 12) {
            // Snapshot target
            SnapshotContainer(id: snapshotViewID) {
                SquareCanvas { side in
                    let filtered = service.render(image: baseImage, filter: workingFilter, brightness: workingBrightness, contrast: workingContrast)
                    Image(uiImage: filtered)
                        .resizable()
                        .scaledToFit()
                        .frame(width: side, height: side)
                        .overlay {
                            Image(uiImage: ContentView.renderTextOverlaysLayer(size: CGSize(width: side, height: side), scale: filtered.scale, overlays: overlays))
                                .resizable()
                                .scaledToFit()
                        }
                }
            }
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 8) {
                Text("Filters")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                FilterPickerView(baseImage: baseImage, selected: $workingFilter) { }
            }
            .padding(.horizontal)

            VStack(spacing: 10) {
                HStack {
                    Text("Brightness")
                    Slider(value: $workingBrightness, in: -0.5...0.5)
                    Text(String(format: "%.2f", workingBrightness))
                        .font(.footnote.monospacedDigit())
                        .frame(width: 52, alignment: .trailing)
                }
                HStack {
                    Text("Contrast")
                    Slider(value: $workingContrast, in: 0.5...1.5)
                    Text(String(format: "%.2f", workingContrast))
                        .font(.footnote.monospacedDigit())
                        .frame(width: 52, alignment: .trailing)
                }
            }
            .padding(.horizontal)

            Spacer(minLength: 8)

            HStack(spacing: 10) {
                Button {
                    // Persist chosen adjustments
                    onNext(workingFilter, workingBrightness, workingContrast)

                    // Render filtered base once more to be sure we capture latest state
                    let filtered = service.render(image: baseImage, filter: workingFilter, brightness: workingBrightness, contrast: workingContrast)

                    // Snapshot the current preview (filtered + overlays)
                    Task { @MainActor in
                        if let finalImage = await SnapshotMaker.snapshot(viewID: snapshotViewID) {
                            exportRequest = ExportRequest(
                                filteredBase: filtered,
                                overlays: overlays,
                                finalImage: finalImage,
                                finalName: "Final"
                            )
                        } else {
                            // Fallback: compose in code if snapshot fails
                            let composed = ContentView.renderTextOverlaysOnImage(base: filtered, overlays: overlays)
                            exportRequest = ExportRequest(
                                filteredBase: filtered,
                                overlays: overlays,
                                finalImage: composed,
                                finalName: "Final"
                            )
                        }
                    }
                } label: {
                    Text("Next")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.black.opacity(0.08))
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .padding(.vertical)
        .navigationTitle("Adjustments")
        .background(GrayscaleRadialBackground().ignoresSafeArea())
        .background(
            ExportRequestEmitter(request: $exportRequest)
        )
        .onChange(of: workingFilter) { _, _ in snapshotViewID = UUID() }
        .onChange(of: workingBrightness) { _, _ in snapshotViewID = UUID() }
        .onChange(of: workingContrast) { _, _ in snapshotViewID = UUID() }
    }
}

// MARK: - Snapshot helpers

// A container that tags a subtree to be snapshotted by SnapshotMaker
private struct SnapshotContainer<Content: View>: View {
    let id: UUID
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(SnapshotTag(id: id))
    }
}

private struct SnapshotTag: View {
    let id: UUID
    var body: some View {
        Color.clear
            .accessibilityIdentifier(id.uuidString) // a stable marker
    }
}

enum SnapshotMaker {
    // Render a snapshot of the view with the given id by traversing UI hierarchy.
    @MainActor
    static func snapshot(viewID: UUID) async -> UIImage? {
        // Find the hosting window
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else { return nil }

        // Find the view with marker
        guard let target = findView(in: window, matching: viewID.uuidString) else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(bounds: target.bounds, format: format)
        return renderer.image { ctx in
            target.drawHierarchy(in: target.bounds, afterScreenUpdates: true)
        }
    }

    private static func findView(in root: UIView, matching identifier: String) -> UIView? {
        if root.accessibilityIdentifier == identifier {
            return root
        }
        for sub in root.subviews {
            if let found = findView(in: sub, matching: identifier) {
                return found
            }
        }
        return nil
    }
}
