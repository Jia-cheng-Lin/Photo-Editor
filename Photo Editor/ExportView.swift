import SwiftUI
import Photos

struct ExportView: View {
    let filteredBase: UIImage
    let overlays: [TextOverlay]

    // If a pre-rendered final image is passed, we’ll still allow zooming by recomposing.
    let finalImage: UIImage?

    @State private var composed: UIImage?
    @State private var showShare: Bool = false

    // Text zoom factor (1.0 = original)
    @State private var textZoom: CGFloat = 1.0

    init(filteredBase: UIImage, overlays: [TextOverlay], finalImage: UIImage? = nil) {
        self.filteredBase = filteredBase
        self.overlays = overlays
        self.finalImage = finalImage
    }

    var body: some View {
        VStack(spacing: 12) {
            SquareCanvas { side in
                let img = composed ?? renderPreview()
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(width: side, height: side)
            }
            .padding(.horizontal)

            // Text Zoom control (only in Export)
            HStack {
                Text("Text Zoom")
                Slider(value: Binding(
                    get: { Double(textZoom) },
                    set: { newVal in
                        textZoom = CGFloat(newVal)
                        composed = renderPreview()
                    }
                ), in: 0.5...20.0, step: 0.2)
                Text(String(format: "%.2fx", textZoom))
                    .font(.footnote.monospacedDigit())
                    .frame(width: 56, alignment: .trailing)
            }
            .padding(.horizontal)

            Spacer(minLength: 8)

            HStack(spacing: 10) {
                Button {
                    let img = composed ?? renderPreview()
                    UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
                } label: {
                    Text("Download")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.black.opacity(0.08))
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    let img = composed ?? renderPreview()
                    composed = img
                    showShare = true
                } label: {
                    Text("Share")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.black.opacity(0.12))
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .navigationTitle("Export")
        .background(GrayscaleRadialBackground().ignoresSafeArea())
        .onAppear {
            composed = renderPreview()
        }
        .sheet(isPresented: $showShare) {
            if let img = composed {
                ShareSheet(activityItems: [img])
            }
        }
    }

    // Compose filteredBase + overlays, then scale the overlays bitmap by textZoom and draw centered.
    private func renderPreview() -> UIImage {
        // Use square render size based on filteredBase
        let side = min(filteredBase.size.width, filteredBase.size.height)
        let renderSize = CGSize(width: side, height: side)
        let scale = filteredBase.scale

        // 1) Render overlays layer at 1.0 zoom using existing helper
        let overlaysLayer = ContentView.renderTextOverlaysLayer(
            size: renderSize,
            scale: scale,
            overlays: overlays
        )

        // 2) Draw base + scaled overlays centered
        UIGraphicsBeginImageContextWithOptions(renderSize, false, scale)
        defer { UIGraphicsEndImageContext() }

        filteredBase.draw(in: CGRect(origin: .zero, size: renderSize))

        // Compute target rect by scaling around center
        let center = CGPoint(x: renderSize.width/2, y: renderSize.height/2)
        let zoom = max(textZoom, 0.01)
        let targetSize = CGSize(width: renderSize.width * zoom, height: renderSize.height * zoom)
        let targetOrigin = CGPoint(x: center.x - targetSize.width/2, y: center.y - targetSize.height/2)
        let targetRect = CGRect(origin: targetOrigin, size: targetSize)

        overlaysLayer.draw(in: targetRect, blendMode: .normal, alpha: 1.0)

        return UIGraphicsGetImageFromCurrentImageContext() ?? filteredBase
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
