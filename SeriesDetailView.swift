import Foundation
import SwiftUI
import UIKit

struct SeriesDetailView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var userStore: UserDataStore
    @Environment(\.horizontalSizeClass) private var hSizeClass
    
    
    @StateObject private var metadataStore = SeriesMetadataStore.shared
    @StateObject private var progressStore = ReadingProgressStore.shared
    @State private var books: [LibraryStore.Book] = []
   
    
    @State private var themeUIColor: UIColor = .black
    @State private var didComputeTheme = false
    
    @State private var downloadingBookURL: URL? = nil
    
    @State private var showMatchSheet = false
    // User sheets
    @State private var showListsSheet = false
    @State private var showNotesSheet = false
    @State private var noteDraft: String = ""

    // MangaDex covers (used INSIDE chapter rows)
    @State private var mdCoverByVolume: [Int: URL] = [:]
    @State private var isLoadingMDCovers = false
    
    // Series cache (instant UI while network fetches)
    @State private var didLoadSeriesCache = false
    
    
    @State private var selectedBookToOpen: LibraryStore.Book? = nil
    @State private var showReader = false

    @State private var showDownloadOverlay = false
    @State private var downloadTitle = ""
    @State private var downloadStatus = ""
    @State private var downloadProgress: Double = 0
    @State private var downloadReadyToOpen = false

    @State private var awards: [AwardItem] = []
    @State private var isLoadingAwards = false
    @State private var wikidataEntityId: String? = nil
    @State private var wikidataPublisher: String? = nil
    @State private var wikidataInceptionYear: String? = nil

    let series: LibraryStore.Series

    // MARK: - Metadata

    private var metadata: SeriesMetadata? {
        metadataStore.metadata(for: series.folderURL)
    }

    private var displayTitle: String {
        metadata?.title ?? series.title
    }
    
    private var seriesBackground: some View {
        Color(themeUIColor)
    }

    // MARK: - Progress

    private var seriesPercent: Double {
        progressStore.seriesPercent(for: books.map { $0.fileURL })
    }

    private var seriesCounts: (read: Int, total: Int) {
        progressStore.seriesPageCounts(for: books.map { $0.fileURL })
    }

    private var percentText: String {
        let pct = Int((seriesPercent * 100.0).rounded())
        if seriesCounts.total == 0 {
            return "0% • Not started"
        } else {
            return "\(pct)% • \(seriesCounts.read)/\(seriesCounts.total) pages"
        }
    }

    private var continueBookURL: URL? {
        progressStore.mostRecentlyOpenedBook(in: books.map { $0.fileURL })
    }

    private var firstUnreadBook: LibraryStore.Book? {
        if let url = continueBookURL,
           let book = books.first(where: { $0.fileURL == url }) {
            return book
        }
        return books.first
    }

    // MARK: - Body

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 10) {

                SeriesHeaderView(
                    series: series,
                    metadata: metadata,
                    wikidataPublisher: wikidataPublisher,
                    wikidataInceptionYear: wikidataInceptionYear,
                    progressPercent: seriesPercent,
                    progressText: percentText,
                    firstUnreadBook: firstUnreadBook
                )
                .padding(.top, 12)
                .padding(.horizontal, 16)

                // ✅ Description
                if let desc = metadata?.description, !desc.isEmpty {
                    DescriptionCard(text: desc)
                        .padding(.top, 16)
                        .padding(.horizontal, 16)
                }

                // ✅ Awards (from Wikidata)
                if !awards.isEmpty {
                    AwardsSection(awards: awards)
                        .padding(.top, 18)
                        .padding(.horizontal, 16)
                }

                // ✅ Notes (user)
                NotesCard(
                    text: userStore.note(for: series.folderURL),
                    onEdit: {
                        noteDraft = userStore.note(for: series.folderURL)
                        showNotesSheet = true
                    }
                )
                .padding(.top, 18)
                .padding(.horizontal, 16)

                // ✅ Volumes section (cleaner)
                VolumeSection(
                    seriesFolderURL: series.folderURL,
                    books: books,
                    totalCount: books.count,
                    coverByVolume: mdCoverByVolume,
                    onTap: { book in
                        Task { await handleOpen(book) }
                    }
                )
                .padding(.top, 8)
                .padding(.horizontal, 16)

                // ✅ Characters + Recommended
                if let meta = metadata {
                    CharactersShelf(characters: meta.characters)
                        .padding(.top, 18)
                        .padding(.horizontal, 16)

                    RecommendationsShelf(recommendations: meta.recommendations)
                        .padding(.top, 18)
                        .padding(.horizontal, 16)
                }

                Spacer(minLength: 0)
                    .frame(height: 30)
            }
        }
        .background(seriesBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .tabBar)

        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {

                // iPad (regular width): show Favorite as a dedicated button
                if hSizeClass != .compact {
                    Button {
                        userStore.toggleFavorite(for: series.folderURL)
                    } label: {
                        Image(systemName: userStore.isFavorite(series.folderURL) ? "star.fill" : "star")
                    }
                }

                // All other actions live in the overflow menu
                Menu {
                    // iPhone (compact): include Favorite inside the menu too
                    if hSizeClass == .compact {
                        Button {
                            userStore.toggleFavorite(for: series.folderURL)
                        } label: {
                            Label(
                                userStore.isFavorite(series.folderURL) ? "Unfavorite" : "Favorite",
                                systemImage: userStore.isFavorite(series.folderURL) ? "star.fill" : "star"
                            )
                        }
                        Divider()
                    }

                    Button {
                        showListsSheet = true
                    } label: {
                        Label("Add to List", systemImage: "text.badge.plus")
                    }

                    Button {
                        noteDraft = userStore.note(for: series.folderURL)
                        showNotesSheet = true
                    } label: {
                        Label("Notes", systemImage: "note.text")
                    }

                    Divider()

                    // Match stays a sheet action
                    Button {
                        showMatchSheet = true
                    } label: {
                        Label("Match…", systemImage: "link")
                    }

                } label: {
                    Image(systemName: "ellipsis.circle")
                }
        }
    }
        .sheet(isPresented: $showMatchSheet) {
            SeriesMatchSheet(
                seriesTitle: displayTitle,
                onSelect: { media in
                    metadataStore.setManualMatch(anilistId: media.id, for: series.folderURL)
                    // Re-fetch metadata using the chosen AniList id
                    Task { await metadataStore.ensureMetadata(for: series) }
                    showMatchSheet = false
                },
                onClear: {
                    metadataStore.clearManualMatch(for: series.folderURL)
                    Task { await metadataStore.ensureMetadata(for: series) }
                    showMatchSheet = false
                }
            )
        }
        .sheet(isPresented: $showListsSheet) {
            SeriesListsSheet(series: series)
                .environmentObject(userStore)
        }
        .sheet(isPresented: $showNotesSheet) {
            SeriesNotesEditorSheet(
                title: displayTitle,
                text: $noteDraft,
                onSave: {
                    userStore.setNote(noteDraft, for: series.folderURL)
                    showNotesSheet = false
                },
                onCancel: {
                    showNotesSheet = false
                }
            )
        }
        .task {
            // 1) Load local books (volumes) first
            if books.isEmpty {
                let loaded = await Task.detached(priority: .userInitiated) { [store, series] in
                    store.books(in: series)
                }.value
                await MainActor.run { books = loaded }
            }

            // 1.5) Load cached series data so UI is populated instantly
            await loadSeriesCacheIfNeeded()

            // 2) Ensure AniList metadata
            await metadataStore.ensureMetadata(for: series)

            // 2.25) Load awards from Wikidata (best-effort)
            await loadWikidataIfNeeded()

            // 2.5) Theme background from dominant cover color (quantized / stable)
            await updateThemeColorIfNeeded()

            // 3) Load MangaDex covers (best effort)
            await loadMangaDexCoversIfNeeded()
        }
        .navigationDestination(isPresented: $showReader) {
            if let book = selectedBookToOpen {
                ReaderView(book: book, seriesTitle: displayTitle)
            } else {
                EmptyView()
            }
        }
        .overlay {
            if showDownloadOverlay {
                DownloadOverlay(
                    title: downloadTitle,
                    status: downloadStatus,
                    progress: downloadProgress,
                    onClose: { showDownloadOverlay = false }
                )
            }
        }
    }

    // MARK: - MangaDex covers

    
    @MainActor
    private func handleOpen(_ book: LibraryStore.Book) async {
        let url = book.fileURL

        // If already local, open immediately.
        if ICloudDownloadHelper.isDownloaded(url) {
            selectedBookToOpen = book
            showReader = true
            return
        }

        // Not downloaded -> show your popup and start download.
        downloadTitle = book.title
        downloadStatus = "Downloading from iCloud…"
        downloadProgress = 0.1
        downloadReadyToOpen = false
        showDownloadOverlay = true

        do {
            try ICloudDownloadHelper.startDownload(url)
        } catch {
            downloadStatus = "Could not start download."
            downloadProgress = 0
            return
        }

        // Poll until downloaded (simple + reliable).
        // We don't have perfect percent here without NSMetadataQuery,
        // but we can still show a real progress bar moving while we wait.
        var fake: Double = 0.15
        while !ICloudDownloadHelper.isDownloaded(url) {
            try? await Task.sleep(nanoseconds: 250_000_000)
            fake = min(0.9, fake + 0.03)
            downloadProgress = fake
        }

        downloadProgress = 1.0
        downloadStatus = "Downloaded. Tap the volume again to open."
        downloadReadyToOpen = true

        // IMPORTANT: we do NOT auto-open — matches your requirement.
    }

    // MARK: - Wikidata awards

    @MainActor
    private func loadWikidataIfNeeded() async {
        // Avoid repeated work
        guard !isLoadingAwards else { return }

        // Prefer the matched AniList title when available.
        let title = displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        // If we already loaded something, don't refetch.
        if wikidataEntityId != nil || !awards.isEmpty || wikidataPublisher != nil || wikidataInceptionYear != nil {
            return
        }

        isLoadingAwards = true
        defer { isLoadingAwards = false }

        do {
            // 1) Resolve the best Wikidata entity id (Q-id) for this series title.
            guard let entityId = try await fetchBestWikidataEntityId(forTitle: title) else {
                awards = []
                return
            }
            wikidataEntityId = entityId

            // 2) Fetch entity details (logo/image + publisher + inception year)
            let details = try await fetchWikidataEntityDetails(entityId: entityId)
            wikidataPublisher = details.publisher
            wikidataInceptionYear = details.inceptionYear

            // 3) Fetch awards using your existing client (entityId-based).
            let found = try await WikidataAwardsClient.shared.fetchAwards(entityId: entityId)
            awards = found
            // Persist to cache so next open is instant
            cacheWikidata(entityId: entityId, publisher: wikidataPublisher, inceptionYear: wikidataInceptionYear, awards: awards)
        } catch {
            awards = []
            print("Wikidata load error:", error)
        }
    }

    // MARK: - Wikidata entity details (logo/image + publisher + inception)

    private struct WikidataDetails {
        let logoURL: URL?
        let publisher: String?
        let inceptionYear: String?
    }

    private func fetchWikidataEntityDetails(entityId: String) async throws -> WikidataDetails {
        // Fetch claims for the entity
        var comps = URLComponents(string: "https://www.wikidata.org/w/api.php")!
        comps.queryItems = [
            .init(name: "action", value: "wbgetentities"),
            .init(name: "ids", value: entityId),
            .init(name: "props", value: "claims"),
            .init(name: "format", value: "json")
        ]

        let url = comps.url!
        let (data, _) = try await URLSession.shared.data(from: url)

        struct EntityResp: Decodable {
            struct Entity: Decodable {
                let claims: [String: [Claim]]?
            }
            let entities: [String: Entity]
        }

        struct Claim: Decodable {
            struct MainSnak: Decodable {
                let datavalue: DataValue?
            }
            let mainsnak: MainSnak
        }

        struct DataValue: Decodable {
            let value: Value
        }

        enum Value: Decodable {
            case string(String)
            case entityId(String)
            case time(String)
            case unknown

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()

                // Most common: string (for Commons file name)
                if let s = try? container.decode(String.self) {
                    self = .string(s)
                    return
                }

                // Entity ids come as {"entity-type":"item","numeric-id":123}
                if let obj = try? decoder.container(keyedBy: DynamicCodingKeys.self) {
                    if let numeric = try? obj.decode(Int.self, forKey: DynamicCodingKeys(stringValue: "numeric-id")!) {
                        self = .entityId("Q\(numeric)")
                        return
                    }
                    if let t = try? obj.nestedContainer(keyedBy: DynamicCodingKeys.self, forKey: DynamicCodingKeys(stringValue: "time")!) {
                        _ = t // no-op
                    }
                }

                // Time value comes as {"time":"+1967-01-01T00:00:00Z", ...}
                if let obj = try? decoder.container(keyedBy: DynamicCodingKeys.self) {
                    if let time = try? obj.decode(String.self, forKey: DynamicCodingKeys(stringValue: "time")!) {
                        self = .time(time)
                        return
                    }
                }

                self = .unknown
            }
        }

        struct DynamicCodingKeys: CodingKey {
            var stringValue: String
            init?(stringValue: String) { self.stringValue = stringValue }
            var intValue: Int? { nil }
            init?(intValue: Int) { return nil }
        }

        let resp = try JSONDecoder().decode(EntityResp.self, from: data)
        guard let entity = resp.entities[entityId] else {
            return WikidataDetails(logoURL: nil, publisher: nil, inceptionYear: nil)
        }

        let claims = entity.claims ?? [:]

        // Prefer logo (P154). If missing, fall back to image (P18).
        let fileName: String? = {
            if let c = claims["P154"], let first = c.first, let dv = first.mainsnak.datavalue {
                if case .string(let s) = dv.value { return s }
            }
            if let c = claims["P18"], let first = c.first, let dv = first.mainsnak.datavalue {
                if case .string(let s) = dv.value { return s }
            }
            return nil
        }()

        let logoURL: URL? = fileName.flatMap { commonsFileURL(for: $0) }

        // Publisher (P123) points to another item (Q-id)
        let publisherId: String? = {
            if let c = claims["P123"], let first = c.first, let dv = first.mainsnak.datavalue {
                if case .entityId(let qid) = dv.value { return qid }
            }
            return nil
        }()

        let publisherLabel: String?
        if let publisherId {
            publisherLabel = try await fetchWikidataLabel(entityId: publisherId)
        } else {
            publisherLabel = nil
        }

        // Inception (P571) is a time string like "+1967-01-01T00:00:00Z"
        let inceptionYear: String? = {
            if let c = claims["P571"], let first = c.first, let dv = first.mainsnak.datavalue {
                if case .time(let t) = dv.value {
                    return extractYear(fromWikidataTime: t)
                }
            }
            return nil
        }()

        return WikidataDetails(logoURL: logoURL, publisher: publisherLabel, inceptionYear: inceptionYear)
    }

    private func fetchWikidataLabel(entityId: String) async throws -> String? {
        var comps = URLComponents(string: "https://www.wikidata.org/w/api.php")!
        comps.queryItems = [
            .init(name: "action", value: "wbgetentities"),
            .init(name: "ids", value: entityId),
            .init(name: "props", value: "labels"),
            .init(name: "languages", value: "en"),
            .init(name: "format", value: "json")
        ]

        let url = comps.url!
        let (data, _) = try await URLSession.shared.data(from: url)

        struct LabelResp: Decodable {
            struct Entity: Decodable {
                struct Label: Decodable { let value: String }
                let labels: [String: Label]?
            }
            let entities: [String: Entity]
        }

        let resp = try JSONDecoder().decode(LabelResp.self, from: data)
        return resp.entities[entityId]?.labels?["en"]?.value
    }

    private func extractYear(fromWikidataTime time: String) -> String? {
        // "+1967-01-01T00:00:00Z" -> "1967"
        // "+02007-01-01T00:00:00Z" -> "2007"
        let trimmed = time.trimmingCharacters(in: CharacterSet(charactersIn: "+"))
        guard trimmed.count >= 4 else { return nil }
        let yearPart = String(trimmed.prefix(5)) // handles 0-padded years
        // Remove leading zeros
        let cleaned = yearPart.trimmingCharacters(in: CharacterSet(charactersIn: "0"))
        if cleaned.isEmpty {
            // fallback: last 4
            return String(trimmed.prefix(4))
        }
        // If it becomes 3 digits (e.g. 2007 ok), keep as-is
        return cleaned
    }

    private func commonsFileURL(for fileName: String) -> URL? {
        // Wikidata stores filenames like "Foo bar.png". Special:FilePath resolves to the actual file URL.
        let underscored = fileName.replacingOccurrences(of: " ", with: "_")
        var comps = URLComponents(string: "https://commons.wikimedia.org/wiki/Special:FilePath/")!
        comps.path += underscored
        return comps.url
    }

    // MARK: - Wikidata entity search (Q-id)

    private func fetchBestWikidataEntityId(forTitle title: String) async throws -> String? {
        // Use Wikidata's public search API to find the best matching entity id.
        // NOTE: This runs at app runtime; it does not affect build-time.
        var comps = URLComponents(string: "https://www.wikidata.org/w/api.php")!
        comps.queryItems = [
            .init(name: "action", value: "wbsearchentities"),
            .init(name: "search", value: title),
            .init(name: "language", value: "en"),
            .init(name: "limit", value: "5"),
            .init(name: "format", value: "json")
        ]

        let url = comps.url!
        let (data, _) = try await URLSession.shared.data(from: url)

        struct SearchResponse: Decodable {
            struct Item: Decodable {
                let id: String
                let label: String?
                let description: String?
            }
            let search: [Item]
        }

        let resp = try JSONDecoder().decode(SearchResponse.self, from: data)
        guard !resp.search.isEmpty else { return nil }

        // Prefer the first result, but if there are multiple with very similar labels,
        // pick the one whose label matches best (case-insensitive).
        let normalized = normalizeForWikidata(title)

        func score(_ item: SearchResponse.Item) -> Double {
            let label = normalizeForWikidata(item.label ?? "")
            if label == normalized { return 1.0 }
            if label.contains(normalized) || normalized.contains(label) { return 0.85 }
            // fallback: token overlap
            let a = Set(normalized.split(separator: " ").map(String.init))
            let b = Set(label.split(separator: " ").map(String.init))
            guard !a.isEmpty, !b.isEmpty else { return 0.0 }
            return Double(a.intersection(b).count) / Double(a.union(b).count)
        }

        let best = resp.search
            .map { ($0, score($0)) }
            .sorted { $0.1 > $1.1 }
            .first

        // Only accept if it looks reasonably close.
        guard let bestItem = best?.0, (best?.1 ?? 0) >= 0.25 else { return nil }
        return bestItem.id
    }

    private func normalizeForWikidata(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: ":", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: " ")
            .split(separator: " ")
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func updateThemeColorIfNeeded() async {
        guard !didComputeTheme else { return }
        didComputeTheme = true

        // Capture lightweight references only
        let localCoverURL = series.coverURL
        let remoteURL: URL? = {
            if let s = metadata?.coverImageLarge, let u = URL(string: s) { return u }
            return nil
        }()

        // Heavy work off-main so your UI doesn't hitch/freeze
        Task.detached(priority: .utility) {
            var img: UIImage?

            // 1) Prefer local cover if it's already downloaded
            if let local = localCoverURL {
                if ICloudDownloadHelper.isDownloaded(local) {
                    img = CoverImageStore.shared.load(from: local)
                } else {
                    img = nil
                }
            } else {
                img = nil
            }

            // 2) Fallback to remote cover (AniList)
            if img == nil, let url = remoteURL {
                img = await fetchUIImage(url: url)
            }

            guard let img else {
                await MainActor.run { self.themeUIColor = .black }
                return
            }

            let theme = img.dominantAppThemeColorQuantized ?? .black
            await MainActor.run {
                self.themeUIColor = theme
                self.cacheThemeColor(theme)
            }
        }
    }

    private func fetchUIImage(url: URL) async -> UIImage? {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return UIImage(data: data)
        } catch {
            return nil
        }
    }
    
    private func loadMangaDexCoversIfNeeded() async {
        guard mdCoverByVolume.isEmpty, !isLoadingMDCovers else { return }
        isLoadingMDCovers = true

        let titleForSearch = metadata?.title ?? series.title

        Task.detached(priority: .utility) {
            do {
                guard let mangaId = try await MangaDexClient.shared.searchMangaId(title: titleForSearch) else {
                    await MainActor.run { self.isLoadingMDCovers = false }
                    return
                }

                let covers = try await MangaDexClient.shared.fetchCovers(mangaId: mangaId)

                // Build volume -> url map
                var map: [Int: URL] = [:]
                for c in covers {
                    guard let vStr = c.volume, let v = Int(vStr) else { continue }
                    if let url = (c.url512 ?? c.url256 ?? c.urlOriginal) {
                        if map[v] == nil { map[v] = url }
                    }
                }

                await MainActor.run {
                    self.mdCoverByVolume = map
                    self.isLoadingMDCovers = false
                    self.cacheMangaDexCovers(map)
                }
            } catch {
                print("MangaDex cover load error:", error)
                await MainActor.run { self.isLoadingMDCovers = false }
            }
        }
    }

    // MARK: - Series Cache (instant UI + persistence)

    @MainActor
    private func loadSeriesCacheIfNeeded() async {
        guard !didLoadSeriesCache else { return }
        didLoadSeriesCache = true

        // Requires SeriesCacheStore.swift (I’ll give you that file next)
        guard let cached = SeriesCacheStore.shared.load(for: series.folderURL) else { return }

        // Apply cached values immediately
        if let hex = cached.themeColorHex, let ui = UIColor(hex: hex) {
            themeUIColor = ui
            didComputeTheme = true
        }

        if let publisher = cached.publisher, wikidataPublisher == nil {
            wikidataPublisher = publisher
        }
        if let year = cached.inceptionYear, wikidataInceptionYear == nil {
            wikidataInceptionYear = year
        }

        if awards.isEmpty, let cachedAwards = cached.awards {
            awards = cachedAwards
            wikidataEntityId = cached.wikidataEntityId
        }

        if mdCoverByVolume.isEmpty, let coverMap = cached.mdCoverByVolume {
            mdCoverByVolume = coverMap
        }
    }

    @MainActor
    private func cacheThemeColor(_ color: UIColor) {
        let hex = color.toHexString()
        SeriesCacheStore.shared.upsert(for: series.folderURL) { draft in
            draft.themeColorHex = hex
        }
    }

    @MainActor
    private func cacheWikidata(entityId: String?, publisher: String?, inceptionYear: String?, awards: [AwardItem]) {
        SeriesCacheStore.shared.upsert(for: series.folderURL) { draft in
            draft.wikidataEntityId = entityId
            draft.publisher = publisher
            draft.inceptionYear = inceptionYear
            draft.awards = awards
        }
    }

    @MainActor
    private func cacheMangaDexCovers(_ map: [Int: URL]) {
        SeriesCacheStore.shared.upsert(for: series.folderURL) { draft in
            draft.mdCoverByVolume = map
        }
    }
}

