import SwiftUI
import MetalKit
import UniformTypeIdentifiers

struct MetalView: NSViewRepresentable {
    let renderer: Renderer
    var onDropRAW: ((URL) -> Void)?

    func makeNSView(context: Context) -> DragDropMTKView {
        let view = DragDropMTKView()
        view.device = renderer.device
        view.delegate = renderer
        view.colorPixelFormat = .rgba16Float
        view.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
        view.clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.framebufferOnly = false
        view.onDropRAW = onDropRAW
        return view
    }

    func updateNSView(_ nsView: DragDropMTKView, context: Context) {
        nsView.onDropRAW = onDropRAW
        nsView.setNeedsDisplay(nsView.bounds)
    }
}

class DragDropMTKView: MTKView {
    var onDropRAW: ((URL) -> Void)?

    override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device)
        registerForDraggedTypes([.fileURL])
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if hasRAWFile(in: sender) {
            return .copy
        }
        return []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = extractFileURL(from: sender) else { return false }

        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
           type.conforms(to: .rawImage) {
            onDropRAW?(url)
            return true
        }
        return false
    }

    private func hasRAWFile(in info: NSDraggingInfo) -> Bool {
        guard let url = extractFileURL(from: info) else { return false }
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return type.conforms(to: .rawImage)
        }
        return false
    }

    private func extractFileURL(from info: NSDraggingInfo) -> URL? {
        guard let items = info.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
              let url = items.first else {
            return nil
        }
        return url
    }
}
