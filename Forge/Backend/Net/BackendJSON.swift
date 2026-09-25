import Foundation

/// One encoder, one decoder, one way of writing a date.
///
/// Every DTO in the backend uses these rather than making its own, because two
/// coders configured slightly differently is how a timestamp written by the
/// phone comes back an hour out and a merge starts picking the wrong winner.
enum BackendJSON {

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(BackendDate.string(from: date))
        }
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            guard let date = BackendDate.date(from: raw) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath,
                          debugDescription: "Not a timestamp: \(raw)")
                )
            }
            return date
        }
        return decoder
    }()
}

/// Timestamps, read and written the way Postgres means them.
///
/// Written one way and read four, on purpose. What goes up is always the same
/// shape; what comes back is whatever the database felt like — `timestamptz`
/// renders with microseconds when it has them and drops the fraction entirely
/// when it does not, and both spellings are the same instant. A parser that
/// only accepts the shape it emits works perfectly until the first row that was
/// written on a whole second.
enum BackendDate {

    /// Always UTC, always with milliseconds. Not the user's timezone: this is a
    /// machine ordering, and the only place a timezone belongs in Forge is
    /// where an instant is turned into a `ForgeDay`.
    static func string(from date: Date) -> String {
        fractional.string(from: date)
    }

    static func date(from raw: String) -> Date? {
        if let parsed = fractional.date(from: raw) { return parsed }
        if let parsed = whole.date(from: raw) { return parsed }
        // Postgres hands back microseconds; some OS versions of the ISO parser
        // will only take three digits of fraction. Trimming the extra ones
        // costs precision no day has ever depended on.
        if let trimmed = truncatingFraction(raw), let parsed = fractional.date(from: trimmed) {
            return parsed
        }
        return nil
    }

    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = .gmt
        return formatter
    }()

    private static let whole: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .gmt
        return formatter
    }()

    /// `...:33.123456+00:00` → `...:33.123+00:00`. Nil when there is no
    /// fraction to trim, so the caller does not re-parse a string it has
    /// already failed on.
    private static func truncatingFraction(_ raw: String) -> String? {
        guard let dot = raw.firstIndex(of: ".") else { return nil }
        let afterDot = raw.index(after: dot)
        let digits = raw[afterDot...].prefix { $0.isNumber }
        guard digits.count > 3 else { return nil }
        let head = String(raw[..<afterDot])
        let keep = String(digits.prefix(3))
        let tail = String(raw[raw.index(afterDot, offsetBy: digits.count)...])
        return head + keep + tail
    }
}