private struct DownloadOverlay: View {
    let title: String
    let status: String
    let progress: Double
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.white)

                    Spacer()

                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                Text(status)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(2)

                ProgressView(value: progress)
                    .tint(.white)
            }
            .padding(16)
            .frame(maxWidth: 420)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(white: 0.12).opacity(0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - Description Card

private struct DescriptionCard: View {
    let text: String
    @State private var expanded = false

    // Tweak these to taste
    private let collapsedLines: Int = 4

    var body: some View {
        let cleaned = clean(text)

        VStack(alignment: .leading, spacing: 12) {

            // Header row
            HStack(spacing: 10) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))

                Text("Synopsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)

                Spacer(minLength: 0)
                
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        expanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(expanded ? "Less" : "More")
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.10))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            // Body text
            Text(cleaned)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.white.opacity(0.92))
                .lineSpacing(4)
                .lineLimit(expanded ? nil : collapsedLines)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            // Optional hint when collapsed
            if !expanded {
                Text("Tap More to read the full synopsis")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func clean(_ s: String) -> String {
        // Normalize common AniList HTML + entities.
        var out = s

        // Line breaks
        out = out.replacingOccurrences(of: "<br>", with: "\n")
        out = out.replacingOccurrences(of: "<br />", with: "\n")
        out = out.replacingOccurrences(of: "<br/>", with: "\n")

        // Strip basic tags
        let tags = ["<i>", "</i>", "<b>", "</b>", "<em>", "</em>", "<strong>", "</strong>"]
        for t in tags { out = out.replacingOccurrences(of: t, with: "") }

        // Very basic link removal: keep the link text, drop the tag
        out = out.replacingOccurrences(of: "</a>", with: "")
        out = out.replacingOccurrences(of: #"<a[^>]*>"#, with: "", options: .regularExpression)

        // Entities
        out = out.replacingOccurrences(of: "&nbsp;", with: " ")
        out = out.replacingOccurrences(of: "&quot;", with: "\"")
        out = out.replacingOccurrences(of: "&#039;", with: "'")
        out = out.replacingOccurrences(of: "&amp;", with: "&")

        // Collapse whitespace but keep paragraph breaks
        out = out
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n\s*\n\s*\n+"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return out
    }
}

// MARK: - Books List (Volumes)


private struct AwardsSection: View {
    let awards: [AwardItem]

    private var topAwards: [AwardItem] {
        Array(awards.prefix(18))
    }

    var body: some View {
        guard !awards.isEmpty else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 12) {

                // Header row (matches Synopsis / Volumes / Characters / Recommended)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "rosette")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Awards")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)

                        Text("From Wikidata")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.65))
                    }

                    Spacer(minLength: 0)

                    Text("\(awards.count)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.10))
                        .clipShape(Capsule())
                }

                // A grid that looks like chips/cards, consistent with your other sections.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                    ForEach(topAwards) { a in
                        AwardChip(award: a)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        )
    }

    // MARK: - Chip

    private struct AwardChip: View {
        let award: AwardItem

        var body: some View {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.10))

                    Image(systemName: "rosette")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.88))
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text(award.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)

                    if let y = award.year, !y.isEmpty {
                        Text(y)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.70))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
        }
    }
}


