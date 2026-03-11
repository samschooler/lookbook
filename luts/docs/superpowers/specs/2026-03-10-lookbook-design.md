# Lookbook — Design Spec

A lightweight macOS RAW photo editor with LUT finishing.

## Overview

Lookbook loads camera RAW files (CR2, NEF, ARW, DNG, etc.), provides basic editing controls, and applies .cube LUTs with thumbnail previews. The entire pipeline is non-destructive and GPU-accelerated via Core Image + Metal.

**Platform:** macOS 14+ (Sonoma), SwiftUI, no third-party dependencies.

**Xcode project and bundle name:** Lookbook.

## Initial State (No File Loaded)

- Image preview area shows a centered prompt: "Drop a RAW file or click Open RAW"
- Edit panel sliders are visible but disabled (grayed out), showing neutral defaults (Exposure: 0.0, Contrast: 1.0, Saturation: 1.0, Temperature: 6500K, Tint: 0)
- LUT panel shows "+ File" and "+ Folder" buttons but no thumbnails (no source image to preview against)
- Export JPEG button is disabled
- On file load, sliders become active and Temperature/Tint snap to values from RAW metadata

## Layout

Three-region split: large image preview on the left, two narrow columns on the right.

```
┌──────────────────────────────────────────────────────────┐
│  [Open RAW]              Lookbook            [Export JPEG]│
├────────────────────────────┬──────────┬───────────────────┤
│                            │  EDIT    │  LUTs             │
│                            │          │                   │
│                            │ Exposure │ ┌───────────────┐ │
│                            │ ───●──── │ │  thumbnail    │ │
│     RAW Image Preview      │          │ │  None (Orig.) │ │
│     (Metal-backed)         │ Temp     │ ├───────────────┤ │
│                            │ ───●──── │ │  thumbnail    │ │
│                            │          │ │  Warm Sunset  │ │
│                            │ Tint     │ ├───────────────┤ │
│                            │ ───●──── │ │  thumbnail    │ │
│                            │          │ │  Cool Teal    │ │
│                            │ Contrast │ ├───────────────┤ │
│                            │ ───●──── │ │  thumbnail    │ │
│                            │          │ │  Kodak Gold   │ │
│                            │ Saturati │ └───────────────┘ │
│                            │ ───●──── │                   │
│                            │          │ + File  + Folder  │
│                            │──────────│                   │
│                            │ EXPORT   │ Intensity         │
│  photo.CR3  7952×5304      │ Qual 90% │ ────────────●     │
└────────────────────────────┴──────────┴───────────────────┘
```

## Components

### 1. Image Preview (MetalView)

- `NSViewRepresentable` wrapping `MTKView`
- Renders `CIImage` via `CIRenderDestination` + `startTask` (no CPU rasterization)
- Pixel format: `.rgba16Float` for wide gamut + EDR support
- Color space: `extendedLinearDisplayP3`
- Supports drag & drop of RAW files (accepts `UTType.rawImage`)
- Render on demand via `setNeedsDisplay()` (not continuous 30fps loop) — more battery-efficient for a photo editor
- Shows filename + dimensions in bottom-left corner

### 2. Edit Panel (left column of right panel)

Minimal controls, all driving `CIRAWFilter` and `CIColorControls`:

| Control | Range | Default | Backed by |
|---------|-------|---------|-----------|
| Exposure | -3.0 to +3.0 EV | 0.0 | `CIRAWFilter.exposure` |
| Temperature | 2000K to 10000K | from RAW metadata (6500K if no file) | `CIRAWFilter.neutralTemperature` |
| Tint | -150 to +150 | from RAW metadata (0 if no file) | `CIRAWFilter.neutralTint` |
| Contrast | 0.0 to 2.0 | 1.0 | `CIColorControls.inputContrast` |
| Saturation | 0.0 to 2.0 | 1.0 | `CIColorControls.inputSaturation` |

On file load, Temperature and Tint sliders initialize to values from `CIRAWFilter.neutralTemperature` / `.neutralTint`. No "reset to default" in MVP.

