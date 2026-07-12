import AppKit
import Combine
import TBTCore

enum DisplayMetric: String, CaseIterable, Identifiable {
    case totalTokens
    case inOut
    case cost
    case rate

    var id: String { rawValue }

    var label: String {
        switch self {
        case .totalTokens: return "Total tokens (today)"
        case .inOut: return "In / Out tokens (today)"
        case .cost: return "Cost (today)"
        case .rate: return "Burn rate"
        }
    }
}

enum PetEnergy: String, CaseIterable, Identifiable {
    case chill
    case normal
    case hyper

    var id: String { rawValue }

    var multiplier: Double {
        switch self {
        case .chill: return 0.6
        case .normal: return 1.0
        case .hyper: return 1.6
        }
    }

    var label: String {
        switch self {
        case .chill: return "Chill"
        case .normal: return "Normal"
        case .hyper: return "Hyper"
        }
    }
}

/// App settings persisted in UserDefaults, observable from SwiftUI and AppKit.
final class Settings: ObservableObject {
    static let shared = Settings()
    static let defaultPort = 43917
    static let defaultMatcher = "Bash|Edit|Write|MultiEdit|NotebookEdit|WebFetch"

    private let d = UserDefaults.standard

    @Published var themeID: String { didSet { d.set(themeID, forKey: "themeID") } }
    @Published var customBackground: String { didSet { d.set(customBackground, forKey: "customBackground") } }
    @Published var customText: String { didSet { d.set(customText, forKey: "customText") } }
    @Published var customAccent: String { didSet { d.set(customAccent, forKey: "customAccent") } }
    @Published var customPet: String { didSet { d.set(customPet, forKey: "customPet") } }

    @Published var petID: String { didSet { d.set(petID, forKey: "petID") } }
    @Published var petEnergy: String { didSet { d.set(petEnergy, forKey: "petEnergy") } }

    @Published var metric: String { didSet { d.set(metric, forKey: "metric") } }
    @Published var showCostLine: Bool { didSet { d.set(showCostLine, forKey: "showCostLine") } }
    @Published var showRateLine: Bool { didSet { d.set(showRateLine, forKey: "showRateLine") } }
    @Published var showLimitBars: Bool { didSet { d.set(showLimitBars, forKey: "showLimitBars") } }
    @Published var expandedLayout: String { didSet { d.set(expandedLayout, forKey: "expandedLayout") } }
    @Published var resetStyle: String { didSet { d.set(resetStyle, forKey: "resetStyle") } }
    @Published var widgetMode: String { didSet { d.set(widgetMode, forKey: "widgetMode") } }
    @Published var provider: String { didSet { d.set(provider, forKey: "provider") } }
    @Published var barStyle: String { didSet { d.set(barStyle, forKey: "barStyle") } }
    @Published var showModelOnBar: Bool { didSet { d.set(showModelOnBar, forKey: "showModelOnBar") } }
    @Published var fiveHourLimitTokens: Int { didSet { d.set(fiveHourLimitTokens, forKey: "fiveHourLimitTokens") } }
    @Published var weeklyLimitTokens: Int { didSet { d.set(weeklyLimitTokens, forKey: "weeklyLimitTokens") } }
    @Published var showWidget: Bool { didSet { d.set(showWidget, forKey: "showWidget") } }
    @Published var menuBarShowsTokens: Bool { didSet { d.set(menuBarShowsTokens, forKey: "menuBarShowsTokens") } }

    @Published var approvalsEnabled: Bool { didSet { d.set(approvalsEnabled, forKey: "approvalsEnabled") } }
    @Published var approvalTimeout: Double { didSet { d.set(approvalTimeout, forKey: "approvalTimeout") } }
    @Published var autoPresentOnRequest: Bool { didSet { d.set(autoPresentOnRequest, forKey: "autoPresentOnRequest") } }
    @Published var playSound: Bool { didSet { d.set(playSound, forKey: "playSound") } }
    @Published var showPanel: Bool { didSet { d.set(showPanel, forKey: "showPanel") } }
    @Published var notifyOnStop: Bool { didSet { d.set(notifyOnStop, forKey: "notifyOnStop") } }

    @Published var port: Int { didSet { d.set(port, forKey: "port") } }
    @Published var toolMatcher: String { didSet { d.set(toolMatcher, forKey: "toolMatcher") } }
    @Published var autoPassPrefixes: String { didSet { d.set(autoPassPrefixes, forKey: "autoPassPrefixes") } }

