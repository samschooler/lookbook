import CoreImage
import CoreImage.CIFilterBuiltins
import Observation

struct LUTEntry: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    let filter: CIFilter
    var thumbnail: CGImage?
}

@Observable
@MainActor
final class EditingPipeline {
    // MARK: - RAW State
    private(set) var rawFilter: CIRAWFilter?
    private(set) var rawURL: URL?
    private(set) var imageDimensions: CGSize = .zero
    private(set) var previewImage: CIImage?

    // MARK: - Edit Parameters
    var exposure: Float = 0.0 {
        didSet { applyRAWParameters() }
    }
    var temperature: Float = 6500.0 {
        didSet { applyRAWParameters() }
    }
    var tint: Float = 0.0 {
        didSet { applyRAWParameters() }
    }
    var contrast: Float = 1.0
    var saturation: Float = 1.0

    // MARK: - LUT State
    var selectedLUT: CIFilter?
    var lutIntensity: Float = 1.0
    var luts: [LUTEntry] = []
    var selectedLUTID: UUID? {
        didSet {
            if let id = selectedLUTID {
                selectedLUT = luts.first(where: { $0.id == id })?.filter
            } else {
                selectedLUT = nil
            }
        }
    }

    // MARK: - Export
    var jpegQuality: Float = 0.9

    // MARK: - Computed Output
    var hasImage: Bool { rawFilter != nil }

    var outputImage: CIImage? {
        guard let rawFilter = rawFilter else {
            return previewImage
        }
        guard var image = rawFilter.outputImage else {
            return previewImage
        }

        if contrast != 1.0 || saturation != 1.0 {
            let colorControls = CIFilter.colorControls()
            colorControls.inputImage = image
            colorControls.contrast = contrast
            colorControls.saturation = saturation
            if let result = colorControls.outputImage {
                image = result
            }
        }

        if let lutFilter = selectedLUT {
            let preBlendImage = image
            lutFilter.setValue(image, forKey: kCIInputImageKey)
            if let lutOutput = lutFilter.outputImage {
                if lutIntensity < 1.0 {
                    let dissolve = CIFilter.dissolveTransition()
                    dissolve.inputImage = preBlendImage
                    dissolve.targetImage = lutOutput
                    dissolve.time = lutIntensity
                    if let blended = dissolve.outputImage {
                        image = blended
                    }
                } else {
                    image = lutOutput
                }
            }
        }

        return image
    }

    var baseImage: CIImage? {
        rawFilter?.outputImage
    }

    var fullResolutionOutput: CIImage? {
        guard let rawURL = rawURL,
              let fullResFilter = CIRAWFilter(imageURL: rawURL) else {
            return nil
        }

        fullResFilter.isDraftModeEnabled = false
        fullResFilter.exposure = exposure
        fullResFilter.neutralTemperature = temperature
        fullResFilter.neutralTint = tint

        guard var image = fullResFilter.outputImage else { return nil }

        if contrast != 1.0 || saturation != 1.0 {
            let colorControls = CIFilter.colorControls()
            colorControls.inputImage = image
            colorControls.contrast = contrast
            colorControls.saturation = saturation
            if let result = colorControls.outputImage {
                image = result
            }
        }

        if let lutFilter = selectedLUT {
            let preBlendImage = image
            lutFilter.setValue(image, forKey: kCIInputImageKey)
            if let lutOutput = lutFilter.outputImage {
                if lutIntensity < 1.0 {
                    let dissolve = CIFilter.dissolveTransition()
                    dissolve.inputImage = preBlendImage
                    dissolve.targetImage = lutOutput
                    dissolve.time = lutIntensity
                    if let blended = dissolve.outputImage {
                        image = blended
                    }
                } else {
                    image = lutOutput
                }
            }
        }

        return image
    }

    // MARK: - Load RAW

