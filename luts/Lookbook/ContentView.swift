import SwiftUI
import MetalKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var pipeline: EditingPipeline
    @State private var showFileImporter = false
    @State private var renderer: Renderer?
    @State private var metalDevice: MTLDevice?
    @State private var showExportPanel = false
    @State private var isExporting = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Button("Open RAW") {
                    showFileImporter = true
                }
                .keyboardShortcut("o", modifiers: .command)

                Spacer()

                Text("Lookbook")
                    .font(.headline)

                Spacer()

                Button("Export JPEG") {
                    showExportPanel = true
                }
                .disabled(!pipeline.hasImage || isExporting)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Main content
            HSplitView {
                // Left: Image preview
                ZStack {
                    if let renderer = renderer {
                        MetalView(renderer: renderer, onDropRAW: { url in
                            pipeline.loadRAW(from: url)
                        })
                    }

                    if !pipeline.hasImage {
                        VStack(spacing: 12) {
                            Text("Drop a RAW file or click Open RAW")
                                .foregroundStyle(.secondary)
                                .font(.title3)
                        }
                    }

                    if let url = pipeline.rawURL {
                        VStack {
                            Spacer()
                            HStack {
                                Text("\(url.lastPathComponent)  \(Int(pipeline.imageDimensions.width))×\(Int(pipeline.imageDimensions.height))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(6)
                                Spacer()
                            }
                        }
                    }
                }
                .frame(minWidth: 600)

                // Right panel: Edit + LUT
                HSplitView {
                    EditPanel(pipeline: pipeline)
                        .frame(minWidth: 180, idealWidth: 200, maxWidth: 250)

                    LUTPanel(pipeline: pipeline)
                        .frame(minWidth: 180, idealWidth: 200, maxWidth: 300)
                }
                .frame(minWidth: 360, idealWidth: 400)
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.rawImage],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                if url.startAccessingSecurityScopedResource() {
                    pipeline.loadRAW(from: url)
                }
            }
        }
        .onChange(of: showExportPanel) { _, show in
            if show {
                showExportPanel = false
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.jpeg]
                panel.nameFieldStringValue = pipeline.rawURL?
                    .deletingPathExtension()
                    .lastPathComponent
                    .appending(".jpg") ?? "export.jpg"
                panel.canCreateDirectories = true

                guard panel.runModal() == .OK, let url = panel.url else { return }

                isExporting = true
                Task.detached {
                    do {
                        if let image = await pipeline.fullResolutionOutput {
                            try ExportManager.exportJPEG(
                                image: image,
                                to: url,
                                quality: await pipeline.jpegQuality
                            )
                        }
                    } catch {
                        print("Export failed: \(error)")
                    }
                    await MainActor.run {
                        isExporting = false
                    }
                }
            }
        }
        .onAppear {
            if let device = MTLCreateSystemDefaultDevice() {
                metalDevice = device
                let r = Renderer(device: device)
                r.imageProvider = { [pipeline] in
                    pipeline.outputImage
                }
                renderer = r
            }
        }
    }
}
