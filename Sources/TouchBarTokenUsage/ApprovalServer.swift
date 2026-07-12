import Foundation
import Network
import TBTCore

struct ApprovalRequest: Identifiable {
    let id: UUID
    let toolName: String
    let title: String
    let detail: String
    let receivedAt: Date
    let deadline: Date
    let isTest: Bool
}

/// Tiny localhost HTTP server that Claude Code hooks talk to.
///
/// POST /v1/hook  (X-TBT-Token header required)
///   - PreToolUse events long-poll until the user taps Accept/Deny on the
///     Touch Bar (200 + hook JSON) or the timeout passes (204 = no decision).
///   - Stop/Notification events show a toast and return immediately.
/// GET /ping — health check.
final class ApprovalServer {
    struct Config {
        var port: UInt16
        var token: String
        var enabled: Bool
        var timeout: TimeInterval
        var toolPattern: String
        var autoPassPrefixes: [String]
        var notifyOnStop: Bool
    }

    var config: Config
    var onQueueChanged: (([ApprovalRequest]) -> Void)?
    var onToast: ((String) -> Void)?
    var onServerState: ((String) -> Void)?

    private var listener: NWListener?
    private var startAttemptsLeft = 0

    /// A hook call waiting for a human decision. Holds its connection
    /// strongly so the long-poll socket stays open.
    private final class Pending {
        let request: ApprovalRequest
        let connection: NWConnection?
        var timeoutItem: DispatchWorkItem?

        init(request: ApprovalRequest, connection: NWConnection?) {
            self.request = request
            self.connection = connection
        }
    }

    private var pendings: [Pending] = []

    init(config: Config) {
        self.config = config
    }

    var currentQueue: [ApprovalRequest] { pendings.map { $0.request } }

    func start() {
        startAttemptsLeft = 3
        startListener()
    }