    func loadRAW(from url: URL) {
        guard let filter = CIRAWFilter(imageURL: url) else {
            print("Failed to create CIRAWFilter for \(url.lastPathComponent)")
            return
        }

        previewImage = filter.previewImage

        rawURL = url
        rawFilter = filter
        filter.isDraftModeEnabled = true
        temperature = filter.neutralTemperature
        tint = filter.neutralTint
        exposure = 0.0

        if let output = filter.outputImage {
            imageDimensions = output.extent.size
        }

        applyRAWParameters()
        regenerateThumbnails()
    }

    // MARK: - LUT Management

    func addLUT(from url: URL) {
        do {
            let filter = try LUTLoader.parse(cubeFileAt: url)
            let entry = LUTEntry(name: url.deletingPathExtension().lastPathComponent, url: url, filter: filter)
            luts.append(entry)

            if let baseImage = baseImage {
                let thumbScale: CGFloat = 0.05
                let scaledBase = baseImage.transformed(by: CGAffineTransform(scaleX: thumbScale, y: thumbScale))
                let lutFilter = entry.filter
                let entryID = entry.id
                Task.detached {
                    if let thumb = LUTThumbnailGenerator.generateThumbnail(from: scaledBase, with: lutFilter) {
                        await MainActor.run {
                            if let index = self.luts.firstIndex(where: { $0.id == entryID }) {
                                self.luts[index].thumbnail = thumb
                            }
                        }
                    }
                }
            }
        } catch {
            print("Failed to load LUT \(url.lastPathComponent): \(error)")
        }
    }

    func addLUTsFromFolder(at url: URL) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: nil) else { return }

        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension.lowercased() == "cube" {
                addLUT(from: fileURL)
            }
        }

        saveFolderBookmark(for: url)
    }

    func removeLUT(_ entry: LUTEntry) {
        luts.removeAll(where: { $0.id == entry.id })
        if selectedLUTID == entry.id {
            selectedLUTID = nil
        }
    }

    // MARK: - Security-Scoped Bookmarks

    private static let bookmarkKey = "lutFolderBookmarks"

    private func saveFolderBookmark(for url: URL) {
        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            var bookmarks = UserDefaults.standard.array(forKey: Self.bookmarkKey) as? [Data] ?? []
            bookmarks.append(bookmark)
            UserDefaults.standard.set(bookmarks, forKey: Self.bookmarkKey)
        } catch {
            print("Failed to save bookmark: \(error)")
        }
    }

    func restoreBookmarkedFolders() {
        guard let bookmarks = UserDefaults.standard.array(forKey: Self.bookmarkKey) as? [Data] else { return }
        var validBookmarks: [Data] = []

        for bookmark in bookmarks {
            var isStale = false
            do {
                let url = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                if isStale { continue }
                if url.startAccessingSecurityScopedResource() {
                    addLUTsFromFolder(at: url)
                    validBookmarks.append(bookmark)
                }
            } catch {
                // Stale or invalid bookmark — skip
            }
        }

        UserDefaults.standard.set(validBookmarks, forKey: Self.bookmarkKey)
    }

    // MARK: - Thumbnails

    func regenerateThumbnails() {
        guard let baseImage = baseImage else { return }

        let thumbScale: CGFloat = 0.05
        let scaledBase = baseImage.transformed(by: CGAffineTransform(scaleX: thumbScale, y: thumbScale))
        let lutSnapshot = luts

        Task.detached {
            var results: [(UUID, CGImage)] = []
            for entry in lutSnapshot {
                if let thumb = LUTThumbnailGenerator.generateThumbnail(from: scaledBase, with: entry.filter) {
                    results.append((entry.id, thumb))
                }
            }

            let finalResults = results
            await MainActor.run {
                for (id, thumb) in finalResults {
                    if let index = self.luts.firstIndex(where: { $0.id == id }) {
                        self.luts[index].thumbnail = thumb
                    }
                }
            }
        }
    }

    // MARK: - Private

    private func applyRAWParameters() {
        guard let rawFilter = rawFilter else { return }
        rawFilter.exposure = exposure
        rawFilter.neutralTemperature = temperature
        rawFilter.neutralTint = tint
    }
}
