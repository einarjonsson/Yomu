import Foundation
import Combine

// MARK: - Stored app metadata (cached per series folder)

struct StaffPerson: Codable, Hashable {
    let name: String
    let role: String?
}

struct CharacterMeta: Codable, Hashable {
    let name: String
    let imageLarge: String?
}

struct RecommendationMeta: Codable, Hashable {
    let anilistId: Int
    let title: String
    let coverImageLarge: String?
}

struct SeriesMetadata: Codable, Hashable {
    let anilistId: Int
    let title: String
    let description: String?
    let averageScore: Int?
    let coverImageLarge: String?
    let bannerImage: String?
    let status: String?

    var staff: [StaffPerson] = []
    var characters: [CharacterMeta] = []
    var recommendations: [RecommendationMeta] = []

    // ✅ add this
    var awards: [AwardItem] = []

    let matchedAt: Date
    let confidence: Double
}

@MainActor
final class SeriesMetadataStore: ObservableObject {
    static let shared = SeriesMetadataStore()

    @Published private(set) var bySeriesFolder: [String: SeriesMetadata] = [:]
    private let storageKey = "series_metadata_v1"

    @Published private(set) var manualBySeriesFolder: [String: Int] = [:] // seriesKey -> anilistId
    private let manualStorageKey = "series_manual_match_v1"

    private init() {
        load()
        loadManual()
    }

    // MARK: - Keying (IMPORTANT)

    /// Canonical key for a series folder URL (stable across iCloud variants)
    private func seriesKey(for folderURL: URL) -> String {
        folderURL.standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }

    // MARK: - Read/write

    func metadata(for seriesFolderURL: URL) -> SeriesMetadata? {
        bySeriesFolder[seriesKey(for: seriesFolderURL)]
    }

    func setMetadata(_ meta: SeriesMetadata, for seriesFolderURL: URL) {
        bySeriesFolder[seriesKey(for: seriesFolderURL)] = meta
        save()
    }

    func hasMetadata(for seriesFolderURL: URL) -> Bool {
        bySeriesFolder[seriesKey(for: seriesFolderURL)] != nil
    }

    // MARK: - Manual matches

    func manualMatchId(for seriesFolderURL: URL) -> Int? {
        manualBySeriesFolder[seriesKey(for: seriesFolderURL)]
    }

    func setManualMatch(anilistId: Int, for seriesFolderURL: URL) {
        let k = seriesKey(for: seriesFolderURL)
        manualBySeriesFolder[k] = anilistId
        saveManual()

        // Bust cached metadata for THIS series key so next ensure fetches forced id
        bySeriesFolder.removeValue(forKey: k)
        save()
    }

    func clearManualMatch(for seriesFolderURL: URL) {
        let k = seriesKey(for: seriesFolderURL)
        manualBySeriesFolder.removeValue(forKey: k)
        saveManual()

        bySeriesFolder.removeValue(forKey: k)
        save()
    }

    // MARK: - Ensure metadata