Export section at bottom of edit panel:

| Control | Range | Default |
|---------|-------|---------|
| JPEG Quality | 0-100% (UI), maps to 0.0-1.0 for API | 90% |

### 3. LUT Panel (right column of right panel)

- Scrollable list of LUT thumbnail cards
- First entry is always "None (Original)" — removes applied LUT
- Each card: small thumbnail preview (LUT applied to current image at low res) + filename
- Selected LUT has a highlighted border
- **+ File** button: `.fileImporter` for individual `.cube` files
- **+ Folder** button: folder picker, scans for all `.cube` files, persists path in UserDefaults
- **Intensity slider** at bottom: 0% = fully original (no LUT), 100% = full LUT effect. Implemented as `CIDissolveTransition(inputImage: lutOutput, targetImage: original, time: 1.0 - intensity)`

### 4. Toolbar

- **Open RAW** button — `.fileImporter` with `UTType.rawImage`
- **Export JPEG** button — `.fileExporter` or `NSSavePanel`, renders full-resolution via separate `CIContext`

## Architecture

### Data Flow

```
User opens RAW file
    │
    ▼
CIRAWFilter (decode, draftMode for preview)
    │
    ▼
CIColorControls (contrast, saturation)
    │
    ▼
CIColorCubeWithColorSpace (selected LUT)
    │
    ▼
CIDissolveTransition (LUT intensity blend)
    │
    ▼
outputImage: CIImage (lazy recipe — no pixels yet)
    │
    ├──▶ Renderer.draw() → CIRenderDestination → MTKView (screen)
    │
    └──▶ Export → CIContext.writeJPEGRepresentation (full res)
```

All CIImage operations are lazy. The filter graph is rebuilt on every parameter change but no pixels are computed until the Renderer draws or the user exports.

### File Structure

```
Lookbook/
├── LookbookApp.swift           — @main App entry, WindowGroup
├── ContentView.swift           — HSplitView: image + right panel
├── MetalView.swift             — NSViewRepresentable wrapping MTKView
├── Renderer.swift              — MTKViewDelegate, CIContext, draw loop
├── EditingPipeline.swift       — @Observable: CIRAWFilter + filter chain
├── LUTLoader.swift             — .cube parser → CIFilter
├── LUTThumbnailGenerator.swift — Generates low-res previews per LUT
└── ExportManager.swift         — JPEG export via CIContext
```

### Key Classes

**EditingPipeline** (`@Observable`)
- Owns `CIRAWFilter`, stores all parameter values
- `selectedLUT: CIFilter?` — currently applied LUT
- `lutIntensity: Float` — blend amount
- `outputImage: CIImage?` — computed property returning the full lazy filter chain
- `loadRAW(from: URL)` — creates CIRAWFilter, extracts metadata defaults
- `loadLUT(from: URL)` — parses .cube, creates CIColorCubeWithColorSpace filter

**Renderer** (`MTKViewDelegate`)
- Holds `MTLDevice`, `MTLCommandQueue`, `CIContext` (for preview rendering only)
- `imageProvider: () -> CIImage?` — closure returning pipeline's outputImage
- `draw(in:)` — scales image to fit view, renders via `CIRenderDestination`
- Single CIContext, reused across frames

**ExportManager**
- Owns a separate `CIContext` (avoids contention with preview renderer)
- `exportJPEG(image: CIImage, to: URL, quality: Float)` — renders at full resolution via `CIContext.writeJPEGRepresentation` with `CGColorSpace.sRGB`

**LUTLoader**
- `static func parse(cubeFileAt: URL) throws -> CIFilter` — parses .cube text, builds RGBA float data, returns `CIColorCubeWithColorSpace` with `inputColorSpace: sRGB` and `extrapolate: true` (EDR)
- Handles `LUT_3D_SIZE`, `DOMAIN_MIN/MAX`, comments, `TITLE`
- Validates: dimension > 0, data count == dimension^3, all values are valid floats
- Throws typed `LUTLoaderError` on failure (missingDimension, dimensionMismatch, invalidData)
- Failed LUTs are silently skipped when scanning a folder (not shown in list)

