import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    @State private var viewMode: ViewMode = .grid
    @State private var recent = RecentSearchesStore.load()

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var suggestedSeries: [LibraryStore.Series] {
        // Simple heuristic: show the biggest series first.
        store.series
            .sorted { $0.cbzCount > $1.cbzCount }
            .prefix(12)
            .map { $0 }
    }

    private var seriesMatches: [LibraryStore.Series] {
        let q = trimmedQuery
        guard !q.isEmpty else { return [] }

        return store.series.filter { s in
            // Title + folder name search.
            if s.title.localizedCaseInsensitiveContains(q) { return true }
            let folderName = s.folderURL.lastPathComponent
            if folderName.localizedCaseInsensitiveContains(q) { return true }

            // Volume filename search (best-effort local index).
            let filenames = VolumeIndexCache.filenames(for: s.folderURL)
            return filenames.contains(where: { $0.localizedCaseInsensitiveContains(q) })
        }
    }

    private var volumeMatches: [VolumeHit] {
        let q = trimmedQuery
        guard !q.isEmpty else { return [] }

        var hits: [VolumeHit] = []
        for s in store.series {
            let filenames = VolumeIndexCache.filenames(for: s.folderURL)
            for name in filenames where name.localizedCaseInsensitiveContains(q) {
                hits.append(.init(series: s, filename: name))
            }
        }

        // Keep it sane.
        return hits.prefix(50).map { $0 }
    }

    var body: some View {
        VStack(spacing: 12) {
            if store.series.isEmpty {
                emptyState
            } else if trimmedQuery.isEmpty {
                discoveryState
            } else {
                resultsState
            }
        }
        .background(Color.black.ignoresSafeArea())
        .foregroundColor(.white)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search manga")
        .focused($searchFocused)
        .onSubmit(of: .search) {
            let q = trimmedQuery
            guard !q.isEmpty else { return }
            RecentSearchesStore.add(q)
            recent = RecentSearchesStore.load()
        }
        .onAppear {
            DispatchQueue.main.async {
                searchFocused = true
            }
        }
    }

    // MARK: - States

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "books.vertical")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No manga imported yet")
                .foregroundStyle(.secondary)
            Text("Go to Libraries and import a folder to get started.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 40)
    }

    private var discoveryState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !recent.isEmpty {
                    sectionHeader("Recent searches")

                    FlowChips(items: recent) { item in
                        applySearch(item)
                    } onDelete: {
                        RecentSearchesStore.clear()
                        recent = []
                    }
                    .padding(.horizontal, 16)
                }

                sectionHeader("Suggested")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(suggestedSeries, id: \.folderURL) { s in
                            NavigationLink {
                                SeriesDetailView(series: s)
                            } label: {
                                SuggestedSeriesPoster(series: s)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 22)
            }
            .padding(.top, 10)
        }
    }

    private var resultsState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // View mode toggle (grid vs list) for series results.
                Picker("View", selection: $viewMode) {
                    Text("Grid").tag(ViewMode.grid)
                    Text("List").tag(ViewMode.list)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 10)

                if seriesMatches.isEmpty && volumeMatches.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 22))
                            .foregroundStyle(.secondary)
                        Text("No results")
                            .foregroundStyle(.secondary)
                        Text("Try a different title, folder name, or volume filename.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    if !seriesMatches.isEmpty {
                        sectionHeader("Series")

                        Group {
                            switch viewMode {
                            case .grid:
                                seriesGrid(items: seriesMatches)
                            case .list:
                                LazyVStack(spacing: 10) {
                                    ForEach(seriesMatches, id: \.folderURL) { s in
                                        NavigationLink {
                                            SeriesDetailView(series: s)
                                        } label: {
                                            SearchSeriesRow(series: s)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                        .padding(.horizontal, viewMode == .grid ? 16 : 0)
                    }

                    if !volumeMatches.isEmpty {
                        sectionHeader("Volumes")

                        LazyVStack(spacing: 10) {
                            ForEach(volumeMatches) { hit in
                                NavigationLink {
                                    // Keep it simple for now: open the series.
                                    // Next step (when you want): deep-link into the exact volume.
                                    SeriesDetailView(series: hit.series)
                                } label: {
                                    VolumeHitRow(hit: hit)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }

                Spacer(minLength: 24)
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.white.opacity(0.75))
            .padding(.horizontal, 16)
    }

    private func applySearch(_ text: String) {
        query = text
        RecentSearchesStore.add(text)
        recent = RecentSearchesStore.load()
        DispatchQueue.main.async {
            searchFocused = true
        }
    }

    private func seriesGrid(items: [LibraryStore.Series]) -> some View {
        let cols = [GridItem(.adaptive(minimum: 120), spacing: 12)]

        return LazyVGrid(columns: cols, spacing: 12) {
            ForEach(items, id: \.folderURL) { s in
                NavigationLink {
                    SeriesDetailView(series: s)
                } label: {
                    SearchSeriesTile(series: s)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private enum ViewMode: Hashable {
        case grid, list
    }
}

// MARK: - Recent searches

private enum RecentSearchesStore {
    private static let key = "manga.search.recent"

    static func load() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func add(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }

        var arr = load()
        arr.removeAll { $0.caseInsensitiveCompare(q) == .orderedSame }
        arr.insert(q, at: 0)
        if arr.count > 12 { arr = Array(arr.prefix(12)) }
        UserDefaults.standard.set(arr, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

// MARK: - Volume index (filenames only)

private enum VolumeIndexCache {
    private static var cache: [URL: [String]] = [:]

    static func filenames(for folderURL: URL) -> [String] {
        if let cached = cache[folderURL] { return cached }

        let fm = FileManager.default
        let exts = ["cbz", "pdf"]
        var names: [String] = []

        if let enumerator = fm.enumerator(at: folderURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator {
                let ext = url.pathExtension.lowercased()
                guard exts.contains(ext) else { continue }
                names.append(url.deletingPathExtension().lastPathComponent)
            }
        }

        // Cache to avoid repeated disk scans.
        cache[folderURL] = names
        return names
    }

    static func clear() {
        cache.removeAll()
    }
}

// MARK: - UI Components

private struct SearchSeriesTile: View {
    let series: LibraryStore.Series

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            cover
                .aspectRatio(2/3, contentMode: .fill)
                .frame(height: 190)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

            Text(series.title)
                .font(.headline)
                .lineLimit(1)

            Text("\(series.cbzCount) book(s)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var cover: some View {
        LocalCoverImage(url: series.coverURL) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.10))

                Image(systemName: "books.vertical")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }
    }
}

private struct SearchSeriesRow: View {
    let series: LibraryStore.Series

    var body: some View {
        HStack(spacing: 12) {
            cover

            VStack(alignment: .leading, spacing: 4) {
                Text(series.title)
                    .font(.headline)
                    .lineLimit(1)

                Text("\(series.cbzCount) book(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.35))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var cover: some View {
        LocalCoverImage(url: series.coverURL) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.10))
                .frame(width: 46, height: 68)
                .overlay(
                    Image(systemName: "books.vertical")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.55))
                )
        }
        .frame(width: 46, height: 68)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct VolumeHit: Identifiable {
    let id = UUID()
    let series: LibraryStore.Series
    let filename: String
}

private struct VolumeHitRow: View {
    let hit: VolumeHit

    var body: some View {
        HStack(spacing: 12) {
            // Volume cover (MangaDex if available) -> fallback to local series cover -> placeholder
            VolumeCoverView(series: hit.series, filename: hit.filename)

            VStack(alignment: .leading, spacing: 3) {
                Text(hit.filename)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text(hit.series.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.35))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }
}

private struct FlowChips: View {
    let items: [String]
    let onTap: (String) -> Void
    let onDelete: (() -> Void)

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Basic two-line wrapping chip layout (simple + stable).
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 10)], spacing: 10) {
                ForEach(items, id: \.self) { t in
                    Button {
                        onTap(t)
                    } label: {
                        Text(t)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .frame(maxWidth: .infinity)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.08))
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Spacer(minLength: 0)
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Text("Clear")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.white.opacity(0.6))
            }
        }
    }
}


// MARK: - Suggested poster (elongated cover)

private struct SuggestedSeriesPoster: View {
    let series: LibraryStore.Series

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                posterCover
                    .aspectRatio(2/3, contentMode: .fill)
                    .frame(width: 128)
                    .clipped()

                // Subtle title legibility gradient
                LinearGradient(
                    colors: [Color.black.opacity(0.0), Color.black.opacity(0.75)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 56)

                VStack(alignment: .leading, spacing: 2) {
                    Text(series.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)

                    Text("\(series.cbzCount) book(s)")
                        .font(.caption2)
                        .foregroundStyle(Color.white.opacity(0.75))
                }
                .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var posterCover: some View {
        if let url = AniListCoverStore.coverURL(seriesFolder: series.folderURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    fallbackPosterCover
                case .empty:
                    fallbackPosterCover
                @unknown default:
                    fallbackPosterCover
                }
            }
        } else {
            fallbackPosterCover
        }
    }

    @ViewBuilder
    private var fallbackPosterCover: some View {
        LocalCoverImage(url: series.coverURL) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.10))

                Image(systemName: "books.vertical")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }
    }
}

