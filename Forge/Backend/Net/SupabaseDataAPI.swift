import Foundation

/// PostgREST, reduced to the two verbs Forge actually needs.
///
/// Read everything that has changed since last time, and write rows that
/// replace themselves rather than piling up. There is no delete: Forge
/// tombstones instead, because a row that vanishes from the server is
/// indistinguishable on the next device from a row that has not arrived yet.
struct SupabaseDataAPI: Sendable {

    let client: HTTPClient

    private func url(for table: Table) -> URL {
        client.config.restURL.appendingPathComponent(table.rawValue)
    }

    /// Every table, and the columns that make a row unique in it. The conflict
    /// target is not optional anywhere: an upsert without one is an insert, and
    /// an insert that runs twice is the duplicate this whole design is built to
    /// avoid.
    enum Table: String, Sendable, CaseIterable {
        case profiles
        case devices
        case activities
        case rituals
        /// The deployed table is still called `mornings`, and the raw value
        /// pins it there. A table name is not a label — it is in production, it
        /// has everybody's history in it, and renaming it would be a migration
        /// against live data to change a word no user will ever see.
        case days = "mornings"
        case blades
        case premiumStatus = "premium_status"
        case identities
        case chapters
        case reviews

        var conflictTarget: String {
            switch self {
            case .profiles: "id"
            case .devices: "id"
            case .activities: "user_id,id"
            case .rituals: "user_id,id"
            case .days: "user_id,day"
            case .blades: "user_id"
            case .premiumStatus: "user_id"
            case .identities: "user_id,id"
            case .chapters: "user_id,id"
            // A review is identified by the week it is about — there cannot be
            // two for one week, which is a property of the thing rather than a
            // constraint on the table. See `WeeklyReview.weekStart`.
            case .reviews: "user_id,week_start"
            }
        }
    }

    // MARK: - Reading

    /// How many rows come back at once.
    ///
    /// A year of days is 365 rows of a few hundred bytes, so this is one
    /// request for almost everybody and the paging below exists for the person
    /// who has been doing this for a decade.
    static let pageSize = 500

    /// Everything the server has seen since `since`, oldest arrival first.
    ///
    /// Paged by offset within one fixed cursor rather than by walking the
    /// cursor forward through the pages. Walking it looks tidier and is wrong:
    /// rows written in one transaction share a `synced_at` to the microsecond,
    /// so a page boundary landing in the middle of such a group and then asking
    /// for "greater than" that value silently skips the rest of it.
    func pull<T: Decodable>(
        _ type: T.Type,
        from table: Table,
        since: Date?,
        offset: Int = 0,
        accessToken: String
    ) async throws -> [T] {
        var query = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order", value: "synced_at.asc"),
            URLQueryItem(name: "limit", value: String(Self.pageSize)),
        ]
        if offset > 0 {
            query.append(URLQueryItem(name: "offset", value: String(offset)))
        }
        if let since {
            query.append(
                URLQueryItem(name: "synced_at", value: "gt.\(BackendDate.string(from: since))")
            )
        }
        return try await client.send(
            [T].self, .get, url: url(for: table), query: query, accessToken: accessToken
        )
    }

    /// The same, followed all the way to the end.
    func pullAll<T: Decodable>(
        _ type: T.Type,
        from table: Table,
        since: Date?,
        accessToken: String
    ) async throws -> [T] {
        var all: [T] = []
        var offset = 0
        while true {
            let page = try await pull(
                type, from: table, since: since, offset: offset, accessToken: accessToken
            )
            all.append(contentsOf: page)
            guard page.count == Self.pageSize else { return all }
            offset += page.count
        }
    }

    // MARK: - Deleting an account

    /// Ends the account itself, and everything hanging off it.
    ///
    /// The one call in this file that is not a table operation, because there
    /// is no table operation that could do it: `auth.users` is not reachable by
    /// `authenticated` and must not be. `0003` puts the delete behind a
    /// `security definer` function that takes no arguments and works only on
    /// `auth.uid()`, so this sends nothing but a token — there is no id here
    /// for a client to get wrong or for a server to have to be sceptical about.
    ///
    /// The cascade does the rest. Nothing here lists the seven tables.
    func deleteAccount(accessToken: String) async throws {
        try await client.send(
            .post,
            url: client.config.restURL.appendingPathComponent("rpc/delete_account"),
            body: Data("{}".utf8),
            accessToken: accessToken
        )
    }

    // MARK: - Writing

    /// Insert or replace, in batches, and never partially.
    ///
    /// `resolution=merge-duplicates` is what makes a re-run of a failed upload
    /// harmless — the same rows land on the same primary keys and the second
    /// attempt changes nothing. That property is the whole of "migration
    /// happens once": it does not have to be prevented from happening twice,
    /// because happening twice has no effect.
    ///
    /// `return=minimal` because the answer is a copy of what we just sent, and
    /// downloading a year of days to confirm we uploaded a year of days
    /// is a way to spend somebody's data plan.
    func upsert(
        _ rows: [some Encodable],
        into table: Table,
        accessToken: String
    ) async throws {
        guard !rows.isEmpty else { return }

        for batch in rows.chunked(into: Self.pageSize) {
            let body: Data
            do {
                body = try BackendJSON.encoder.encode(batch)
            } catch {
                throw BackendError.decoding
            }
            try await client.send(
                .post,
                url: url(for: table),
                query: [URLQueryItem(name: "on_conflict", value: table.conflictTarget)],
                body: body,
                headers: ["Prefer": "resolution=merge-duplicates,return=minimal"],
                accessToken: accessToken
            )
        }
    }
}

extension Array {
    /// Fixed-size slices. Postgres will take a very large insert and the
    /// network will not, and a day lost to a request that was too big to
    /// send is a poor way to find that out.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0, count > size else { return isEmpty ? [] : [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
