import CoreGraphics

/// Reads what a capture caught, without the capture itself, so it can be tested on images made
/// for the purpose.
enum CapturedImage {
    /// Whether any pixel is fully opaque. A menu bar icon always has one, and a fading menu bar
    /// scales every pixel's opacity down, so none is until the fade is over.
    static func isFullyDrawn(_ image: CGImage) -> Bool {
        let width = image.width, height = image.height
        guard width > 0, height > 0,
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
              )
        else { return true }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return true }
        let alphas = data.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * height)
        return (0..<(context.bytesPerRow * height)).contains { alphas[$0] == .max }
    }
}
