import Foundation

enum ICloudDownloadHelper {
    static func isUbiquitous(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) ?? false
    }

    static func isDownloaded(_ url: URL) -> Bool {
        // If not ubiquitous, treat as downloaded.
        guard isUbiquitous(url) else { return true }

        // On iOS, this is the most reliable “is it local” check.
        // If it’s in iCloud and not local yet, this will usually be false.
        let vals = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        let status = vals?.ubiquitousItemDownloadingStatus

        // If status is nil we assume it’s local (some providers don’t return it cleanly).
        if status == nil { return true }

        // Common values: .current / .downloaded / .notDownloaded (varies by provider)
        // Treat "current" / "downloaded" as ready.
        return status == URLUbiquitousItemDownloadingStatus.current
            || status == URLUbiquitousItemDownloadingStatus.downloaded
    }

    static func startDownload(_ url: URL) throws {
        guard isUbiquitous(url) else { return }
        try FileManager.default.startDownloadingUbiquitousItem(at: url)
    }
}
