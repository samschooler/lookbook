import Metal
import MetalKit
import CoreImage

final class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let ciContext: CIContext
    var imageProvider: (() -> CIImage?)?

    init(device: MTLDevice) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        self.ciContext = CIContext(
            mtlDevice: device,
            options: [
                .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!,
                .cacheIntermediates: false
            ]
        )
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let image = imageProvider?(),
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        let drawableSize = view.drawableSize
        let destination = CIRenderDestination(
            width: Int(drawableSize.width),
            height: Int(drawableSize.height),
            pixelFormat: view.colorPixelFormat,
            commandBuffer: commandBuffer,
            mtlTextureProvider: { () -> MTLTexture in
                return drawable.texture
            }
        )
        destination.colorSpace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)

        let scaleX = drawableSize.width / image.extent.width
        let scaleY = drawableSize.height / image.extent.height
        let scale = min(scaleX, scaleY)

        var scaledImage = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let offsetX = (drawableSize.width - scaledImage.extent.width) / 2 - scaledImage.extent.origin.x
        let offsetY = (drawableSize.height - scaledImage.extent.height) / 2 - scaledImage.extent.origin.y
        scaledImage = scaledImage.transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))

        do {
            try ciContext.startTask(toRender: scaledImage, to: destination)
        } catch {
            print("CIRenderDestination error: \(error)")
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