private struct VolumeSection: View {
    let seriesFolderURL: URL
    let books: [LibraryStore.Book]
    let totalCount: Int
    let coverByVolume: [Int: URL]
    let onTap: (LibraryStore.Book) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {

                Image(systemName: "books.vertical")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Volumes")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)

                    Text("Tap a volume to open")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.65))
                }

                Spacer(minLength: 0)

                Text("\(totalCount)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.10))
                    .clipShape(Capsule())
            }

            BooksListView(
                seriesFolderURL: seriesFolderURL,
                books: books,
                coverByVolume: coverByVolume,
                onTap: onTap
            )
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct BooksListView: View {
    let seriesFolderURL: URL
    let books: [LibraryStore.Book]
    let coverByVolume: [Int: URL]
    let onTap: (LibraryStore.Book) -> Void

    private struct Group: Identifiable {
        let id: String
        let title: String
        let books: [LibraryStore.Book]
    }

    private var groups: [Group] {
        // Group by the immediate parent folder under the series folder.
        // If the book lives directly in the series root, it goes into the "" group.
        let keyed = Dictionary(grouping: books) { book -> String in
            let parent = book.fileURL.deletingLastPathComponent()
            // If parent is the series root, treat as ungrouped.
            if parent.standardizedFileURL == seriesFolderURL.standardizedFileURL {
                return ""
            }
            return parent.lastPathComponent
        }

        // Sort groups: ungrouped first, then alphabetically.
        let sortedKeys = keyed.keys.sorted { a, b in
            if a.isEmpty { return true }
            if b.isEmpty { return false }
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }

        return sortedKeys.map { key in
            Group(id: key, title: key.isEmpty ? "" : key, books: keyed[key] ?? [])
        }
    }

    var body: some View {
        LazyVStack(spacing: 12) {
            ForEach(groups) { group in
                if !group.title.isEmpty {
                    subsectionHeader(group.title)
                }

                LazyVStack(spacing: 10) {
                    ForEach(group.books) { book in
                        Button {
                            onTap(book)
                        } label: {
                            ChapterRow(
                                book: book,
                                coverURL: coverURL(for: book)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func subsectionHeader(_ title: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.75))
                .textCase(.uppercase)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.top, 2)
        .padding(.bottom, 2)
    }

    private func coverURL(for book: LibraryStore.Book) -> URL? {
        guard let v = extractVolumeNumber(from: book.title) else { return nil }
        return coverByVolume[v]
    }

    private func extractVolumeNumber(from title: String) -> Int? {
        let patterns = [
            #"(?i)\bv\s*([0-9]{1,3})\b"#,                 // v00, v02, v 02
            #"(?i)\bv\s*([0-9]{1,3})(?=[^0-9]|$)"#,       // v00, v02, (comma/space/end)
            #"(?i)\bvol(?:ume)?\.?\s*([0-9]{1,3})\b"#     // vol 0 / volume 02
        ]
        for p in patterns {
            guard let r = try? NSRegularExpression(pattern: p) else { continue }
            let ns = title as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let m = r.firstMatch(in: title, range: range), m.numberOfRanges >= 2 {
                let raw = ns.substring(with: m.range(at: 1))
                return Int(raw)
            }
        }
        return nil
    }
}

private struct ChapterRow: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass

    let book: LibraryStore.Book
    let coverURL: URL?
    @ObservedObject private var progressStore = ReadingProgressStore.shared

    private var isCompact: Bool { hSizeClass == .compact }
    private var coverSize: CGSize { isCompact ? CGSize(width: 96, height: 132) : CGSize(width: 132, height: 180) }
    private var titleFontSize: CGFloat { isCompact ? 17 : 20 }
    private var subtitleFontSize: CGFloat { isCompact ? 12 : 13 }
    private var progressFontSize: CGFloat { isCompact ? 12 : 14 }

    private var isDownloaded: Bool {
        ICloudDownloadHelper.isDownloaded(book.fileURL)
    }

    private enum StatusBadge {
        case finished, reading, ready, icloud

        var text: String {
            switch self {
            case .finished: return "Finished"
            case .reading:  return "Reading"
            case .ready:    return "Ready"
            case .icloud:   return "iCloud"
            }
        }

        var icon: String {
            switch self {
            case .finished: return "checkmark.seal.fill"
            case .reading:  return "bookmark.fill"
            case .ready:    return "checkmark.circle"
            case .icloud:   return "icloud.and.arrow.down"
            }
        }

        var backgroundOpacity: Double {
            switch self {
            case .finished: return 0.18
            case .reading:  return 0.16
            case .ready:    return 0.12
            case .icloud:   return 0.16
            }
        }
    }

    private var badge: StatusBadge {
        if let p = progressStore.progress(for: book.fileURL) {
            if p.isCompleted { return .finished }
            return .reading
        }
        return isDownloaded ? .ready : .icloud
    }

    private var progressText: String? {
        if let p = progressStore.progress(for: book.fileURL) {
            // Only show page numbers while reading
            if p.isCompleted {
                return "Finished"
            }
            return "Page \(p.lastPageIndex + 1) of \(p.totalPages)"
        }
        return nil
    }

    private var progressValue: Double {
        progressStore.progressValue(for: book.fileURL)
    }

    private var showsProgress: Bool {
        guard let p = progressStore.progress(for: book.fileURL) else { return false }
        return !p.isCompleted
    }

    private var titleParts: (label: String, subtitle: String?) {
        // Make a clean label like “Volume 2” when possible.
        if let v = extractVolumeNumber(from: book.title) {
            let label = "Volume \(v)"
            return (label, book.title)
        }
        return (book.title, nil)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {

            // Cover
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.10))

                if let coverURL {
                    AsyncImage(url: coverURL) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                        default:
                            Color.white.opacity(0.06)
                        }
                    }
                } else {
                    Image(systemName: "book.closed")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(.white.opacity(0.55))
                }
            }
            .frame(width: coverSize.width, height: coverSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )

            // Text + progress
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(titleParts.label)
                        .font(.system(size: titleFontSize, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    HStack(spacing: 6) {
                        Image(systemName: badge.icon)
                            .font(.system(size: 11, weight: .bold))

                        // iPhone: icon-only to reduce clutter
                        if !isCompact {
                            Text(badge.text)
                                .font(.system(size: 12, weight: .bold))
                        }
                    }
                    .foregroundColor(.white.opacity(badge == .ready ? 0.78 : 1.0))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(badge.backgroundOpacity))
                    .clipShape(Capsule())
                }

                if !isCompact, let subtitle = titleParts.subtitle {
                    Text(subtitle)
                        .font(.system(size: subtitleFontSize, weight: .medium))
                        .foregroundColor(.white.opacity(0.60))
                        .lineLimit(1)
                }

                if let progressText {
                    Text(progressText)
                        .font(.system(size: progressFontSize, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                }

                if showsProgress {
                    ProgressView(value: progressValue)
                        .tint(.white)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.35))
                .padding(.top, 6)
        }
        .padding(isCompact ? 10 : 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func extractVolumeNumber(from title: String) -> Int? {
        let patterns = [
            #"(?i)\bv\s*([0-9]{1,3})\b"#,                 // v00, v02, v 02
            #"(?i)\bv\s*([0-9]{1,3})(?=[^0-9]|$)"#,       // v00, v02, (comma/space/end)
            #"(?i)\bvol(?:ume)?\.?\s*([0-9]{1,3})\b"#     // vol 0 / volume 02
        ]
        for p in patterns {
            guard let r = try? NSRegularExpression(pattern: p) else { continue }
            let ns = title as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let m = r.firstMatch(in: title, range: range), m.numberOfRanges >= 2 {
                let raw = ns.substring(with: m.range(at: 1))
                return Int(raw)
            }
        }
        return nil
    }
}


// MARK: - Cover View

private struct SeriesCoverView: View {
    let series: LibraryStore.Series
    let metadata: SeriesMetadata?
    let size: CGSize

    init(series: LibraryStore.Series, metadata: SeriesMetadata?, size: CGSize = CGSize(width: 160, height: 230)) {
        self.series = series
        self.metadata = metadata
        self.size = size
    }

    var body: some View {
        ZStack {
            if let local = series.coverURL,
               let img = CoverImageStore.shared.load(from: local) {
                Image(uiImage: img).resizable().scaledToFill()
            } else if let remote = metadata?.coverImageLarge,
                      let url = URL(string: remote) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: Color.gray.opacity(0.4)
                    }
                }
            } else {
                Color.gray.opacity(0.4)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(radius: 6)
    }
}

