import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

enum FilterKind: CaseIterable, Identifiable {
    case none
    case mono
    case noir
    case fade
    case chrome
    case instant
    case transfer
    case process
    case sepia

    var id: String { name }
    var name: String {
        switch self {
        case .none: return "原圖"
        case .mono: return "Mono"
        case .noir: return "Noir"
        case .fade: return "Fade"
        case .chrome: return "Chrome"
        case .instant: return "Instant"
        case .transfer: return "Transfer"
        case .process: return "Process"
        case .sepia: return "Sepia"
        }
    }

    func apply(to input: CIImage) -> CIImage {
        switch self {
        case .none:
            return input
        case .mono:
            let f = CIFilter.photoEffectMono()
            f.inputImage = input
            return f.outputImage ?? input
        case .noir:
            let f = CIFilter.photoEffectNoir()
            f.inputImage = input
            return f.outputImage ?? input
        case .fade:
            let f = CIFilter.photoEffectFade()
            f.inputImage = input
            return f.outputImage ?? input
        case .chrome:
            let f = CIFilter.photoEffectChrome()
            f.inputImage = input
            return f.outputImage ?? input
        case .instant:
            let f = CIFilter.photoEffectInstant()
            f.inputImage = input
            return f.outputImage ?? input
        case .transfer:
            let f = CIFilter.photoEffectTransfer()
            f.inputImage = input
            return f.outputImage ?? input
        case .process:
            let f = CIFilter.photoEffectProcess()
            f.inputImage = input
            return f.outputImage ?? input
        case .sepia:
            let f = CIFilter.sepiaTone()
            f.inputImage = input
            f.intensity = 0.9
            return f.outputImage ?? input
        }
    }
}

struct FilterService {
    private let context = CIContext()

    func render(image: UIImage, filter: FilterKind, brightness: Double, contrast: Double) -> UIImage {
        guard let ci = CIImage(image: image) else { return image }

        // 濾鏡
        let filtered = filter.apply(to: ci)

        // 亮度與對比
        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = filtered
        colorControls.brightness = Float(brightness)
        colorControls.contrast = Float(contrast)

        guard let output = colorControls.outputImage,
              let cg = context.createCGImage(output, from: output.extent) else {
            return image
        }
        return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
    }

    func previewThumbnail(for image: UIImage, filter: FilterKind, targetSize: CGSize = .init(width: 56, height: 56)) -> UIImage {
        // 先縮小原圖以提高效率
        let resized = image.resized(maxDimension: max(targetSize.width, targetSize.height))
        return render(image: resized, filter: filter, brightness: 0, contrast: 1)
    }
}

private extension UIImage {
    func resized(maxDimension: CGFloat) -> UIImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension, maxSide > 0 else { return self }
        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        UIGraphicsBeginImageContextWithOptions(newSize, false, 1)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: newSize))
        return UIGraphicsGetImageFromCurrentImageContext() ?? self
    }
}