// MARK: - Volume covers (MangaDex hook)

private struct VolumeCoverView: View {
    let series: LibraryStore.Series
    let filename: String

    var body: some View {
        HStack(spacing: 0) {
            cover
                .frame(width: 40, height: 56)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    @ViewBuilder
    private var cover: some View {
        if let url = MangaDexCoverStore.coverURL(seriesFolder: series.folderURL, filename: filename) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    fallbackSeriesCover
                case .empty:
                    fallbackSeriesCover
                @unknown default:
                    fallbackSeriesCover
                }
            }
        } else {
            fallbackSeriesCover
        }
    }

    @ViewBuilder
    private var fallbackSeriesCover: some View {
        LocalCoverImage(url: series.coverURL) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.10))
                .overlay(
                    Image(systemName: "book")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.55))
                )
        }
    }
}

/// Small in-memory store for MangaDex volume cover URLs.
///
/// How to use (wherever you fetch MangaDex metadata):
/// `MangaDexCoverStore.setCoverURL(url, seriesFolder: seriesFolderURL, filename: volumeFilename)`
private enum MangaDexCoverStore {
    private static var cache: [String: URL] = [:]

    static func key(seriesFolder: URL, filename: String) -> String {
        seriesFolder.path + "::" + filename
    }

    static func setCoverURL(_ url: URL, seriesFolder: URL, filename: String) {
        cache[key(seriesFolder: seriesFolder, filename: filename)] = url
    }