// MARK: - Hero Header

private struct SeriesHeaderView: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass

    let series: LibraryStore.Series
    let metadata: SeriesMetadata?
    let wikidataPublisher: String?
    let wikidataInceptionYear: String?
    let progressPercent: Double
    let progressText: String
    let firstUnreadBook: LibraryStore.Book?

    private var isCompact: Bool { hSizeClass == .compact }

    private var headerHeight: CGFloat { isCompact ? 420 : 560 }
    private var coverSize: CGSize { isCompact ? CGSize(width: 110, height: 160) : CGSize(width: 160, height: 230) }
    private var titleFontSize: CGFloat { isCompact ? 28 : 42 }
    private var subtitleFontSize: CGFloat { isCompact ? 14 : 16 }
    private var authorFontSize: CGFloat { isCompact ? 15 : 18 }
    private var scoreFontSize: CGFloat { isCompact ? 16 : 20 }
    private var topPadding: CGFloat { isCompact ? 96 : 160 }

    private var authorLine: String? {
        guard let staff = metadata?.staff, !staff.isEmpty else { return nil }
        let preferred =
            staff.first(where: { ($0.role ?? "").localizedCaseInsensitiveContains("story") }) ??
            staff.first(where: { ($0.role ?? "").localizedCaseInsensitiveContains("art") }) ??
            staff.first
        return preferred?.name
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {

            headerBackground
                .frame(height: headerHeight)
                .clipped()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.0),
                    Color.black.opacity(0.45),
                    Color.black.opacity(0.75)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: headerHeight)

            Group {
                if isCompact {
                    // iPhone: tighter header + stacked full-width buttons (prevents "Contin-ue")
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .bottom, spacing: 12) {
                            SeriesCoverView(series: series, metadata: metadata, size: coverSize)

                            VStack(alignment: .leading, spacing: 8) {
                                Text(metadata?.title ?? series.title)
                                    .font(.system(size: titleFontSize, weight: .bold))
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.85)
                                    .allowsTightening(true)

                                if let publisher = wikidataPublisher {
                                    let year = wikidataInceptionYear
                                    Text(year == nil ? publisher : "\(publisher) • Since \(year!)")
                                        .font(.system(size: subtitleFontSize, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.86))
                                        .lineLimit(1)
                                }

                                if let authorLine {
                                    Text(authorLine)
                                        .font(.system(size: authorFontSize, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.90))
                                        .lineLimit(1)
                                }

                                if let score = metadata?.averageScore {
                                    Text("⭐️ \(score)/100")
                                        .font(.system(size: scoreFontSize, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.88))
                                }
                            }

                            Spacer(minLength: 0)
                        }

                        ProgressView(value: progressPercent)
                            .tint(.white)

                        Text(progressText)
                            .font(.system(size: subtitleFontSize, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)

                        VStack(spacing: 10) {
                            if let book = firstUnreadBook {
                                NavigationLink {
                                    ReaderView(book: book, seriesTitle: metadata?.title ?? series.title)
                                } label: {
                                    Label("Continue", systemImage: "play.fill")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color.white)
                                        .foregroundColor(.black)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }

                            if let first = firstUnreadBook {
                                NavigationLink {
                                    ReaderView(book: first, seriesTitle: metadata?.title ?? series.title)
                                } label: {
                                    Label("Open", systemImage: "book")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color.white.opacity(0.18))
                                        .foregroundColor(.white)
                                        .clipShape(Capsule())
                                        .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            } else {
                                Label("Open", systemImage: "book")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.white.opacity(0.10))
                                    .foregroundColor(.white.opacity(0.6))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                } else {
                    // iPad: keep existing layout
                    HStack(alignment: .bottom, spacing: 16) {
                        SeriesCoverView(series: series, metadata: metadata, size: coverSize)

                        VStack(alignment: .leading, spacing: 10) {
                            Text(metadata?.title ?? series.title)
                                .font(.system(size: titleFontSize, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(2)

                            if let publisher = wikidataPublisher {
                                let year = wikidataInceptionYear
                                Text(year == nil ? publisher : "\(publisher) • Since \(year!)")
                                    .font(.system(size: subtitleFontSize, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.86))
                                    .lineLimit(1)
                            }

                            if let authorLine {
                                Text(authorLine)
                                    .font(.system(size: authorFontSize, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.90))
                                    .lineLimit(1)
                            }

                            if let score = metadata?.averageScore {
                                Text("⭐️ \(score)/100")
                                    .font(.system(size: scoreFontSize, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.88))
                            }

                            ProgressView(value: progressPercent)
                                .tint(.white)

                            Text(progressText)
                                .font(.system(size: subtitleFontSize, weight: .medium))
                                .foregroundColor(.white.opacity(0.85))
                                .lineLimit(1)

                            HStack(spacing: 12) {
                                if let book = firstUnreadBook {
                                    NavigationLink {
                                        ReaderView(book: book, seriesTitle: metadata?.title ?? series.title)
                                    } label: {
                                        Label("Continue", systemImage: "play.fill")
                                            .font(.headline)
                                            .padding(.vertical, 10)
                                            .padding(.horizontal, 14)
                                            .background(Color.white)
                                            .foregroundColor(.black)
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }

                                if let first = firstUnreadBook {
                                    NavigationLink {
                                        ReaderView(book: first, seriesTitle: metadata?.title ?? series.title)
                                    } label: {
                                        Label("Open", systemImage: "book")
                                            .font(.headline)
                                            .padding(.vertical, 10)
                                            .padding(.horizontal, 14)
                                            .background(Color.white.opacity(0.18))
                                            .foregroundColor(.white)
                                            .clipShape(Capsule())
                                            .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    Label("Open", systemImage: "book")
                                        .font(.headline)
                                        .padding(.vertical, 10)
                                        .padding(.horizontal, 14)
                                        .background(Color.white.opacity(0.10))
                                        .foregroundColor(.white.opacity(0.6))
                                        .clipShape(Capsule())
                                }
                            }
                        }

                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.leading, isCompact ? 18 : 24)
            .padding(.trailing, isCompact ? 18 : 24)
            .padding(.bottom, 26)
            .padding(.top, topPadding)
        }
        .frame(height: headerHeight)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // ✅ FIXES “banner stretch / weird zoom”:
    // Uses blurred fill + fit foreground for any aspect ratio.
    private var headerBackground: some View {
        GeometryReader { geo in
            ZStack {
                if let banner = metadata?.bannerImage,
                   let url = URL(string: banner) {

                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            constrainedHero(img, width: geo.size.width, height: headerHeight)
                        default:
                            constrainedFallback(width: geo.size.width, height: headerHeight)
                        }
                    }

                } else {
                    constrainedFallback(width: geo.size.width, height: headerHeight)
                }
            }
            .frame(width: geo.size.width, height: headerHeight)      // ✅ hard clamp width/height
            .clipped()                                               // ✅ never draw outside
            .contentShape(Rectangle())
        }
        .frame(height: headerHeight)                                // ✅ keeps parent layout stable
    }
    
    @ViewBuilder private func constrainedFallback(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            if let local = series.coverURL,
               let ui = CoverImageStore.shared.load(from: local) {
                constrainedHero(Image(uiImage: ui), width: width, height: height)
            } else if let cover = metadata?.coverImageLarge, let url = URL(string: cover) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        constrainedHero(img, width: width, height: height)
                    default:
                        Color.white.opacity(0.06)
                            .frame(width: width, height: height)
                    }
                }
            } else {
                Color.white.opacity(0.06)
                    .frame(width: width, height: height)
            }
        }
    }
    @ViewBuilder private func constrainedHero(_ image: Image, width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            // Background blur fill (cannot affect layout because we force frame)
            image
                .resizable()
                .scaledToFill()
                .frame(width: width, height: height)
                .clipped()
                .blur(radius: 26)
                .opacity(0.65)

            // Foreground fill (crop) so it covers the whole header
            image
                .resizable()
                .scaledToFill()
                .frame(width: width, height: height)
                .clipped()
        }
        .frame(width: width, height: height)
        .clipped()
    }
}

