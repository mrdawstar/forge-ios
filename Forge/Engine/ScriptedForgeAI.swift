import Foundation

#if DEBUG
/// **DEBUG only, and never compiled into a release build.** A stand-in for the
/// `forge-ai` function, so every state of Ask Forge, the Weekly Reading and
/// Plan in your own words can be walked in the Simulator without a Sandbox
/// purchase — which the real server refuses from the Simulator by design
/// (Xcode StoreKit transactions are not Apple-signed, FORGE_CONTEXT §2q).
///
/// Launch with `-ForgeAIScript <scenario>`:
///
/// | Scenario | What every request gets |
/// |---|---|
/// | `ok` | an answer: a reading that checks out against the week, a plan for the first activity, and for Ask Forge a reply — with a proposal when the message asks for a change |
/// | `offline` | no connection |
/// | `402`, `429`, `500` | that status |
///
/// The request still goes through `RemoteForgeAI` and `AIEndpoint` exactly as
/// in the app — the consent, the order of checks, the body and the headers —
/// with this transport where the network would be. The entitlement and token
/// are placeholders; nothing leaves the Simulator.
struct ScriptedForgeAI: BackendTransport {
    enum Scenario: String {
        case ok, offline
        case paymentRequired = "402"
        case rateLimited = "429"
        case serverError = "500"
    }

    let scenario: Scenario

    static let config = SupabaseConfig(
        url: URL(string: "https://scripted.forge.invalid")!,
        anonKey: "sb_publishable_scripted"
    )

    /// The scenario named on the command line, or nil for the real backend.
    static func fromLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> ScriptedForgeAI? {
        guard let index = arguments.firstIndex(of: "-ForgeAIScript"),
              arguments.indices.contains(index + 1),
              let scenario = Scenario(rawValue: arguments[index + 1])
        else { return nil }
        return ScriptedForgeAI(scenario: scenario)
    }

    var endpoint: AIEndpoint {
        AIEndpoint(config: Self.config, client: HTTPClient(config: Self.config, transport: self))
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        // Long enough to see the typing indicator and "Working through your
        // week"; short enough to walk every state in a minute.
        try await Task.sleep(for: .milliseconds(1400))
        let status: Int
        let body: String
        switch scenario {
        case .offline:
            throw BackendError.offline
        case .paymentRequired:
            (status, body) = (402, #"{"error":"not_entitled"}"#)
        case .rateLimited:
            (status, body) = (429, #"{"error":"rate_limited"}"#)
        case .serverError:
            (status, body) = (500, #"{"error":"upstream"}"#)
        case .ok:
            (status, body) = (200, Self.answer(to: request.httpBody ?? Data()))
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(body.utf8), response)
    }

    // MARK: - The answers

    private static func answer(to data: Data) -> String {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let brief = object["brief"] as? [String: Any] ?? [:]
        let activities = brief["activities"] as? [[String: Any]] ?? []
        switch object["task"] as? String {
        case "reading":
            let week = brief["week"] as? [String: Any] ?? [:]
            let kept = week["kept"] as? Int ?? 0
            return json(["observation": "\(ForgeCount.spelled(kept)) days were kept."])
        case "plan":
            return json(proposal(for: activities) ?? ["summary": "", "changes": []])
        case "coach":
            let messages = object["messages"] as? [[String: Any]] ?? []
            let last = (messages.last?["text"] as? String ?? "").lowercased()
            let coach = brief["coach"] as? [String: Any] ?? [:]
            let wantsChange = ["harder", "move", "fit", "time", "plan", "evening"].contains { last.contains($0) }
            if wantsChange, let proposal = proposal(for: activities) {
                return json([
                    "reply": "Moving \(activities.first?["name"] as? String ?? "it") to 07:00 puts it before the day can crowd it out. Review the change below; nothing moves until you apply it.",
                    "proposal": proposal,
                ])
            }
            let overall = coach["overall"] as? Int
            return json([
                "reply": overall.map { "OVR is \($0). The lowest of the six is where a single extra day kept moves the number most this week." }
                    ?? "There is not enough record yet to say. Keep three days this week and the six will have something to read.",
                "proposal": NSNull(),
            ])
        default:
            return #"{"error":"task"}"#
        }
    }

    /// A time change for the first activity: 07:00, or 07:30 if it is already
    /// at 07:00 — always a real change to a real id.
    private static func proposal(for activities: [[String: Any]]) -> [String: Any]? {
        guard let first = activities.first, let id = first["id"] as? String else { return nil }
        let minute = (first["startMinute"] as? Int) == 420 ? 450 : 420
        return [
            "summary": "\(first["name"] as? String ?? "It") moves to the start of the day.",
            "changes": [["kind": "time", "id": id, "minute": minute, "minutes": NSNull(), "weekdays": NSNull()]],
        ]
    }

    private static func json(_ value: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
#endif
