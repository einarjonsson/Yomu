import UIKit
import ZIPFoundation


final class BookThumbnailStore {
    static let shared = BookThumbnailStore()
    private let cache = NSCache<NSURL, UIImage>()

    private init() {}

    func cached(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }
    
    func cachedSync(for cbzURL: URL) -> UIImage? {
        cache.object(forKey: cbzURL as NSURL)
    }

    /// Loads the first image inside a CBZ (sorted by filename) and caches it.
    /// Call this from a background Task (not on main thread).
    func loadFirstPageThumbnail(from cbzURL: URL) -> UIImage? {
        if let img = cache.object(forKey: cbzURL as NSURL) { return img }

        #if canImport(ZIPFoundation)
        // Security scope (Files/iCloud)
        let didAccess = cbzURL.startAccessingSecurityScopedResource()
        defer { if didAccess { cbzURL.stopAccessingSecurityScopedResource() } }

        guard let archive = Archive(url: cbzURL, accessMode: .read) else { return nil }

        let imageExts = Set(["jpg", "jpeg", "png", "webp"])

        // Pick the first image by alphabetical order (typical page ordering)
        let first = archive
            .filter { entry in
                let ext = URL(fileURLWithPath: entry.path).pathExtension.lowercased()
                return imageExts.contains(ext)
            }
            .sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
            .first

        guard let firstEntry = first else { return nil }

        var data = Data()
        do {
            _ = try archive.extract(firstEntry) { part in data.append(part) }
            guard let img = UIImage(data: data) else { return nil }
            cache.setObject(img, forKey: cbzURL as NSURL)
            return img
        } catch {
            return nil
        }
        #else
        // ZIPFoundation is not available; cannot extract thumbnails from CBZ. Return nil.
        return nil
        #endif
    }
}