    private init() {
        d.register(defaults: [
            "themeID": "midnight",
            "customBackground": "#101014",
            "customText": "#F2F2F7",
            "customAccent": "#0A84FF",
            "customPet": "#64D2FF",
            "petID": "penguin",
            "petEnergy": "normal",
            "metric": DisplayMetric.totalTokens.rawValue,
            "showCostLine": true,
            "showRateLine": true,
            "showLimitBars": true,
            "expandedLayout": "bars",
            "resetStyle": "remaining",
            "barStyle": "auto",
            "widgetMode": "full",
            "provider": "claude",
            "showModelOnBar": true,
            "fiveHourLimitTokens": 0,
            "weeklyLimitTokens": 0,
            "showWidget": true,
            "menuBarShowsTokens": true,
            "approvalsEnabled": true,
            "approvalTimeout": 20.0,
            "autoPresentOnRequest": true,
            "playSound": true,
            "showPanel": true,
            "notifyOnStop": true,
            "port": Settings.defaultPort,
            "toolMatcher": Settings.defaultMatcher,
            "autoPassPrefixes": "",
        ])

        themeID = d.string(forKey: "themeID") ?? "midnight"
        customBackground = d.string(forKey: "customBackground") ?? "#101014"
        customText = d.string(forKey: "customText") ?? "#F2F2F7"
        customAccent = d.string(forKey: "customAccent") ?? "#0A84FF"
        customPet = d.string(forKey: "customPet") ?? "#64D2FF"
        petID = d.string(forKey: "petID") ?? "penguin"
        petEnergy = d.string(forKey: "petEnergy") ?? "normal"
        metric = d.string(forKey: "metric") ?? DisplayMetric.totalTokens.rawValue
        showCostLine = d.bool(forKey: "showCostLine")
        showRateLine = d.bool(forKey: "showRateLine")
        showLimitBars = d.bool(forKey: "showLimitBars")
        expandedLayout = d.string(forKey: "expandedLayout") ?? "bars"
        resetStyle = d.string(forKey: "resetStyle") ?? "remaining"
        barStyle = d.string(forKey: "barStyle") ?? "auto"
        widgetMode = d.string(forKey: "widgetMode") ?? "full"
        provider = d.string(forKey: "provider") ?? "claude"
        showModelOnBar = d.bool(forKey: "showModelOnBar")
        fiveHourLimitTokens = d.integer(forKey: "fiveHourLimitTokens")
        weeklyLimitTokens = d.integer(forKey: "weeklyLimitTokens")
        showWidget = d.bool(forKey: "showWidget")
        menuBarShowsTokens = d.bool(forKey: "menuBarShowsTokens")
        approvalsEnabled = d.bool(forKey: "approvalsEnabled")
        approvalTimeout = d.double(forKey: "approvalTimeout")
        autoPresentOnRequest = d.bool(forKey: "autoPresentOnRequest")
        playSound = d.bool(forKey: "playSound")
        showPanel = d.bool(forKey: "showPanel")
        notifyOnStop = d.bool(forKey: "notifyOnStop")
        port = d.integer(forKey: "port")
        toolMatcher = d.string(forKey: "toolMatcher") ?? Settings.defaultMatcher
        autoPassPrefixes = d.string(forKey: "autoPassPrefixes") ?? ""
        if port <= 0 || port > 65535 { port = Settings.defaultPort }
        if approvalTimeout < 5 || approvalTimeout > 55 { approvalTimeout = 20 }
        // Migrate removed pets (cat/dog) from older versions.
        if PetKind(rawValue: petID) == nil { petID = "penguin" }
    }

    var theme: Theme { Theme.resolve(settings: self) }
    var pet: PetKind { PetKind(rawValue: petID) ?? .penguin }
    var expandedLayoutIsBars: Bool { expandedLayout != "stats" }
    var resetStyleIsClock: Bool { resetStyle == "clock" }
    var widgetModeIsFull: Bool { widgetMode != "compact" }
    var providerIncludesClaude: Bool { provider != "codex" }
    var providerIncludesCodex: Bool { provider == "codex" || provider == "both" }
    var displayMetric: DisplayMetric { DisplayMetric(rawValue: metric) ?? .totalTokens }
    var energy: PetEnergy { PetEnergy(rawValue: petEnergy) ?? .normal }
}

enum AppFmt {
    static let hourMinute: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    static let weekdayTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE HH:mm"
        return f
    }()

    /// "↻1:42" / "↻2d15h" (time left) or "↻14:30" / "↻Sat 05:59" (clock).
    /// nil when there is no data for that window yet.
    static func resetDisplay(resetAt: Date?, hasData: Bool, clock: Bool) -> String? {
        guard hasData, let resetAt = resetAt else { return nil }
        let interval = resetAt.timeIntervalSinceNow
        if clock {
            let formatter = interval > 20 * 3600 ? weekdayTime : hourMinute
            return "↻" + formatter.string(from: resetAt)
        }
        if interval > 24 * 3600 {
            let days = Int(interval) / 86400
            let hours = (Int(interval) % 86400) / 3600
            return "↻\(days)d\(hours)h"
        }
        return "↻" + Fmt.remaining(interval)
    }
}
