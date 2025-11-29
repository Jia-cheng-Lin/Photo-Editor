//  ContentView.swift
//  Picture Editor
//
//  Created by 陳芸萱 on 2025/11/26.
//

import SwiftUI
import PhotosUI
import AVFoundation
import UIKit

struct ContentView: View {
    // Navigation
    @State private var path: [EditorStep] = []

    // Photo picking
    @State private var selectedItem: PhotosPickerItem?
    @State private var showImageSourceMenu: Bool = false
    @State private var showCameraPicker: Bool = false
    @State private var cameraImage: UIImage?
    @State private var showPhotosPicker: Bool = false

    // Original image
    @State private var originalImage: UIImage?

    // Step 1: Transform
    @State private var currentZoom: CGFloat = 1.0
    @State private var dragOffsetScreen: CGSize = .zero
    @State private var cumulativeOffsetScreen: CGSize = .zero
    @State private var centerInImage: CGPoint?

    // Step 2: Text overlays (shared state across steps)
    @State private var overlays: [TextOverlay] = []
    @State private var selectedOverlayID: UUID? = nil
    @State private var isTyping: Bool = false
    @FocusState private var textFieldFocused: Bool

    // Simple typing inputs
    @State private var typedText: String = ""
    @State private var selectedFontName: String? = nil
    @State private var textColor: Color = .black
    @State private var fontSize: CGFloat = 28

    // UI options
    private let fontOptions: [String?] = [nil, "PingFang TC", "Helvetica Neue", "Avenir Next", "Georgia", "Times New Roman", "Courier New"]
    private let colorOptions: [Color] = [.black, .white, .red, .orange, .yellow, .green, .blue, .purple]

    // Step 3: filter + adjustments (combined)
    @State private var selectedFilter: FilterKind = .none
    @State private var brightness: Double = 0.0
    @State private var contrast: Double = 1.0

    private let filterService = FilterService()

    var body: some View {
        NavigationStack(path: $path) {
            startScreen
                .navigationDestination(for: EditorStep.self) { step in
                    switch step.kind {
                    case .transform:
                        TransformView()
                    case .addText(let baseImage):
                        AddTextView(baseImage: baseImage)
                    case .combinedAdjust(let baseImage, let overlays):
                        CombinedAdjustView(
                            baseImage: baseImage,
                            overlays: overlays,
                            initialFilter: selectedFilter,
                            initialBrightness: brightness,
                            initialContrast: contrast,
                            onNext: { chosenFilter, b, c in
                                selectedFilter = chosenFilter
                                brightness = b
                                contrast = c
                            }
                        )
                    }
                }
        }
        .preferredColorScheme(.light)
        .tint(.black)
        .background(GrayscaleRadialBackground().ignoresSafeArea())
    }