    static func coverURL(seriesFolder: URL, filename: String) -> URL? {
        cache[key(seriesFolder: seriesFolder, filename: filename)]
    }

    static func clear() {
        cache.removeAll()
    }
}
/// Small in-memory store for AniList series cover URLs.
///
/// Where you fetch AniList metadata, call:
/// AniListCoverStore.setCoverURL(url, seriesFolder: seriesFolderURL)
private enum AniListCoverStore {
    private static var cache: [String: URL] = [:]

    static func key(seriesFolder: URL) -> String {
        seriesFolder.path
    }

    static func setCoverURL(_ url: URL, seriesFolder: URL) {
        cache[key(seriesFolder: seriesFolder)] = url
    }

    static func coverURL(seriesFolder: URL) -> URL? {
        cache[key(seriesFolder: seriesFolder)]
    }

    static func clear() {
        cache.removeAll()
    }
}



// MARK: - Async local cover loader (fixes iCloud + fast list/grid rendering)

private struct LocalCoverImage<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage? = nil

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            await loadWithRetries()
        }
    }

    private func loadWithRetries() async {
        image = nil
        guard let url else { return }

        // Try a few times. This helps when the file is in iCloud and is still downloading.
        let delays: [UInt64] = [0, 250_000_000, 500_000_000, 900_000_000] // ns

        for d in delays {
            if d > 0 { try? await Task.sleep(nanoseconds: d) }

            if let img = CoverImageStore.shared.load(from: url) {
                await MainActor.run { self.image = img }
                return
            }
        }
    }
}
