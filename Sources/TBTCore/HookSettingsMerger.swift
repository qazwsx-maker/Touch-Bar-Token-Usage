import Foundation

/// Merges/removes our hook entries in `~/.claude/settings.json` while
/// preserving everything else the user has configured.
public enum HookSettingsMerger {
    /// All entries we manage contain this marker in their command path.
    public static let marker = "touchbar-usage"

    public static func merged(existingJSON: Data?,
                              hookCommand: String,
                              preToolUseMatcher: String,
                              includeExtraEvents: Bool) throws -> Data {
        var root = parse(existingJSON)
        var hooks = (root["hooks"] as? [String: Any]) ?? [:]

        hooks["PreToolUse"] = upsert(entries: hooks["PreToolUse"],
                                     matcher: preToolUseMatcher,
                                     command: hookCommand,
                                     timeout: 90)
        for event in ["Stop", "Notification"] {
            if includeExtraEvents {
                hooks[event] = upsert(entries: hooks[event], matcher: nil, command: hookCommand, timeout: 10)
            } else if let stripped = strip(entries: hooks[event]) {
                if stripped.isEmpty {
                    hooks.removeValue(forKey: event)
                } else {
                    hooks[event] = stripped
                }
            }
        }

        root["hooks"] = hooks
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    public static func removed(existingJSON: Data?) throws -> Data {
        var root = parse(existingJSON)
        if var hooks = root["hooks"] as? [String: Any] {
            for key in Array(hooks.keys) {
                guard let stripped = strip(entries: hooks[key]) else { continue }
                if stripped.isEmpty {
                    hooks.removeValue(forKey: key)
                } else {
                    hooks[key] = stripped
                }
            }
            if hooks.isEmpty {
                root.removeValue(forKey: "hooks")
            } else {
                root["hooks"] = hooks
            }
        }
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    public static func isInstalled(existingJSON: Data?) -> Bool {
        guard let data = existingJSON, let s = String(data: data, encoding: .utf8) else { return false }
        return s.contains(marker)
    }

    // MARK: - Internals

    private static func parse(_ data: Data?) -> [String: Any] {
        guard let data = data,
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return [:]
        }
        return obj
    }

    private static func entryIsOurs(_ entry: [String: Any]) -> Bool {
        guard let hookList = entry["hooks"] as? [[String: Any]] else { return false }
        return hookList.contains { (($0["command"] as? String) ?? "").contains(marker) }
    }

    /// Removes our entries from an event's entry array. nil when the value
    /// wasn't an array (leave unknown shapes untouched).
    private static func strip(entries: Any?) -> [[String: Any]]? {
        guard let arr = entries as? [[String: Any]] else { return nil }
        return arr.filter { !entryIsOurs($0) }
    }

    private static func upsert(entries: Any?, matcher: String?, command: String, timeout: Int) -> [[String: Any]] {
        var arr = strip(entries: entries) ?? []
        let hook: [String: Any] = ["type": "command", "command": command, "timeout": timeout]
        var entry: [String: Any] = ["hooks": [hook]]
        if let matcher = matcher {
            entry["matcher"] = matcher
        }
        arr.append(entry)
        return arr
    }
}

/// The shell script installed at ~/.claude/touchbar-usage/hook.sh.
public enum HookScript {
    public static func content(defaultPort: Int) -> String {
        """
        #!/bin/bash
        # Touch Bar Token Usage — Claude Code hook bridge.
        # Reads the hook JSON from stdin, forwards it to the local app, and prints
        # the app's decision (if any). Always exits 0 so Claude falls back to its
        # normal permission flow whenever the app is not running.
        DIR="$HOME/.claude/touchbar-usage"
        PORT="$(cat "$DIR/port" 2>/dev/null || echo \(defaultPort))"
        TOKEN="$(cat "$DIR/token" 2>/dev/null || echo none)"
        RESP="$(curl -s -m 58 -H "X-TBT-Token: $TOKEN" -H "Content-Type: application/json" --data-binary @- "http://127.0.0.1:$PORT/v1/hook" 2>/dev/null)"
        if [ -n "$RESP" ]; then
          printf '%s' "$RESP"
        fi
        exit 0
        """
    }
}
