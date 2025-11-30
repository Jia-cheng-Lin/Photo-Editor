import SwiftUI

struct VerticalSizeSlider: View {
    @Binding var value: CGFloat
    var range: ClosedRange<CGFloat> = 12...96

    private let trackWidth: CGFloat = 6
    private let knobSize: CGFloat = 22

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let progress = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let y = height - progress * height

            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.black.opacity(0.08))
                    .frame(width: trackWidth)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.black.opacity(0.25))
                    .frame(width: trackWidth)
                    .mask(
                        VStack { Spacer(minLength: 0); Rectangle().frame(height: height * progress) }
                    )

                Circle()
                    .fill(Color.white)
                    .overlay(Circle().stroke(Color.black.opacity(0.2), lineWidth: 1))
                    .frame(width: knobSize, height: knobSize)
                    .position(x: geo.size.width / 2, y: y.clamped(to: 0...height))
                    .shadow(radius: 1)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { g in
                                let clampedY = min(max(g.location.y, 0), height)
                                let newProgress = 1 - clampedY / height
                                let newValue = range.lowerBound + (range.upperBound - range.lowerBound) * newProgress
                                value = newValue.clamped(to: range.lowerBound...range.upperBound)
                            }
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