    private func startListener() {
        stopListener()
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            guard let port = NWEndpoint.Port(rawValue: config.port) else {
                onServerState?("invalid port \(config.port)")
                return
            }
            params.requiredLocalEndpoint = NWEndpoint.hostPort(host: NWEndpoint.Host("127.0.0.1"), port: port)
            let l = try NWListener(using: params)
            l.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.startAttemptsLeft = 3
                    self.onServerState?("listening on 127.0.0.1:\(self.config.port)")
                case .failed(let error):
                    // The port can linger briefly while an old instance shuts
                    // down (e.g. right after an upgrade) — retry a few times.
                    if self.startAttemptsLeft > 0 {
                        self.startAttemptsLeft -= 1
                        self.onServerState?("port busy — retrying…")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                            self?.startListener()
                        }
                    } else {
                        self.onServerState?("failed: \(error.localizedDescription)")
                    }
                default:
                    break
                }
            }
            l.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            l.start(queue: .main)
            listener = l
        } catch {
            onServerState?("failed to start: \(error.localizedDescription)")
        }
    }

    func stop() {
        stopListener()
        for pending in pendings {
            pending.timeoutItem?.cancel()
            respond(pending, json: nil)
        }
        pendings.removeAll()
        notifyQueueChanged()
    }

    private func stopListener() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, isComplete, error in
            guard let self = self else {
                connection.cancel()
                return
            }
            var buf = buffer
            if let data = data {
                buf.append(data)
            }
            if let request = Self.parseHTTP(buf) {
                self.route(request, connection: connection)
            } else if isComplete || error != nil || buf.count > 2_000_000 {
                connection.cancel()
            } else {
                self.receive(connection, buffer: buf)
            }
        }
    }

    /// After a PreToolUse request is queued, keep reading so we notice when
    /// the hook script gives up (curl timeout / Ctrl-C) and can drop the item.
    private func watchForDisconnect(_ connection: NWConnection, requestID: UUID) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] _, _, isComplete, error in
            guard let self = self else { return }
            if isComplete || error != nil {
                self.removePendingIfPresent(requestID)
            } else {
                self.watchForDisconnect(connection, requestID: requestID)
            }
        }
    }

    struct HTTPRequest {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    static func parseHTTP(_ data: Data) -> HTTPRequest? {
        guard let headerRange = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard let head = String(data: data[data.startIndex..<headerRange.lowerBound], encoding: .utf8) else { return nil }
        var lines = head.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }
        let requestParts = lines.removeFirst().components(separatedBy: " ")
        guard requestParts.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerRange.upperBound
        guard data.endIndex - bodyStart >= contentLength else { return nil }
        let body = Data(data[bodyStart..<(bodyStart + contentLength)])
        return HTTPRequest(method: requestParts[0], path: requestParts[1], headers: headers, body: body)
    }

    private func route(_ request: HTTPRequest, connection: NWConnection) {
        switch (request.method, request.path) {
        case ("GET", "/ping"):
            send(connection, status: 200, body: Data("{\"app\":\"TouchBarTokenUsage\"}".utf8))
        case ("POST", "/v1/hook"):
            guard !config.token.isEmpty, request.headers["x-tbt-token"] == config.token else {
                send(connection, status: 401, body: nil)
                return
            }
            guard let object = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] else {
                send(connection, status: 400, body: nil)
                return
            }
            handleHook(object, connection: connection)
        default:
            send(connection, status: 404, body: nil)
        }
    }

    private func handleHook(_ object: [String: Any], connection: NWConnection) {
        let event = (object["hook_event_name"] as? String) ?? ""
        switch event {
        case "PreToolUse":
            handlePreToolUse(object, connection: connection)
        case "Stop":
            if config.notifyOnStop {
                onToast?("✅ Claude finished")
            }
            send(connection, status: 204, body: nil)
        case "Notification":
            if config.notifyOnStop, let message = object["message"] as? String, !message.isEmpty {
                onToast?("💬 " + Fmt.truncate(message, max: 42))
            }
            send(connection, status: 204, body: nil)
        default:
            send(connection, status: 204, body: nil)
        }
    }

    private func handlePreToolUse(_ object: [String: Any], connection: NWConnection) {
        let toolName = (object["tool_name"] as? String) ?? "Tool"
        let toolInput = (object["tool_input"] as? [String: Any]) ?? [:]

        guard config.enabled, ApprovalSummarizer.toolMatches(toolName, pattern: config.toolPattern) else {
            send(connection, status: 204, body: nil)
            return
        }
        if toolName == "Bash", let command = (toolInput["command"] as? String)?.trimmingCharacters(in: .whitespaces) {
            let passes = config.autoPassPrefixes.contains { !$0.isEmpty && command.hasPrefix($0) }
            if passes {
                send(connection, status: 204, body: nil)
                return
            }
        }

        let summary = ApprovalSummarizer.summarize(toolName: toolName, toolInput: toolInput, cwd: object["cwd"] as? String)
        let request = ApprovalRequest(id: UUID(),
                                      toolName: toolName,
                                      title: summary.title,
                                      detail: summary.detail,
                                      receivedAt: Date(),
                                      deadline: Date().addingTimeInterval(config.timeout),
                                      isTest: false)
        let pending = Pending(request: request, connection: connection)
        let timeoutItem = DispatchWorkItem { [weak self] in
            self?.decide(request.id, .pass)
        }
        pending.timeoutItem = timeoutItem
        DispatchQueue.main.asyncAfter(deadline: .now() + config.timeout, execute: timeoutItem)
        pendings.append(pending)
        watchForDisconnect(connection, requestID: request.id)
        notifyQueueChanged()
    }

    // MARK: - Decisions

    func decide(_ id: UUID, _ decision: ApprovalDecision) {
        guard let index = pendings.firstIndex(where: { $0.request.id == id }) else { return }
        let pending = pendings.remove(at: index)
        pending.timeoutItem?.cancel()

        let reason = decision == .allow ? "Approved from Touch Bar" : "Denied from Touch Bar"
        respond(pending, json: HookResponse.preToolUseJSON(decision: decision, reason: reason))

        if pending.request.isTest {
            let toast: String
            switch decision {
            case .allow: toast = "✅ Test request approved"
            case .deny: toast = "🚫 Test request denied"
            case .pass: toast = "↷ Test request passed"
            }
            onToast?(toast)
        }
        notifyQueueChanged()
    }

    private func respond(_ pending: Pending, json: String?) {
        guard let connection = pending.connection else { return }
        if let json = json {
            send(connection, status: 200, body: Data(json.utf8))
        } else {
            send(connection, status: 204, body: nil)
        }
    }

    /// Injects a fake request so the user can try the flow without Claude.
    func injectTest() {
        let request = ApprovalRequest(id: UUID(),
                                      toolName: "Bash",
                                      title: "Bash · demo-project",
                                      detail: "git push origin main   (test request)",
                                      receivedAt: Date(),
                                      deadline: Date().addingTimeInterval(config.timeout),
                                      isTest: true)
        let pending = Pending(request: request, connection: nil)
        let timeoutItem = DispatchWorkItem { [weak self] in
            self?.decide(request.id, .pass)
        }
        pending.timeoutItem = timeoutItem
        DispatchQueue.main.asyncAfter(deadline: .now() + config.timeout, execute: timeoutItem)
        pendings.append(pending)
        notifyQueueChanged()
    }

    private func removePendingIfPresent(_ id: UUID) {
        guard let index = pendings.firstIndex(where: { $0.request.id == id }) else { return }
        pendings[index].timeoutItem?.cancel()
        pendings[index].connection?.cancel()
        pendings.remove(at: index)
        notifyQueueChanged()
    }

    private func notifyQueueChanged() {
        onQueueChanged?(currentQueue)
    }

    private func send(_ connection: NWConnection, status: Int, body: Data?, contentType: String = "application/json") {
        let reasons: [Int: String] = [200: "OK", 204: "No Content", 400: "Bad Request",
                                      401: "Unauthorized", 404: "Not Found"]
        var head = "HTTP/1.1 \(status) \(reasons[status] ?? "OK")\r\nConnection: close\r\n"
        if let body = body, !body.isEmpty {
            head += "Content-Type: \(contentType)\r\nContent-Length: \(body.count)\r\n"
        } else {
            head += "Content-Length: 0\r\n"
        }
        head += "\r\n"
        var out = Data(head.utf8)
        if let body = body {
            out.append(body)
        }
        connection.send(content: out, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
