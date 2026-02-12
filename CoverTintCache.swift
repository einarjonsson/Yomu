import UIKit
import CoreImage

final class CoverTintCache {
    static let shared = CoverTintCache()
    private init() {}

    private var map: [URL: UIColor] = [:]

    func color(for url: URL) -> UIColor? { map[url] }

    func setColor(_ color: UIColor, for url: URL) {
        map[url] = color
    }
}

extension UIImage {
    var averageColor: UIColor? {
        guard let cgImage = self.cgImage else { return nil }

        let ciImage = CIImage(cgImage: cgImage)
        let extent = ciImage.extent

        let context = CIContext(options: [.workingColorSpace: NSNull()])
        guard let filter = CIFilter(name: "CIAreaAverage") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: extent), forKey: kCIInputExtentKey)

        guard let output = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )

        return UIColor(
            red: CGFloat(bitmap[0]) / 255.0,
            green: CGFloat(bitmap[1]) / 255.0,
            blue: CGFloat(bitmap[2]) / 255.0,
            alpha: 1.0
        )
    }
}

extension UIColor {
    func softenedForUI() -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)

        // Slightly darken / neutralize
        let mix: CGFloat = 0.22
        let rr = r * (1 - mix) + 0.10 * mix
        let gg = g * (1 - mix) + 0.10 * mix
        let bb = b * (1 - mix) + 0.10 * mix

        return UIColor(red: rr, green: gg, blue: bb, alpha: 1.0)
    }
}
