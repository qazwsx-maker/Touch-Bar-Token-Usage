import Foundation
import Security
import TBTCore

/// Reads the Claude Code OAuth token that already lives on this Mac and asks
/// Anthropic's usage endpoint for the *real* limit percentages — the same
/// numbers `/usage` shows in Claude Code. Falls back gracefully when there is
/// no login, the token expired, or the endpoint is unreachable.
enum ClaudeCredentials {
    enum Credential {
        case token(String, expiresAt: Date?)
        case denied      // user rejected the Keychain prompt
        case notFound    // no credentials file, no Keychain item
        case unreadable  // credentials exist but could not be parsed
    }

    static let keychainService = "Claude Code-credentials"

    static func load() -> Credential {
        var fallback = Credential.notFound
        func rank(_ c: Credential) -> Int {
            switch c {
            case .token: return 3
            case .denied: return 2
            case .unreadable: return 1
            case .notFound: return 0
            }
        }
        // Keeps the most useful non-fresh result while we look for a fresh
        // token; ties go to the later source (the Keychain outranks a stale file).
        func remember(_ c: Credential) {
            if rank(c) >= rank(fallback) { fallback = c }
        }
        func fresh(_ c: Credential) -> Credential? {
            if case .token(_, let expiresAt) = c {
                if let expiry = expiresAt, expiry < Date() {
                    remember(c)
                    return nil
                }
                return c
            }
            remember(c)
            return nil
        }

        // 1) Plain-file credentials (Linux/older setups, some installs).
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        if let data = try? Data(contentsOf: file), let hit = fresh(parse(data)) {
            return hit
        }

        // 2) macOS Keychain item created by Claude Code. Reading through the
        //    Security framework makes the one-time prompt carry *our* app name
        //    and an "Always Allow" button.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            if let data = item as? Data {
                if let hit = fresh(parse(data)) { return hit }
            } else {
                remember(.unreadable)
            }
        case errSecItemNotFound:
            // Legacy fallback: `security` searches every keychain in the user's
            // search list. The item is absent from the default one, so this
            // cannot prompt.
            if let data = securityCLIRead(), let hit = fresh(parse(data)) {
                return hit
            }
        case errSecAuthFailed, errSecUserCanceled, errSecInteractionNotAllowed:
            remember(.denied)
        default:
            break
        }
        return fallback
    }

    private static func parse(_ data: Data) -> Credential {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let oauth = object["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else {
            return .unreadable
        }
        var expiresAt: Date?
        if let expires = oauth["expiresAt"] as? Double, expires > 0 {
            expiresAt = Date(timeIntervalSince1970: expires / 1000)  // stored in ms
        }
        return .token(token, expiresAt: expiresAt)
    }

    private static func securityCLIRead() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", keychainService, "-w"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        guard let string = String(data: output, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else {
            return nil
        }
        return Data(string.utf8)
    }
}

final class QuotaFetcher {
    /// (quota or nil, human-readable source status) — delivered on main.
    var onUpdate: ((Quota?, String) -> Void)?

    private let queue = DispatchQueue(label: "tbtu.quota", qos: .utility)
    private var timer: DispatchSourceTimer?

    private struct CachedToken {
        let value: String
        let expiresAt: Date?
        let fetchedAt: Date
        var isUsable: Bool {
            if let expiry = expiresAt { return Date() < expiry.addingTimeInterval(-120) }
            return Date() < fetchedAt.addingTimeInterval(30 * 60)
        }
    }

    /// Reused between polls so the Keychain is not re-read (and cannot
    /// re-prompt) every 60 seconds.
    private var cachedToken: CachedToken?
    /// After a credentials-level failure, skip automatic re-reads until this
    /// moment so a denied prompt doesn't reappear once a minute. Manual
    /// "Refresh Claude Quota" clears it.
    private var suspendCredentialReadsUntil: Date?

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + .seconds(1), repeating: .seconds(60))
        t.setEventHandler { [weak self] in
            self?.fetch()
        }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// Menu action: forget everything and try again right now (may re-prompt).
    func retryNow() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.cachedToken = nil
            self.suspendCredentialReadsUntil = nil
            self.fetch(force: true)
        }
    }

    private func fetch(force: Bool = false) {
        var token: String?
        if let cached = cachedToken, cached.isUsable {
            token = cached.value
        }
        if token == nil {
            if !force, let until = suspendCredentialReadsUntil, Date() < until {
                return  // status was already delivered; stay quiet on local estimates
            }
            switch ClaudeCredentials.load() {
            case .token(let value, let expiresAt):
                // An expired token is still worth one request — server clocks
                // decide, and the 401 handler explains the rest.
                cachedToken = CachedToken(value: value, expiresAt: expiresAt, fetchedAt: Date())
                token = value
            case .denied:
                suspendCredentialReadsUntil = Date().addingTimeInterval(30 * 60)
                deliver(nil, "local estimate (Keychain access denied — pick “Refresh Claude Quota” in this menu, then click Always Allow)")
                return
            case .notFound:
                suspendCredentialReadsUntil = Date().addingTimeInterval(10 * 60)
                deliver(nil, "local estimate (no Claude Code login on this Mac)")
                return
            case .unreadable:
                suspendCredentialReadsUntil = Date().addingTimeInterval(10 * 60)
                deliver(nil, "local estimate (couldn’t read the Claude Code credentials)")
                return
            }
        }
        guard let bearer = token,
              let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self = self else { return }
            self.queue.async {
                guard let http = response as? HTTPURLResponse else {
                    self.deliver(nil, "local estimate (Claude API unreachable)")
                    return
                }
                // Always record the raw response so a wrong number can be
                // diagnosed from the file instead of guessing the API shape.
                self.dumpDebug(status: http.statusCode, body: data)
                if http.statusCode == 200, let data = data, let quota = QuotaParser.parse(data) {
                    self.suspendCredentialReadsUntil = nil
                    self.deliver(quota, "live from Claude API")
                } else if http.statusCode == 401 || http.statusCode == 403 {
                    self.cachedToken = nil
                    self.suspendCredentialReadsUntil = Date().addingTimeInterval(10 * 60)
                    self.deliver(nil, "local estimate (Claude login expired — open Claude Code once, then “Refresh Claude Quota”)")
                } else if http.statusCode == 200 {
                    // Token worked but we couldn't map the response — the dump
                    // file has the shape to teach the parser.
                    self.deliver(nil, "local estimate (Claude API 200 but response not recognized — see usage-debug.json)")
                } else {
                    self.deliver(nil, "local estimate (Claude API \(http.statusCode))")
                }
            }
        }
        task.resume()
    }

    /// Writes the latest usage response to
    /// ~/.claude/touchbar-usage/usage-debug.json for troubleshooting mismatched
    /// numbers. Contains only quota percentages/reset times — no token.
    private func dumpDebug(status: Int, body: Data?) {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/touchbar-usage")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("usage-debug.json")
        var text = "// HTTP \(status) — GET /api/oauth/usage\n"
        if let body = body, let s = String(data: body, encoding: .utf8) {
            text += s
        } else {
            text += "(empty body)"
        }
        try? text.write(to: file, atomically: true, encoding: .utf8)
    }

    private func deliver(_ quota: Quota?, _ status: String) {
        DispatchQueue.main.async { [weak self] in
            self?.onUpdate?(quota, status)
        }
    }
}
