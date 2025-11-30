import SwiftUI

// 方形畫布容器，會在可用寬度內取最小邊為正方形，並套上背景、圓角與邊框
struct SquareCanvas<Content: View>: View {
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
