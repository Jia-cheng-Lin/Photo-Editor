import SwiftUI

struct FilterPickerView: View {
    let baseImage: UIImage
    @Binding var selected: FilterKind
    var onSelect: () -> Void

    private let thumbSize: CGFloat = 56
    private let service = FilterService()

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(FilterKind.allCases) { filter in
                    VStack(spacing: 6) {
                        Image(uiImage: service.previewThumbnail(for: baseImage, filter: filter, targetSize: .init(width: thumbSize, height: thumbSize)))
                            .resizable()
                            .scaledToFill()
                            .frame(width: thumbSize, height: thumbSize)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(filter == selected ? Color.accentColor : Color.clear, lineWidth: 2)
                            )
                        Text(filter.name)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .onTapGesture {
                        selected = filter
                        onSelect()
                    }
                }
            }
        }
    }
}
