import Foundation
import TBTCore

/// Owns the files under `~/.claude/touchbar-usage/` (hook script, port,
/// shared-secret token) and the hook entries in `~/.claude/settings.json`.
final class HookInstaller {
    let baseDir: URL
    let settingsFile: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        baseDir = home.appendingPathComponent(".claude/touchbar-usage")
        settingsFile = home.appendingPathComponent(".claude/settings.json")
    }

    var hookScriptURL: URL { baseDir.appendingPathComponent("hook.sh") }
    var portFileURL: URL { baseDir.appendingPathComponent("port") }
    var tokenFileURL: URL { baseDir.appendingPathComponent("token") }

    /// Writes hook.sh + port file, creates the token on first run.
    /// Returns the shared token.
    @discardableResult
    func ensureRuntimeFiles(port: Int) -> String {
        let fm = FileManager.default
        try? fm.createDirectory(at: baseDir, withIntermediateDirectories: true)

        let script = HookScript.content(defaultPort: Settings.defaultPort)
        try? Data(script.utf8).write(to: hookScriptURL)
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookScriptURL.path)

        try? Data("\(port)".utf8).write(to: portFileURL)

        if !fm.fileExists(atPath: tokenFileURL.path) {
            let token = UUID().uuidString + "-" + UUID().uuidString
            try? Data(token.utf8).write(to: tokenFileURL)
        }
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenFileURL.path)
        return readToken()
    }

    func readToken() -> String {
        (try? String(contentsOf: tokenFileURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func isInstalled() -> Bool {
        HookSettingsMerger.isInstalled(existingJSON: try? Data(contentsOf: settingsFile))
    }

    func install(matcher: String, includeExtraEvents: Bool) throws {
        let existing = try? Data(contentsOf: settingsFile)
        let merged = try HookSettingsMerger.merged(existingJSON: existing,
                                                   hookCommand: hookScriptURL.path,
                                                   preToolUseMatcher: matcher,
                                                   includeExtraEvents: includeExtraEvents)
        try FileManager.default.createDirectory(at: settingsFile.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try merged.write(to: settingsFile)
    }

    func remove() throws {
        guard let existing = try? Data(contentsOf: settingsFile) else { return }
        let cleaned = try HookSettingsMerger.removed(existingJSON: existing)
        try cleaned.write(to: settingsFile)
    }
}