**LUTThumbnailGenerator**
- Takes the current RAW image (at reduced scale) and a list of CIFilters (parsed LUTs)
- Generates small CIImage thumbnails by applying each LUT to the preview image
- Renders via a background CIContext to avoid blocking the main renderer
- Thumbnails reflect the base RAW decode only (not edit parameter changes) — avoids expensive regeneration on every slider drag
- Regenerates only when the source image changes (new file loaded)
- Lazy rendering: only generates thumbnails for LUTs currently visible in the scroll view
- For folders with many LUTs: parsing and thumbnail generation are async; cards appear as they're ready

### Performance Strategy

| Phase | draftMode | scaleFactor | Notes |
|-------|-----------|-------------|-------|
| Initial load | — | — | Show `previewImage` (embedded JPEG) instantly |
| Editing | true | fit to screen | ~5MB, 2-5x faster decode |
| LUT thumbnails | true | ~0.05 (tiny) | One per LUT, background thread |
| Export | false | 1.0 | Full resolution, separate CIContext |

### Memory Budget

- Preview image: ~1MB (embedded JPEG)
- Draft decode at screen res: ~5-10MB
- LUT thumbnail data per LUT: ~50KB
- Full resolution export: ~320MB peak (released after export)
- CIFilter (parsed LUT): ~4MB per 64^3 cube, ~260KB per 33^3 cube

### Color Space Pipeline

1. CIRAWFilter outputs in Core Image's linear working space
2. CIColorControls operates in working space (fine for contrast/saturation)
3. CIColorCubeWithColorSpace with `inputColorSpace: sRGB` and `extrapolate: true` — converts to sRGB before applying LUT, converts back after; extrapolate preserves EDR highlights
4. MTKView displays in `extendedLinearDisplayP3`
5. JPEG export targets `CGColorSpace.sRGB`

### File Access

- RAW files: `.fileImporter` with `allowedContentTypes: [.rawImage]`
- LUT files: `.fileImporter` with `UTType(filenameExtension: "cube")`
- LUT folders: folder picker, path stored in `UserDefaults`
- Security-scoped bookmarks for sandboxed access to persisted folder paths: bookmark created on folder selection, resolved on app launch. If stale (folder moved/deleted), silently remove from UserDefaults. Requires `com.apple.security.files.bookmarks.app-scope` entitlement.
- Drag & drop on MetalView for RAW files (`UTType.rawImage`); drag & drop on LUT panel for `.cube` files

### Concurrency

- `EditingPipeline` is `@MainActor` isolated
- `LUTThumbnailGenerator` runs on a detached `Task`, delivers thumbnails back to main actor
- LUT folder scanning + parsing runs async; results stream in as each file is parsed

### Interaction Details

- Clicking a LUT thumbnail applies it immediately to the main preview
- "None (Original)" removes the LUT (sets `selectedLUT = nil`)
- Slider changes trigger SwiftUI state updates → `outputImage` recomputed (lazy) → MTKView redraws
- LUT intensity at 0% = original image, 100% = full LUT effect
- Export renders at full resolution regardless of preview scale

## Out of Scope (MVP)

- Multiple image editing / batch processing
- Undo/redo stack
- Crop, rotate, transform tools
- Histogram display
- Before/after split view
- TIFF/PNG/HEIF export
- 1D LUT support
- Custom Metal shaders for LUT application
- iCloud sync or document-based app architecture

## Sources

- [CIRAWFilter docs](https://developer.apple.com/documentation/coreimage/cirawfilter)
- [CIColorCubeWithColorSpace docs](https://developer.apple.com/documentation/coreimage/cicolorcubewithcolorspace)
- [WWDC22 — Display EDR content](https://developer.apple.com/videos/play/wwdc2022/10114/)
- [Cube LUT Spec 1.0 (Adobe)](https://kono.phpage.fr/images/a/a1/Adobe-cube-lut-specification-1.0.pdf)
- [Technical research doc](../research/2026-03-10-raw-lut-mac-app.md)
