import SwiftUI

struct AddTextStepView: View {
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

    // helpers from ContentView
    let bindingFor: (TextOverlay) -> Binding<TextOverlay>
    let currentOverlay: () -> TextOverlay?
    let selectedIndex: () -> Int?

    let onSelectOverlay: (TextOverlay) -> Void
    let onNext: (UIImage) -> Void
    let onIGText: (UIImage) -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Move the canvas slightly lower for page alignment parity
            Spacer(minLength: 4)

            // Canvas with left vertical size slider
            SquareCanvas { side in
                ZStack(alignment: .leading) {
                    ZStack {
                        Image(uiImage: baseImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: side, height: side)

                        ForEach(overlays) { overlay in
                            DraggableTextOverlay(
                                overlay: bindingFor(overlay),
                                isSelected: selectedOverlayID == overlay.id,
                                onTap: { onSelectOverlay(overlay) }
                            )
                        }
                    }
                    .frame(width: side, height: side)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let new = makeNewOverlay()
                        overlays.append(new)
                        onSelectOverlay(new)
                    }

                    // Vertical size slider on the left side of the image.
                    if let i = selectedIndex() {
                        VerticalSizeSlider(
                            value: Binding(
                                get: { overlays[i].fontSize },
                                set: { overlays[i].fontSize = $0; fontSize = $0 }
                            ),
                            range: 12...96
                        )
                        .frame(width: 48, height: side * 0.6)
                        .padding(.leading, 8)
                    }
                }
                .frame(width: side, height: side)
            }
            .padding(.horizontal)

            // Raise buttons a bit by reducing extra spacer
            Spacer(minLength: 4)

            // Tool panel (fonts, text color, background controls, text field)
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
                                .background((currentOverlay()?.fontName == name) ? Color.black.opacity(0.12) : Color.black.opacity(0.06))
                                .clipShape(Capsule())
                                .onTapGesture {
                                    if let i = selectedIndex() {
                                        overlays[i].fontName = name
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
                                        if currentOverlay()?.textColor == c {
                                            Circle().stroke(Color.black, lineWidth: 2)
                                        }
                                    }
                                )
                                .onTapGesture {
                                    if let i = selectedIndex() {
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
                            if let i = selectedIndex() {
                                overlays[i].hasBackground.toggle()
                                bgEnabled = overlays[i].hasBackground
                            }
                        } label: {
                            Label(bgEnabled ? "Background: On" : "Background: Off",
                                  systemImage: bgEnabled ? "rectangle.fill.on.rectangle.fill" : "rectangle.on.rectangle")
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.06))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.black)

                        if selectedIndex() != nil {
                            HStack(spacing: 6) {
                                Image(systemName: "square.dashed")
                                Slider(value: Binding(
                                    get: { bgOpacity },
                                    set: { newVal in
                                        bgOpacity = newVal
                                        if let i = selectedIndex() {
                                            // keep swatches opaque; apply opacity to overlay only
                                            let base = bgColor
                                            overlays[i].backgroundColor = base.opacity(newVal)
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

                    // Background color palette (opaque dots)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(backgroundOptions.indices, id: \.self) { idx in
                                let base = backgroundOptions[idx]
                                Circle()
                                    .fill(base)
                                    .frame(width: 28, height: 28)
                                    .overlay(Circle().stroke(Color.black.opacity(0.2), lineWidth: 1))
                                    .overlay(
                                        Group {
                                            if colorsEqualIgnoringAlpha(currentOverlay()?.backgroundColor, base) {
                                                Circle().stroke(Color.black, lineWidth: 2)
                                            }
                                        }
                                    )
                                    .onTapGesture {
                                        if let i = selectedIndex() {
                                            bgColor = base
                                            overlays[i].backgroundColor = base.opacity(bgOpacity)
                                            overlays[i].hasBackground = true
                                            bgEnabled = true
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                // TextField only (horizontal slider removed)
                let textBinding = Binding<String>(
                    get: { currentOverlay()?.text ?? "" },
                    set: {
                        if let i = selectedIndex() {
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
                    .padding(.horizontal)
                    .padding(.bottom, 2) // slightly tighter to raise the bottom buttons
            }
            .background(.ultraThinMaterial)

            // Bottom buttons (raised a bit)
            HStack(spacing: 10) {
                Button(action: { onNext(baseImage) }) {
                    Text("Next")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.black.opacity(0.08))
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button(action: { onIGText(baseImage) }) {
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
            .padding(.top, 2) // small raise
            .padding(.bottom, 8)
        }
        .padding(.vertical)
        .background(GrayscaleRadialBackground().ignoresSafeArea())
        .navigationTitle("Add Text")
        .toolbar {
            if textFieldFocused || isTyping {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Remove") {
                        if let id = selectedOverlayID,
                           let idx = overlays.firstIndex(where: { $0.id == id }) {
                            overlays.remove(at: idx)
                            selectedOverlayID = nil
                            isTyping = false
                            textFieldFocused = false
                        }
                    }
                    Button("Done") {
                        textFieldFocused = false
                        isTyping = false
                    }
                }
            }
        }
        .onChange(of: selectedOverlayID) { _, newValue in
            guard let id = newValue, let ov = overlays.first(where: { $0.id == id }) else { return }
            syncFromOverlay(ov)
        }
        .onChange(of: textFieldFocused) { _, focused in
            if !focused { isTyping = false }
        }
        // Keep simple editor inputs in sync when changed from panel
        .onChange(of: selectedFontName) { _, newVal in
            if let i = selectedIndex() {
                overlays[i].fontName = (newVal?.isEmpty == true) ? nil : newVal
            }
        }
        .onChange(of: textColor) { _, newVal in
            if let i = selectedIndex() { overlays[i].textColor = newVal }
        }
        .onChange(of: fontSize) { _, newVal in
            if let i = selectedIndex() { overlays[i].fontSize = newVal }
        }
        .onChange(of: bgEnabled) { _, newVal in
            if let i = selectedIndex() { overlays[i].hasBackground = newVal }
        }
        .onChange(of: bgColor) { _, newVal in
            if let i = selectedIndex() { overlays[i].backgroundColor = newVal.opacity(bgOpacity) }
        }
        .onChange(of: bgOpacity) { _, newVal in
            if let i = selectedIndex() { overlays[i].backgroundColor = bgColor.opacity(newVal) }
        }
    }

    // MARK: - Helpers

    private func makeNewOverlay() -> TextOverlay {
        TextOverlay(
            text: "",
            position: .zero,
            fontSize: 28,
            fontWeight: .bold,
            fontName: selectedFontName,
            textColor: textColor,
            hasBackground: bgEnabled,
            backgroundColor: bgColor.opacity(bgOpacity),
            measuredSize: .zero
        )
    }

    private func syncFromOverlay(_ ov: TextOverlay) {
        isTyping = true
        textFieldFocused = true
        typedText = ov.text
        selectedFontName = ov.fontName
        textColor = ov.textColor
        fontSize = ov.fontSize
        bgEnabled = ov.hasBackground
        bgColor = stripAlpha(from: ov.backgroundColor)
        bgOpacity = Double(UIColor(ov.backgroundColor).cgColor.alpha)
    }

    // Compare by RGB only (ignore alpha)
    private func colorsEqualIgnoringAlpha(_ c1: Color?, _ c2: Color) -> Bool {
        guard let c1 else { return false }
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        UIColor(c1).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        UIColor(c2).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return abs(r1 - r2) < 0.001 && abs(g1 - g2) < 0.001 && abs(b1 - b2) < 0.001
    }

    private func stripAlpha(from color: Color) -> Color {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return Color(red: Double(r), green: Double(g), blue: Double(b))
    }
}
