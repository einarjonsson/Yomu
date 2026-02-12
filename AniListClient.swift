import Foundation

// MARK: - AniList Models (what SeriesMetadataStore expects)

/// A staff member credited on an AniList media entry.
///
/// - Note: `role` is optional because AniList sometimes returns `null` for the edge role.
struct AniListStaff: Hashable {
    /// Full name of the staff member (e.g., "Eiichiro Oda").
    let name: String

    /// Staff role on the work (e.g., "Story & Art", "Assistant", "Translator").
    let role: String?
}

/// A character appearing in an AniList media entry.
struct AniListCharacter: Hashable {
    /// Character name (typically user-preferred / localized where available).
    let name: String

    /// URL to a large character image, if provided by AniList.
    let imageLarge: String?
}

/// A recommendation entry related to an AniList media entry.
struct AniListRecommendation: Hashable {
    /// AniList media ID for the recommended item.
    let id: Int

    /// User-preferred title for the recommended item.
    let title: String

    /// URL to a large cover image for the recommended item.
    let coverImageLarge: String?
}

/// A simplified manga model returned by AniList, shaped to what your app needs.
///
/// This intentionally flattens AniList's GraphQL response into a convenient Swift model.
struct AniListMedia: Hashable {
    /// AniList media ID.
    let id: Int

    // Titles
    let titleUserPreferred: String?
    let titleEnglish: String?
    let titleRomaji: String?
    let titleNative: String?

    // Core
    /// Plain text description (AniList can return HTML; we request non-HTML).
    let description: String?
    /// Average community score (0–100). Optional if not available.
    let averageScore: Int?
    /// URL to the cover image (large).
    let coverImageLarge: String?
    /// URL to the banner image (wide hero-style image).
    let bannerImage: String?

    // Status (e.g., FINISHED, RELEASING, CANCELLED, HIATUS)
    let status: String?

    // Extra
    let staff: [AniListStaff]
    let characters: [AniListCharacter]
    let recommendations: [AniListRecommendation]

    /// Best available title in a reasonable preference order.
    ///
    /// Preference order:
    /// 1. User preferred (AniList decides based on user settings / locale)
    /// 2. English
    /// 3. Romaji
    /// 4. Native
    /// 5. Fallback "Untitled"
    var bestTitle: String {
        titleUserPreferred ?? titleEnglish ?? titleRomaji ?? titleNative ?? "Untitled"
    }
}

// MARK: - AniList Client

/// Lightweight GraphQL client for AniList focused on MANGA.
///
/// Responsibilities:
/// - Perform search queries by title text
/// - Fetch a specific manga by AniList ID
/// - Decode only the fields needed by the app
///
/// - Important: This client does not currently handle AniList GraphQL errors in a 200 response.
///   If you want to be extra robust, you can decode the `errors` field from GraphQL responses as well.
final class AniListClient {
    /// Shared singleton instance used across the app.
    static let shared = AniListClient()
    private init() {}

    /// AniList GraphQL endpoint.
    private let endpoint = URL(string: "https://graphql.anilist.co")!

    /// URLSession configured with reasonable defaults for mobile networking.
    ///
    /// - Note:
    ///   `waitsForConnectivity = true` means the request may wait for network connectivity instead of failing immediately.
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    // MARK: Search (Page)