// MARK: - Characters Shelf

private struct CharactersShelf: View {
    let characters: [CharacterMeta]

    private var topCharacters: [CharacterMeta] {
        Array(characters.prefix(14))
    }

    var body: some View {
        guard !characters.isEmpty else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 12) {

                // Header row (matches Synopsis / Volumes styling)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Characters")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)

                        Text("Main cast")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.65))
                    }

                    Spacer(minLength: 0)

                    Text("\(characters.count)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.10))
                        .clipShape(Capsule())
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(topCharacters, id: \.name) { c in
                            CharacterCard(character: c)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        )
    }
}

private struct CharacterCard: View {
    let character: CharacterMeta

    var body: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.10))

            // Image / placeholder
            Group {
                if let s = character.imageLarge, let url = URL(string: s) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                        default:
                            Color.white.opacity(0.06)
                        }
                    }
                } else {
                    ZStack {
                        Color.white.opacity(0.06)
                        Image(systemName: "person.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Bottom readability gradient (taller so 2-line names fit)
            VStack {
                Spacer()
                LinearGradient(
                    colors: [Color.black.opacity(0.0), Color.black.opacity(0.82)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 96)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Name pinned inside the card (won't get clipped)
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                Text(character.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .frame(width: 160, height: 230)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Recommendations Shelf

// MARK: - Recommendations Shelf

private struct RecommendationsShelf: View {
    @EnvironmentObject private var store: LibraryStore
    @StateObject private var metadataStore = SeriesMetadataStore.shared

    let recommendations: [RecommendationMeta]

    private var topRecs: [RecommendationMeta] {
        Array(recommendations.prefix(18))
    }

    var body: some View {
        guard !recommendations.isEmpty else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 12) {

                // Header row (matches Synopsis / Volumes / Characters)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recommended")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)

                        Text("You might also like")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.65))
                    }

                    Spacer(minLength: 0)

                    Text("\(recommendations.count)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.10))
                        .clipShape(Capsule())
                }

                // Horizontal list with compact cards so ~3 fit on screen
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(topRecs, id: \.anilistId) { r in
                            if let matched = matchedSeries(forAniListId: r.anilistId) {
                                NavigationLink {
                                    SeriesDetailView(series: matched)
                                } label: {
                                    RecommendationMiniCard(rec: r, showsChevron: true)
                                }
                                .buttonStyle(.plain)
                            } else {
                                RecommendationMiniCard(rec: r, showsChevron: false)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        )
    }

    /// Best-effort local match: if any series in the user's library has metadata with this AniList id,
    /// we consider it linkable.
    private func matchedSeries(forAniListId id: Int) -> LibraryStore.Series? {
        for s in store.series {
            if metadataStore.metadata(for: s.folderURL)?.anilistId == id {
                return s
            }
        }
        return nil
    }

    // MARK: - Recommendation Card

    private struct RecommendationMiniCard: View {
        let rec: RecommendationMeta
        let showsChevron: Bool

        private var yearText: String? {
            // Best-effort: if the title contains a year like "(2014)" or "2019", show it.
            extractYear(from: rec.title)
        }

        var body: some View {
            HStack(alignment: .center, spacing: 12) {

                // Cover
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.08))

                    if let s = rec.coverImageLarge, let url = URL(string: s) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().scaledToFill()
                            default:
                                Color.white.opacity(0.06)
                            }
                        }
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.white.opacity(0.55))
                    }
                }
                .frame(width: 72, height: 102)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )

                // Text
                VStack(alignment: .leading, spacing: 6) {
                    Text(rec.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)

                    if let y = yearText {
                        Text(y)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.70))
                            .lineLimit(1)
                    } else {
                        Text(" ")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.clear)
                            .lineLimit(1)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .semibold))
                        Text(showsChevron ? "Open" : "Not in Library")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.white.opacity(0.78))
                    .padding(.top, 2)
                }

                Spacer(minLength: 0)

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.35))
                }
            }
            .padding(14)
            .frame(width: 340, height: 120)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
        }

        private func extractYear(from s: String) -> String? {
            // Match 4-digit years in a reasonable range.
            let pattern = #"(19[5-9][0-9]|20[0-4][0-9])"#
            guard let r = try? NSRegularExpression(pattern: pattern) else { return nil }
            let ns = s as NSString
            let range = NSRange(location: 0, length: ns.length)
            guard let m = r.firstMatch(in: s, range: range) else { return nil }
            return ns.substring(with: m.range(at: 1))
        }
    }
}

