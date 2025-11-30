import SwiftUI
import Photos

struct ExportView: View {
    let filteredBase: UIImage
    let overlays: [TextOverlay]

    @State private var exporting: Bool = false
    @State private var showShare: Bool = false
    @State private var exportedImage: UIImage?

    var body: some View {
        VStack(spacing: 12) {
            SquareCanvas { side in
                let composed = compose()
                Image(uiImage: composed)
                    .resizable()
                    .scaledToFit()
                    .frame(width: side, height: side)
            }
            .padding(.horizontal)

            Spacer(minLength: 8)

            HStack(spacing: 10) {
                Button {
                    saveToPhotos()
                } label: {
                    Text("儲存到照片")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.black.opacity(0.08))
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    exportedImage = compose()
                    showShare = true
                } label: {
                    Text("分享")
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
        .navigationTitle("匯出")
        .background(GrayscaleRadialBackground().ignoresSafeArea())
        .sheet(isPresented: $showShare) {
            if let img = exportedImage {
                ShareSheet(activityItems: [img])
            }
        }
    }

    private func compose() -> UIImage {
        // 將 filteredBase 與 overlays 合成
        ContentView.renderTextOverlaysOnImage(base: filteredBase, overlays: overlays)
    }

    private func saveToPhotos() {
        let composed = compose()
        UIImageWriteToSavedPhotosAlbum(composed, nil, nil, nil)
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

