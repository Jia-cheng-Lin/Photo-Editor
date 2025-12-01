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

    // Step 2/IG: Text overlays
    @State private var overlays: [TextOverlay] = []
    @State private var selectedOverlayID: UUID? = nil
    @State private var isTyping: Bool = false
    @FocusState private var textFieldFocused: Bool

    // Simple typing inputs (mirror selected overlay)
    @State private var typedText: String = ""
    @State private var selectedFontName: String? = nil
    @State private var textColor: Color = .black
    @State private var fontSize: CGFloat = 28
    @State private var bgEnabled: Bool = false
    @State private var bgColor: Color = Color.black.opacity(0.06)
    @State private var bgOpacity: Double = 0.06

    // UI options
    private let fontOptions: [String?] = [nil, "PingFang TC", "Helvetica Neue", "Avenir Next", "Georgia", "Times New Roman", "Courier New"]
    private let colorOptions: [Color] = [.black, .white, .red, .orange, .yellow, .green, .blue, .purple]
    private let backgroundOptions: [Color] = [.black, .white, .red, .orange, .yellow, .green, .blue, .purple]

    // Step 3: filter + adjustments
    @State private var selectedFilter: FilterKind = .none
    @State private var brightness: Double = 0.0
    @State private var contrast: Double = 1.0

    private let filterService = FilterService()

    var body: some View {
        NavigationStack(path: $path) {
            startScreen
                .navigationDestination(for: EditorStep.self) { step in
                    destination(for: step)
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

            PickImageCanvas(
                originalImage: originalImage,
                onTap: { showImageSourceMenu = true }
            )
            .padding(.horizontal)

            Spacer(minLength: 8)

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

    private func destination(for step: EditorStep) -> some View {
        switch step.kind {
        case .transform:
            return AnyView(TransformStepView(
                originalImage: originalImage,
                currentZoom: $currentZoom,
                dragOffsetScreen: $dragOffsetScreen,
                cumulativeOffsetScreen: $cumulativeOffsetScreen,
                centerInImage: $centerInImage,
                onNext: handleTransformNext
            ))
        case .addText(let baseImage):
            return AnyView(AddTextStepView(
                baseImage: baseImage,
                overlays: $overlays,
                selectedOverlayID: $selectedOverlayID,
                isTyping: $isTyping,
                textFieldFocused: _textFieldFocused,
                typedText: $typedText,
                selectedFontName: $selectedFontName,
                textColor: $textColor,
                fontSize: $fontSize,
                bgEnabled: $bgEnabled,
                bgColor: $bgColor,
                bgOpacity: $bgOpacity,
                fontOptions: fontOptions,
                colorOptions: colorOptions,
                backgroundOptions: backgroundOptions,
                bindingFor: binding(for:),
                currentOverlay: { currentOverlay },
                selectedIndex: { selectedIndex },
                onSelectOverlay: handleSelectOverlay,
                onNext: handleAddTextNext,
                onIGText: pushToIGText
            ))
        case .igAddText(let baseImage):
            return AnyView(IGTextStepView(
                baseImage: baseImage,
                overlays: $overlays,
                selectedOverlayID: $selectedOverlayID,
                isTyping: $isTyping,
                textFieldFocused: _textFieldFocused,
                typedText: $typedText,
                selectedFontName: $selectedFontName,
                textColor: $textColor,
                fontSize: $fontSize,
                bgEnabled: $bgEnabled,
                bgColor: $bgColor,
                bgOpacity: $bgOpacity,
                fontOptions: fontOptions,
                colorOptions: colorOptions,
                backgroundOptions: backgroundOptions,
                bindingFor: binding(for:),
                currentOverlay: { currentOverlay },
                selectedIndex: { selectedIndex },
                onCreateEmpty: createAndActivateEmptyOverlay,
                onActivate: activateTyping(for:),
                onDelete: deleteOverlay(_:),
                onNext: handleIGAddTextNext
            ))
        case .combinedAdjust(let baseImage, let overlays):
            return AnyView(CombinedAdjustView(
                baseImage: baseImage,
                overlays: overlays,
                initialFilter: selectedFilter,
                initialBrightness: brightness,
                initialContrast: contrast,
                onNext: { chosenFilter, b, c in
                    selectedFilter = chosenFilter
                    brightness = b
                    contrast = c
                },
                onExport: { _, _ in }
            )
            .onPreferenceChange(ExportRequestKey.self) { req in
                guard let req else { return }
                path.append(.init(kind: .export(filteredBase: req.filteredBase, overlays: req.overlays)))
            })
        case .export(let filteredBase, let overlays):
            return AnyView(ExportView(filteredBase: filteredBase, overlays: overlays))
        }
    }

    private func pushToTransform() {
        path = [.init(kind: .transform)]
    }

    // MARK: - Step 1: Transform
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

    // MARK: - Step 2: Add Text helpers
    private var selectedIndex: Int? {
        guard let sel = selectedOverlayID,
              let idx = overlays.firstIndex(where: { $0.id == sel }) else { return nil }
        return idx
    }
    private var currentOverlay: TextOverlay? {
        guard let i = selectedIndex else { return nil }
        return overlays[i]
    }

    private func handleSelectOverlay(_ overlay: TextOverlay) {
        selectedOverlayID = overlay.id
        isTyping = true
        textFieldFocused = true
        typedText = overlay.text
        selectedFontName = overlay.fontName
        textColor = overlay.textColor
        fontSize = overlay.fontSize
        bgEnabled = overlay.hasBackground
        bgColor = overlay.backgroundColor
        bgOpacity = alpha(of: overlay.backgroundColor)
    }

    private func handleAddTextNext(baseImage: UIImage) {
        let overlaysSnapshot = overlays
        path.append(.init(kind: .combinedAdjust(baseImage: baseImage, overlays: overlaysSnapshot)))
    }

    private func pushToIGText(baseImage: UIImage) {
        path.append(.init(kind: .igAddText(baseImage: baseImage)))
    }

    private func makeNewOverlayEmpty() -> TextOverlay {
        TextOverlay(
            text: "",
            position: .zero,
            fontSize: 28,
            fontWeight: .bold,
            fontName: nil,
            textColor: .black,
            hasBackground: false,
            backgroundColor: Color.black.opacity(0.06),
            measuredSize: .zero
        )
    }

    // MARK: - IG Text helpers
    @State private var isDraggingOverlay: Bool = false
    @State private var trashZoneRect: CGRect? = nil

    private func createAndActivateEmptyOverlay() {
        let new = makeNewOverlayEmpty()
        overlays.append(new)
        activateTyping(for: new)
    }

    private func activateTyping(for overlay: TextOverlay) {
        selectedOverlayID = overlay.id
        isTyping = true
        textFieldFocused = true
        typedText = overlay.text
        selectedFontName = overlay.fontName
        textColor = overlay.textColor
        fontSize = overlay.fontSize
        bgEnabled = overlay.hasBackground
        bgColor = overlay.backgroundColor
        bgOpacity = alpha(of: overlay.backgroundColor)
    }

    private func deleteOverlay(_ overlay: TextOverlay) {
        if let idx = overlays.firstIndex(where: { $0.id == overlay.id }) {
            overlays.remove(at: idx)
        }
        if selectedOverlayID == overlay.id {
            selectedOverlayID = nil
            isTyping = false
            textFieldFocused = false
        }
    }

    private func handleIGAddTextNext(baseImage: UIImage) {
        let overlaysSnapshot = overlays
        path.append(.init(kind: .combinedAdjust(baseImage: baseImage, overlays: overlaysSnapshot)))
    }

    // MARK: - Render helpers for overlays
    static func renderTextOverlaysLayer(size: CGSize, scale: CGFloat, overlays: [TextOverlay]) -> UIImage {
        let renderSize = size
        UIGraphicsBeginImageContextWithOptions(renderSize, false, scale)
        defer { UIGraphicsEndImageContext() }

        for ov in overlays {
            let uiFont: UIFont = makeUIFont(fontName: ov.fontName, size: ov.fontSize, weight: ov.fontWeight)

            let attrs: [NSAttributedString.Key: Any] = [
                .font: uiFont,
                .foregroundColor: uiColor(from: ov.textColor)
            ]

            let textSize: CGSize = {
                if ov.measuredSize != .zero { return ov.measuredSize }
                let ns = ov.text as NSString
                let bounds = ns.boundingRect(with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
                                             options: [.usesLineFragmentOrigin, .usesFontLeading],
                                             attributes: attrs,
                                             context: nil).integral
                return bounds.size
            }()

            let canvasCenter = CGPoint(x: renderSize.width/2, y: renderSize.height/2)
            let origin = CGPoint(
                x: canvasCenter.x - textSize.width/2 + ov.position.width,
                y: canvasCenter.y - textSize.height/2 + ov.position.height
            )

            if ov.hasBackground {
                let bgRect = CGRect(origin: origin, size: textSize).insetBy(dx: -8, dy: -6)
                let path = UIBezierPath(roundedRect: bgRect, cornerRadius: 8)
                uiColor(from: ov.backgroundColor).setFill()
                path.fill()
            }

            let ns = ov.text as NSString
            ns.draw(at: origin, withAttributes: attrs)
        }

        return UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
    }

    static func renderTextOverlaysOnImage(base: UIImage, overlays: [TextOverlay]) -> UIImage {
        let side = min(base.size.width, base.size.height)
        let renderSize = CGSize(width: side, height: side)

        UIGraphicsBeginImageContextWithOptions(renderSize, false, base.scale)
        defer { UIGraphicsEndImageContext() }

        base.draw(in: CGRect(origin: .zero, size: renderSize))

        for ov in overlays {
            let uiFont: UIFont = makeUIFont(fontName: ov.fontName, size: ov.fontSize, weight: ov.fontWeight)

            let attrs: [NSAttributedString.Key: Any] = [
                .font: uiFont,
                .foregroundColor: uiColor(from: ov.textColor)
            ]

            let textSize: CGSize = {
                if ov.measuredSize != .zero { return ov.measuredSize }
                let ns = ov.text as NSString
                let bounds = ns.boundingRect(with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
                                             options: [.usesLineFragmentOrigin, .usesFontLeading],
                                             attributes: attrs,
                                             context: nil).integral
                return bounds.size
            }()

            let canvasCenter = CGPoint(x: renderSize.width/2, y: renderSize.height/2)
            let origin = CGPoint(
                x: canvasCenter.x - textSize.width/2 + ov.position.width,
                y: canvasCenter.y - textSize.height/2 + ov.position.height
            )

            if ov.hasBackground {
                let bgRect = CGRect(origin: origin, size: textSize).insetBy(dx: -8, dy: -6)
                let path = UIBezierPath(roundedRect: bgRect, cornerRadius: 8)
                uiColor(from: ov.backgroundColor).setFill()
                path.fill()
            }

            let ns = ov.text as NSString
            ns.draw(at: origin, withAttributes: attrs)
        }

        return UIGraphicsGetImageFromCurrentImageContext() ?? base
    }

    private static func makeUIFont(fontName: String?, size: CGFloat, weight: Font.Weight) -> UIFont {
        let uiWeight: UIFont.Weight = {
            switch weight {
            case .ultraLight: return .ultraLight
            case .thin: return .thin
            case .light: return .light
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            case .heavy: return .heavy
            case .black: return .black
            default: return .regular
            }
        }()

        guard let name = fontName, !name.isEmpty else {
            return UIFont.systemFont(ofSize: size, weight: uiWeight)
        }

        if let baseFont = UIFont(name: name, size: size) {
            let traits: [UIFontDescriptor.TraitKey: Any] = [
                .weight: uiWeight
            ]
            let desc = baseFont.fontDescriptor.addingAttributes([.traits: traits])
            let weighted = UIFont(descriptor: desc, size: size)
            return weighted
        } else {
            return UIFont.systemFont(ofSize: size, weight: uiWeight)
        }
    }

    // Binding for overlay
    private func binding(for: TextOverlay) -> Binding<TextOverlay> {
        guard let idx = overlays.firstIndex(where: { $0.id == `for`.id }) else {
            return .constant(`for`)
        }
        return $overlays[idx]
    }

    // MARK: - Camera / Picker helpers

    struct EditorStep: Hashable {
        enum Kind {
            case transform
            case addText(baseImage: UIImage)
            case igAddText(baseImage: UIImage)
            case combinedAdjust(baseImage: UIImage, overlays: [TextOverlay])
            case export(filteredBase: UIImage, overlays: [TextOverlay])
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
        bgEnabled = false
        bgColor = Color.black.opacity(0.06)
        bgOpacity = 0.06
    }

    // MARK: - Color helpers
    private func alpha(of color: Color) -> Double {
        Double(UIColor(color).cgColor.alpha)
    }

    private func color(_ base: Color, withAlpha alpha: Double) -> Color {
        let ui = UIColor(base)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return Color(red: Double(r), green: Double(g), blue: Double(b), opacity: alpha)
    }

    private func colorsEqual(_ c1: Color?, _ c2: Color) -> Bool {
        guard let c1 else { return false }
        let u1 = ContentView.uiColor(from: c1)
        let u2 = ContentView.uiColor(from: c2)
        return u1.isEqual(u2)
    }

    private static func uiColor(from color: Color) -> UIColor {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if ui.getRed(&r, green: &g, blue: &b, alpha: &a) {
            return UIColor(red: r, green: g, blue: b, alpha: a)
        } else {
            return ui
        }
    }
}

// MARK: - Small subviews to reduce type-check complexity

private struct PickImageCanvas: View {
    let originalImage: UIImage?
    let onTap: () -> Void

    var body: some View {
        SquareCanvas { side in
            ZStack {
                if let img = originalImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(width: side, height: side)
                } else {
                    EmptyPickHint()
                        .frame(width: side, height: side)
                }
            }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
        }
    }
}

private struct EmptyPickHint: View {
    var body: some View {
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
    }
}

private struct TransformStepView: View {
    let originalImage: UIImage?
    @Binding var currentZoom: CGFloat
    @Binding var dragOffsetScreen: CGSize
    @Binding var cumulativeOffsetScreen: CGSize
    @Binding var centerInImage: CGPoint?

    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            SquareCanvas { side in
                ZStack {
                    if let base = originalImage {
                        TransformCanvasImage(
                            base: base,
                            side: side,
                            currentZoom: $currentZoom,
                            dragOffsetScreen: $dragOffsetScreen,
                            cumulativeOffsetScreen: $cumulativeOffsetScreen,
                            centerInImage: $centerInImage
                        )
                    }
                }
                .frame(width: side, height: side)
            }
            .padding(.horizontal)

            ZoomSlider(currentZoom: $currentZoom)

            Spacer(minLength: 8)

            VStack(spacing: 10) {
                Button(action: onNext) {
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
}

private struct TransformCanvasImage: View {
    let base: UIImage
    let side: CGFloat
    @Binding var currentZoom: CGFloat
    @Binding var dragOffsetScreen: CGSize
    @Binding var cumulativeOffsetScreen: CGSize
    @Binding var centerInImage: CGPoint?

    var body: some View {
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

                let imageCenter = centerInImage ?? CGPoint(x: base.size.width/2, y: base.size.height/2)
                var newCenter = CGPoint(
                    x: imageCenter.x + deltaInBitmap.x,
                    y: imageCenter.y + deltaInBitmap.y
                )

                newCenter.x = max(0, min(base.size.width, newCenter.x))
                newCenter.y = max(0, min(base.size.height, newCenter.y))

                centerInImage = newCenter
                dragOffsetScreen = .zero
            }

        let zoomRange: ClosedRange<CGFloat> = 0.5...3.0
        let zoomDamping: CGFloat = 0.3

        let magnify = MagnificationGesture()
            .onChanged { scale in
                let delta = scale - 1
                let adjusted = 1 + delta * zoomDamping
                currentZoom = (currentZoom * adjusted).clamped(to: zoomRange)
            }
            .onEnded { finalScale in
                let delta = finalScale - 1
                let adjusted = 1 + delta * zoomDamping
                currentZoom = (currentZoom * adjusted).clamped(to: zoomRange)
            }

        return Image(uiImage: base)
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

private struct ZoomSlider: View {
    @Binding var currentZoom: CGFloat

    var body: some View {
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
    }
}

#Preview {
    ContentView()
}
