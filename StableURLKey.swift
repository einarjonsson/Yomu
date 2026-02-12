import Foundation

/// A stable identifier for file system URLs (works better than absoluteString, especially with iCloud / symlinks).
func stableURLKey(_ url: URL) -> String {
    url.standardizedFileURL
        .resolvingSymlinksInPath()
        .path
}