    // MARK: - Start / Pick screen
    private var startScreen: some View {
        VStack(spacing: 16) {
            Spacer()

            SquareCanvas { side in
                ZStack {
                    if let img = originalImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(width: side, height: side)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 40, weight: .regular))
                                .foregroundStyle(Color.black.opacity(0.8))
                            Text("Add a photo")
                                .foregroundStyle(Color.black)
                            Text("Tap to choose from Library or Camera")
                                .font(.footnote)
                                .foregroundStyle(Color.black.opacity(0.7))
                        }
                        .frame(width: side, height: side)
                    }
                }
                .frame(width: side, height: side)
                .contentShape(Rectangle())
                .onTapGesture { showImageSourceMenu = true }
            }
            .padding(.horizontal)

            Spacer(minLength: 8)

            // Next button on the start page
            VStack(spacing: 10) {
                Button(action: pushToTransform) {
                    Text("Next")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.black.opacity(0.08))
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(originalImage == nil)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            Spacer(minLength: 0)
        }
        .background(GrayscaleRadialBackground().ignoresSafeArea())
        .navigationTitle("Photo Editor")
        .confirmationDialog("Select Image Source", isPresented: $showImageSourceMenu, titleVisibility: .visible) {
            Button("Photo Library") {
                selectedItem = nil
                showPhotosPicker = true
            }
            Button("Camera") {
                requestCameraAccessAndPresent()
            }
            Button("Cancel", role: .cancel) { }
        }
        .photosPicker(isPresented: $showPhotosPicker, selection: $selectedItem, matching: .images)
        .onChange(of: selectedItem) { _, newValue in
            Task { await loadImage(from: newValue) }
        }
        .sheet(isPresented: $showCameraPicker) {
            CameraPicker(image: $cameraImage)
                .ignoresSafeArea()
        }
        .onChange(of: cameraImage) { _, newValue in
            guard let img = newValue else { return }
            resetState(with: img)
            pushToTransform()
        }
    }

    private func pushToTransform() {
        path = [.init(kind: .transform)]
    }

    // MARK: - Step 1: Transform
    @ViewBuilder
    private func TransformView() -> some View {
        VStack(spacing: 12) {
            SquareCanvas { side in
                ZStack {
                    if let base = originalImage {
                        let imageCenter = centerInImage ?? CGPoint(x: base.size.width/2, y: base.size.height/2)

                        let drag = DragGesture()
                            .onChanged { value in
                                dragOffsetScreen = value.translation
                            }
                            .onEnded { value in
                                cumulativeOffsetScreen.width += value.translation.width
                                cumulativeOffsetScreen.height += value.translation.height

                                let fittedScale = min(side / base.size.width, side / base.size.height)
                                let displayScale = fittedScale * max(currentZoom, 0.0001)

                                let deltaInBitmap = CGPoint(
                                    x: -value.translation.width / displayScale,
                                    y: -value.translation.height / displayScale
                                )

                                var newCenter = CGPoint(
                                    x: imageCenter.x + deltaInBitmap.x,
                                    y: imageCenter.y + deltaInBitmap.y
                                )

                                newCenter.x = max(0, min(base.size.width, newCenter.x))
                                newCenter.y = max(0, min(base.size.height, newCenter.y))

                                centerInImage = newCenter
                                dragOffsetScreen = .zero
                            }

                        let magnify = MagnificationGesture()
                            .onChanged { scale in
                                currentZoom = (scale * currentZoom).clamped(to: 0.5...3.0)
                            }
                            .onEnded { finalScale in
                                currentZoom = (currentZoom * finalScale).clamped(to: 0.5...3.0)
                            }

                        Image(uiImage: base)
                            .resizable()
                            .scaledToFit()
                            .frame(width: side, height: side)
                            .scaleEffect(currentZoom)
                            .offset(x: cumulativeOffsetScreen.width + dragOffsetScreen.width,
                                    y: cumulativeOffsetScreen.height + dragOffsetScreen.height)
                            .contentShape(Rectangle())
                            .simultaneousGesture(drag)
                            .simultaneousGesture(magnify)
                            .onAppear {
                                if centerInImage == nil {
                                    centerInImage = CGPoint(x: base.size.width/2, y: base.size.height/2)
                                }
                            }
                    }
                }
                .frame(width: side, height: side)
            }
            .padding(.horizontal)

            // Zoom slider + ratio label
            VStack(spacing: 8) {
                HStack {
                    Text("Zoom")
                        .font(.footnote)
                        .foregroundStyle(.black.opacity(0.7))

                    let zoomBinding = Binding<Double>(
                        get: { Double(currentZoom) },
                        set: { currentZoom = CGFloat($0).clamped(to: 0.5...3.0) }
                    )
                    Slider(value: zoomBinding, in: 0.5...3.0)

                    Text(String(format: "%.2fx", currentZoom))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.black.opacity(0.9))
                        .frame(width: 56, alignment: .trailing)
                }
                .padding(.horizontal)
            }

            Spacer(minLength: 8)

            VStack(spacing: 10) {
                Button(action: handleTransformNext) {
                    Text("Next")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.black.opacity(0.08))
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(originalImage == nil)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .padding(.vertical)
        .background(GrayscaleRadialBackground().ignoresSafeArea())
        .navigationTitle("Zoom & Move")
    }

    private func handleTransformNext() {
        guard let base = originalImage else { return }
        let center = centerInImage ?? CGPoint(x: base.size.width/2, y: base.size.height/2)
        let canvasSide: CGFloat = 360
        let flattened = renderFromCenterCrop(base: base, center: center, zoom: currentZoom, canvasSide: canvasSide)
        path.append(.init(kind: .addText(baseImage: flattened)))
    }

    private func renderFromCenterCrop(base: UIImage, center: CGPoint, zoom: CGFloat, canvasSide: CGFloat) -> UIImage {
        let fittedScale = min(canvasSide / base.size.width, canvasSide / base.size.height)
        let displayScale = fittedScale * max(zoom, 0.0001)
        let squareSideInBitmap = canvasSide / displayScale

        var cropRect = CGRect(
            x: center.x - squareSideInBitmap/2,
            y: center.y - squareSideInBitmap/2,
            width: squareSideInBitmap,
            height: squareSideInBitmap
        )

        if cropRect.minX < 0 { cropRect.origin.x = 0 }
        if cropRect.minY < 0 { cropRect.origin.y = 0 }
        if cropRect.maxX > base.size.width { cropRect.origin.x = base.size.width - cropRect.width }
        if cropRect.maxY > base.size.height { cropRect.origin.y = base.size.height - cropRect.height }

        cropRect.origin.x = max(0, cropRect.origin.x)
        cropRect.origin.y = max(0, cropRect.origin.y)
        cropRect.size.width = min(cropRect.size.width, base.size.width)
        cropRect.size.height = min(cropRect.size.height, base.size.height)

        let outputSide = min(base.size.width, base.size.height)
        let renderSize = CGSize(width: outputSide, height: outputSide)

        UIGraphicsBeginImageContextWithOptions(renderSize, false, base.scale)
        defer { UIGraphicsEndImageContext() }

        if let cg = base.cgImage {
            let scaleFactor = base.scale
            let scaledCrop = CGRect(x: cropRect.origin.x * scaleFactor,
                                    y: cropRect.origin.y * scaleFactor,
                                    width: cropRect.size.width * scaleFactor,
                                    height: cropRect.size.height * scaleFactor)
            if let sub = cg.cropping(to: scaledCrop.integral) {
                UIImage(cgImage: sub, scale: base.scale, orientation: base.imageOrientation)
                    .draw(in: CGRect(origin: .zero, size: renderSize))
            } else {
                base.draw(in: CGRect(origin: .zero, size: renderSize), blendMode: .normal, alpha: 1)
            }
        } else {
            base.draw(in: CGRect(origin: .zero, size: renderSize), blendMode: .normal, alpha: 1)
        }

        return UIGraphicsGetImageFromCurrentImageContext() ?? base
    }

    // MARK: - Step 2: Add Text
    @ViewBuilder
    private func AddTextView(baseImage: UIImage) -> some View {
        VStack(spacing: 12) {
            SquareCanvas { side in
                ZStack {
                    Image(uiImage: baseImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: side, height: side)

                    ForEach(overlays) { overlay in
                        ZStack(alignment: .topTrailing) {
                            DraggableTextOverlay(
                                overlay: binding(for: overlay),
                                isSelected: selectedOverlayID == overlay.id,
                                onTap: { handleSelectOverlay(overlay) }
                            )

                            if selectedOverlayID == overlay.id && isTyping {
                                Button(action: { handleDeleteOverlay(overlay) }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(.black)
                                        .background(Circle().fill(Color.red))
                                }
                                .offset(x: 10, y: -10)
                            }
                        }
                    }
                }
                .frame(width: side, height: side)
                .contentShape(Rectangle())
                .onTapGesture {
                    let new = makeNewOverlay()
                    overlays.append(new)
                    selectedOverlayID = new.id
                    isTyping = true
                    textFieldFocused = true

                    typedText = new.text
                    selectedFontName = new.fontName
                    textColor = new.textColor
                    fontSize = new.fontSize
                }
            }
            .padding(.horizontal)

            Spacer(minLength: 8)

            VStack(spacing: 10) {
                Button(action: { handleAddTextNext(baseImage: baseImage) }) {
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
        }
        .padding(.vertical)
        .background(GrayscaleRadialBackground().ignoresSafeArea())
        .navigationTitle("Add Text")
        .safeAreaInset(edge: .bottom) {
            if let sel = selectedOverlayID,
               let index = overlays.firstIndex(where: { $0.id == sel }),
               isTyping {
                VStack(spacing: 8) {
                    // Font selection
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(fontOptions, id: \.self) { name in
                                let label = name ?? "System"
                                Text(label)
                                    .font(name != nil ? .custom(name!, size: 16) : .system(size: 16))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background((overlays[index].fontName == name) ? Color.black.opacity(0.12) : Color.black.opacity(0.06))
                                    .clipShape(Capsule())
                                    .onTapGesture {
                                        overlays[index].fontName = name
                                        selectedFontName = name
                                    }
                                    .foregroundStyle(.black)
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Color selection
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(colorOptions.indices, id: \.self) { idx in
                                let c = colorOptions[idx]
                                Circle()
                                    .fill(c)
                                    .frame(width: 28, height: 28)
                                    .overlay(Circle().stroke(Color.black.opacity(0.2), lineWidth: 1))
                                    .onTapGesture {
                                        overlays[index].textColor = c
                                        textColor = c
                                    }
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Text input + font size
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 8) {
                            let textBinding = Binding<String>(
                                get: { overlays[index].text },
                                set: { overlays[index].text = $0; typedText = $0 }
                            )
                            TextField("Enter text", text: textBinding, axis: .vertical)
                                .lineLimit(1...3)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                                .focused($textFieldFocused)
                                .padding(10)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                                .foregroundStyle(.black)

                            let sizeBinding = Binding<CGFloat>(
                                get: { overlays[index].fontSize },
                                set: { overlays[index].fontSize = $0; fontSize = $0 }
                            )
                            HStack {
                                Image(systemName: "textformat.size.smaller")
                                Slider(value: sizeBinding, in: 12...96, step: 1)
                                Image(systemName: "textformat.size.larger")
                            }
                            .foregroundStyle(.black)
                        }

                        let verticalSizeBinding = Binding<CGFloat>(
                            get: { overlays[index].fontSize },
                            set: { overlays[index].fontSize = $0; fontSize = $0 }
                        )
                        VerticalSizeSlider(value: verticalSizeBinding, range: 12...96)
                            .frame(width: 48, height: 140)
                            .padding(.leading, 8)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 6)
                }
                .background(.ultraThinMaterial)
            }
        }
        .onChange(of: textFieldFocused) { _, focused in
            if !focused { isTyping = false }
        }
    }

    private func handleSelectOverlay(_ overlay: TextOverlay) {
        selectedOverlayID = overlay.id
        isTyping = true
        textFieldFocused = true
        typedText = overlay.text
        selectedFontName = overlay.fontName
        textColor = overlay.textColor
        fontSize = overlay.fontSize
    }

    private func handleDeleteOverlay(_ overlay: TextOverlay) {
        if let idx = overlays.firstIndex(where: { $0.id == overlay.id }) {
            overlays.remove(at: idx)
        }
        selectedOverlayID = nil
        isTyping = false
        textFieldFocused = false
    }

    private func handleAddTextNext(baseImage: UIImage) {
        let overlaysSnapshot = overlays
        path.append(.init(kind: .combinedAdjust(baseImage: baseImage, overlays: overlaysSnapshot)))
    }

    private func makeNewOverlay() -> TextOverlay {
        TextOverlay(
            text: "Type here",
            position: .zero,
            fontSize: 28,
            fontWeight: .bold,
            fontName: nil,
            textColor: .black,
            hasBackground: false,
            backgroundColor: Color.black.opacity(0.06)
        )
    }

    // Storage for trash zone rect used by the Alt step
    @State private var _trashZoneRect: CGRect? = nil

    // Render overlays to transparent layer (Core Graphics)
    static func renderTextOverlaysLayer(size: CGSize, scale: CGFloat, overlays: [TextOverlay]) -> UIImage {
        let renderSize = size
        UIGraphicsBeginImageContextWithOptions(renderSize, false, scale)
        defer { UIGraphicsEndImageContext() }

        for ov in overlays {
            let uiFont: UIFont = {
                if let name = ov.fontName, !name.isEmpty, let f = UIFont(name: name, size: ov.fontSize) {
                    return f
                } else {
                    let weight: UIFont.Weight
                    switch ov.fontWeight {
                    case .regular: weight = .regular
                    case .semibold: weight = .semibold
                    case .bold: weight = .bold
                    default: weight = .bold
                    }
                    return UIFont.systemFont(ofSize: ov.fontSize, weight: weight)
                }
            }()

            let attrs: [NSAttributedString.Key: Any] = [
                .font: uiFont,
                .foregroundColor: UIColor(ov.textColor)
            ]

            let ns = ov.text as NSString
            let bounds = ns.boundingRect(with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
                                         options: [.usesLineFragmentOrigin, .usesFontLeading],
                                         attributes: attrs,
                                         context: nil).integral
            let textSize = bounds.size

            let canvasCenter = CGPoint(x: renderSize.width/2, y: renderSize.height/2)
            let origin = CGPoint(
                x: canvasCenter.x - textSize.width/2 + ov.position.width,
                y: canvasCenter.y - textSize.height/2 + ov.position.height
            )

            if ov.hasBackground {
                let bgRect = CGRect(origin: origin, size: textSize).insetBy(dx: -8, dy: -6)
                let path = UIBezierPath(roundedRect: bgRect, cornerRadius: 8)
                UIColor(ov.backgroundColor).setFill()
                path.fill()
            }

            ns.draw(at: origin, withAttributes: attrs)
        }

        return UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
    }

    // Composite overlays onto base image (Core Graphics)
    static func renderTextOverlaysOnImage(base: UIImage, overlays: [TextOverlay]) -> UIImage {
        let side = min(base.size.width, base.size.height)
        let renderSize = CGSize(width: side, height: side)

        UIGraphicsBeginImageContextWithOptions(renderSize, false, base.scale)
        defer { UIGraphicsEndImageContext() }

        base.draw(in: CGRect(origin: .zero, size: renderSize))

        for ov in overlays {
            let uiFont: UIFont = {
                if let name = ov.fontName, !name.isEmpty, let f = UIFont(name: name, size: ov.fontSize) {
                    return f
                } else {
                    let weight: UIFont.Weight
                    switch ov.fontWeight {
                    case .regular: weight = .regular
                    case .semibold: weight = .semibold
                    case .bold: weight = .bold
                    default: weight = .bold
                    }
                    return UIFont.systemFont(ofSize: ov.fontSize, weight: weight)
                }
            }()

            let attrs: [NSAttributedString.Key: Any] = [
                .font: uiFont,
                .foregroundColor: UIColor(ov.textColor)
            ]

            let ns = ov.text as NSString
            let bounds = ns.boundingRect(with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
                                         options: [.usesLineFragmentOrigin, .usesFontLeading],
                                         attributes: attrs,
                                         context: nil).integral
            let textSize = bounds.size

            let canvasCenter = CGPoint(x: renderSize.width/2, y: renderSize.height/2)
            let origin = CGPoint(
                x: canvasCenter.x - textSize.width/2 + ov.position.width,
                y: canvasCenter.y - textSize.height/2 + ov.position.height
            )

            if ov.hasBackground {
                let bgRect = CGRect(origin: origin, size: textSize).insetBy(dx: -8, dy: -6)
                let path = UIBezierPath(roundedRect: bgRect, cornerRadius: 8)
                UIColor(ov.backgroundColor).setFill()
                path.fill()
            }

            ns.draw(at: origin, withAttributes: attrs)
        }

        return UIGraphicsGetImageFromCurrentImageContext() ?? base
    }

    // Binding for overlay
    private func binding(for: TextOverlay) -> Binding<TextOverlay> {
        guard let idx = overlays.firstIndex(where: { $0.id == `for`.id }) else {
            return .constant(`for`)
        }
        return $overlays[idx]
    }

    // MARK: - Helpers

    struct EditorStep: Hashable {
        enum Kind {
            case transform
            case addText(baseImage: UIImage)
            case combinedAdjust(baseImage: UIImage, overlays: [TextOverlay])
        }
        let id = UUID()
        let kind: Kind

        static func == (lhs: EditorStep, rhs: EditorStep) -> Bool {
            lhs.id == rhs.id
        }
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    private func requestCameraAccessAndPresent() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCameraPicker = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { showCameraPicker = true }
                }
            }
        default:
            break
        }
    }

    private func loadImage(from item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                resetState(with: uiImage)
                pushToTransform()
            }
        } catch {
            print("Load image error: \(error)")
        }
    }

    private func resetState(with image: UIImage) {
        originalImage = image
        currentZoom = 1.0
        dragOffsetScreen = .zero
        cumulativeOffsetScreen = .zero
        centerInImage = CGPoint(x: image.size.width/2, y: image.size.height/2)
        overlays = []
        selectedOverlayID = nil
        isTyping = false
        typedText = ""
        selectedFontName = nil
        textColor = .black
        fontSize = 28
        selectedFilter = .none
        brightness = 0.0
        contrast = 1.0
    }
}

