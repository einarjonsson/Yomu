import UIKit
import CoreGraphics

extension UIImage {

    /// Dominant theme color using quantized histogram (most common color cluster),
    /// sampled from center crop and filtering whites/blacks/low-sat.
    var dominantAppThemeColor: UIColor? {
        guard let cg = self.cgImage else { return nil }

        // 1) Downscale for speed
        let targetW = 64
        let targetH = 64

        guard let small = cg.downscaled(to: CGSize(width: targetW, height: targetH)) else { return nil }

        // 2) Extract RGBA pixels
        guard let data = small.rgbaBytes() else { return nil }

        // 3) Sample center region (avoid borders)
        let cropX0 = Int(Double(targetW) * 0.20)
        let cropY0 = Int(Double(targetH) * 0.20)
        let cropX1 = Int(Double(targetW) * 0.80)
        let cropY1 = Int(Double(targetH) * 0.80)

        // 4) Quantize colors into bins (4 bits per channel = 4096 bins)
        // bin = rrrrrgggggbbbb (12 bits)
        var hist: [Int: Int] = [:]
        hist.reserveCapacity(2048)

        func isBadPixel(r: Int, g: Int, b: Int) -> Bool {
            // Ignore near-white and near-black
            let maxC = max(r, max(g, b))
            let minC = min(r, min(g, b))
            if maxC > 245 { return true } // mostly white
            if maxC < 18 { return true }  // mostly black

            // Ignore low saturation (grayish)
            let delta = maxC - minC
            if delta < 18 { return true }

            return false
        }

        for y in cropY0..<cropY1 {
            for x in cropX0..<cropX1 {
                let i = (y * targetW + x) * 4
                let r = Int(data[i + 0])
                let g = Int(data[i + 1])
                let b = Int(data[i + 2])
                let a = Int(data[i + 3])

                // Ignore transparent-ish
                if a < 30 { continue }
                if isBadPixel(r: r, g: g, b: b) { continue }

                // Quantize to 4 bits per channel
                let rq = (r >> 4) & 0x0F
                let gq = (g >> 4) & 0x0F
                let bq = (b >> 4) & 0x0F
                let key = (rq << 8) | (gq << 4) | bq

                hist[key, default: 0] += 1
            }
        }

        guard let best = hist.max(by: { $0.value < $1.value })?.key else {
            // Fallback: if everything got filtered, try a looser method
            return self.fallbackAverageThemeColor()
        }

        // 5) Convert bin back to RGB (center of bin)
        let rq = (best >> 8) & 0x0F
        let gq = (best >> 4) & 0x0F
        let bq = best & 0x0F

        let r = CGFloat(rq * 16 + 8) / 255.0
        let g = CGFloat(gq * 16 + 8) / 255.0
        let b = CGFloat(bq * 16 + 8) / 255.0

        let base = UIColor(red: r, green: g, blue: b, alpha: 1.0)

        // 6) Grade it into a nice app background color
        return base.gradedForBackground()
    }

    // MARK: - Fallback (if histogram filters too much)

    private func fallbackAverageThemeColor() -> UIColor? {
        guard let cg = self.cgImage else { return nil }
        guard let small = cg.downscaled(to: CGSize(width: 32, height: 32)) else { return nil }
        guard let data = small.rgbaBytes() else { return nil }

        let w = small.width
        let h = small.height

        var rSum: CGFloat = 0
        var gSum: CGFloat = 0
        var bSum: CGFloat = 0
        var count: CGFloat = 0

        // center-ish sampling
        let x0 = Int(Double(w) * 0.25)
        let x1 = Int(Double(w) * 0.75)
        let y0 = Int(Double(h) * 0.25)
        let y1 = Int(Double(h) * 0.75)

        for y in y0..<y1 {
            for x in x0..<x1 {
                let i = (y * w + x) * 4
                let r = CGFloat(data[i + 0])
                let g = CGFloat(data[i + 1])
                let b = CGFloat(data[i + 2])
                let a = CGFloat(data[i + 3])
                if a < 30 { continue }
                rSum += r; gSum += g; bSum += b
                count += 1
            }
        }

        guard count > 0 else { return nil }
        let base = UIColor(
            red: (rSum / count) / 255.0,
            green: (gSum / count) / 255.0,
            blue: (bSum / count) / 255.0,
            alpha: 1.0
        )
        return base.gradedForBackground()
    }
}

// MARK: - Helpers

private extension CGImage {

    func downscaled(to size: CGSize) -> CGImage? {
        let w = Int(size.width)
        let h = Int(size.height)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = w * 4

        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .low
        ctx.draw(self, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    func rgbaBytes() -> [UInt8]? {
        let w = self.width
        let h = self.height
        let bytesPerRow = w * 4
        let count = h * bytesPerRow

        var bytes = [UInt8](repeating: 0, count: count)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let ctx = CGContext(
            data: &bytes,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.draw(self, in: CGRect(x: 0, y: 0, width: w, height: h))
        return bytes
    }
}

private extension UIColor {

    /// Makes colors look good as an iOS “theme background”.
    func gradedForBackground() -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        guard self.getHue(&h, saturation: &s, brightness: &v, alpha: &a) else { return self }

        // boost saturation, clamp brightness down
        let sat = min(max(s * 1.35, 0.40), 0.95)
        let bri = min(max(v * 0.55, 0.18), 0.55)

        return UIColor(hue: h, saturation: sat, brightness: bri, alpha: 1.0)
    }
}
