import Foundation
import TBTCore

/// Reads the Claude Code OAuth token that already lives on this Mac and asks
/// Anthropic's usage endpoint for the *real* limit percentages — the same
/// numbers `/usage` shows in Claude Code. Falls back gracefully when there is
/// no login, the token expired, or the endpoint is unreachable.
enum ClaudeCredentials {
    static func accessToken() -> String? {
        // 1) Plain-file credentials (Linux/older setups, some installs)
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        if let data = try? Data(contentsOf: file), let token = token(from: data) {
            return token
        }
        // 2) macOS Keychain item created by Claude Code.
        //    May show a one-time "allow" prompt for our app.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
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
        return token(from: Data(string.utf8))
    }

    private static func token(from data: Data) -> String? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let oauth = object["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else {
            return nil
        }
        if let expires = oauth["expiresAt"] as? Double, expires > 0,
           Date(timeIntervalSince1970: expires / 1000) < Date() {
            return nil  // expired — Claude Code refreshes it next time it runs
        }
        return token
    }
}

final class QuotaFetcher {
    /// (quota or nil, human-readable source status) — delivered on main.
    var onUpdate: ((Quota?, String) -> Void)?

    private let queue = DispatchQueue(label: "tbtu.quota", qos: .utility)
    private var timer: DispatchSourceTimer?

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

    private func fetch() {
        guard let token = ClaudeCredentials.accessToken() else {
            deliver(nil, "local estimate (no Claude Code login found)")
            return
        }
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self = self else { return }
            guard let http = response as? HTTPURLResponse else {
                self.deliver(nil, "local estimate (Claude API unreachable)")
                return
            }
            if http.statusCode == 200, let data = data, let quota = QuotaParser.parse(data) {
                self.deliver(quota, "live from Claude API")
            } else if http.statusCode == 401 || http.statusCode == 403 {
                self.deliver(nil, "local estimate (Claude login expired — open Claude Code once)")
            } else {
                self.deliver(nil, "local estimate (Claude API \(http.statusCode))")
            }
        }
        task.resume()
    }

    private func deliver(_ quota: Quota?, _ status: String) {
        DispatchQueue.main.async { [weak self] in
            self?.onUpdate?(quota, status)
        }
    }
}