// MARK: - Combined Filter + Adjust view
private struct CombinedAdjustView: View {
    let baseImage: UIImage
    let overlays: [TextOverlay]
    let initialFilter: FilterKind
    let initialBrightness: Double
    let initialContrast: Double
    let onNext: (FilterKind, Double, Double) -> Void

    @State private var localFilter: FilterKind
    @State private var localBrightness: Double
    @State private var localContrast: Double
    @State private var filteredBasePreview: UIImage

    private let filterService = FilterService()

    init(baseImage: UIImage, overlays: [TextOverlay], initialFilter: FilterKind, initialBrightness: Double, initialContrast: Double, onNext: @escaping (FilterKind, Double, Double) -> Void) {
        self.baseImage = baseImage
        self.overlays = overlays
        self.initialFilter = initialFilter
        self.initialBrightness = initialBrightness
        self.initialContrast = initialContrast
        self.onNext = onNext
        _localFilter = State(initialValue: initialFilter)
        _localBrightness = State(initialValue: initialBrightness)
        _localContrast = State(initialValue: initialContrast)
        _filteredBasePreview = State(initialValue: baseImage)
    }

    var body: some View {
        VStack(spacing: 12) {
            // 預覽區
            SquareCanvas { side in
                ZStack {
                    Image(uiImage: filteredBasePreview)
                        .resizable()
                        .scaledToFit()
                        .frame(width: side, height: side)

                    Image(uiImage: overlayPreviewImage(side: side))
                        .resizable()
                        .scaledToFit()
                        .frame(width: side, height: side)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)

            // Brightness & Contrast
            VStack(alignment: .leading, spacing: 12) {
                Text("Brightness & Contrast")
                    .font(.headline)

                VStack(spacing: 10) {
                    HStack {
                        Text("Brightness")
                            .font(.subheadline)
                            .foregroundStyle(.black.opacity(0.8))

                        let bBinding = Binding<Double>(
                            get: { localBrightness },
                            set: { newVal in
                                let snapped = (newVal * 10).rounded() / 10
                                localBrightness = min(max(snapped, -1), 1)
                                updatePreview()
                            }
                        )
                        Slider(value: bBinding, in: -1...1, step: 0.1)
                    }

                    HStack {
                        Text("Contrast")
                            .font(.subheadline)
                            .foregroundStyle(.black.opacity(0.8))

                        let cBinding = Binding<Double>(
                            get: { localContrast },
                            set: { newVal in
                                let snapped = (newVal * 10).rounded() / 10
                                localContrast = min(max(snapped, 0), 4)
                                updatePreview()
                            }
                        )
                        Slider(value: cBinding, in: 0...4, step: 0.1)
                    }
                }
            }
            .padding(.horizontal)

            // Filter
            VStack(alignment: .leading, spacing: 8) {
                Text("Filters")
                    .font(.headline)
                FilterPickerView(
                    baseImage: baseImage,
                    selected: Binding(
                        get: { localFilter },
                        set: { newValue in
                            localFilter = newValue
                            updatePreview()
                        }
                    ),
                    onSelect: { updatePreview() }
                )
                .padding(.horizontal, 0)
            }
            .padding(.horizontal)

            Spacer()

            // Save / Share buttons
            let finalImage = ContentView.renderTextOverlaysOnImage(
                base: filteredBasePreview,
                overlays: overlays
            )

            HStack {
                Button {
                    UIImageWriteToSavedPhotosAlbum(finalImage, nil, nil, nil)
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.black.opacity(0.06))
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                ShareLink(item: Image(uiImage: finalImage), preview: SharePreview("Edited Image", image: Image(uiImage: finalImage))) {
                    Text("Share")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.black.opacity(0.08))
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .background(GrayscaleRadialBackground().ignoresSafeArea())
        .navigationTitle("Adjust")
        .onAppear {
            updatePreview()
        }
    }

    private func overlayPreviewImage(side: CGFloat) -> UIImage {
        ContentView.renderTextOverlaysLayer(
            size: CGSize(width: side, height: side),
            scale: UIScreen.main.scale,
            overlays: overlays
        )
    }

    private func updatePreview() {
        filteredBasePreview = filterService.render(image: baseImage, filter: localFilter, brightness: localBrightness, contrast: localContrast)
        onNext(localFilter, localBrightness, localContrast)
    }
}

// MARK: - SwiftUI overlay presentation (unused but kept for parity)
private struct OverlayTextView: View {
    let overlay: TextOverlay

    var body: some View {
        var font: Font
        if let name = overlay.fontName, !name.isEmpty {
            font = .custom(name, size: overlay.fontSize).weight(overlay.fontWeight)
        } else {
            font = .system(size: overlay.fontSize, weight: overlay.fontWeight)
        }

        return Text(overlay.text)
            .font(font)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(overlay.hasBackground ? overlay.backgroundColor : Color.clear)
            .foregroundStyle(overlay.textColor)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .offset(x: overlay.position.width, y: overlay.position.height)
    }
}

// MARK: - Square canvas helper
private struct SquareCanvas<Content: View>: View {
    let content: (CGFloat) -> Content
    init(@ViewBuilder content: @escaping (CGFloat) -> Content) {
        self.content = content
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.width)
            ZStack {
                GrayscaleRadialBackground()
                content(side)
                    .frame(width: side, height: side)
                    .clipped()
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.15), lineWidth: 1))
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(height: 360)
        .background(GrayscaleRadialBackground())
    }
}

