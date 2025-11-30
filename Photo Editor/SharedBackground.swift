import SwiftUI

// 共用灰白基調的漸層背景（放射狀）
struct GrayscaleRadialBackground: View {
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
