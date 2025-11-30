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

    // Step 2/IG: Text overlays (shared if desired; each step takes a snapshot when navigating)
    @State private var overlays: [TextOverlay] = []
    @State private var selectedOverlayID: UUID? = nil
    @State private var isTyping: Bool = false
    @FocusState private var textFieldFocused: Bool

    // Simple typing inputs (for original typing panel)
    @State private var typedText: String = ""
    @State private var selectedFontName: String? = nil
    @State private var textColor: Color = .black
    @State private var fontSize: CGFloat = 28

    // UI options
    private let fontOptions: [String?] = [nil, "PingFang TC", "Helvetica Neue", "Avenir Next", "Georgia", "Times New Roman", "Courier New"]
    private let colorOptions: [Color] = [.black, .white, .red, .orange, .yellow, .green, .blue, .purple]

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

    // MARK: - Step 2: Add Text (Original typing panel)
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
                    // 新增一個 overlay 並選取以供底部輸入
                    let new = makeNewOverlayEmpty()
                    overlays.append(new)
                    handleSelectOverlay(new)
                }
            }
            .padding(.horizontal)

            Spacer(minLength: 8)

            // 下方：兩個按鈕（Next 與 IG Text）
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
            // 顯示鍵盤時提供「完成」按鈕
            if textFieldFocused || isTyping {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        textFieldFocused = false
                        isTyping = false
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let sel = selectedOverlayID,
               let index = overlays.firstIndex(where: { $0.id == sel }) {
                VStack(spacing: 8) {
                    // 字體選擇
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

                    // 顏色選擇
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

                    // 文字輸入 + 字級
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 8) {
                            let textBinding = Binding<String>(
                                get: { overlays[index].text },
                                set: { overlays[index].text = $0; typedText = $0 }
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

    private func handleAddTextNext(baseImage: UIImage) {
        let overlaysSnapshot = overlays
        path.append(.init(kind: .combinedAdjust(baseImage: baseImage, overlays: overlaysSnapshot)))
    }

    private func pushToIGText(baseImage: UIImage) {
        // 進到 IG 式打字頁，沿用目前 overlays 當作初始值（或想要清空可改成 overlays = [] 再傳）
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

    // MARK: - Step IG: On-canvas typing page (IG style)
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

                        // 拖曳時顯示垃圾桶區
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

                        // 文字 overlays（可拖曳、選取即打字）
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

                // 左側垂直字級滑桿（作用於選取中的 overlay）
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

            // 下方：字體與顏色列（以「Font」無名稱樣式）
            VStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(fontOptions, id: \.self) { name in
                            let label = "Font"
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

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(colorOptions.indices, id: \.self) { idx in
                            let c = colorOptions[idx]
                            Circle()
                                .fill(c)
                                .frame(width: 28, height: 28)
                                .overlay(Circle().stroke(Color.black.opacity(0.2), lineWidth: 1))
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
            // 右上角：新增文字
            ToolbarItem(placement: .topBarTrailing) {
                Button("Text") { createAndActivateEmptyOverlay() }
            }
            // 鍵盤出現時顯示「完成」
            if textFieldFocused || isTyping {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
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
                .foregroundColor: UIColor(ov.textColor)
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
                UIColor(ov.backgroundColor).setFill()
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
                .foregroundColor: UIColor(ov.textColor)
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
                UIColor(ov.backgroundColor).setFill()
                path.fill()
            }

            let ns = ov.text as NSString
            ns.draw(at: origin, withAttributes: attrs)
        }

        return UIGraphicsGetImageFromCurrentImageContext() ?? base
    }

    // 統一字型建立：盡可能讓 Core Graphics 與 SwiftUI 的 Font(weight) 視覺一致
    private static func makeUIFont(fontName: String?, size: CGFloat, weight: Font.Weight) -> UIFont {
        // 將 SwiftUI Font.Weight 映射到 UIFont.Weight
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

        // 沒有指定字體名稱 → 系統字體直接用 weight
        guard let name = fontName, !name.isEmpty else {
            return UIFont.systemFont(ofSize: size, weight: uiWeight)
        }

        // 指定字體名稱：先嘗試載入，再加上 weight trait
        if let baseFont = UIFont(name: name, size: size) {
            // 透過字體描述符加上 weight trait
            let traits: [UIFontDescriptor.TraitKey: Any] = [
                .weight: uiWeight
            ]
            let desc = baseFont.fontDescriptor.addingAttributes([.traits: traits])
            let weighted = UIFont(descriptor: desc, size: size)

            // 若字型家族不支援該 weight，weighted.pointSize 仍正確但外觀可能不變。
            // 為了保證至少有對應粗細，若 weighted 與 baseFont 的字重無法觀察差異，可 fallback 為系統字體。
            // 在這裡直接回傳 weighted；如需更激進可檢查 familyNames/availableMembers 做更精細對應。
            return weighted
        } else {
            // 名稱無效時退回系統字體
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
            case addText(baseImage: UIImage)       // 原本的打字方式（底部輸入欄）
            case igAddText(baseImage: UIImage)     // IG 式畫布上打字
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

// MARK: - Draggable typing overlay with trash delete (IG style)
private struct DraggableTypingOverlay: View {
    @Binding var overlay: TextOverlay
    var isSelected: Bool
    var onBeginDrag: () -> Void
    var onEndDrag: (CGRect) -> Void
    @FocusState var textFieldFocused: Bool

    @State private var dragOffset: CGSize = .zero
    @State private var frameInCanvas: CGRect = .zero

    var body: some View {
        content
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

    @ViewBuilder
    private var content: some View {
        if isSelected {
            textFieldView
        } else {
            textView
        }
    }

    private var textView: some View {
        let font = fontForOverlay()
        return Text(overlay.text.isEmpty ? "Type here" : overlay.text)
            .font(font)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(overlay.hasBackground ? overlay.backgroundColor : Color.clear)
            .foregroundStyle(overlay.textColor)
            .clipShape(RoundedRectangle(cornerRadius: 8))
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
        .focused($textFieldFocused)
        .font(font)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(overlay.hasBackground ? overlay.backgroundColor : Color.clear)
        .foregroundStyle(overlay.textColor)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear { DispatchQueue.main.async { self.textFieldFocused = true } }
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

// MARK: - Trash zone view
private struct TrashZoneView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.6), lineWidth: 2))
            Image(systemName: "trash")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.red)
        }
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

            VStack(alignment: .leading, spacing: 12) {
                Text("Brightness & Contrast")
                    .font(.headline)

                VStack(spacing: 10) {
                    HStack {
                        Text("Brightness")
                            .font(.subheadline)
                            .foregroundStyle(.black.opacity(0.8))
                        Slider(value: Binding(
                            get: { localBrightness },
                            set: { localBrightness = ( ($0 * 10).rounded() / 10 ).clamped(to: -1...1); updatePreview() }
                        ), in: -1...1, step: 0.1)
                    }
                    HStack {
                        Text("Contrast")
                            .font(.subheadline)
                            .foregroundStyle(.black.opacity(0.8))
                        Slider(value: Binding(
                            get: { localContrast },
                            set: { localContrast = ( ($0 * 10).rounded() / 10 ).clamped(to: 0...4); updatePreview() }
                        ), in: 0...4, step: 0.1)
                    }
                }
            }
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 8) {
                Text("Filters")
                    .font(.headline)
                FilterPickerView(
                    baseImage: baseImage,
                    selected: Binding(
                        get: { localFilter },
                        set: { localFilter = $0; updatePreview() }
                    ),
                    onSelect: { updatePreview() }
                )
                .padding(.horizontal, 0)
            }
            .padding(.horizontal)

            Spacer()

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
                Color(white: 0.95),
                Color(white: 0.75),
                Color(white: 0.45),
                Color(white: 0.20)
            ]),
            center: .center,
            startRadius: 0,
            endRadius: 1200
        )
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

