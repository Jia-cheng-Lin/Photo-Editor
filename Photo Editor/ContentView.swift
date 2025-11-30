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
    // Background color options (same palette; opacity controlled by slider)
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
                    switch step.kind {
                    case .transform:
                        TransformView()
                    case .addText(let baseImage):
                        AddTextView(baseImage: baseImage)
                    case .igAddText(let baseImage):
                        IGTextAddView(baseImage: baseImage)
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
                            },
                            onExport: { filteredBase, overlays in
                                let final = ContentView.renderTextOverlaysOnImage(base: filteredBase, overlays: overlays)
                                UIImageWriteToSavedPhotosAlbum(final, nil, nil, nil)
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

                        // Zoom damping
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

    // MARK: - Step 2: Add Text (panel)
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
                        DraggableTextOverlay(
                            overlay: binding(for: overlay),
                            isSelected: selectedOverlayID == overlay.id,
                            onTap: { handleSelectOverlay(overlay) }
                        )
                    }
                }
                .frame(width: side, height: side)
                .contentShape(Rectangle())
                .onTapGesture {
                    let new = makeNewOverlayEmpty()
                    overlays.append(new)
                    handleSelectOverlay(new)
                }
            }
            .padding(.horizontal)

            Spacer(minLength: 8)

            // Tool panel
            VStack(spacing: 10) {
                // Fonts
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(fontOptions, id: \.self) { name in
                            let label = name ?? "System"
                            Text(label)
                                .font(name != nil ? .custom(name!, size: 16) : .system(size: 16))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(currentOverlay?.fontName == name ? Color.black.opacity(0.12) : Color.black.opacity(0.06))
                                .clipShape(Capsule())
                                .onTapGesture {
                                    if let idx = selectedIndex {
                                        overlays[idx].fontName = name
                                        selectedFontName = name
                                    }
                                }
                                .foregroundStyle(.black)
                        }
                    }
                    .padding(.horizontal)
                }

                // Text color
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(colorOptions.indices, id: \.self) { idx in
                            let c = colorOptions[idx]
                            Circle()
                                .fill(c)
                                .frame(width: 28, height: 28)
                                .overlay(Circle().stroke(Color.black.opacity(0.2), lineWidth: 1))
                                .overlay(
                                    Group {
                                        if currentOverlay?.textColor == c {
                                            Circle().stroke(Color.black, lineWidth: 2)
                                        }
                                    }
                                )
                                .onTapGesture {
                                    if let i = selectedIndex {
                                        overlays[i].textColor = c
                                        textColor = c
                                    }
                                }
                        }
                    }
                    .padding(.horizontal)
                }

                // Background toggle + color + opacity
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        Button {
                            if let i = selectedIndex {
                                overlays[i].hasBackground.toggle()
                                bgEnabled = overlays[i].hasBackground
                            }
                        } label: {
                            Label(bgEnabled ? "Background: On" : "Background: Off", systemImage: bgEnabled ? "rectangle.fill.on.rectangle.fill" : "rectangle.on.rectangle")
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.06))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.black)

                        if selectedIndex != nil {
                            HStack(spacing: 6) {
                                Image(systemName: "square.dashed")
                                Slider(value: Binding(
                                    get: { bgOpacity },
                                    set: { newVal in
                                        bgOpacity = newVal
                                        if let i = selectedIndex {
                                            overlays[i].backgroundColor = color(overlays[i].backgroundColor, withAlpha: newVal)
                                            overlays[i].hasBackground = true
                                            bgEnabled = true
                                        }
                                    }
                                ), in: 0...1)
                                Image(systemName: "square.fill")
                            }
                            .foregroundStyle(.black.opacity(0.8))
                            .frame(maxWidth: 220)
                        }

                        Spacer()
                    }
                    .padding(.horizontal)

                    // Background color palette
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(backgroundOptions.indices, id: \.self) { idx in
                                let base = backgroundOptions[idx]
                                let swatch = color(base, withAlpha: bgOpacity)
                                Circle()
                                    .fill(swatch)
                                    .frame(width: 28, height: 28)
                                    .overlay(Circle().stroke(Color.black.opacity(0.2), lineWidth: 1))
                                    .overlay(
                                        Group {
                                            if colorsEqual(currentOverlay?.backgroundColor, swatch) {
                                                Circle().stroke(Color.black, lineWidth: 2)
                                            }
                                        }
                                    )
                                    .onTapGesture {
                                        if let i = selectedIndex {
                                            overlays[i].backgroundColor = swatch
                                            bgColor = swatch
                                            overlays[i].hasBackground = true
                                            bgEnabled = true
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                // Text + size + vertical slider
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 8) {
                        let textBinding = Binding<String>(
                            get: { currentOverlay?.text ?? "" },
                            set: {
                                if let i = selectedIndex {
                                    overlays[i].text = $0
                                    typedText = $0
                                }
                            }
                        )
                        TextField("Type here", text: textBinding, axis: .vertical)
                            .lineLimit(1...3)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .focused($textFieldFocused)
                            .padding(10)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(.black)

                        let sizeBinding = Binding<CGFloat>(
                            get: { currentOverlay?.fontSize ?? fontSize },
                            set: {
                                if let i = selectedIndex {
                                    overlays[i].fontSize = $0
                                    fontSize = $0
                                }
                            }
                        )
                        HStack {
                            Image(systemName: "textformat.size.smaller")
                            Slider(value: sizeBinding, in: 12...96, step: 1)
                            Image(systemName: "textformat.size.larger")
                        }
                        .foregroundStyle(.black)
                    }

                    let verticalSizeBinding = Binding<CGFloat>(
                        get: { currentOverlay?.fontSize ?? fontSize },
                        set: {
                            if let i = selectedIndex {
                                overlays[i].fontSize = $0
                                fontSize = $0
                            }
                        }
                    )
                    VerticalSizeSlider(value: verticalSizeBinding, range: 12...96)
                        .frame(width: 48, height: 140)
                        .padding(.leading, 8)
                }
                .padding(.horizontal)
                .padding(.bottom, 6)
            }
            .background(.ultraThinMaterial)

            // Bottom buttons
            HStack(spacing: 10) {
                Button(action: { handleAddTextNext(baseImage: baseImage) }) {
                    Text("Next")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.black.opacity(0.08))
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button(action: { pushToIGText(baseImage: baseImage) }) {
                    Text("IG Text")
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
        .background(GrayscaleRadialBackground().ignoresSafeArea())
        .navigationTitle("Add Text")
        .toolbar {
            if textFieldFocused || isTyping {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        textFieldFocused = false
                        isTyping = false
                    }
                }
            }
        }
        .onChange(of: textFieldFocused) { _, focused in
            if !focused { isTyping = false }
        }
    }

    // Selected overlay helpers
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

    // MARK: - IG Text page (on-canvas typing)
    @ViewBuilder
    private func IGTextAddView(baseImage: UIImage) -> some View {
        VStack(spacing: 12) {
            ZStack {
                SquareCanvas { side in
                    ZStack {
                        Image(uiImage: baseImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: side, height: side)

                        // Trash zone while dragging
                        if isDraggingOverlay {
                            TrashZoneView()
                                .frame(width: 120, height: 60)
                                .position(x: side/2, y: side - 40)
                                .background(
                                    GeometryReader { geo in
                                        Color.clear
                                            .onAppear { trashZoneRect = geo.frame(in: .named("Canvas")) }
                                            .onChange(of: geo.size) { _, _ in
                                                trashZoneRect = geo.frame(in: .named("Canvas"))
                                            }
                                    }
                                )
                        }

                        // Overlays: always TextField; size matches text content & font
                        ForEach(overlays) { overlay in
                            let isSelected = (selectedOverlayID == overlay.id)
                            DraggableTypingOverlay(
                                overlay: binding(for: overlay),
                                isSelected: isSelected,
                                onBeginDrag: { isDraggingOverlay = true },
                                onEndDrag: { finalFrame in
                                    isDraggingOverlay = false
                                    if let trash = trashZoneRect, trash.intersects(finalFrame) {
                                        deleteOverlay(overlay)
                                    }
                                },
                                textFieldFocused: _textFieldFocused
                            )
                            .onTapGesture { activateTyping(for: overlay) }
                        }
                    }
                    .coordinateSpace(name: "Canvas")
                }

                // Left vertical size slider for selected overlay
                if let sel = selectedOverlayID, let idx = overlays.firstIndex(where: { $0.id == sel }) {
                    VStack {
                        Spacer()
                        VerticalSizeSlider(value: Binding(
                            get: { overlays[idx].fontSize },
                            set: { overlays[idx].fontSize = $0; fontSize = $0 }
                        ), range: 12...96)
                        .frame(width: 48, height: 220)
                        .padding(.bottom, 40)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 6)
                }
            }
            .padding(.horizontal)

            Spacer(minLength: 8)

            // Bottom toolbars
            VStack(spacing: 10) {
                // Fonts
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(fontOptions, id: \.self) { name in
                            let label = name ?? "System"
                            Text(label)
                                .font(name != nil ? .custom(name!, size: 18) : .system(size: 18))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color.black.opacity(0.06))
                                .clipShape(Capsule())
                                .onTapGesture {
                                    if let sel = selectedOverlayID,
                                       let idx = overlays.firstIndex(where: { $0.id == sel }) {
                                        overlays[idx].fontName = name
                                        selectedFontName = name
                                    }
                                }
                                .foregroundStyle(.black)
                        }
                    }
                    .padding(.horizontal)
                }

                // Text color
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(colorOptions.indices, id: \.self) { idx in
                            let c = colorOptions[idx]
                            Circle()
                                .fill(c)
                                .frame(width: 28, height: 28)
                                .overlay(Circle().stroke(Color.black.opacity(0.2), lineWidth: 1))
                                .overlay(
                                    Group {
                                        if currentOverlay?.textColor == c {
                                            Circle().stroke(Color.black, lineWidth: 2)
                                        }
                                    }
                                )
                                .onTapGesture {
                                    if let sel = selectedOverlayID,
                                       let i = overlays.firstIndex(where: { $0.id == sel }) {
                                        overlays[i].textColor = c
                                        textColor = c
                                    }
                                }
                        }
                    }
                    .padding(.horizontal)
                }

                // Background toggle + color + opacity
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        Button {
                            if let sel = selectedOverlayID,
                               let i = overlays.firstIndex(where: { $0.id == sel }) {
                                overlays[i].hasBackground.toggle()
                                bgEnabled = overlays[i].hasBackground
                            }
                        } label: {
                            Label(bgEnabled ? "Background: On" : "Background: Off", systemImage: bgEnabled ? "rectangle.fill.on.rectangle.fill" : "rectangle.on.rectangle")
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.06))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.black)

                        if selectedIndex != nil {
                            HStack(spacing: 6) {
                                Image(systemName: "square.dashed")
                                Slider(value: Binding(
                                    get: { bgOpacity },
                                    set: { newVal in
                                        bgOpacity = newVal
                                        if let i = selectedIndex {
                                            overlays[i].backgroundColor = color(overlays[i].backgroundColor, withAlpha: newVal)
                                            overlays[i].hasBackground = true
                                            bgEnabled = true
                                        }
                                    }
                                ), in: 0...1)
                                Image(systemName: "square.fill")
                            }
                            .foregroundStyle(.black.opacity(0.8))
                            .frame(maxWidth: 220)
                        }

                        Spacer()
                    }
                    .padding(.horizontal)

                    // Background color palette
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(backgroundOptions.indices, id: \.self) { idx in
                                let base = backgroundOptions[idx]
                                let swatch = color(base, withAlpha: bgOpacity)
                                Circle()
                                    .fill(swatch)
                                    .frame(width: 28, height: 28)
                                    .overlay(Circle().stroke(Color.black.opacity(0.2), lineWidth: 1))
                                    .overlay(
                                        Group {
                                            if colorsEqual(currentOverlay?.backgroundColor, swatch) {
                                                Circle().stroke(Color.black, lineWidth: 2)
                                            }
                                        }
                                    )
                                    .onTapGesture {
                                        if let sel = selectedOverlayID,
                                           let i = overlays.firstIndex(where: { $0.id == sel }) {
                                            overlays[i].backgroundColor = swatch
                                            bgColor = swatch
                                            overlays[i].hasBackground = true
                                            bgEnabled = true
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                Button(action: { handleIGAddTextNext(baseImage: baseImage) }) {
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
        .navigationTitle("IG Text")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add Text") { createAndActivateEmptyOverlay() }
            }
            if textFieldFocused || isTyping {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        textFieldFocused = false
                        isTyping = false
                    }
                }
            }
        }
        .onChange(of: textFieldFocused) { _, focused in
            if !focused { isTyping = false }
        }
    }

    // IG helpers
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

    // MARK: - Helpers

    struct EditorStep: Hashable {
        enum Kind {
            case transform
            case addText(baseImage: UIImage)
            case igAddText(baseImage: UIImage)
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

// MARK: - Draggable typing overlay with TextField (size matches content)
private struct DraggableTypingOverlay: View {
    @Binding var overlay: TextOverlay
    var isSelected: Bool
    var onBeginDrag: () -> Void
    var onEndDrag: (CGRect) -> Void
    @FocusState var textFieldFocused: Bool

    @State private var dragOffset: CGSize = .zero
    @State private var frameInCanvas: CGRect = .zero

    var body: some View {
        textFieldView
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { updateFrame(geo: geo) }
                        .onChange(of: geo.size) { _, _ in updateFrame(geo: geo) }
                        .onChange(of: overlay.position) { _, _ in updateFrame(geo: geo) }
                }
            )
            .offset(x: overlay.position.width + dragOffset.width,
                    y: overlay.position.height + dragOffset.height)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation
                        onBeginDrag()
                    }
                    .onEnded { value in
                        overlay.position.width += value.translation.width
                        overlay.position.height += value.translation.height
                        dragOffset = .zero
                        onEndDrag(frameInCanvas)
                    }
            )
            .animation(.snappy, value: overlay.position)
    }

    private var textFieldView: some View {
        let font = fontForOverlay()
        return TextField("Type here", text: Binding(
            get: { overlay.text },
            set: { overlay.text = $0 }
        ), axis: .vertical)
        .lineLimit(1...3)
        .textInputAutocapitalization(.never)
        .disableAutocorrection(true)
        .focused($textFieldFocused, equals: true)
        .font(font)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(overlay.hasBackground ? overlay.backgroundColor : Color.clear)
        .foregroundStyle(overlay.textColor)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.2, dash: [6, 4]))
            }
        }
        .onAppear {
            if isSelected {
                DispatchQueue.main.async { self.textFieldFocused = true }
            }
        }
        .onChange(of: isSelected) { _, newValue in
            if newValue {
                DispatchQueue.main.async { self.textFieldFocused = true }
            } else {
                self.textFieldFocused = false
            }
        }
        .background(
            SizeReader { size in
                overlay.measuredSize = size
            }
        )
    }

    private func fontForOverlay() -> Font {
        if let name = overlay.fontName, !name.isEmpty {
            return .custom(name, size: overlay.fontSize).weight(overlay.fontWeight)
        } else {
            return .system(size: overlay.fontSize, weight: overlay.fontWeight)
        }
    }

    private func updateFrame(geo: GeometryProxy) {
        let size = geo.size
        overlay.measuredSize = size
        let origin = CGPoint(x: overlay.position.width, y: overlay.position.height)
        frameInCanvas = CGRect(origin: origin, size: size)
    }
}

// Helper to read rendered size of a view
private struct SizeReader: View {
    var onChange: (CGSize) -> Void
    var body: some View {
        GeometryReader { geo in
            Color.clear
                .preference(key: SizePreferenceKey.self, value: geo.size)
        }
        .onPreferenceChange(SizePreferenceKey.self, perform: onChange)
    }
}

private struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
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

private struct GrayscaleRadialBackground_Preview: View {
    var body: some View {
        GrayscaleRadialBackground()
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

