# RAW Image + LUT Application: macOS App Technical Research

## Summary

Building a simple Mac app to load camera RAW files and apply .cube LUTs requires only Apple-native frameworks: **CIRAWFilter** (Core Image) for RAW decoding, **CIColorCubeWithColorSpace** for LUT application, and **MTKView** (MetalKit) for GPU-accelerated display in SwiftUI. The entire pipeline is lazy/non-destructive — no pixels are computed until final render. Minimum viable app is ~7 files.

---

## 1. RAW Decoding: CIRAWFilter

### The API

`CIRAWFilter` (macOS 12+ / iOS 15+) is a `CIFilter` subclass with strongly-typed Swift properties. It replaces the older key-value-based `CIFilter` RAW API.

```swift
let rawFilter = CIRAWFilter(imageURL: url)!
rawFilter.exposure = 1.0           // EV adjustment
rawFilter.neutralTemperature = 5500 // white balance
rawFilter.draftModeEnabled = true   // fast preview
let image = rawFilter.outputImage   // lazy CIImage — no pixels yet
```

### Supported Formats

Apple natively supports 400+ camera models across 19+ manufacturers — Canon CR2/CR3, Nikon NEF, Sony ARW, Fujifilm RAF, Adobe DNG, Apple ProRAW, and more. Full list: https://support.apple.com/en-us/120534

`UTType.rawImage` (`public.camera-raw-image`) covers all vendor formats through UTType conformance hierarchy — no need to enumerate individual types.

### Internal Pipeline (WWDC16 Session 505)

The RAW decode pipeline runs ~4,500 lines of CIKernel code in this order:

1. **Linearization** — decompand stored data to linear scene values
2. **Demosaicing** — reconstruct full RGB from Bayer/X-Trans mosaic
3. **Geometric/lens correction** — barrel distortion, chromatic aberration
4. **Noise reduction** — over half the kernel code; luminance + chroma NR
5. **White balance** — applied in linear scene-referred space
6. **Baseline exposure** — per-camera from DNG metadata
7. **→ `linearSpaceFilter` insertion point ←** — your custom filter goes here
8. **Profile tone curve / local tone mapping** — DNG 1.6 gain tables
9. **Gamut mapping** — scene-referred to output gamut
10. **Sharpening, contrast, saturation** — final perceptual adjustments

### Processing Controls

| Category | Properties |
|----------|-----------|
| **Exposure/Tone** | `exposure`, `baselineExposure`, `boostAmount`, `boostShadowAmount`, `localToneMapAmount`, `contrastAmount` |
| **White Balance** | `neutralTemperature`, `neutralTint`, `neutralChromaticity`, `neutralLocation` |
| **Detail/Noise** | `sharpnessAmount`, `luminanceNoiseReductionAmount`, `colorNoiseReductionAmount`, `moireReductionAmount`, `detailAmount` |
| **Output Mode** | `isDraftModeEnabled`, `scaleFactor`, `extendedDynamicRangeAmount`, `orientation` |
| **Pipeline Injection** | `linearSpaceFilter` — insert a CIFilter mid-pipeline in linear space |

### Getting Linear Output for LUT Application

Two approaches:

**Approach A: Disable all "look" processing** — zero out tone mapping, gamut mapping, boost. Produces flat, scene-referred linear data with up to 14 stops of unclipped dynamic range. You apply your own LUT and tone mapping.

```swift
rawFilter.baselineExposure = 0.0
rawFilter.boostAmount = 0.0
rawFilter.localToneMapAmount = 0.0
rawFilter.isGamutMappingEnabled = false
// Result: linear, flat image — apply LUT yourself
```

**Approach B: Use `linearSpaceFilter`** — inject your LUT mid-pipeline, before Apple's tone curve and gamut mapping. Best of both worlds: your LUT operates on linear data, then Apple finishes the image.

```swift
rawFilter.linearSpaceFilter = myLUTFilter
// LUT applied in linear space, then tone curve + gamut mapping run on top
```

### Performance

- Metal-accelerated since macOS 10.14
- `isDraftModeEnabled = true` → 2-5x faster decode
- `scaleFactor = 0.25` on a 40MP image → ~2.5MP preview
- `previewImage` property → instant embedded JPEG preview (free)
- Use `CIFormat.RGBAh` (half-float) — 8 bytes/pixel, sufficient precision, good GPU perf
- Max supported: 120MP on 2GB+ devices

