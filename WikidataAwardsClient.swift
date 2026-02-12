import Foundation

struct AwardItem: Codable, Hashable, Identifiable {
    let id: String          // award Q-id (or a stable string)
    let name: String        // human label
    let year: String?       // optional (often not present)
}

final class WikidataAwardsClient {
    static let shared = WikidataAwardsClient()
    private init() {}

    // 1) Find entity ID by title (Qxxxx)
    func findEntityId(title: String) async throws -> String? {
        let q = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }

        var comps = URLComponents(string: "https://www.wikidata.org/w/api.php")!
        comps.queryItems = [
            .init(name: "action", value: "wbsearchentities"),
            .init(name: "search", value: q),
            .init(name: "language", value: "en"),
            .init(name: "format", value: "json"),
            .init(name: "limit", value: "1")
        ]

        let (data, _) = try await URLSession.shared.data(from: comps.url!)

        struct Resp: Decodable {
            struct Item: Decodable { let id: String }
            let search: [Item]
        }

        let decoded = try JSONDecoder().decode(Resp.self, from: data)
        return decoded.search.first?.id
    }

    // 2) SPARQL query: awards received (P166)
    func fetchAwards(entityId: String) async throws -> [AwardItem] {
        // Some items include qualifiers for time; many don’t.
        // We’ll fetch award labels + (optional) time if present.
        let sparql = """
        SELECT ?award ?awardLabel ?time WHERE {
          wd:\(entityId) p:P166 ?statement .
          ?statement ps:P166 ?award .
          OPTIONAL { ?statement pq:P585 ?time . }
          SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
        }
        ORDER BY DESC(?time)
        """

        var comps = URLComponents(string: "https://query.wikidata.org/sparql")!
        comps.queryItems = [
            .init(name: "format", value: "json"),
            .init(name: "query", value: sparql)
        ]

        var req = URLRequest(url: comps.url!)
        req.setValue("application/sparql-results+json", forHTTPHeaderField: "Accept")
        // Wikidata likes a User-Agent; add one if you ship this publicly.
        req.setValue("MangaReaderApp/1.0 (contact: none)", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: req)

        struct SPARQL: Decodable {
            struct Results: Decodable {
                struct Binding: Decodable {
                    struct Value: Decodable { let value: String }
                    let award: Value
                    let awardLabel: Value
                    let time: Value?
                }
                let bindings: [Binding]
            }
            let results: Results
        }

        let decoded = try JSONDecoder().decode(SPARQL.self, from: data)

        // Map to AwardItem
        return decoded.results.bindings.map { b in
            let awardURL = b.award.value  // like https://www.wikidata.org/entity/Qxxxx
            let qid = awardURL.split(separator: "/").last.map(String.init) ?? awardURL

            let year: String? = {
                guard let t = b.time?.value else { return nil }
                // time format often: 2017-01-01T00:00:00Z
                return String(t.prefix(4))
            }()

            return AwardItem(id: qid, name: b.awardLabel.value, year: year)
        }
    }

    // Convenience: title -> awards
    func awards(forTitle title: String) async throws -> [AwardItem] {
        guard let qid = try await findEntityId(title: title) else { return [] }
        return try await fetchAwards(entityId: qid)
    }
}
