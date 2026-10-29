import CoreGraphics

/// Reads what a capture caught, without the capture itself, so it can be tested on images made
/// for the purpose.
enum CapturedImage {
    /// Whether the top-left pixel is fully transparent: true of the one `MenuBarAgent` window that
    /// holds macOS 27's status items on nothing, and of none of the bar's opaque layers.
    static func hasClearCorner(_ image: CGImage) -> Bool {
        guard let context = CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 1,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
        ) else { return false }
        // Drawn so the image's top-left pixel lands on the context's only one.
        context.draw(image, in: CGRect(x: 0, y: 1 - image.height, width: image.width, height: image.height))
        return context.data?.load(as: UInt8.self) == 0
    }

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