---

## 2. LUT File Format: .cube

### Specification

The .cube format (IRIDAS/Adobe, 2003) is plain-text ASCII. It's the industry standard across DaVinci Resolve, Premiere, Final Cut Pro, etc.

```
# Comment
TITLE "My Color Grade"
LUT_3D_SIZE 33
DOMAIN_MIN 0.0 0.0 0.0
DOMAIN_MAX 1.0 1.0 1.0

0.000000 0.000000 0.000000
0.047059 0.000000 0.000000
0.101961 0.000000 0.000000
...
# Total lines = 33^3 = 35,937 RGB triplets
```

**Data ordering:** R varies fastest, then G, then B (nested loops: B outer, G middle, R inner). This matches what CIColorCube expects — no reordering needed.

**Common sizes:** 17, 33, 65. A single .cube file can contain both a 1D shaper LUT and a 3D LUT.

### 1D vs 3D LUTs

- **1D LUT:** Per-channel transforms only (gamma, contrast curves). Cannot create cross-channel effects (no hue shifts).
- **3D LUT:** Maps all three channels simultaneously. Captures cross-channel interactions — enables complex color grades, film emulations, creative looks.
- Core Image has no "CIColorCube1D" — use `CIColorCurves` or promote 1D to 3D trivially.

---

## 3. LUT Application: CIColorCubeWithColorSpace

### The Filter

```swift
let filter = CIFilter(name: "CIColorCubeWithColorSpace")!
filter.setValue(dimension, forKey: "inputCubeDimension")  // 2-128
filter.setValue(cubeData, forKey: "inputCubeData")         // RGBA float32 Data
filter.setValue(CGColorSpace(name: CGColorSpace.sRGB)!, forKey: "inputColorSpace")
```

**`inputCubeData` format:** Flat array of 32-bit float RGBA values. Size = `dimension^3 × 4 × 4` bytes. The .cube file provides RGB triplets; you must append `1.0` alpha to each entry.

### Why Not Plain CIColorCube?

`CIColorCube` operates in Core Image's linear generic RGB working space. Most .cube files are authored in sRGB (gamma-encoded). Using `CIColorCube` directly produces wrong colors — washed out or too dark.

`CIColorCubeWithColorSpace` with `inputColorSpace: sRGB` automatically:
1. Converts input image to sRGB
2. Applies the LUT
3. Converts back to Core Image's working space

**Always use `CIColorCubeWithColorSpace`.**

### EDR Support (macOS 13+)

Set `extrapolate = true` to handle values outside 0.0-1.0 (EDR highlights).

### Parsing .cube → CIFilter

```swift
func loadCubeLUT(from url: URL) throws -> CIFilter {
    let content = try String(contentsOf: url, encoding: .utf8)
    let lines = content.components(separatedBy: .newlines)

    var dimension = 0
    var cubeData: [Float] = []

    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("TITLE") { continue }

        if trimmed.hasPrefix("LUT_3D_SIZE") {
            dimension = Int(trimmed.split(separator: " ").last ?? "0") ?? 0
            cubeData.reserveCapacity(dimension * dimension * dimension * 4)
            continue
        }

        // Skip other header keywords
        if trimmed.hasPrefix("DOMAIN") || trimmed.hasPrefix("LUT_1D") { continue }

        let components = trimmed.split(separator: " ").compactMap { Float($0) }
        guard components.count >= 3 else { continue }

        cubeData.append(components[0])  // R
        cubeData.append(components[1])  // G
        cubeData.append(components[2])  // B
        cubeData.append(1.0)            // A
    }

    let data = cubeData.withUnsafeBufferPointer { Data(buffer: $0) }

    return CIFilter(name: "CIColorCubeWithColorSpace", parameters: [
        "inputCubeDimension": dimension,
        "inputCubeData": data,
        "inputColorSpace": CGColorSpace(name: CGColorSpace.sRGB)!
    ])!
}
```

---

## 4. Display Pipeline: MTKView + CIRenderDestination

### Why Not CIImage → CGImage → NSImage → SwiftUI Image?