// MARK: - Manual Match Sheet

private struct SeriesMatchSheet: View {
    let seriesTitle: String
    let onSelect: (AniListMedia) -> Void
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query: String
    @State private var isSearching = false
    @State private var results: [AniListMedia] = []
    @State private var errorText: String? = nil
    @FocusState private var fieldFocused: Bool

    init(seriesTitle: String, onSelect: @escaping (AniListMedia) -> Void, onClear: @escaping () -> Void) {
        self.seriesTitle = seriesTitle
        self.onSelect = onSelect
        self.onClear = onClear
        _query = State(initialValue: seriesTitle)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Search AniList…", text: $query)
                        .focused($fieldFocused)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { Task { await runSearch() } }

                    Button {
                        Task { await runSearch() }
                    } label: {
                        HStack {
                            Text("Search")
                            Spacer()
                            if isSearching { ProgressView() }
                        }
                    }
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
                }

                if let errorText {
                    Section {
                        Text(errorText)
                            .foregroundStyle(.secondary)
                    }
                }

                if !results.isEmpty {
                    Section("Results") {
                        ForEach(results, id: \.id) { m in
                            Button {
                                onSelect(m)
                            } label: {
                                HStack(spacing: 12) {
                                    AsyncImage(url: URL(string: m.coverImageLarge ?? "")) { phase in
                                        switch phase {
                                        case .success(let img):
                                            img.resizable().scaledToFill()
                                        default:
                                            Color.white.opacity(0.08)
                                        }
                                    }
                                    .frame(width: 44, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(m.titleEnglish ?? m.titleRomaji ?? m.titleNative ?? "Untitled")
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)

                                        if let score = m.averageScore {
                                            Text("⭐️ \(score)/100")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        onClear()
                    } label: {
                        Text("Clear manual match")
                    }
                }
            }
            .navigationTitle("Match series")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                // Auto-search on first open, but don't compete with the first keyboard focus.
                // A short delay makes the sheet/keyboard animation smooth.
                if results.isEmpty {
                    try? await Task.sleep(nanoseconds: 250_000_000) // 0.25s
                    if !fieldFocused {
                        await runSearch()
                    }
                }
            }
        }
    }

