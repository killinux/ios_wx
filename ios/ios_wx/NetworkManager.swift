import Foundation
import Combine

class NetworkManager: ObservableObject {
    static let shared = NetworkManager()

    let baseURL = "http://49.233.189.223:8080"
    var wsURL: String { baseURL.replacingOccurrences(of: "http", with: "ws") + "/ws" }

    @Published var token: String = UserDefaults.standard.string(forKey: "token") ?? ""
    @Published var userId: Int = UserDefaults.standard.integer(forKey: "userId")
    @Published var nickname: String = UserDefaults.standard.string(forKey: "nickname") ?? ""
    @Published var isLoggedIn: Bool = false

    private var wsTask: URLSessionWebSocketTask?
    private var wsSession: URLSession?
    private var wsRetryCount = 0
    private let maxWsRetries = 5
    @Published var wsConnected = false

    var onNewMessage: ((ChatMessage) -> Void)?
    var onTyping: ((Int) -> Void)?

    private var pollTimer: Timer?
    private var pollPeerId: Int?
    private var lastPollMessageId: Int = 0

    private init() {
        isLoggedIn = !token.isEmpty && userId > 0
    }

    func saveAuth(id: Int, token: String, nickname: String) {
        self.userId = id
        self.token = token
        self.nickname = nickname
        self.isLoggedIn = true
        UserDefaults.standard.set(token, forKey: "token")
        UserDefaults.standard.set(id, forKey: "userId")
        UserDefaults.standard.set(nickname, forKey: "nickname")
    }

    func logout() {
        token = ""
        userId = 0
        nickname = ""
        isLoggedIn = false
        UserDefaults.standard.removeObject(forKey: "token")
        UserDefaults.standard.removeObject(forKey: "userId")
        UserDefaults.standard.removeObject(forKey: "nickname")
        disconnectWS()
    }

    // MARK: - HTTP

    func request<T: Decodable>(_ method: String, _ path: String, body: Data? = nil) async throws -> T {
        let separator = path.contains("?") ? "&" : "?"
        let urlStr = "\(baseURL)\(path)\(separator)token=\(token)"
        var req = URLRequest(url: URL(string: urlStr)!)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 15
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status >= 400 {
            let msg = String(data: data, encoding: .utf8) ?? "error"
            throw APIError.server(status, msg)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func post<T: Decodable>(_ path: String, _ body: Encodable) async throws -> T {
        let data = try JSONEncoder().encode(body)
        return try await request("POST", path, body: data)
    }

    func get<T: Decodable>(_ path: String) async throws -> T {
        return try await request("GET", path)
    }

    // MARK: - WebSocket

    func connectWS() {
        guard !token.isEmpty else { return }
        let url = URL(string: "\(wsURL)?token=\(token)")!
        let session = URLSession(configuration: .default)
        wsSession = session
        wsTask = session.webSocketTask(with: url)
        wsTask?.resume()
        wsConnected = true
        wsRetryCount = 0
        stopPolling()
        receiveWS()
        startPing()
    }

    func disconnectWS() {
        wsTask?.cancel(with: .normalClosure, reason: nil)
        wsTask = nil
        wsConnected = false
    }

    private func receiveWS() {
        wsTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let msg):
                switch msg {
                case .string(let text):
                    self.handleWSMessage(text)
                default: break
                }
                self.receiveWS()
            case .failure:
                DispatchQueue.main.async {
                    self.wsConnected = false
                    self.retryWS()
                }
            }
        }
    }

    private func handleWSMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        if type == "new_message", let msgData = json["message"] as? [String: Any] {
            let msg = ChatMessage(
                id: msgData["id"] as? Int ?? 0,
                from_id: msgData["from_id"] as? Int ?? 0,
                to_id: msgData["to_id"] as? Int ?? 0,
                text: msgData["text"] as? String ?? "",
                created_at: msgData["created_at"] as? String ?? ""
            )
            DispatchQueue.main.async { self.onNewMessage?(msg) }
        } else if type == "typing", let fromId = json["from_id"] as? Int {
            DispatchQueue.main.async { self.onTyping?(fromId) }
        }
    }

    func sendWSMessage(toId: Int, text: String) {
        let payload: [String: Any] = ["type": "send_message", "to_id": toId, "text": text]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let str = String(data: data, encoding: .utf8) else { return }
        wsTask?.send(.string(str)) { _ in }
    }

    func sendTyping(toId: Int) {
        let payload: [String: Any] = ["type": "typing", "to_id": toId]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let str = String(data: data, encoding: .utf8) else { return }
        wsTask?.send(.string(str)) { _ in }
    }

    private func startPing() {
        DispatchQueue.global().asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self, self.wsConnected else { return }
            self.wsTask?.sendPing { error in
                if error != nil {
                    DispatchQueue.main.async {
                        self.wsConnected = false
                        self.retryWS()
                    }
                } else {
                    self.startPing()
                }
            }
        }
    }

    private func retryWS() {
        guard wsRetryCount < maxWsRetries else {
            startPolling()
            return
        }
        wsRetryCount += 1
        let delay = Double(min(wsRetryCount * 2, 10))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.connectWS()
        }
    }

    // MARK: - HTTP Polling fallback

    func startPolling(peerId: Int? = nil) {
        stopPolling()
        pollPeerId = peerId
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.pollOnce()
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func pollOnce() {
        guard let peerId = pollPeerId else { return }
        Task {
            do {
                let msgs: [ChatMessage] = try await get("/api/messages/poll/\(peerId)?after=\(lastPollMessageId)")
                for m in msgs {
                    lastPollMessageId = max(lastPollMessageId, m.id)
                    await MainActor.run { onNewMessage?(m) }
                }
            } catch { }
        }
    }
}

enum APIError: Error, LocalizedError {
    case server(Int, String)
    var errorDescription: String? {
        switch self {
        case .server(let code, let msg): return "[\(code)] \(msg)"
        }
    }
}

struct ChatMessage: Codable, Identifiable {
    let id: Int
    let from_id: Int
    let to_id: Int
    let text: String
    let created_at: String
}

struct AuthResponse: Codable {
    let id: Int
    let token: String
    let nickname: String
}

struct UserInfo: Codable, Identifiable {
    let id: Int
    let username: String
    let nickname: String
    let avatar: String
}

struct ChatItem: Codable, Identifiable {
    var id: Int { peer_id }
    let peer_id: Int
    let peer_name: String
    let peer_avatar: String
    let last_message: String
    let last_time: String
    let unread: Int
}

struct MomentItem: Codable, Identifiable {
    let id: Int
    let user_id: Int
    let text: String
    let images: [String]
    let created_at: String
    let nickname: String
    let avatar: String
    let likes: [String]
}

struct OkResponse: Codable {
    let ok: Bool?
    let id: Int?
    let liked: Bool?
}
