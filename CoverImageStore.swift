import UIKit

final class CoverImageStore {
    static let shared = CoverImageStore()
    private let cache = NSCache<NSURL, UIImage>()

    private init() {}

    func load(from url: URL) -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }

        guard let data = safeReadData(from: url),
              let img = UIImage(data: data) else {
            return nil
        }

        cache.setObject(img, forKey: url as NSURL)
        return img
    }

    /// Reads file data in a way that works with Document Picker + iCloud Drive URLs.
    private func safeReadData(from url: URL) -> Data? {
        // If the file is in iCloud and not downloaded yet, kick off a download.
        // We don’t block waiting for completion here; the next render pass will succeed.
        triggerICloudDownloadIfNeeded(url)

        var didAccess = false
        if url.startAccessingSecurityScopedResource() {
            didAccess = true
        }
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }

        // Coordinated read avoids common failures when reading security-scoped / iCloud files.
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        var data: Data?

        coordinator.coordinate(readingItemAt: url, options: [], error: &coordError) { coordinatedURL in
            data = try? Data(contentsOf: coordinatedURL)
        }

        // Fallback (in case coordination fails but direct read works).
        if data == nil {
            data = try? Data(contentsOf: url)
        }

        return data
    }

    private func triggerICloudDownloadIfNeeded(_ url: URL) {
        // Only makes sense for file URLs.
        guard url.isFileURL else { return }

        let fm = FileManager.default

        // If it’s not an iCloud ubiquitous item, nothing to do.
        guard fm.isUbiquitousItem(at: url) else { return }

        // If it’s already downloaded, nothing to do.
        if let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
           values.ubiquitousItemDownloadingStatus == URLUbiquitousItemDownloadingStatus.current {
            return
        }

        // Best-effort: request download.
        try? fm.startDownloadingUbiquitousItem(at: url)
    }
}

