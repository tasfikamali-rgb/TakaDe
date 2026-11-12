import Foundation

/// A small Supabase Realtime client over one WebSocket (Phoenix protocol, JSON v1), with no
/// Supabase SDK. It does two things for the Social tab (docs/adr/0024-friend-messages.md):
/// tells the app the moment a message is waiting for it (database changes, filtered by the
/// server's row-level security), and passes "typing" signals between two phones on a
/// channel only those two phones can name. Events are nudges only: messages themselves are
/// always fetched and checked through the normal API.
@MainActor
final class RealtimeClient {
    enum Event {
        /// Something changed in a table this phone listens to.
        case change(topic: String)
        case broadcast(topic: String, event: String, payload: [String: Any])
    }

    var onEvent: ((Event) -> Void)?

    private let config: SupabaseConfig
    private let token: () async throws -> String
    private var socket: URLSessionWebSocketTask?
    /// Channels to be in, by topic, with the config sent when joining. Rejoined after a
    /// reconnect.
    private var channels: [String: [String: Any]] = [:]
    private var ref = 0
    private var wanted = false
    private var lastToken: String?
    private var heartbeat: Task<Void, Never>?
    private var reconnect: Task<Void, Never>?
    private var failures = 0

    init(config: SupabaseConfig, token: @escaping () async throws -> String) {
        self.config = config
        self.token = token
    }

    var isConnected: Bool { socket != nil }

    // MARK: Connection

    func connect() {
        wanted = true
        guard socket == nil, reconnect == nil else { return }
        Task { await open() }
    }

    func disconnect() {
        wanted = false
        reconnect?.cancel()
        reconnect = nil
        close()
    }

    private func open() async {
        guard wanted, socket == nil else { return }
        guard let current = try? await token() else {
            scheduleReconnect()
            return
        }
        lastToken = current
        var components = URLComponents(url: config.baseURL.appendingPathComponent("realtime/v1/websocket"),
                                       resolvingAgainstBaseURL: false)
        components?.scheme = "wss"
        components?.queryItems = [URLQueryItem(name: "apikey", value: config.anonKey),
                                  URLQueryItem(name: "vsn", value: "1.0.0")]
        guard let url = components?.url else { return }
        let task = URLSession.shared.webSocketTask(with: url)
        socket = task
        task.resume()
        receive(on: task)
        for (topic, settings) in channels { sendJoin(topic, settings: settings) }
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(25))
                guard let self, !Task.isCancelled else { return }
                await self.beat()
            }
        }
    }

    private func close() {
        heartbeat?.cancel()
        heartbeat = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    private func scheduleReconnect() {
        close()
        guard wanted, reconnect == nil else { return }
        failures += 1
        let delay = min(30, 1 << min(failures, 5))
        reconnect = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            self.reconnect = nil
            await self.open()
        }
    }

    /// Keeps the socket alive and hands Realtime a fresh token before the old one expires.
    private func beat() async {
        push(["topic": "phoenix", "event": "heartbeat", "payload": [String: Any]()])
        guard let current = try? await token(), current != lastToken else { return }
        lastToken = current
        for topic in channels.keys {
            push(["topic": wireTopic(topic), "event": "access_token", "payload": ["access_token": current]])
        }
    }

    private func receive(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.socket === task else { return }
                switch result {
                case .success(let message):
                    self.failures = 0
                    if case .string(let text) = message { self.handle(text) }
                    self.receive(on: task)
                case .failure:
                    self.scheduleReconnect()
                }
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let wire = json["topic"] as? String, wire.hasPrefix("realtime:"),
              let event = json["event"] as? String else { return }
        let topic = String(wire.dropFirst("realtime:".count))
        let payload = json["payload"] as? [String: Any] ?? [:]
        switch event {
        case "postgres_changes":
            onEvent?(.change(topic: topic))
        case "broadcast":
            guard let name = payload["event"] as? String else { return }
            onEvent?(.broadcast(topic: topic, event: name, payload: payload["payload"] as? [String: Any] ?? [:]))
        default:
            break
        }
    }

    // MARK: Channels

    /// Listens for new rows the signed-in account may read in `table` (row-level security
    /// still applies on the server).
    func listen(topic: String, table: String, filter: String) {
        join(topic, settings: [
            "broadcast": ["self": false, "ack": false],
            "presence": ["key": ""],
            "postgres_changes": [["event": "INSERT", "schema": "public", "table": table, "filter": filter]],
            "private": false,
        ])
    }

    /// Joins a broadcast-only channel, e.g. a chat's typing channel.
    func joinBroadcast(topic: String) {
        join(topic, settings: [
            "broadcast": ["self": false, "ack": false],
            "presence": ["key": ""],
            "postgres_changes": [[String: Any]](),
            "private": false,
        ])
    }

    func leave(topic: String) {
        guard channels.removeValue(forKey: topic) != nil else { return }
        push(["topic": wireTopic(topic), "event": "phx_leave", "payload": [String: Any]()])
    }

    func leaveAll() {
        for topic in channels.keys { leave(topic: topic) }
    }

    func broadcast(topic: String, event: String, payload: [String: Any] = [:]) {
        guard channels[topic] != nil else { return }
        push(["topic": wireTopic(topic), "event": "broadcast",
              "payload": ["type": "broadcast", "event": event, "payload": payload]])
    }

    private func join(_ topic: String, settings: [String: Any]) {
        guard channels[topic] == nil else { return }
        channels[topic] = settings
        sendJoin(topic, settings: settings)
    }

    private func sendJoin(_ topic: String, settings: [String: Any]) {
        guard socket != nil else { return }
        var payload: [String: Any] = ["config": settings]
        if let lastToken { payload["access_token"] = lastToken }
        ref += 1
        push(["topic": wireTopic(topic), "event": "phx_join", "payload": payload, "join_ref": String(ref)])
    }

    private func wireTopic(_ topic: String) -> String { "realtime:" + topic }

    private func push(_ message: [String: Any]) {
        guard let socket else { return }
        ref += 1
        var message = message
        message["ref"] = String(ref)
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: data, encoding: .utf8) else { return }
        socket.send(.string(text)) { _ in }
    }
}
