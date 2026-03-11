import CoreImage

struct ExportManager {
    private static let ciContext = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!,
        .highQualityDownsample: true
    ])

    static func exportJPEG(image: CIImage, to url: URL, quality: Float) throws {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        try ciContext.writeJPEGRepresentation(
            of: image,
            to: url,
            colorSpace: colorSpace,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality]
        )
    }
}
