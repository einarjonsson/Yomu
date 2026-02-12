import Foundation

// MARK: - Stable Series Key

/// A stable key derived from the series folder URL (good across iCloud url variations).
/// We store this everywhere as the identifier for a series.
public typealias SeriesKey = String

public extension URL {
    /// Normalized key for series folder URLs
    var seriesKey: SeriesKey {
        standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }
}

// MARK: - User Models

/// Per-series user data (favorites, notes, tags, rating, custom lists membership)
public struct SeriesUserData: Codable, Hashable {
    public var isFavorite: Bool
    public var note: String
    public var rating: Int?              // 1–10 (nil = not rated)
    public var tags: [String]            // simple tags like "Peak", "Comedy", etc.
    public var lists: Set<String>        // list IDs (Favorites, WantToRead, etc.)
    public var updatedAt: Date

    public init(
        isFavorite: Bool = false,
        note: String = "",
        rating: Int? = nil,
        tags: [String] = [],
        lists: Set<String> = [],
        updatedAt: Date = Date()
    ) {
        self.isFavorite = isFavorite
        self.note = note
        self.rating = rating
        self.tags = tags
        self.lists = lists
        self.updatedAt = updatedAt
    }
}

/// A custom list the user can create (plus system lists).
public struct UserList: Codable, Hashable, Identifiable {
    public var id: String               // stable id
    public var name: String
    public var createdAt: Date
    public var isSystem: Bool

    public init(id: String, name: String, createdAt: Date = Date(), isSystem: Bool) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.isSystem = isSystem
    }
}

// MARK: - System list IDs

public enum SystemListID {
    public static let favorites = "system.favorites"
    public static let wantToRead = "system.wantToRead"
}
