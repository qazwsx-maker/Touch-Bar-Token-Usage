import Foundation

public enum ApprovalDecision: String {
    case allow
    case deny
    case pass
}

/// Builds the JSON that a Claude Code PreToolUse hook must print on stdout
/// to allow/deny a tool call. `pass` produces nil (print nothing → Claude
/// falls through to its normal permission flow).
public enum HookResponse {
    public static func preToolUseJSON(decision: ApprovalDecision, reason: String) -> String? {
        let permission: String
        switch decision {
        case .allow: permission = "allow"
        case .deny: permission = "deny"
        case .pass: return nil
        }
        let payload: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PreToolUse",
                "permissionDecision": permission,
                "permissionDecisionReason": reason,
            ] as [String: Any]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }
}

public struct ToolSummary: Equatable {
    public let title: String
    public let detail: String

    public init(title: String, detail: String) {
        self.title = title
        self.detail = detail
    }
}

public enum ApprovalSummarizer {
    /// Human-readable one-liner for a tool call, shown on the Touch Bar.
    public static func summarize(toolName: String, toolInput: [String: Any], cwd: String?) -> ToolSummary {
        var title = toolName
        if let cwd = cwd {
            let project = (cwd as NSString).lastPathComponent
            if !project.isEmpty && project != "/" {
                title = "\(toolName) · \(project)"
            }
        }

        var detail: String
        switch toolName {
        case "Bash":
            let cmd = (toolInput["command"] as? String) ?? ""
            detail = cmd.split(whereSeparator: \.isNewline).first.map(String.init) ?? cmd
        case "Edit", "Write", "MultiEdit", "NotebookEdit", "Read":
            detail = Fmt.shortPath((toolInput["file_path"] as? String) ?? "")
        case "WebFetch":
            detail = (toolInput["url"] as? String) ?? ""
        case "WebSearch":
            detail = (toolInput["query"] as? String) ?? ""
        default:
            if JSONSerialization.isValidJSONObject(toolInput),
               let data = try? JSONSerialization.data(withJSONObject: toolInput, options: [.sortedKeys]),
               let s = String(data: data, encoding: .utf8) {
                detail = s
            } else {
                detail = ""
            }
        }
        detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.isEmpty { detail = "(no details)" }
        return ToolSummary(title: title, detail: Fmt.truncate(detail, max: 90))
    }

    /// Same semantics as Claude Code hook matchers: regex, full match, "" or "*" = all.
    public static func toolMatches(_ toolName: String, pattern: String) -> Bool {
        let trimmed = pattern.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed == "*" { return true }
        guard let re = try? NSRegularExpression(pattern: "^(?:\(trimmed))$") else { return true }
        let range = NSRange(toolName.startIndex..., in: toolName)
        return re.firstMatch(in: toolName, options: [], range: range) != nil
    }
}
