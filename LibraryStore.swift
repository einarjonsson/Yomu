import Foundation
import Combine

@MainActor
final class LibraryStore: ObservableObject {
    // Recursively collect readable book files under a series folder.
    // This enables structures like: Series/Dark Horse/*.cbz
    private func collectBookFilesRecursively(in seriesFolderURL: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: seriesFolderURL,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var out: [URL] = []
        for case let url as URL in enumerator {
            let vals = try? url.resourceValues(forKeys: [.isDirectoryKey])
            if vals?.isDirectory == true { continue }

            let ext = url.pathExtension.lowercased()
            if ext == "cbz" || ext == "pdf" {
                out.append(url)
            }
        }

        return out.sorted { a, b in
            a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
        }
    }
    @Published var status: String = "Ready"

    // The ONE root library folder the user picked
    @Published private(set) var source: URL? = nil

    // Series = immediate subfolders of source
    @Published private(set) var series: [Series] = []

    @Published private(set) var allBooksIndex: [String: Book] = [:]
    
    @Published private(set) var recentlyAdded: [Book] = []
    
    struct Series: Identifiable, Hashable {
        let id = UUID()
        let title: String
        let folderURL: URL
        let cbzCount: Int
        let coverURL: URL?
    }
    
    struct Book: Identifiable, Hashable {
        let id = UUID()
        let title: String
        let fileURL: URL
        let seriesFolderURL: URL   // ✅ ADD THIS
    }

    private let bookmarkKey = "library_root_bookmark_v1"

    init() {
        // Try to restore previously chosen folder
        restoreSourceFromBookmark()
        refreshSeries()
    }

    // MARK: - Called after user picks a folder

    func setPickedFolder(_ url: URL) {
        source = url
        status = "Saving folder…"
        saveBookmark(for: url)
        refreshSeries()
    }
    
    func autoMatchMetadataForSeries() async {
        guard !series.isEmpty else { return }

        status = "Matching metadata…"

        // Only match series that don’t already have metadata saved
        let toMatch = series.filter { !SeriesMetadataStore.shared.hasMetadata(for: $0.folderURL) }

        if toMatch.isEmpty {
            status = "Metadata already matched."
            return
        }

        var matched = 0

        for s in toMatch {
            // Throttle so we don’t hit AniList rate limits
            try? await Task.sleep(nanoseconds: 400_000_000) // 0.4s

            do {
                let results = try await AniListClient.shared.searchManga(query: s.title, limit: 6)

                // Pick best by similarity against returned titles
                let best = results
                    .map { media -> (AniListMedia, Double) in
                        let candidateTitle = (media.titleEnglish ?? media.titleRomaji ?? media.titleNative ?? "")
                        return (media, similarityScore(s.title, candidateTitle))
                    }
                    .sorted { $0.1 > $1.1 }
                    .first

                if let (media, score) = best, score >= 0.35 {
                    let title = media.titleEnglish ?? media.titleRomaji ?? media.titleNative ?? s.title
                    let meta = SeriesMetadata(
                        anilistId: media.id,
                        title: title,
                        description: media.description,
                        averageScore: media.averageScore,
                        coverImageLarge: media.coverImageLarge,
                        bannerImage: media.bannerImage,
                        status: media.status,
                        matchedAt: Date(),
                        confidence: score
                    )
                    SeriesMetadataStore.shared.setMetadata(meta, for: s.folderURL)
                    matched += 1
                }
            } catch {
                // Don’t kill the whole loop if one query fails
                continue
            }
        }

        status = "Matched \(matched) / \(toMatch.count) series."
    }

    // MARK: - Bookmark persistence

    private func saveBookmark(for url: URL) {
        do {
            // Important on iOS: access while creating bookmark
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

            let data = try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(data, forKey: bookmarkKey)
            status = "Folder saved."
        } catch {
            status = "Could not save folder: \(error.localizedDescription)"
        }
    }

    private func restoreSourceFromBookmark() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else {
            status = "Pick your Library folder"
            return
        }

        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            // If stale, refresh bookmark
            if isStale {
                saveBookmark(for: url)
            }