    private func runSearch() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }

        await MainActor.run {
            isSearching = true
            errorText = nil
        }

        do {
            // Do network + decoding off-main to keep typing/keyboard smooth.
            let found: [AniListMedia] = try await Task.detached(priority: .utility) {
                try await AniListClient.shared.searchManga(query: q, limit: 10)
            }.value

            await MainActor.run {
                results = found
                isSearching = false
            }
        } catch {
            await MainActor.run {
                results = []
                isSearching = false
                errorText = error.localizedDescription
            }
        }
    }
}

// MARK: - Theme color extraction (fast quantize / most-common bucket)

private extension UIImage {
    /// A fast, stable "most common" color suitable for app theming.
    /// - Downsamples the image.
    /// - Quantizes RGB into buckets.
    /// - Picks the most common bucket, ignoring near-black/near-white/low-sat pixels.
    var dominantAppThemeColorQuantized: UIColor? {
        guard let cg = self.cgImage else { return nil }

        let targetW = 48
        let targetH = 48

        let bytesPerPixel = 4
        let bytesPerRow = targetW * bytesPerPixel
        var data = [UInt8](repeating: 0, count: targetH * bytesPerRow)

        guard let ctx = CGContext(
            data: &data,
            width: targetW,
            height: targetH,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .low
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))

