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
            SquareCanvas { side in
                ZStack {
                    Image(uiImage: baseImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: side, height: side)

                    // Center-origin canvas for overlays
                    ZStack {
                        ForEach(overlays) { ov in
                            DraggableTextOverlay(
                                overlay: bindingFor(ov),
                                isSelected: selectedOverlayID == ov.id,
                                onTap: {
                                    onSelectOverlay(ov)
                                }
                            )
                        }
                    }
                    .frame(width: side, height: side)
                    .clipped()
                    .contentShape(Rectangle())
                }
                .frame(width: side, height: side)
            }
            .padding(.horizontal)

            controls

            Spacer(minLength: 8)

            HStack(spacing: 10) {
                Button {
                    onIGText(baseImage)
                } label: {
                    Text("IG 文字模式")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.black.opacity(0.08))
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
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
            .padding(.bottom, 8)
        }
        .padding(.vertical)
        .background(GrayscaleRadialBackground().ignoresSafeArea())
        .navigationTitle("Add Text")
        .onChange(of: selectedOverlayID) { _, newValue in
            guard let id = newValue, let ov = overlays.first(where: { $0.id == id }) else { return }
            // keep simple editor inputs in sync
            typedText = ov.text
            selectedFontName = ov.fontName
            textColor = ov.textColor
            fontSize = ov.fontSize
            bgEnabled = ov.hasBackground
            bgColor = ov.backgroundColor
            bgOpacity = Double(UIColor(ov.backgroundColor).cgColor.alpha)
        }
        .onChange(of: typedText) { _, newVal in
            guard let idx = selectedIndex() else { return }
            overlays[idx].text = newVal
        }
        .onChange(of: selectedFontName) { _, newVal in
            guard let idx = selectedIndex() else { return }
            overlays[idx].fontName = (newVal?.isEmpty == true) ? nil : newVal
        }
        .onChange(of: textColor) { _, newVal in
            guard let idx = selectedIndex() else { return }
            overlays[idx].textColor = newVal
        }
        .onChange(of: fontSize) { _, newVal in
            guard let idx = selectedIndex() else { return }
            overlays[idx].fontSize = newVal
        }
        .onChange(of: bgEnabled) { _, newVal in
            guard let idx = selectedIndex() else { return }
            overlays[idx].hasBackground = newVal
        }
        .onChange(of: bgColor) { _, newVal in
            guard let idx = selectedIndex() else { return }
            overlays[idx].backgroundColor = newVal.opacity(bgOpacity)
        }
        .onChange(of: bgOpacity) { _, newVal in
            guard let idx = selectedIndex() else { return }
            overlays[idx].backgroundColor = bgColor.opacity(newVal)
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    // create a new overlay and select it
                    let new = TextOverlay(text: "新文字",
                                          position: .zero,
                                          fontSize: 28,
                                          fontWeight: .bold,
                                          fontName: nil,
                                          textColor: .black,
                                          hasBackground: false,
                                          backgroundColor: Color.black.opacity(0.06))
                    overlays.append(new)
                    onSelectOverlay(new)
                } label: {
                    Label("新增文字", systemImage: "plus")
                }
                Spacer()
            }

            if let ov = currentOverlay() {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("輸入內容", text: Binding(
                        get: { ov.text },
                        set: { newVal in
                            if let idx = selectedIndex() {
                                overlays[idx].text = newVal
                                typedText = newVal
                            }
                        }
                    ))
                    .textFieldStyle(.roundedBorder)

                    HStack {
                        Text("大小")
                        Slider(value: Binding(
                            get: { ov.fontSize },
                            set: { newVal in
                                if let idx = selectedIndex() {
                                    overlays[idx].fontSize = newVal
                                    fontSize = newVal
                                }
                            }
                        ), in: 12...96)
                        Text("\(Int(ov.fontSize))")
                            .font(.footnote.monospacedDigit())
                            .frame(width: 44, alignment: .trailing)
                    }

                    HStack {
                        Text("字體")
                        Spacer()
                        Menu(ov.fontName ?? "系統預設") {
                            Button("系統預設") {
                                if let idx = selectedIndex() {
                                    overlays[idx].fontName = nil
                                    selectedFontName = nil
                                }
                            }
                            ForEach(fontOptions.compactMap { $0 }, id: \.self) { name in
                                Button(name) {
                                    if let idx = selectedIndex() {
                                        overlays[idx].fontName = name
                                        selectedFontName = name
                                    }
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading) {
                        Text("文字顏色")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(colorOptions.indices, id: \.self) { i in
                                    let c = colorOptions[i]
                                    Circle()
                                        .fill(c)
                                        .frame(width: 24, height: 24)
                                        .overlay(Circle().stroke(Color.black.opacity(0.2), lineWidth: 1))
                                        .onTapGesture {
                                            if let idx = selectedIndex() {
                                                overlays[idx].textColor = c
                                                textColor = c
                                            }
                                        }
                                }
                            }
                        }
                    }

                    Toggle("背景", isOn: Binding(
                        get: { ov.hasBackground },
                        set: { val in
                            if let idx = selectedIndex() {
                                overlays[idx].hasBackground = val
                                bgEnabled = val
                            }
                        }
                    ))

                    if ov.hasBackground {
                        VStack(alignment: .leading) {
                            Text("背景顏色")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(backgroundOptions.indices, id: \.self) { i in
                                        let c = backgroundOptions[i]
                                        Circle()
                                            .fill(c)
                                            .frame(width: 24, height: 24)
                                            .overlay(Circle().stroke(Color.black.opacity(0.2), lineWidth: 1))
                                            .onTapGesture {
                                                if let idx = selectedIndex() {
                                                    overlays[idx].backgroundColor = c.opacity(bgOpacity)
                                                    bgColor = c
                                                }
                                            }
                                    }
                                }
                            }

                            HStack {
                                Text("透明度")
                                Slider(value: Binding(
                                    get: { ov.backgroundColorOpacity },
                                    set: { newVal in
                                        if let idx = selectedIndex() {
                                            overlays[idx].backgroundColor = bgColor.opacity(newVal)
                                            bgOpacity = newVal
                                        }
                                    }
                                ), in: 0...1)
                                Text(String(format: "%.2f", ov.backgroundColorOpacity))
                                    .font(.footnote.monospacedDigit())
                                    .frame(width: 44, alignment: .trailing)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

private extension TextOverlay {
    var backgroundColorOpacity: Double {
        Double(UIColor(self.backgroundColor).cgColor.alpha)
    }
}