    func ensureMetadata(for series: LibraryStore.Series) async {
        let k = seriesKey(for: series.folderURL)

        // If already cached, do nothing
        if bySeriesFolder[k] != nil { return }

        do {
            // 1) Manual match overrides everything
            if let forcedId = manualBySeriesFolder[k] {
                guard let best = try await AniListClient.shared.fetchManga(id: forcedId) else { return }

                var meta = SeriesMetadata(
                    anilistId: best.id,
                    title: best.bestTitle,
                    description: best.description,
                    averageScore: best.averageScore,
                    coverImageLarge: best.coverImageLarge,
                    bannerImage: best.bannerImage,
                    status: best.status,
                    staff: best.staff.map { StaffPerson(name: $0.name, role: $0.role) },
                    characters: best.characters.map { CharacterMeta(name: $0.name, imageLarge: $0.imageLarge) },
                    recommendations: best.recommendations.map { RecommendationMeta(anilistId: $0.id, title: $0.title, coverImageLarge: $0.coverImageLarge) },
                    matchedAt: Date(),
                    confidence: 1.0
                )

                // Best-effort awards
                do {
                    let awards = try await WikidataAwardsClient.shared.awards(forTitle: meta.title)
                    meta.awards = Array(awards.prefix(12))
                } catch {
                    // ignore; awards just won't show
                }

                setMetadata(meta, for: series.folderURL)
                return
            }

            // 2) Normal search
            let query = series.title
            let candidates = try await AniListClient.shared.searchManga(query: query, limit: 6)
            guard let best = pickBestMatch(query: query, candidates: candidates) else { return }

            var meta = SeriesMetadata(
                anilistId: best.id,
                title: best.bestTitle,
                description: best.description,
                averageScore: best.averageScore,
                coverImageLarge: best.coverImageLarge,
                bannerImage: best.bannerImage,
                status: best.status,
                staff: best.staff.map { StaffPerson(name: $0.name, role: $0.role) },
                characters: best.characters.map { CharacterMeta(name: $0.name, imageLarge: $0.imageLarge) },
                recommendations: best.recommendations.map { RecommendationMeta(anilistId: $0.id, title: $0.title, coverImageLarge: $0.coverImageLarge) },
                matchedAt: Date(),
                confidence: bestMatchConfidence(query: query, title: best.bestTitle)
            )

            // Best-effort awards
            do {
                let awards = try await WikidataAwardsClient.shared.awards(forTitle: meta.title)
                meta.awards = Array(awards.prefix(12))
            } catch {
                // ignore; awards just won't show
            }

            setMetadata(meta, for: series.folderURL)

        } catch {
            print("AniList ensureMetadata error:", error)
        }
    }

    // MARK: - Matching (simple + stable)

    private func pickBestMatch(query: String, candidates: [AniListMedia]) -> AniListMedia? {
        let q = normalize(query)
        guard !q.isEmpty else { return candidates.first }

        var best: (score: Double, item: AniListMedia)? = nil
        for item in candidates {
            let t = normalize(item.bestTitle)
            let s = similarityScore(q, t)
            if best == nil || s > best!.score {
                best = (s, item)
            }
        }
        return best?.item ?? candidates.first
    }

    private func bestMatchConfidence(query: String, title: String) -> Double {
        similarityScore(normalize(query), normalize(title))
    }

    private func normalize(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "vol.", with: "")
            .replacingOccurrences(of: "volume", with: "")
            .replacingOccurrences(of: "season", with: "")
            .replacingOccurrences(of: ":", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: " ")
            .split(separator: " ")
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func similarityScore(_ a: String, _ b: String) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        if a == b { return 1.0 }
        if b.contains(a) || a.contains(b) { return 0.85 }

        let at = Set(a.split(separator: " ").map(String.init))
        let bt = Set(b.split(separator: " ").map(String.init))
        if at.isEmpty || bt.isEmpty { return 0 }

        let inter = Double(at.intersection(bt).count)
        let union = Double(at.union(bt).count)
        return max(0.0, min(0.8, inter / union))
    }

    // MARK: - Persistence

    private func loadManual() {
        guard let data = UserDefaults.standard.data(forKey: manualStorageKey) else { return }
        do {
            manualBySeriesFolder = try JSONDecoder().decode([String: Int].self, from: data)
        } catch {
            manualBySeriesFolder = [:]
        }
    }

    private func saveManual() {
        do {
            let data = try JSONEncoder().encode(manualBySeriesFolder)
            UserDefaults.standard.set(data, forKey: manualStorageKey)
        } catch {
            // ignore for now
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            bySeriesFolder = try JSONDecoder().decode([String: SeriesMetadata].self, from: data)
        } catch {
            bySeriesFolder = [:]
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(bySeriesFolder)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            // ignore for now
        }
    }
}

