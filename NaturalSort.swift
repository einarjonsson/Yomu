import Foundation

enum NaturalSort {
    /// Sorts strings like: 1,2,10 instead of 1,10,2
    static func less(_ a: String, _ b: String) -> Bool {
        let aParts = tokenize(a)
        let bParts = tokenize(b)

        let n = min(aParts.count, bParts.count)
        for i in 0..<n {
            switch (aParts[i], bParts[i]) {
            case let (.number(x), .number(y)):
                if x != y { return x < y }
            case let (.text(x), .text(y)):
                let cmp = x.localizedCaseInsensitiveCompare(y)
                if cmp != .orderedSame { return cmp == .orderedAscending }
            case (.number, .text):
                return true
            case (.text, .number):
                return false
            }
        }

        // If all equal so far, shorter one first
        return aParts.count < bParts.count
    }

    private enum Token {
        case number(Int)
        case text(String)
    }

    private static func tokenize(_ s: String) -> [Token] {
        var out: [Token] = []
        var buf = ""
        var isNum: Bool? = nil

        func flush() {
            guard !buf.isEmpty else { return }
            if isNum == true, let v = Int(buf) {
                out.append(.number(v))
            } else {
                out.append(.text(buf))
            }
            buf = ""
        }

        for ch in s {
            let digit = ch.isNumber
            if isNum == nil {
                isNum = digit
                buf.append(ch)
                continue
            }

            if digit == isNum {
                buf.append(ch)
            } else {
                flush()
                isNum = digit
                buf.append(ch)
            }
        }

        flush()
        return out
    }
}