    /// Searches AniList for manga matching a text query.
    ///
    /// Uses AniList's `Page` wrapper with `media(search:type:)`.
    ///
    /// - Parameters:
    ///   - query: Search string (e.g. "One Piece").
    ///   - limit: Maximum number of results to return (default 6).
    /// - Returns: Array of `AniListMedia` items mapped from the GraphQL response.
    /// - Throws: Networking or decoding errors, or an HTTP error for non-2xx responses.
    func searchManga(query: String, limit: Int = 6) async throws -> [AniListMedia] {
        // GraphQL query requesting a small set of fields + limited staff/characters/recs for UI.
        let gql = """
        query ($search: String, $perPage: Int) {
          Page(perPage: $perPage) {
            media(search: $search, type: MANGA) {
              id
              title { userPreferred romaji english native }
              description(asHtml: false)
              averageScore
              coverImage { large }
              bannerImage
              status

              staff(perPage: 6) {
                edges { role node { name { full } } }
              }

              characters(perPage: 12) {
                edges { node { name { userPreferred } image { large } } }
              }

              recommendations(perPage: 10) {
                nodes {
                  mediaRecommendation {
                    id
                    title { userPreferred }
                    coverImage { large }
                  }
                }
              }
            }
          }
        }
        """

        // JSON body for AniList GraphQL
        let body: [String: Any] = [
            "query": gql,
            "variables": [
                "search": query,
                "perPage": limit
            ]
        ]

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await session.data(for: req)
        try validate(resp: resp, data: data)

        // Local response DTOs matching the GraphQL response shape.
        // These are intentionally nested to avoid polluting the global namespace.
        struct Response: Decodable {
            struct DataObj: Decodable {
                struct PageObj: Decodable {
                    struct MediaObj: Decodable {
                        let id: Int

                        struct Title: Decodable {
                            let userPreferred: String?
                            let romaji: String?
                            let english: String?
                            let native: String?
                        }
                        let title: Title

                        let description: String?
                        let averageScore: Int?

                        struct Cover: Decodable { let large: String? }
                        let coverImage: Cover

                        let bannerImage: String?
                        let status: String?

                        struct Staff: Decodable {
                            struct Edge: Decodable {
                                let role: String?
                                struct Node: Decodable {
                                    struct Name: Decodable { let full: String }
                                    let name: Name
                                }
                                let node: Node
                            }
                            let edges: [Edge]
                        }
                        let staff: Staff?

                        struct Characters: Decodable {
                            struct Edge: Decodable {
                                struct Node: Decodable {
                                    struct Name: Decodable { let userPreferred: String? }
                                    struct Image: Decodable { let large: String? }
                                    let name: Name
                                    let image: Image?
                                }
                                let node: Node
                            }
                            let edges: [Edge]
                        }
                        let characters: Characters?

                        struct Recommendations: Decodable {
                            struct Node: Decodable {
                                struct MediaRec: Decodable {
                                    let id: Int
                                    struct Title: Decodable { let userPreferred: String? }
                                    let title: Title
                                    struct Cover: Decodable { let large: String? }
                                    let coverImage: Cover
                                }
                                let mediaRecommendation: MediaRec
                            }
                            let nodes: [Node]
                        }
                        let recommendations: Recommendations?
                    }

                    let media: [MediaObj]
                }
                let Page: PageObj
            }
            let data: DataObj
        }

        // Decode off the main thread (URLSession already doesn't guarantee main, but this is explicit).
        let decoded: Response = try await Task.detached(priority: .userInitiated) {
            try JSONDecoder().decode(Response.self, from: data)
        }.value

        // Map DTO -> app model
        return decoded.data.Page.media.map { m in
            let staff = (m.staff?.edges ?? []).map {
                AniListStaff(name: $0.node.name.full, role: $0.role)
            }
            let chars = (m.characters?.edges ?? []).map {
                AniListCharacter(
                    name: $0.node.name.userPreferred ?? "Unknown",
                    imageLarge: $0.node.image?.large
                )
            }
            let recs = (m.recommendations?.nodes ?? []).map {
                AniListRecommendation(
                    id: $0.mediaRecommendation.id,
                    title: $0.mediaRecommendation.title.userPreferred ?? "Untitled",
                    coverImageLarge: $0.mediaRecommendation.coverImage.large
                )
            }

            return AniListMedia(
                id: m.id,
                titleUserPreferred: m.title.userPreferred,
                titleEnglish: m.title.english,
                titleRomaji: m.title.romaji,
                titleNative: m.title.native,
                description: m.description,
                averageScore: m.averageScore,
                coverImageLarge: m.coverImage.large,
                bannerImage: m.bannerImage,
                status: m.status,
                staff: staff,
                characters: chars,
                recommendations: recs
            )
        }
    }

    // MARK: Fetch by ID (for manual override)

