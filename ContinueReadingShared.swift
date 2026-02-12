import Foundation

struct ContinueReadingState: Codable, Equatable {
    var seriesId: String
    var seriesTitle: String
    var volumeTitle: String
    var currentPage: Int
    var totalPages: Int
    var updatedAt: Date

    var progress: Double {
        guard totalPages > 0 else { return 0 }
        return min(1, max(0, Double(currentPage) / Double(totalPages)))
    }
}

enum ContinueReadingStore {
    static let suiteName = "group.com.yourcompany.MangaReader"
    static let key = "continueReadingState"

    static func save(_ state: ContinueReadingState) {
        let defaults = UserDefaults(suiteName: suiteName)
        let data = try? JSONEncoder().encode(state)
        defaults?.set(data, forKey: key)
    }

    static func load() -> ContinueReadingState? {
        let defaults = UserDefaults(suiteName: suiteName)
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ContinueReadingState.self, from: data)
    }
}