            source = url
            status = "Library folder restored."
        } catch {
            status = "Saved folder invalid. Pick again."
            source = nil
        }
    }

    // MARK: - Series scanning

    func rebuildBookIndex() {
        let fm = FileManager.default
        guard let source else {
            allBooksIndex = [:]
            recentlyAdded = []
            return
        }

        status = "Indexing books…"

        let didAccess = source.startAccessingSecurityScopedResource()
        defer { if didAccess { source.stopAccessingSecurityScopedResource() } }

        var index: [String: Book] = [:]

        // For "Recently Added"
        var dated: [(book: Book, date: Date)] = []

        for s in series {
            let files = collectBookFilesRecursively(in: s.folderURL)

            for file in files {
                let book = Book(
                    title: file.deletingPathExtension().lastPathComponent,
                    fileURL: file,
                    seriesFolderURL: s.folderURL
                )

                let key = ReadingProgressStore.shared.bookKey(for: file)
                index[key] = book

                let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                dated.append((book: book, date: date))
            }
        }

        allBooksIndex = index

        // Most recently modified first
        let sortedRecent = dated
            .sorted { $0.date > $1.date }
            .map { $0.book }

        // Dedupe by the same stable key used everywhere else
        var seen = Set<String>()
        var unique: [Book] = []
        unique.reserveCapacity(12)

        for b in sortedRecent {
            // Dedupe by the same stable key used everywhere else
            let k = ReadingProgressStore.shared.bookKey(for: b.fileURL)
            if !seen.contains(k) {
                seen.insert(k)
                unique.append(b)
            }
            if unique.count == 12 { break }
        }

        recentlyAdded = unique
    }
    
    func refreshSeries() {
        guard let source else {
            series = []
            return
        }

        let fm = FileManager.default
        var found: [Series] = []

        status = "Scanning series…"

        let didAccess = source.startAccessingSecurityScopedResource()
        defer { if didAccess { source.stopAccessingSecurityScopedResource() } }

        do {
            let children = try fm.contentsOfDirectory(
                at: source,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            for child in children {
                let values = try child.resourceValues(forKeys: [.isDirectoryKey])
                guard values.isDirectory == true else { continue }

                // Count readable volumes anywhere under the series folder (recursive)
                let files = collectBookFilesRecursively(in: child)
                let count = files.count

                if count > 0 {
                    let cover = findCoverImage(in: child)
                    found.append(Series(title: child.lastPathComponent, folderURL: child, cbzCount: count, coverURL: cover))
                }
            }

            series = found.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            status = "Found \(series.count) series."
        } catch {
            status = "Scan failed: \(error.localizedDescription)"
            series = []
        }
        rebuildBookIndex()
    }
    
    func books(in series: Series) -> [Book] {
        // Access source (series is inside source)
        let didAccess = (source?.startAccessingSecurityScopedResource() ?? false)
        defer { if didAccess { source?.stopAccessingSecurityScopedResource() } }

        let files = collectBookFilesRecursively(in: series.folderURL)

        return files.map { url in
            Book(
                title: url.deletingPathExtension().lastPathComponent,
                fileURL: url,
                // IMPORTANT: keep the SERIES root here so SeriesDetailView can group by relative subfolders
                seriesFolderURL: series.folderURL
            )
        }
    }

    // Optional: clear saved folder during development
    func clearSavedFolder() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        source = nil
        series = []
        status = "Cleared. Pick your Library folder"
    }
    
    private func findCoverImage(in seriesFolder: URL) -> URL? {
        let fm = FileManager.default

        let candidates = [
            "cover.jpg", "cover.jpeg", "cover.png", "cover.webp",
            "folder.jpg", "folder.png", "folder.jpeg"
        ]

        for name in candidates {
            let url = seriesFolder.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) {
                return url
            }
        }

        return nil
    }
    
    private func normalizeTitle(_ s: String) -> String {
        let lowered = s.lowercased()
        // Remove common junk that breaks matching
        let removed = lowered
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
        // Strip volume markers like "vol 1", "volume 01", etc.
        let patterns = [
            #"vol\.?\s*\d+"#,
            #"volume\s*\d+"#,
            #"\(\s*vol\.?\s*\d+\s*\)"#,
            #"\[\s*vol\.?\s*\d+\s*\]"#
        ]
        var out = removed
        for p in patterns {
            out = out.replacingOccurrences(of: p, with: "", options: .regularExpression)
        }
        // Trim whitespace
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func similarityScore(_ a: String, _ b: String) -> Double {
        // Simple token overlap (good enough to start)
        let ta = Set(normalizeTitle(a).split(separator: " ").map(String.init))
        let tb = Set(normalizeTitle(b).split(separator: " ").map(String.init))
        guard !ta.isEmpty, !tb.isEmpty else { return 0 }
        let inter = ta.intersection(tb).count
        let union = ta.union(tb).count
        return Double(inter) / Double(union)
    }
    
    
}

