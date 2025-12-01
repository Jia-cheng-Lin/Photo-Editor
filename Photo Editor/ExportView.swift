import SwiftUI
import Photos

struct ExportView: View {
    // New: accept an optional final image (from snapshot)
    let filteredBase: UIImage
    let overlays: [TextOverlay]
    let finalImage: UIImage?

    @State private var composed: UIImage?
    @State private var showShare: Bool = false

    init(filteredBase: UIImage, overlays: [TextOverlay], finalImage: UIImage? = nil) {
        self.filteredBase = filteredBase
        self.overlays = overlays
        self.finalImage = finalImage
    }

    var body: some View {
        VStack(spacing: 12) {
            SquareCanvas { side in
                // Prefer the provided final image; fall back to composing once
                let img = composed ?? finalImage ?? composeOnce()
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(width: side, height: side)
            }
            .padding(.horizontal)

            Spacer(minLength: 8)

            HStack(spacing: 10) {
                Button {
                    let img = composed ?? finalImage ?? composeOnce()
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
                    let img = composed ?? finalImage ?? composeOnce()
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
            // Cache once for consistent preview/actions
            composed = finalImage ?? composeOnce()
        }
        .sheet(isPresented: $showShare) {
            if let img = composed {
                ShareSheet(activityItems: [img])
            }
        }
    }

    private func composeOnce() -> UIImage {
        ContentView.renderTextOverlaysOnImage(base: filteredBase, overlays: overlays)
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
