import Foundation
import UIKit
import ImageIO

#if canImport(ZIPFoundation)
import ZIPFoundation
#endif

enum CBZExtractor {

    enum CBZError: LocalizedError {
        case zipFoundationMissing
        case notReachable
        case noImagesFound

        var errorDescription: String? {
            switch self {
            case .zipFoundationMissing:
                return "ZIPFoundation is missing. Add it via Swift Package Manager."
            case .notReachable:
                return "This CBZ is not available locally yet (still in iCloud)."
            case .noImagesFound:
                return "No images were found inside this CBZ."
            }
        }
    }

    // MARK: - Public

    static func extractImages(from url: URL) throws -> [UIImage] {
        #if !canImport(ZIPFoundation)
        throw CBZError.zipFoundationMissing
        #else

        try ensureLocalFile(url)

        guard let archive = Archive(url: url, accessMode: .read) else {
            throw CBZError.noImagesFound
        }

        // Add more extensions that commonly appear in CBZs
        let imageExts: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "bmp", "tif", "tiff", "heic", "heif"]

        // Collect PATHS (strings) - avoids Archive.Entry type issues
        var imagePaths: [String] = []
        imagePaths.reserveCapacity(512)

        for entry in archive {
            let path = entry.path
            if path.hasPrefix("__MACOSX/") { continue }
            if path.hasSuffix(".DS_Store") { continue }

            let ext = (path as NSString).pathExtension.lowercased()
            guard imageExts.contains(ext) else { continue }

            imagePaths.append(path)
        }

        guard !imagePaths.isEmpty else {
            throw CBZError.noImagesFound
        }

        // Natural sort
        imagePaths.sort { NaturalSort.less($0, $1) }

        var images: [UIImage] = []
        images.reserveCapacity(imagePaths.count)

        var extractedOK = 0
        var decodedOK = 0
        var failed: [(String, String)] = []  // (path, reason)

        for (idx, path) in imagePaths.enumerated() {
            guard let entry = archive[path] else {
                failed.append((path, "missing entry in archive"))
                images.append(placeholderPage(text: "Missing entry\n\(lastName(path))"))
                continue
            }

            var data = Data()
            do {
                _ = try archive.extract(entry) { chunk in
                    data.append(chunk)
                }
                extractedOK += 1
            } catch {
                failed.append((path, "extract failed: \(error.localizedDescription)"))
                images.append(placeholderPage(text: "Extract failed\n\(lastName(path))"))
                continue
            }

            // Decode with ImageIO (more robust than UIImage(data:))
            if let img = decodeImageData(data) {
                decodedOK += 1
                images.append(img)
            } else {
                failed.append((path, "decode failed (unsupported or huge)"))
                images.append(placeholderPage(text: "Decode failed\n\(lastName(path))"))
            }

            // Reduce peak memory when books are large
            if idx % 12 == 0 { autoreleasepool { } }
        }

        // Debug summary in console (super useful)
        print("CBZExtractor:", url.lastPathComponent)
        print("  paths found:", imagePaths.count)
        print("  extracted ok:", extractedOK)
        print("  decoded ok:", decodedOK)
        print("  failed:", failed.count)
        if !failed.isEmpty {
            print("  first failures:")
            for item in failed.prefix(10) {
                print("   -", item.0, "=>", item.1)
            }
        }

        // Important: even if some fail, we still return placeholders (no “missing pages”)
        if images.isEmpty { throw CBZError.noImagesFound }
        return images
        #endif
    }

    // MARK: - iCloud download ensure

    private static func ensureLocalFile(_ url: URL) throws {
        let fm = FileManager.default

        let isUbiquitous = (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) ?? false
        if isUbiquitous {
            try? fm.startDownloadingUbiquitousItem(at: url)
            try waitUntilDownloaded(url, timeoutSeconds: 90)
        }

        guard fm.fileExists(atPath: url.path) else { throw CBZError.notReachable }
        guard FileHandle(forReadingAtPath: url.path) != nil else { throw CBZError.notReachable }
    }

    private static func waitUntilDownloaded(_ url: URL, timeoutSeconds: TimeInterval) throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)

        while Date() < deadline {
            let status = (try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus)

            if status == URLUbiquitousItemDownloadingStatus.current ||
               status == URLUbiquitousItemDownloadingStatus.downloaded ||
               status == nil {
                return
            }

            Thread.sleep(forTimeInterval: 0.15)
        }

        throw CBZError.notReachable
    }

    // MARK: - Decode helpers

    private static func decodeImageData(_ data: Data) -> UIImage? {
        // ImageIO decoder is often more forgiving than UIImage(data:)
        let cf = data as CFData
        guard let src = CGImageSourceCreateWithData(cf, nil) else { return nil }

        // Use first frame (works for GIF too)
        guard let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return UIImage(cgImage: cg)
    }

    private static func lastName(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    // MARK: - Placeholder page (so nothing is “missing”)

    private static func placeholderPage(text: String) -> UIImage {
        let size = CGSize(width: 1200, height: 1800) // page-like aspect
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { ctx in
            UIColor(white: 0.10, alpha: 1.0).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            // border
            UIColor(white: 1.0, alpha: 0.08).setStroke()
            ctx.cgContext.setLineWidth(6)
            ctx.cgContext.stroke(CGRect(x: 24, y: 24, width: size.width - 48, height: size.height - 48))

            // icon-ish mark
            let mark = "!"
            let markAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 220, weight: .black),
                .foregroundColor: UIColor(white: 1.0, alpha: 0.25)
            ]
            let mSize = (mark as NSString).size(withAttributes: markAttrs)
            (mark as NSString).draw(
                at: CGPoint(x: (size.width - mSize.width)/2, y: 180),
                withAttributes: markAttrs
            )

            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 54, weight: .semibold),
                .foregroundColor: UIColor(white: 1.0, alpha: 0.85)
            ]

            let para = NSMutableParagraphStyle()
            para.alignment = .center
            let attrs2: [NSAttributedString.Key: Any] = attrs.merging([.paragraphStyle: para]) { $1 }

            let rect = CGRect(x: 80, y: 520, width: size.width - 160, height: size.height - 600)
            (text as NSString).draw(in: rect, withAttributes: attrs2)
        }
    }
}