        struct Bucket { var count: Int = 0; var r: Int = 0; var g: Int = 0; var b: Int = 0 }
        var buckets = Array(repeating: Bucket(), count: 512)

        func rgbToSV(_ r: Double, _ g: Double, _ b: Double) -> (s: Double, v: Double) {
            let maxV = max(r, g, b)
            let minV = min(r, g, b)
            let delta = maxV - minV
            let v = maxV
            let s = maxV == 0 ? 0 : (delta / maxV)
            return (s, v)
        }

        for y in 0..<targetH {
            for x in 0..<targetW {
                let i = y * bytesPerRow + x * bytesPerPixel
                let r = Double(data[i]) / 255.0
                let g = Double(data[i + 1]) / 255.0
                let b = Double(data[i + 2]) / 255.0
                let a = Double(data[i + 3]) / 255.0

                if a < 0.5 { continue }

                let sv = rgbToSV(r, g, b)

                // Ignore near-black
                if sv.v < 0.10 { continue }

                // Ignore near-white / near-gray highlights
                if sv.v > 0.95 && sv.s < 0.10 { continue }

                // Ignore dull grays (these cause "always gray/black theme")
                if sv.s < 0.18 { continue }

                let qr = min(7, Int(r * 7.999))
                let qg = min(7, Int(g * 7.999))
                let qb = min(7, Int(b * 7.999))
                let idx = (qr << 6) | (qg << 3) | qb

                buckets[idx].count += 1
                buckets[idx].r += Int(data[i])
                buckets[idx].g += Int(data[i + 1])
                buckets[idx].b += Int(data[i + 2])
            }
        }

        guard let best = buckets.enumerated().max(by: { $0.element.count < $1.element.count }),
              best.element.count > 0 else {
            return nil
        }

        let c = best.element.count
        let rr = CGFloat(best.element.r) / CGFloat(c) / 255.0
        let gg = CGFloat(best.element.g) / CGFloat(c) / 255.0
        let bb = CGFloat(best.element.b) / CGFloat(c) / 255.0

        // Gentle grading so it looks good as a background
        func clamp(_ x: CGFloat) -> CGFloat { min(1, max(0, x)) }
        let gradedR = clamp(rr * 0.92 + 0.04)
        let gradedG = clamp(gg * 0.92 + 0.04)
        let gradedB = clamp(bb * 0.92 + 0.04)

        return UIColor(red: gradedR, green: gradedG, blue: gradedB, alpha: 1.0)
    }
}

// MARK: - UIColor helpers (hex)

private extension UIColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 else { return nil }
        var rgb: UInt64 = 0
        guard Scanner(string: s).scanHexInt64(&rgb) else { return nil }
        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }

    func toHexString() -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        let rr = Int(round(r * 255))
        let gg = Int(round(g * 255))
        let bb = Int(round(b * 255))
        return String(format: "#%02X%02X%02X", rr, gg, bb)
    }
}


// MARK: - Notes Card (User)

private struct NotesCard: View {
    let text: String
    let onEdit: () -> Void

    private var preview: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Add notes for this series…" }
        return trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "note.text")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Notes")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)

                    Text("Personal")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.65))
                }

                Spacer(minLength: 0)

                Button {
                    onEdit()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.pencil")
                        Text(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Add" : "Edit")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.10))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            Text(preview)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .white.opacity(0.60) : .white.opacity(0.90))
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture { onEdit() }
    }
}

// MARK: - List Selector Sheet

private struct SeriesListsSheet: View {
    @EnvironmentObject private var userStore: UserDataStore
    @Environment(\.dismiss) private var dismiss

    let series: LibraryStore.Series

    private var sortedLists: [UserList] {
        userStore.lists.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Add \(series.title) to your lists.")
                        .foregroundStyle(.secondary)
                }

                Section("Lists") {
                    ForEach(sortedLists) { list in
                        let enabled = userStore.data(for: series.folderURL).lists.contains(list.id)

                        Button {
                            userStore.setSeries(series.folderURL, inList: list.id, enabled: !enabled)
                        } label: {
                            HStack {
                                Label(list.name, systemImage: list.isSystem ? "lock.fill" : "list.bullet")
                                Spacer()
                                if enabled {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    Button {
                        userStore.toggleFavorite(for: series.folderURL)
                    } label: {
                        Label(userStore.isFavorite(series.folderURL) ? "Remove from Favorites" : "Add to Favorites", systemImage: "star")
                    }
                }
            }
            .navigationTitle("Lists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Notes Editor Sheet

private struct SeriesNotesEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    @Binding var text: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $text)
                    .padding(12)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
            }
            .navigationTitle("Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