Each call to `context.createCGImage()` forces full rasterization into CPU memory. For a 40MP RAW at float16 RGBA, that's ~320MB allocated per slider movement. Unusable for interactive editing.

### The Right Way: Metal-backed rendering

**MetalView.swift** — NSViewRepresentable wrapping MTKView:

```swift
struct MetalView: NSViewRepresentable {
    let renderer: Renderer

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: renderer.device)
        view.delegate = renderer
        view.preferredFramesPerSecond = 30
        view.framebufferOnly = false
        view.colorPixelFormat = .rgba16Float
        view.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
        if let layer = view.layer as? CAMetalLayer {
            layer.wantsExtendedDynamicRangeContent = true
        }
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {}
}
```

**Renderer.swift** — MTKViewDelegate rendering CIImage directly to GPU:

```swift
class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let ciContext: CIContext
    var imageProvider: (() -> CIImage?)?

    init(device: MTLDevice = MTLCreateSystemDefaultDevice()!) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        self.ciContext = CIContext(mtlDevice: device, options: [
            .cacheIntermediates: false
        ])
    }

    func draw(in view: MTKView) {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let drawable = view.currentDrawable,
              let image = imageProvider?() else { return }

        let dest = CIRenderDestination(
            width: Int(view.drawableSize.width),
            height: Int(view.drawableSize.height),
            pixelFormat: view.colorPixelFormat,
            commandBuffer: commandBuffer,
            mtlTextureProvider: { drawable.texture }
        )

        let scaleX = view.drawableSize.width / image.extent.width
        let scaleY = view.drawableSize.height / image.extent.height
        let scale = min(scaleX, scaleY)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        try? ciContext.startTask(toRender: scaled,
                                 from: CGRect(origin: .zero, size: view.drawableSize),
                                 to: dest, at: .zero)
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}
```

CIImage renders directly to a Metal texture on the GPU. No CPU-side CGImage allocation. No intermediate buffer copies.

---

## 5. Non-Destructive Editing Pipeline

CIImage is a **recipe**, not a bitmap. Rasterization only occurs when `CIContext` executes it.

```swift
@Observable
class EditingPipeline {
    private var rawFilter: CIRAWFilter?
    private var lutFilter: CIFilter?

    var exposure: Float = 0.0
    var temperature: Float = 6500.0
    var contrast: Float = 1.0
    var saturation: Float = 1.0
    var lutIntensity: Float = 1.0

    var outputImage: CIImage? {
        guard let rawFilter else { return nil }

        rawFilter.exposure = exposure
        guard var image = rawFilter.outputImage else { return nil }

        // Adjustments (lazy)
        image = image.applyingFilter("CIColorControls", parameters: [
            kCIInputContrastKey: contrast,
            kCIInputSaturationKey: saturation
        ])

        // LUT (lazy)
        if let lutFilter, lutIntensity > 0 {
            lutFilter.setValue(image, forKey: kCIInputImageKey)
            if let lutOutput = lutFilter.outputImage {
                if lutIntensity < 1.0 {
                    // Blend for intensity control
                    image = lutOutput.applyingFilter("CIDissolveTransition", parameters: [
                        kCIInputTargetImageKey: image,
                        kCIInputTimeKey: 1.0 - lutIntensity
                    ])
                } else {
                    image = lutOutput
                }
            }
        }

        return image  // ZERO pixels computed — it's just a recipe
    }
}
```

When the Renderer calls `ciContext.startTask(toRender: pipeline.outputImage)`, Core Image optimizes the entire graph — concatenates color matrices, eliminates redundant conversions, executes in a single GPU pass where possible.

---

## 6. File Access

### SwiftUI `.fileImporter`

```swift
.fileImporter(
    isPresented: $showFilePicker,
    allowedContentTypes: [.rawImage, .image],
    allowsMultipleSelection: false
) { result in
    guard case .success(let urls) = result, let url = urls.first else { return }
    guard url.startAccessingSecurityScopedResource() else { return }
    defer { url.stopAccessingSecurityScopedResource() }
    loadRAWImage(from: url)
}
```

For LUT files:
```swift
allowedContentTypes: [UTType(filenameExtension: "cube")!]
```

### Export

