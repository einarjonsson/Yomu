import Foundation
import UIKit

// MARK: - Cached payload

struct SeriesCache: Codable {
    // Theme
    var themeColorHex: String?

    // Wikidata
    var wikidataEntityId: String?
    var publisher: String?
    var inceptionYear: String?
    var awards: [AwardItem]?

    // MangaDex: volume -> URL
    var mdCoverByVolume: [Int: URL]?

    // Housekeeping
    var updatedAt: Date = Date()
}

// MARK: - Store

@MainActor
final class SeriesCacheStore {
    static let shared = SeriesCacheStore()

    private init() {}

    private let rootKey = "series_cache_v1"

    private func seriesKey(for folderURL: URL) -> String {
        folderURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }

    func load(for seriesFolderURL: URL) -> SeriesCache? {
        let all = loadAll()
        return all[seriesKey(for: seriesFolderURL)]
    }

    func upsert(for seriesFolderURL: URL, mutate: (inout SeriesCache) -> Void) {
        var all = loadAll()
        let key = seriesKey(for: seriesFolderURL)
        var existing = all[key] ?? SeriesCache()
        mutate(&existing)
        existing.updatedAt = Date()
        all[key] = existing
        saveAll(all)
    }

    // MARK: - Persistence

    private func loadAll() -> [String: SeriesCache] {
        guard let data = UserDefaults.standard.data(forKey: rootKey) else { return [:] }
        do {
            return try JSONDecoder().decode([String: SeriesCache].self, from: data)
        } catch {
            return [:]
        }
    }

    private func saveAll(_ dict: [String: SeriesCache]) {
        do {
            let data = try JSONEncoder().encode(dict)
            UserDefaults.standard.set(data, forKey: rootKey)
        } catch {
            // ignore for now
        }
    }
}
