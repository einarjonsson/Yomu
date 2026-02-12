import Foundation
import Combine

struct BookProgress: Codable {
    var lastPageIndex: Int
    var totalPages: Int
    var lastOpenedAt: Date

    // Stats
    var isCompleted: Bool
    var completedAt: Date?
    var minutesReadToday: Int
    var lastReadDay: String // "YYYY-MM-DD"
}

@MainActor
final class ReadingProgressStore: ObservableObject {
    static let shared = ReadingProgressStore()

    @Published private(set) var progressByBookKey: [String: BookProgress] = [:]

    private let storageKey = "reading_progress_v1"

    private init() {
        load()
    }

    // MARK: - Keying

    /// Current canonical key (stable across iCloud URL variations)
    func bookKey(for fileURL: URL) -> String {
        fileURL.standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }

    /// Older formats we may have used in previous app versions
    private func legacyKeys(for fileURL: URL) -> [String] {
        let standardized = fileURL.standardizedFileURL
        let resolved = standardized.resolvingSymlinksInPath()

        var keys: [String] = []

        // Older variants: absoluteString
        keys.append(standardized.absoluteString)
        keys.append(resolved.absoluteString)
        keys.append(fileURL.absoluteString)

        // Older variants: path
        keys.append(standardized.path)
        keys.append(resolved.path)
        keys.append(fileURL.path)

        // Dedup (preserve order)
        var seen = Set<String>()
        return keys.filter { seen.insert($0).inserted }
    }

    /// If progress exists under an old key, migrate it to the canonical key.
    private func migrateIfNeeded(for fileURL: URL) {
        let newKey = bookKey(for: fileURL)
        if progressByBookKey[newKey] != nil { return }

        for oldKey in legacyKeys(for: fileURL) {
            if let old = progressByBookKey[oldKey] {
                progressByBookKey[newKey] = old
                progressByBookKey.removeValue(forKey: oldKey)
                save()
                return
            }
        }
    }

    // MARK: - Date helpers

    private static func todayKey(_ date: Date = Date()) -> String {
        let cal = Calendar.current
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    // MARK: - Public API

    func progress(for fileURL: URL) -> BookProgress? {
        migrateIfNeeded(for: fileURL)
        return progressByBookKey[bookKey(for: fileURL)]
    }

    func setProgress(for fileURL: URL, lastPageIndex: Int, totalPages: Int) {
        migrateIfNeeded(for: fileURL)

        let k = bookKey(for: fileURL)
        let safeTotal = max(1, totalPages)
        let safeLast = max(0, min(lastPageIndex, safeTotal - 1))

        var existing = progressByBookKey[k] ?? BookProgress(
            lastPageIndex: 0,
            totalPages: safeTotal,
            lastOpenedAt: Date(),
            isCompleted: false,
            completedAt: nil,
            minutesReadToday: 0,
            lastReadDay: Self.todayKey()
        )

        existing.totalPages = safeTotal
        existing.lastPageIndex = safeLast
        existing.lastOpenedAt = Date()

        // Completion
        if safeLast >= safeTotal - 1 {
            if existing.isCompleted == false {
                existing.isCompleted = true
                existing.completedAt = Date()
            }
        } else {
            existing.isCompleted = false
            existing.completedAt = nil
        }

        progressByBookKey[k] = existing
        save()
    }

    func markOpened(for fileURL: URL) {
        migrateIfNeeded(for: fileURL)
        let k = bookKey(for: fileURL)

        // If no progress yet, create a minimal entry so Continue Reading can still pick it up
        if progressByBookKey[k] == nil {
            progressByBookKey[k] = BookProgress(
                lastPageIndex: 0,
                totalPages: 1,
                lastOpenedAt: Date(),
                isCompleted: false,
                completedAt: nil,
                minutesReadToday: 0,
                lastReadDay: Self.todayKey()
            )
            save()
            return
        }

        var p = progressByBookKey[k]!
        p.lastOpenedAt = Date()
        progressByBookKey[k] = p
        save()
    }

    /// Call this when a reading session ends.
    func addMinutesRead(_ minutes: Int, for fileURL: URL) {
        migrateIfNeeded(for: fileURL)
        let k = bookKey(for: fileURL)
        guard var p = progressByBookKey[k] else { return }

        let today = Self.todayKey()
        if p.lastReadDay != today {
            p.lastReadDay = today
            p.minutesReadToday = 0
        }

        p.minutesReadToday += max(0, minutes)
        p.lastOpenedAt = Date()
        progressByBookKey[k] = p
        save()
    }

    // MARK: - Stats

    func minutesReadTodayTotal() -> Int {
        let today = Self.todayKey()
        return progressByBookKey.values
            .filter { $0.lastReadDay == today }
            .map { $0.minutesReadToday }
            .reduce(0, +)
    }

    func completedBooksTotal() -> Int {
        progressByBookKey.values.filter { $0.isCompleted }.count
    }

    func booksFinishedThisYear() -> Int {
        let cal = Calendar.current
        let year = cal.component(.year, from: Date())
        return progressByBookKey.values.filter {
            guard let d = $0.completedAt else { return false }
            return cal.component(.year, from: d) == year
        }.count
    }

    /// Returns the number of consecutive days up to today where any reading activity occurred.
    func currentStreak() -> Int {
        let cal = Calendar.current
        let today = Date()
        let activityDays: Set<String> = Set(progressByBookKey.values.map { $0.lastReadDay })

        var streak = 0
        var day = today

        while true {
            let dayKey = Self.todayKey(day)
            if activityDays.contains(dayKey) {
                streak += 1
                guard let previousDay = cal.date(byAdding: .day, value: -1, to: day) else { break }
                day = previousDay
            } else {
                break
            }
        }

        return streak
    }

    /// Returns the longest streak of consecutive days with any reading activity (all-time).
    func longestStreak() -> Int {
        let cal = Calendar.current
        let activityDays = Set(progressByBookKey.values.map { $0.lastReadDay })
        let sortedDays = activityDays.sorted()

        guard !sortedDays.isEmpty else { return 0 }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)

        var longest = 1
        var currentStreak = 1

        var previousDate = dateFormatter.date(from: sortedDays[0])!

        for dayKey in sortedDays.dropFirst() {
            guard let currentDate = dateFormatter.date(from: dayKey) else { continue }
            let nextDay = cal.date(byAdding: .day, value: 1, to: previousDate)!

            if cal.isDate(currentDate, inSameDayAs: nextDay) {
                currentStreak += 1
            } else {
                longest = max(longest, currentStreak)
                currentStreak = 1
            }
            previousDate = currentDate
        }

        longest = max(longest, currentStreak)
        return longest
    }

