import CoreImage

enum LUTLoaderError: Error, LocalizedError {
    case missingDimension
    case dimensionMismatch(expected: Int, got: Int)
    case invalidData(line: Int, content: String)
    case fileReadError(URL)

    var errorDescription: String? {
        switch self {
        case .missingDimension:
            return "LUT file missing LUT_3D_SIZE declaration"
        case .dimensionMismatch(let expected, let got):
            return "Expected \(expected) RGB entries, got \(got)"
        case .invalidData(let line, let content):
            return "Invalid data at line \(line): \(content)"
        case .fileReadError(let url):
            return "Failed to read file: \(url.lastPathComponent)"
        }
    }
}

struct LUTLoader {
    static func parse(cubeFileAt url: URL) throws -> CIFilter {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            throw LUTLoaderError.fileReadError(url)
        }

        var dimension: Int?
        var rgbData: [Float] = []

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if trimmed.hasPrefix("TITLE") { continue }

            if trimmed.hasPrefix("LUT_3D_SIZE") {
                let parts = trimmed.split(separator: " ")
                if parts.count >= 2, let dim = Int(parts[1]) {
                    dimension = dim
                }
                continue
            }

            if trimmed.hasPrefix("DOMAIN_MIN") || trimmed.hasPrefix("DOMAIN_MAX") {
                continue
            }

            // Skip LUT_1D_SIZE (not supported)
            if trimmed.hasPrefix("LUT_1D_SIZE") { continue }

            let parts = trimmed.split(separator: " ")
            if parts.count >= 3,
               let r = Float(parts[0]),
               let g = Float(parts[1]),
               let b = Float(parts[2]) {
                rgbData.append(contentsOf: [r, g, b])
            }
        }

        guard let dim = dimension, dim > 0 else {
            throw LUTLoaderError.missingDimension
        }

        let expectedCount = dim * dim * dim
        let actualCount = rgbData.count / 3
        guard actualCount == expectedCount else {
            throw LUTLoaderError.dimensionMismatch(expected: expectedCount, got: actualCount)
        }

        var rgbaData: [Float] = []
        rgbaData.reserveCapacity(expectedCount * 4)
        for i in 0..<expectedCount {
            rgbaData.append(rgbData[i * 3])
            rgbaData.append(rgbData[i * 3 + 1])
            rgbaData.append(rgbData[i * 3 + 2])
            rgbaData.append(1.0)
        }

        let data = Data(bytes: rgbaData, count: rgbaData.count * MemoryLayout<Float>.size)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

        let filter = CIFilter(name: "CIColorCubeWithColorSpace")!
        filter.setValue(dim, forKey: "inputCubeDimension")
        filter.setValue(data, forKey: "inputCubeData")
        filter.setValue(colorSpace, forKey: "inputColorSpace")
        filter.setValue(true, forKey: "inputExtrapolate")

        return filter
    }
}
