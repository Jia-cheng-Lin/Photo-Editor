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

    @State private var isDragging: Bool = false
    @State private var trashRect: CGRect = .zero
    @State private var showTrashHint: Bool = false

    var body: some View {
        VStack(spacing: 12) {
            SquareCanvas { side in
                ZStack {
                    Image(uiImage: baseImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: side, height: side)

                    ZStack {
                        ForEach(overlays) { ov in
                            DraggableTypingOverlay(
                                overlay: bindingFor(ov),
                                isSelected: selectedOverlayID == ov.id,
                                onBeginDrag: {
                                    withAnimation(.easeInOut) {
                                        isDragging = true
                                        showTrashHint = true
                                    }
                                },
                                onEndDrag: { frame in
                                    withAnimation(.easeInOut) {
                                        isDragging = false
                                    }
                                    // Simple collision check with trash zone rect (in canvas coords)
                                    if trashRect.intersects(frame) {
                                        onDelete(ov)
                                    }
                                },
                                textFieldFocused: _textFieldFocused
                            )
                            .onTapGesture {
                                onActivate(ov)
                            }
                        }
                    }
                    .frame(width: side, height: side)
                    .clipped()
                }
                .frame(width: side, height: side)
                .overlay(alignment: .bottom) {
                    if showTrashHint {
                        TrashZoneView()
                            .background(
                                GeometryReader { geo in
                                    Color.clear
                                        .onAppear { trashRect = geo.frame(in: .local) }
                                        .onChange(of: geo.size) { _, _ in trashRect = geo.frame(in: .local) }
                                }
                            )
                            .padding(.bottom, 12)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .padding(.horizontal)

            HStack(spacing: 12) {
                Button {
                    onCreateEmpty()
                } label: {
                    Label("新增", systemImage: "plus")
                }

                Spacer()

                VerticalSizeSlider(value: Binding(
                    get: { fontSizeForSelection() },
                    set: { newVal in
                        applyToSelection { $0.fontSize = newVal }
                        fontSize = newVal
                    }
                ))
                .frame(width: 44, height: 160)

                Menu("字體") {
                    Button("系統預設") {
                        applyToSelection { $0.fontName = nil }
                        selectedFontName = nil
                    }
                    ForEach(fontOptions.compactMap { $0 }, id: \.self) { name in
                        Button(name) {
                            applyToSelection { $0.fontName = name }
                            selectedFontName = name
                        }
                    }
                }

                Menu("文字色") {
                    ForEach(colorOptions.indices, id: \.self) { i in
                        let c = colorOptions[i]
                        Button {
                            applyToSelection { $0.textColor = c }
                            textColor = c
                        } label: {
                            HStack {
                                Circle().fill(c).frame(width: 16, height: 16)
                                Text(" ")
                            }
                        }
                    }
                }

                Toggle("背景", isOn: Binding(
                    get: { currentOverlay()?.hasBackground ?? false },
                    set: { val in
                        applyToSelection { $0.hasBackground = val }
                        bgEnabled = val
                    }
                ))
                .toggleStyle(.switch)

                Menu("背景色") {
                    ForEach(backgroundOptions.indices, id: \.self) { i in
                        let c = backgroundOptions[i]
                        Button {
                            applyToSelection { $0.backgroundColor = c.opacity(bgOpacity) }
                            bgColor = c
                        } label: {
                            HStack {
                                Circle().fill(c).frame(width: 16, height: 16)
                                Text(" ")
                            }
                        }
                    }
                }

                VStack {
                    Text("透明度")
                    Slider(value: Binding(
                        get: { Double(currentOverlayOpacity()) },
                        set: { newVal in
                            applyToSelection { $0.backgroundColor = bgColor.opacity(newVal) }
                            bgOpacity = newVal
                        }
                    ), in: 0...1)
                    .frame(width: 120)
                }
            }
            .padding(.horizontal)

            Spacer(minLength: 8)

            HStack(spacing: 10) {
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
        .navigationTitle("IG Text")
        .onChange(of: isDragging) { _, newVal in
            withAnimation(.easeInOut) {
                showTrashHint = newVal
            }
        }
    }

    // Helpers to read/apply to current selection
    private func applyToSelection(_ update: (inout TextOverlay) -> Void) {
        guard let idx = selectedIndex() else { return }
        update(&overlays[idx])
    }

    private func fontSizeForSelection() -> CGFloat {
        currentOverlay()?.fontSize ?? fontSize
    }

    private func currentOverlayOpacity() -> CGFloat {
        guard let ov = currentOverlay() else { return CGFloat(bgOpacity) }
        return CGFloat(UIColor(ov.backgroundColor).cgColor.alpha)
    }
}
