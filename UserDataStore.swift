import Foundation
import Combine

@MainActor
final class UserDataStore: ObservableObject {
    static let shared = UserDataStore()

    // MARK: - Published state

    /// seriesKey -> user data
    @Published private(set) var bySeries: [SeriesKey: SeriesUserData] = [:]

    /// listId -> list
    @Published private(set) var lists: [String: UserList] = [:]

    // MARK: - Persistence keys

    private let bySeriesKey = "user_bySeries_v1"
    private let listsKey = "user_lists_v1"

    private init() {
        load()
        ensureSystemLists()
    }

    // MARK: - System lists

    private func ensureSystemLists() {
        var changed = false

        if lists[SystemListID.favorites] == nil {
            lists[SystemListID.favorites] = UserList(
                id: SystemListID.favorites,
                name: "Favorites",
                isSystem: true
            )
            changed = true
        }

        if lists[SystemListID.wantToRead] == nil {
            lists[SystemListID.wantToRead] = UserList(
                id: SystemListID.wantToRead,
                name: "Want to Read",
                isSystem: true
            )
            changed = true
        }

        if changed { saveLists() }
    }

    // MARK: - Accessors

    func data(for seriesFolderURL: URL) -> SeriesUserData {
        let key = seriesFolderURL.seriesKey
        return bySeries[key] ?? SeriesUserData()
    }

    func isFavorite(_ seriesFolderURL: URL) -> Bool {
        data(for: seriesFolderURL).isFavorite
    }

    func note(for seriesFolderURL: URL) -> String {
        data(for: seriesFolderURL).note
    }

    func rating(for seriesFolderURL: URL) -> Int? {
        data(for: seriesFolderURL).rating
    }

    func tags(for seriesFolderURL: URL) -> [String] {
        data(for: seriesFolderURL).tags
    }

    func listsForSeries(_ seriesFolderURL: URL) -> [UserList] {
        let d = data(for: seriesFolderURL)
        return d.lists.compactMap { lists[$0] }.sorted { $0.name < $1.name }
    }

    // MARK: - Mutations

    func toggleFavorite(for seriesFolderURL: URL) {
        let key = seriesFolderURL.seriesKey
        var d = bySeries[key] ?? SeriesUserData()
        d.isFavorite.toggle()
        d.updatedAt = Date()

        // keep favorites list in sync
        if d.isFavorite {
            d.lists.insert(SystemListID.favorites)
        } else {
            d.lists.remove(SystemListID.favorites)
        }

        bySeries[key] = d
        saveBySeries()
    }

    func setNote(_ text: String, for seriesFolderURL: URL) {
        let key = seriesFolderURL.seriesKey
        var d = bySeries[key] ?? SeriesUserData()
        d.note = text
        d.updatedAt = Date()
        bySeries[key] = d
        saveBySeries()
    }

    func setRating(_ rating: Int?, for seriesFolderURL: URL) {
        let key = seriesFolderURL.seriesKey
        var d = bySeries[key] ?? SeriesUserData()
        if let r = rating {
            d.rating = min(10, max(1, r))
        } else {
            d.rating = nil
        }
        d.updatedAt = Date()
        bySeries[key] = d
        saveBySeries()
    }

    func addTag(_ tag: String, for seriesFolderURL: URL) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let key = seriesFolderURL.seriesKey
        var d = bySeries[key] ?? SeriesUserData()

        if !d.tags.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            d.tags.append(trimmed)
            d.tags.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            d.updatedAt = Date()
            bySeries[key] = d
            saveBySeries()
        }
    }

    func removeTag(_ tag: String, for seriesFolderURL: URL) {
        let key = seriesFolderURL.seriesKey
        var d = bySeries[key] ?? SeriesUserData()
        d.tags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
        d.updatedAt = Date()
        bySeries[key] = d
        saveBySeries()
    }

    func setSeries(_ seriesFolderURL: URL, inList listId: String, enabled: Bool) {
        guard lists[listId] != nil else { return }

        let key = seriesFolderURL.seriesKey
        var d = bySeries[key] ?? SeriesUserData()

        if enabled {
            d.lists.insert(listId)
            if listId == SystemListID.favorites { d.isFavorite = true }
        } else {
            d.lists.remove(listId)
            if listId == SystemListID.favorites { d.isFavorite = false }
        }

        d.updatedAt = Date()
        bySeries[key] = d
        saveBySeries()
    }

    // MARK: - Lists management

    func createList(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // basic unique id
        let id = "list.\(UUID().uuidString.lowercased())"
        lists[id] = UserList(id: id, name: trimmed, isSystem: false)
        saveLists()
    }

    func renameList(id: String, newName: String) {
        guard var l = lists[id], !l.isSystem else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        l.name = trimmed
        lists[id] = l
        saveLists()
    }

    func deleteList(id: String) {
        guard let l = lists[id], !l.isSystem else { return }

        // remove membership from all series
        for (k, var d) in bySeries {
            if d.lists.contains(id) {
                d.lists.remove(id)
                d.updatedAt = Date()
                bySeries[k] = d
            }
        }

        lists.removeValue(forKey: id)
        saveLists()
        saveBySeries()
    }

    // MARK: - Queries for UI

    func favoriteSeriesKeys() -> [SeriesKey] {
        bySeries
            .filter { $0.value.isFavorite }
            .map { $0.key }
            .sorted()
    }

    func seriesKeys(inList id: String) -> [SeriesKey] {
        bySeries
            .filter { $0.value.lists.contains(id) }
            .map { $0.key }
            .sorted()
    }

    // MARK: - Persistence

    private func load() {
        // bySeries
        if let data = UserDefaults.standard.data(forKey: bySeriesKey) {
            do {
                bySeries = try JSONDecoder().decode([SeriesKey: SeriesUserData].self, from: data)
            } catch {
                bySeries = [:]
            }
        }

        // lists
        if let data = UserDefaults.standard.data(forKey: listsKey) {
            do {
                lists = try JSONDecoder().decode([String: UserList].self, from: data)
            } catch {
                lists = [:]
            }
        }
    }

    private func saveBySeries() {
        do {
            let data = try JSONEncoder().encode(bySeries)
            UserDefaults.standard.set(data, forKey: bySeriesKey)
        } catch {
            // ignore for now
        }
    }

    private func saveLists() {
        do {
            let data = try JSONEncoder().encode(lists)
            UserDefaults.standard.set(data, forKey: listsKey)
        } catch {
            // ignore for now
        }
    }
}
