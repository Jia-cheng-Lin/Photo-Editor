import SwiftUI

struct IGTextStepView: View {
    let baseImage: UIImage

    @Binding var overlays: [TextOverlay]
    @Binding var selectedOverlayID: UUID?
    @Binding var isTyping: Bool
    @FocusState var textFieldFocused: Bool

    @Binding var typedText: String
    @Binding var selectedFontName: String?
    @Binding var textColor: Color
    @Binding var fontSize: CGFloat
    @Binding var bgEnabled: Bool
    @Binding var bgColor: Color
    @Binding var bgOpacity: Double

    let fontOptions: [String?]
    let colorOptions: [Color]
    let backgroundOptions: [Color]

    let bindingFor: (TextOverlay) -> Binding<TextOverlay>
    let currentOverlay: () -> TextOverlay?
    let selectedIndex: () -> Int?

    let onCreateEmpty: () -> Void
    let onActivate: (TextOverlay) -> Void
    let onDelete: (TextOverlay) -> Void
    let onNext: (UIImage) -> Void

    @State private var isDraggingOverlay: Bool = false
    @State private var trashZoneRect: CGRect? = nil

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                SquareCanvas { side in
                    ZStack {
                        Image(uiImage: baseImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: side, height: side)

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

                        ForEach(overlays) { ov in
                            DraggableTypingOverlay(
                                overlay: bindingFor(ov),
                                isSelected: selectedOverlayID == ov.id,
                                onBeginDrag: { withAnimation { isDraggingOverlay = true } },
                                onEndDrag: { frame in
                                    withAnimation { isDraggingOverlay = false }
                                    if let trash = trashZoneRect, trash.intersects(frame) {
                                        onDelete(ov)
                                    }
                                },
                                textFieldFocused: _textFieldFocused
                            )
                            .onTapGesture { onActivate(ov) }
                        }
                    }
                    .coordinateSpace(name: "Canvas")
                }

                if let sel = selectedOverlayID,
                   let idx = overlays.firstIndex(where: { $0.id == sel }) {
                    VStack {
                        Spacer()
                        VerticalSizeSlider(
                            value: Binding(
                                get: { overlays[idx].fontSize },
                                set: { overlays[idx].fontSize = $0; fontSize = $0 }
                            ),
                            range: 12...96
                        )
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

            VStack(spacing: 10) {
                // Fonts
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        fontCapsule(label: "System", isSelected: selectedFontName == nil) {
                            applyToSelection { $0.fontName = nil }
                            selectedFontName = nil
                        }
                        ForEach(fontOptions.compactMap { $0 }, id: \.self) { name in
                            fontCapsule(label: name, isSelected: selectedFontName == name) {
                                applyToSelection { $0.fontName = name }
                                selectedFontName = name
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                // Text color
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(colorOptions.indices, id: \.self) { i in
                            let c = colorOptions[i]
                            ColorDot(color: c, selected: currentOverlay()?.textColor == c) {
                                applyToSelection { $0.textColor = c }
                                textColor = c
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                // Background: toggle + opacity + color dots (opaque)
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        Button {
                            applyToSelection {
                                $0.hasBackground.toggle()
                                bgEnabled = $0.hasBackground
                            }
                        } label: {
                            Label(bgEnabled ? "Background: On" : "Background: Off",
                                  systemImage: bgEnabled ? "rectangle.fill.on.rectangle.fill" : "rectangle.on.rectangle")
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.06))
                                .clipShape(Capsule())
                                .foregroundStyle(.black)
                        }
                        .buttonStyle(.plain)

                        if selectedIndex() != nil {
                            HStack(spacing: 6) {
                                Image(systemName: "square.dashed")
                                Slider(value: Binding(
                                    get: { bgOpacity },
                                    set: { newVal in
                                        bgOpacity = newVal
                                        applyToSelection {
                                            $0.backgroundColor = bgColor.opacity(newVal)
                                            $0.hasBackground = true
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

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(backgroundOptions.indices, id: \.self) { i in
                                let base = backgroundOptions[i]
                                ColorDot(color: base, selected: colorsEqualIgnoringAlpha(currentOverlay()?.backgroundColor, base)) {
                                    applyToSelection {
                                        $0.backgroundColor = base.opacity(bgOpacity) // apply opacity to overlay only
                                        $0.hasBackground = true
                                    }
                                    bgColor = base
                                    bgEnabled = true
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                Button {
                    onNext(baseImage)
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
        }
        .padding(.vertical)
        .background(GrayscaleRadialBackground().ignoresSafeArea())
        .navigationTitle("IG Text")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add Text") {
                    // Create and immediately activate to focus keyboard
                    onCreateEmpty()
                    if let ov = overlays.last {
                        onActivate(ov)
                        // Ensure focus flag is set (defensive; activate already sets it upstream)
                        isTyping = true
                        textFieldFocused = true
                    }
                }
            }
            if textFieldFocused || isTyping {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Remove") {
                        if let id = selectedOverlayID,
                           let ov = overlays.first(where: { $0.id == id }) {
                            onDelete(ov)
                        }
                    }
                    Button("Done") {
                        // Freeze background size to avoid later drift
                        if let id = selectedOverlayID,
                           let idx = overlays.firstIndex(where: { $0.id == id }) {
                            overlays[idx].fixedBackgroundSize = overlays[idx].measuredSize
                        }
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

    // Helpers
    private func applyToSelection(_ update: (inout TextOverlay) -> Void) {
        guard let idx = selectedIndex() else { return }
        update(&overlays[idx])
    }

    private func colorsEqualIgnoringAlpha(_ c1: Color?, _ c2: Color) -> Bool {
        guard let c1 else { return false }
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        UIColor(c1).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        UIColor(c2).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return abs(r1 - r2) < 0.001 && abs(g1 - g2) < 0.001 && abs(b1 - b2) < 0.001
    }

    private struct ColorDot: View {
        let color: Color
        let selected: Bool
        let onTap: () -> Void
        var body: some View {
            Circle()
                .fill(color)
                .frame(width: 28, height: 28)
                .overlay(Circle().stroke(Color.black.opacity(0.2), lineWidth: 1))
                .overlay(
                    Group {
                        if selected {
                            Circle().stroke(Color.black, lineWidth: 2)
                        }
                    }
                )
                .onTapGesture { onTap() }
        }
    }

    private func fontCapsule(label: String, isSelected: Bool, onTap: @escaping () -> Void) -> some View {
        Text(label)
            .font(.system(size: 18))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.06))
            .clipShape(Capsule())
            .foregroundStyle(.black)
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.black : Color.clear, lineWidth: 2)
            )
            .onTapGesture(perform: onTap)
    }
}
