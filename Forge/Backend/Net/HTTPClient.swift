import Foundation

/// The one place a request actually leaves the phone.
///
/// A protocol rather than `URLSession` directly, so every layer above it — the
/// auth flow, the sync engine, the merge — can be exercised against a scripted
/// backend that never touches a socket. Nothing above this file knows what a
/// `URLSession` is.
protocol BackendTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Every host Forge's own code may open a connection to. **One.**
///
/// TelemetryDeck's ingest host, for anonymous usage (`ForgeTelemetry`). The SDK
/// opens that connection itself; this list is what the tests hold it to, and
/// what `URLSessionTransport` refuses anything outside of. Supabase is not on
/// it: 1.0 has no account (§2n), so putting sync back means adding its host
/// here and changing `NoNetworkTests` and `BackendRegressionTests` in the same
/// commit — deliberately, not by pasting a URL into `Info.plist`.
///
/// **Prepared for AI (§2r):** the configured Supabase project's host joins the
/// list only when `RemoteForgeAI.isModelEnabled` is true *and* a project is in
/// `Info.plist`. Both are false in this build, so the list is still exactly
/// TelemetryDeck's host — `NoNetworkTests` and `BackendRegressionTests` hold
/// that — and the activation PR does not have to touch this file.
enum ForgeNetwork {
    static var allowedHosts: Set<String> {
        var hosts: Set<String> = [ForgeTelemetry.host]
        // The bundle is not even read while the switch is off.
        if RemoteForgeAI.isModelEnabled,
           let ai = aiHost(enabled: true, config: SupabaseConfig.fromBundle()) {
            hosts.insert(ai)
        }
        return hosts
    }

    /// The Forge backend's host, when — and only when — the model is switched
    /// on and a project is configured. Pure, so the tests can hold both halves.
    static func aiHost(enabled: Bool, config: SupabaseConfig?) -> String? {
        guard enabled, let host = config?.url.host?.lowercased(), !host.isEmpty else { return nil }
        return host
    }

    /// HTTPS, and a host on the list exactly. A suffix match would let
    /// `nom.telemetrydeck.com.example.net` through.
    static func permits(_ url: URL?) -> Bool {
        guard let url, url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else { return false }
        return allowedHosts.contains(host)
    }
}

struct URLSessionTransport: BackendTransport {
    let session: URLSession

    /// A session handed in whole — the tests' way of watching what would have
    /// gone out, with a `URLProtocol` standing where the network would be.
    init(session: URLSession) {
        self.session = session
    }

    /// Short by web standards and deliberately so. Everything Forge sends can
    /// wait until the next foreground, and a request still hanging on after
    /// half a minute is a request that has already failed to be useful.
    init(timeout: TimeInterval = 20) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 3
        // The system's own reachability wait, rather than one of ours. On a
        // phone in a tunnel this is the difference between a queued request and
        // a failure that has to be rediscovered by polling.
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        // Refused before a socket is opened. "Nothing was attempted" is
        // exactly what happened.
        guard ForgeNetwork.permits(request.url) else { throw BackendError.notConfigured }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw BackendError.decoding
            }
            return (data, http)
        } catch let error as BackendError {
            throw error
        } catch let error as URLError {
            throw HTTPClient.classify(error)
        } catch is CancellationError {
            throw BackendError.cancelled
        }
    }
}

/// Builds requests, reads responses, and turns both into something the rest of
/// the app can reason about.
///
/// Knows about HTTP and about Supabase's two conventions — the `apikey` header
/// and the bearer token — and about nothing else. It has never heard of a
/// day.
struct HTTPClient: Sendable {

    let config: SupabaseConfig
    let transport: BackendTransport

    init(config: SupabaseConfig, transport: BackendTransport = URLSessionTransport()) {
        self.config = config
        self.transport = transport
    }

    enum Method: String, Sendable {
        case get = "GET"
        case post = "POST"
        case patch = "PATCH"
        case delete = "DELETE"
    }

    // MARK: - Sending

    /// The whole request surface, in one function.
    ///
    /// `accessToken` is passed in rather than read from somewhere, so this
    /// object holds no session and cannot be the reason a stale token is used.
    /// Whoever calls it has just decided which identity the call is being made
    /// under, which is where that decision belongs.
    @discardableResult
    func send(
        _ method: Method,
        url: URL,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        headers: [String: String] = [:],
        accessToken: String? = nil
    ) async throws -> Data {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query
            // `+` is legal in a query component, so `URLComponents` leaves it
            // alone — and PostgREST then decodes it as a space, the way form
            // encoding says to. A timestamp filter is the one place that
            // matters: `synced_at=gt.…+00:00` arrives as `… 00:00` and comes
            // back 400 "invalid input syntax for timestamp with time zone".
            //
            // Forge writes its timestamps in UTC as `…Z`, so this cannot bite
            // today — but a 400 is classified as our bug rather than a
            // condition to wait out, so if it ever did, the incremental pull
            // would fail permanently and silently on every device that had
            // synced once. Two lines to make the whole class of it impossible.
            if let encoded = components?.percentEncodedQuery {
                components?.percentEncodedQuery =
                    encoded.replacingOccurrences(of: "+", with: "%2B")
            }
        }
        guard let resolved = components?.url else { throw BackendError.decoding }

        var request = URLRequest(url: resolved)
        request.httpMethod = method.rawValue
        request.httpBody = body
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        // Falls back to the anon key rather than omitting the header. GoTrue
        // wants a bearer on endpoints that have no user yet, and sending the
        // project key is what it expects there.
        request.setValue("Bearer \(accessToken ?? config.anonKey)",
                         forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw Self.failure(status: response.statusCode, data: data, response: response)
        }
        return data
    }

    /// Send, and decode. A 204 or an empty body decodes to nothing, which is a
    /// real answer for an upsert rather than an error.
    func send<T: Decodable>(
        _ type: T.Type,
        _ method: Method,
        url: URL,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        headers: [String: String] = [:],
        accessToken: String? = nil
    ) async throws -> T {
        let data = try await send(
            method, url: url, query: query, body: body,
            headers: headers, accessToken: accessToken
        )
        do {
            return try BackendJSON.decoder.decode(T.self, from: data)
        } catch {
            throw BackendError.decoding
        }
    }

    // MARK: - Reading a failure

    /// What the status code means to Forge.
    ///
    /// The body is read for a message but never for a decision: a backend that
    /// says "everything is fine" in a 500 is still a 500, and the code is the
    /// only part of an error response that is guaranteed to be honest.
    static func failure(status: Int, data: Data, response: HTTPURLResponse) -> BackendError {
        switch status {
        case 401:
            return .unauthorized
        case 403:
            return .forbidden
        case 429:
            let header = response.value(forHTTPHeaderField: "Retry-After")
            return .rateLimited(retryAfter: header.flatMap(TimeInterval.init))
        case 500...599:
            return .server(status: status)
        default:
            return .request(status: status, message: message(from: data))
        }
    }

    /// Supabase puts the reason in one of three fields depending on which of
    /// its services answered. Best effort, and only ever for a log.
    private static func message(from data: Data) -> String? {
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        for key in ["message", "error_description", "msg", "error", "hint"] {
            if let found = object[key] as? String, !found.isEmpty { return found }
        }
        return nil
    }

    static func classify(_ error: URLError) -> BackendError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost,
             .dataNotAllowed, .internationalRoamingOff, .cannotConnectToHost,
             .cannotFindHost, .dnsLookupFailed:
            .offline
        case .timedOut:
            .timedOut
        case .cancelled:
            .cancelled
        default:
            .server(status: error.errorCode)
        }
    }
}