// MARK: - Vertical size Slider + triangle background
private struct VerticalSizeSlider: View {
    @Binding var value: CGFloat
    var range: ClosedRange<CGFloat>

    var body: some View {
        GeometryReader { geo in
            ZStack {
                TriangleUp()
                    .fill(LinearGradient(colors: [Color.black.opacity(0.06), Color.black.opacity(0.12)],
                                         startPoint: .bottom, endPoint: .top))
                    .padding(.horizontal, 12)

                let dblBinding = Binding<Double>(
                    get: { Double(value) },
                    set: { value = CGFloat($0) }
                )
                Slider(
                    value: dblBinding,
                    in: Double(range.lowerBound)...Double(range.upperBound)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: geo.size.height)
            }
        }
    }
}

private struct TriangleUp: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Camera wrapper
private struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) { }

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let img = info[.originalImage] as? UIImage {
                parent.image = img
            }
            picker.dismiss(animated: true)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

#Preview {
    ContentView()
}

// 共用灰白基調的漸層背景（預設：放射狀）
private struct GrayscaleRadialBackground: View {
    var body: some View {
        RadialGradient(
            gradient: Gradient(colors: [
                Color(white: 0.95),   // 近白
                Color(white: 0.75),
                Color(white: 0.45),   // 中灰
                Color(white: 0.20)    // 深灰
            ]),
            center: .center,
            startRadius: 0,
            endRadius: 1200
        )
    }
}

// 可選：線性灰白漸層背景（若偏好線性可改用此元件）
private struct LinearGrayscaleBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(white: 0.95),
                Color(white: 0.80),
                Color(white: 0.55),
                Color(white: 0.25)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