    // MARK: - Continue / Series helpers

    func recentBookKeys(limit: Int = 20) -> [String] {
        let sorted = progressByBookKey.sorted { a, b in
            a.value.lastOpenedAt > b.value.lastOpenedAt
        }
        return Array(sorted.prefix(limit).map { $0.key })
    }

    func mostRecentlyOpenedBook(in bookURLs: [URL]) -> URL? {
        for url in bookURLs { migrateIfNeeded(for: url) }

        let sorted = bookURLs.sorted { a, b in
            let pa = progressByBookKey[bookKey(for: a)]?.lastOpenedAt ?? .distantPast
            let pb = progressByBookKey[bookKey(for: b)]?.lastOpenedAt ?? .distantPast
            return pa > pb
        }
        return sorted.first
    }

    func progressValue(for fileURL: URL) -> Double {
        guard let p = progress(for: fileURL), p.totalPages > 0 else { return 0 }
        let current = Double(p.lastPageIndex + 1)
        let total = Double(max(1, p.totalPages))
        return min(1.0, max(0.0, current / total))
    }

    func startedCount(in bookURLs: [URL]) -> Int {
        bookURLs.forEach { migrateIfNeeded(for: $0) }
        return bookURLs.filter { progressByBookKey[bookKey(for: $0)] != nil }.count
    }

    func seriesPercent(for bookURLs: [URL]) -> Double {
        bookURLs.forEach { migrateIfNeeded(for: $0) }

        var readPages = 0
        var totalPages = 0

        for url in bookURLs {
            let k = bookKey(for: url)
            guard let p = progressByBookKey[k] else { continue }
            let total = max(1, p.totalPages)
            let read = min(max(0, p.lastPageIndex + 1), total)
            readPages += read
            totalPages += total
        }

        guard totalPages > 0 else { return 0.0 }
        return Double(readPages) / Double(totalPages)
    }

    func seriesPageCounts(for bookURLs: [URL]) -> (read: Int, total: Int) {
        bookURLs.forEach { migrateIfNeeded(for: $0) }

        var readPages = 0
        var totalPages = 0

        for url in bookURLs {
            let k = bookKey(for: url)
            guard let p = progressByBookKey[k] else { continue }
            let total = max(1, p.totalPages)
            let read = min(max(0, p.lastPageIndex + 1), total)
            readPages += read
            totalPages += total
        }

        return (readPages, totalPages)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            progressByBookKey = try JSONDecoder().decode([String: BookProgress].self, from: data)
        } catch {
            progressByBookKey = [:]
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(progressByBookKey)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            // ignore for now
        }
    }
}
