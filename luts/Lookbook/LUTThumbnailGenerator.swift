import CoreImage
import CoreGraphics

struct LUTThumbnailGenerator {
    private static let ciContext = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        .cacheIntermediates: false
    ])

    private static let maxSize: CGFloat = 120

    static func generateThumbnail(from baseImage: CIImage, with lutFilter: CIFilter) -> CGImage? {
        let scale = min(maxSize / baseImage.extent.width, maxSize / baseImage.extent.height, 1.0)
        var image = baseImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        lutFilter.setValue(image, forKey: kCIInputImageKey)
        if let output = lutFilter.outputImage {
            image = output
        } else {
            return nil
        }

        return ciContext.createCGImage(image, from: image.extent)
    }
}
