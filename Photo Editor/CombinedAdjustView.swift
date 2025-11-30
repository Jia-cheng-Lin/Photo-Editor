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
            SquareCanvas { side in
                let filtered = service.render(image: baseImage, filter: workingFilter, brightness: workingBrightness, contrast: workingContrast)
                Image(uiImage: filtered)
                    .resizable()
                    .scaledToFit()
                    .frame(width: side, height: side)
                    .overlay {
                        // 預覽文字覆蓋
                        Image(uiImage: ContentView.renderTextOverlaysLayer(size: CGSize(width: side, height: side), scale: filtered.scale, overlays: overlays))
                            .resizable()
                            .scaledToFit()
                    }
            }
            .padding(.horizontal)

            // 濾鏡
            VStack(alignment: .leading, spacing: 8) {
                Text("濾鏡")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                FilterPickerView(baseImage: baseImage, selected: $workingFilter) {
                    // 立即更新預覽即可
                }
            }
            .padding(.horizontal)

            // 亮度/對比
            VStack(spacing: 10) {
                HStack {
                    Text("亮度")
                    Slider(value: $workingBrightness, in: -0.5...0.5)
                    Text(String(format: "%.2f", workingBrightness))
                        .font(.footnote.monospacedDigit())
                        .frame(width: 52, alignment: .trailing)
                }
                HStack {
                    Text("對比")
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
                    onNext(workingFilter, workingBrightness, workingContrast)
                } label: {
                    Text("套用並繼續")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.black.opacity(0.08))
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    let filtered = service.render(image: baseImage, filter: workingFilter, brightness: workingBrightness, contrast: workingContrast)
                    onExport(filtered, overlays)
                } label: {
                    Text("直接匯出")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.black.opacity(0.12))
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .padding(.vertical)
        .navigationTitle("濾鏡與調整")
        .background(GrayscaleRadialBackground().ignoresSafeArea())
    }
}