    /// Fetches a single manga by AniList ID.
    ///
    /// Useful when you want a manual override path (e.g., user selects the right entry from search,
    /// then you store the ID and fetch the canonical data later).
    ///
    /// - Parameter id: AniList media ID.
    /// - Returns: `AniListMedia` if found, otherwise `nil`.
    /// - Throws: Networking/decoding errors, or HTTP error for non-2xx responses.
    func fetchManga(id: Int) async throws -> AniListMedia? {
        let gql = """
        query ($id: Int) {
          Media(id: $id, type: MANGA) {
            id
            title { userPreferred romaji english native }
            description(asHtml: false)
            averageScore
            coverImage { large }
            bannerImage
            status

            staff(perPage: 6) {
              edges { role node { name { full } } }
            }

            characters(perPage: 12) {
              edges { node { name { userPreferred } image { large } } }
            }

            recommendations(perPage: 10) {
              nodes {
                mediaRecommendation {
                  id
                  title { userPreferred }
                  coverImage { large }
                }
              }
            }
          }
        }
        """

        let body: [String: Any] = [
            "query": gql,
            "variables": [ "id": id ]
        ]

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await session.data(for: req)
        try validate(resp: resp, data: data)

        struct Response: Decodable {
            struct DataObj: Decodable {
                struct MediaObj: Decodable {
                    let id: Int
                    struct Title: Decodable {
                        let userPreferred: String?
                        let romaji: String?
                        let english: String?
                        let native: String?
                    }
                    let title: Title
                    let description: String?
                    let averageScore: Int?
                    struct Cover: Decodable { let large: String? }
                    let coverImage: Cover
                    let bannerImage: String?
                    let status: String?

                    struct Staff: Decodable {
                        struct Edge: Decodable {
                            let role: String?
                            struct Node: Decodable {
                                struct Name: Decodable { let full: String }
                                let name: Name
                            }
                            let node: Node
                        }
                        let edges: [Edge]
                    }
                    let staff: Staff?

                    struct Characters: Decodable {
                        struct Edge: Decodable {
                            struct Node: Decodable {
                                struct Name: Decodable { let userPreferred: String? }
                                struct Image: Decodable { let large: String? }
                                let name: Name
                                let image: Image?
                            }
                            let node: Node
                        }
                        let edges: [Edge]
                    }
                    let characters: Characters?

                    struct Recommendations: Decodable {
                        struct Node: Decodable {
                            struct MediaRec: Decodable {
                                let id: Int
                                struct Title: Decodable { let userPreferred: String? }
                                let title: Title
                                struct Cover: Decodable { let large: String? }
                                let coverImage: Cover
                            }
                            let mediaRecommendation: MediaRec
                        }
                        let nodes: [Node]
                    }
                    let recommendations: Recommendations?
                }

                let Media: MediaObj?
            }
            let data: DataObj
        }

        let decoded: Response = try await Task.detached(priority: .userInitiated) {
            try JSONDecoder().decode(Response.self, from: data)
        }.value

        guard let m = decoded.data.Media else { return nil }

        let staff = (m.staff?.edges ?? []).map { AniListStaff(name: $0.node.name.full, role: $0.role) }
        let chars = (m.characters?.edges ?? []).map { AniListCharacter(name: $0.node.name.userPreferred ?? "Unknown", imageLarge: $0.node.image?.large) }
        let recs = (m.recommendations?.nodes ?? []).map {
            AniListRecommendation(
                id: $0.mediaRecommendation.id,
                title: $0.mediaRecommendation.title.userPreferred ?? "Untitled",
                coverImageLarge: $0.mediaRecommendation.coverImage.large
            )
        }

        return AniListMedia(
            id: m.id,
            titleUserPreferred: m.title.userPreferred,
            titleEnglish: m.title.english,
            titleRomaji: m.title.romaji,
            titleNative: m.title.native,
            description: m.description,
            averageScore: m.averageScore,
            coverImageLarge: m.coverImage.large,
            bannerImage: m.bannerImage,
            status: m.status,
            staff: staff,
            characters: chars,
            recommendations: recs
        )
    }

    // MARK: Helpers

    /// Validates that the server responded with a successful HTTP status code.
    ///
    /// - Throws: An `NSError` containing a short snippet of the response body for debugging.
    private func validate(resp: URLResponse, data: Data) throws {
        guard let http = resp as? HTTPURLResponse else {
            throw NSError(
                domain: "AniList",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "No HTTP response"]
            )
        }

        if !(200..<300).contains(http.statusCode) {
            let bodyText = String(data: data, encoding: .utf8) ?? "<no body>"
            let snippet = bodyText.prefix(250)
            throw NSError(
                domain: "AniList",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "AniList HTTP \(http.statusCode): \(snippet)"]
            )
        }
    }
}
