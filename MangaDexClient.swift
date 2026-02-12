import Foundation

// MARK: - Public model your UI can use

struct MangaDexCover: Identifiable, Hashable {
    let id: String
    let mangaId: String
    let volume: String?          // often "1", "2", etc (can be nil)
    let fileName: String         // e.g. "abc123.jpg"
    let locale: String?          // language code sometimes
    let createdAt: Date?

    // Common MangaDex cover URL formats
    // 256px / 512px variants are widely used.
    var url256: URL? { URL(string: "https://uploads.mangadex.org/covers/\(mangaId)/\(fileName).256.jpg") }
    var url512: URL? { URL(string: "https://uploads.mangadex.org/covers/\(mangaId)/\(fileName).512.jpg") }
    var urlOriginal: URL? { URL(string: "https://uploads.mangadex.org/covers/\(mangaId)/\(fileName)") }
}

// MARK: - Client

final class MangaDexClient {
    static let shared = MangaDexClient()
    private init() {}

    private let base = URL(string: "https://api.mangadex.org")!

    /// 1) Search MangaDex by title -> returns best match mangaId (or nil).
    func searchMangaId(title: String, limit: Int = 5) async throws -> String? {
        var comps = URLComponents(url: base.appendingPathComponent("manga"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "order[relevance]", value: "desc")
        ]

        let url = comps.url!
        let (data, resp) = try await URLSession.shared.data(from: url)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "MangaDex", code: 0, userInfo: [NSLocalizedDescriptionKey: "Search failed"])
        }

        let decoded = try JSONDecoder().decode(MDListResponse<MDManga>.self, from: data)
        return decoded.data.first?.id
    }

    /// 2) Fetch all covers for a mangaId.
    func fetchCovers(mangaId: String, limit: Int = 100) async throws -> [MangaDexCover] {
        var comps = URLComponents(url: base.appendingPathComponent("cover"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "manga[]", value: mangaId),
            URLQueryItem(name: "order[volume]", value: "asc")
        ]

        let url = comps.url!
        let (data, resp) = try await URLSession.shared.data(from: url)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "MangaDex", code: 0, userInfo: [NSLocalizedDescriptionKey: "Cover fetch failed"])
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(MDListResponse<MDCover>.self, from: data)

        // Map to our UI model
        return decoded.data.map { cover in
            MangaDexCover(
                id: cover.id,
                mangaId: mangaId,
                volume: cover.attributes.volume,
                fileName: cover.attributes.fileName,
                locale: cover.attributes.locale,
                createdAt: cover.attributes.createdAt
            )
        }
        // Prefer volume numeric order where possible
        .sorted { a, b in
            let ai = Int(a.volume ?? "") ?? Int.max
            let bi = Int(b.volume ?? "") ?? Int.max
            if ai != bi { return ai < bi }
            return (a.createdAt ?? .distantPast) > (b.createdAt ?? .distantPast)
        }
    }
}

// MARK: - Minimal Decoding Types (covers + manga list)

private struct MDListResponse<T: Decodable>: Decodable {
    let data: [T]
}

private struct MDManga: Decodable {
    let id: String
}

private struct MDCover: Decodable {
    let id: String
    let attributes: Attributes

    struct Attributes: Decodable {
        let volume: String?
        let fileName: String
        let locale: String?
        let createdAt: Date?
    }
}