CIContext provides direct-to-disk methods — no intermediate allocations:

```swift
try ciContext.writeJPEGRepresentation(of: image, to: url,
    colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)

try ciContext.writeTIFFRepresentation(of: image, to: url,
    format: .RGBA16, colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!)
```

---

## 7. Memory Strategy

```
User opens file
  → [1] Show previewImage immediately (embedded JPEG, ~1MB)
  → [2] Background: decode with draftMode=true, scaleFactor=screenFit (~5MB)
  → [3] User edits: re-evaluate filter graph (lazy, no extra memory until render)
  → [4] Export: draftMode=false, scaleFactor=1.0 (full res, ~320MB peak)
  → [5] After export: release full-res, return to preview scale
```

---

## 8. MVP File Structure

```
LUTs.app/
├── LUTsApp.swift              — App entry point
├── ContentView.swift           — Layout, file pickers, sidebar controls
├── MetalView.swift             — NSViewRepresentable + MTKView
├── Renderer.swift              — MTKViewDelegate, CIContext, draw loop
├── EditingPipeline.swift       — CIRAWFilter + filter chain + parameters
├── LUTLoader.swift             — .cube parser → CIFilter
└── ExportManager.swift         — JPEG/TIFF/PNG/HEIF export
```

---

## 9. Key Architectural Decisions

| Decision | Recommendation | Rationale |
|----------|---------------|-----------|
| Display pipeline | `CIRenderDestination` + `startTask` | Avoids 320MB CPU allocation per frame |
| Preview strategy | `draftMode=true` + reduced `scaleFactor` | 2-5x faster, minimal quality loss at screen res |
| LUT filter | `CIColorCubeWithColorSpace` (not `CIColorCube`) | Correct color space handling for sRGB-authored LUTs |
| LUT insertion | Apply after RAW decode in filter chain | Simpler than `linearSpaceFilter` for standard LUTs |
| Working format | `CIFormat.RGBAh` (half-float) | 16-bit precision sufficient for RAW, good GPU perf |
| CIContext count | 2 (one preview, one export) | Avoid contention between interactive and batch rendering |
| Pixel format | `.rgba16Float` | Supports EDR + wide gamut |

---

## 10. Color Space Cheat Sheet

| Scenario | Color Space | Notes |
|----------|------------|-------|
| Most .cube LUTs | `CGColorSpace.sRGB` | Standard color grading tools author in sRGB |
| Wide gamut LUTs | `CGColorSpace.displayP3` | For P3-authored LUTs |
| Linear/technical LUTs | `nil` (linear generic RGB) | Calibration LUTs |
| JPEG export | `CGColorSpace.sRGB` | Universal compatibility |
| TIFF/PNG export | `CGColorSpace.displayP3` + `.RGBA16` | Preserve wide gamut |
| Metal display | `extendedLinearDisplayP3` | EDR + wide gamut display |

---

## Sources

- [CIRAWFilter — Apple Developer Documentation](https://developer.apple.com/documentation/coreimage/cirawfilter)
- [CIColorCubeWithColorSpace — Apple Developer Documentation](https://developer.apple.com/documentation/coreimage/cicolorcubewithcolorspace)
- [Live Photo Editing and RAW Processing — WWDC16 Session 505](https://asciiwwdc.com/2016/sessions/505)
- [Display EDR content with Core Image — WWDC22](https://developer.apple.com/videos/play/wwdc2022/10114/)
- [Cube LUT Specification 1.0 (Adobe)](https://kono.phpage.fr/images/a/a1/Adobe-cube-lut-specification-1.0.pdf)
- [Supported RAW Formats — Apple Support](https://support.apple.com/en-us/120534)
- [Core Image Render Destination Sample](https://developer.apple.com/documentation/coreimage/generating-an-animation-with-a-core-image-render-destination)
- [Color Management in Core Image (JuniperPhoton)](https://juniperphoton.substack.com/p/color-management-across-apple-frameworks-cf7)
- [LUT Cubes and Shaders (optional.is)](https://optional.is/required/2025/08/27/lut-cubes-and-shaders/)
- [Brightroom (FluidGroup)](https://github.com/FluidGroup/Brightroom)
- [SwiftCube](https://github.com/ronan18/SwiftCube)
