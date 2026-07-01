import Foundation

/// Native ownership of the anonymous widget session (CONTRACT B.4).
///
/// iOS WebKit wipes partitioned third-party storage on app kill, so the web
/// runtime cannot reliably keep the anon session in `mode=sdk`. The SDK persists
/// it natively and re-injects `_lsuid` / `_lscid` on every WebView load — fixing
/// the historical iOS session-loss class of bugs.
///
/// Backed by `UserDefaults`: the right medium for a **pseudonymous** id — it
/// survives app relaunches (the bug we fix) but is cleared on app uninstall, so
/// a reinstall starts a clean identity. (Keychain would survive uninstall too,
/// resurrecting identity + history — undesirable for an anonymous id.)
public final class LoopsSessionStore: @unchecked Sendable {
    private let anonUserKey = "com.loopsai.chat.anonUserId"
    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "com.loopsai.chat.session.store")

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The durable anonymous user id, persisted across app relaunches.
    public var anonUserId: String? {
        get { queue.sync { defaults.string(forKey: anonUserKey) } }
        set { queue.sync { setOrRemove(anonUserKey, newValue) } }
    }

    /// Last conversation id for a given agent (per agent). `nil` clears it — used
    /// by ``LoopsAIChatViewController/startNewConversation()`` to drop the resume
    /// pointer so the next load starts a fresh conversation.
    public func conversationId(for agentId: String) -> String? {
        queue.sync { defaults.string(forKey: conversationKey(agentId)) }
    }

    public func setConversationId(_ id: String?, for agentId: String) {
        queue.sync { setOrRemove(conversationKey(agentId), id) }
    }

    /// Wipe the entire native session: the anon user id and every per-agent
    /// conversation pointer. Use for a "reset all data" / logout flow so the next
    /// chat load bootstraps a brand-new pseudonymous identity and conversation.
    public func reset() {
        queue.sync {
            for key in defaults.dictionaryRepresentation().keys
            where key == anonUserKey || key.hasPrefix("com.loopsai.chat.conversationId_") {
                defaults.removeObject(forKey: key)
            }
        }
    }

    /// Applies a `persistSession` payload from the web runtime (CONTRACT B.2).
    func apply(persistSession payload: [String: Any]) {
        if let uid = payload["anonUserId"] as? String, !uid.isEmpty {
            anonUserId = uid
        }
        if let agentId = payload["agentId"] as? String,
           let cid = payload["conversationId"] as? String, !cid.isEmpty {
            setConversationId(cid, for: agentId)
        }
    }

    private func conversationKey(_ agentId: String) -> String {
        "com.loopsai.chat.conversationId_\(agentId)"
    }

    private func setOrRemove(_ key: String, _ value: String?) {
        if let value, !value.isEmpty {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

/// Bootstraps the anon session against `POST /api/widget/session` (CONTRACT B.4),
/// migrating any locally-stored legacy id, then caches the result in the store.
struct LoopsSessionBootstrapper {
    let baseURL: URL
    let store: LoopsSessionStore

    struct Result {
        let anonUserId: String
        let lastConversationId: String?
    }

    /// Max bootstrap attempts (1 try + 2 retries) with exponential backoff.
    static let maxAttempts = 3

    func bootstrap(agentId: String, completion: @escaping (Swift.Result<Result, LoopsError>) -> Void) {
        attempt(agentId: agentId, attempt: 1, completion: completion)
    }

    private func attempt(
        agentId: String,
        attempt n: Int,
        completion: @escaping (Swift.Result<Result, LoopsError>) -> Void
    ) {
        let url = baseURL.appendingPathComponent("api/widget/session")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        var body: [String: Any] = ["agentId": agentId]
        if let legacy = store.anonUserId { body["legacyAnonUserId"] = legacy }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            // Retry transport errors and 5xx; never retry a valid 4xx (caller error).
            let transient = error != nil || (500...599).contains(status)

            if transient, n < Self.maxAttempts {
                // Exponential backoff: 0.5s, 1s, … (jitter-free is fine here).
                let delay = 0.5 * pow(2.0, Double(n - 1))
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                    self.attempt(agentId: agentId, attempt: n + 1, completion: completion)
                }
                return
            }

            if let error {
                completion(.failure(.session(reason: error.localizedDescription)))
                return
            }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let anonUserId = json["anonUserId"] as? String else {
                completion(.failure(.session(reason: "invalid /api/widget/session response (status \(status))")))
                return
            }
            let lastConversationId = json["lastConversationId"] as? String
            store.anonUserId = anonUserId
            if let lastConversationId {
                store.setConversationId(lastConversationId, for: agentId)
            }
            completion(.success(Result(anonUserId: anonUserId, lastConversationId: lastConversationId)))
        }.resume()
    }
}
