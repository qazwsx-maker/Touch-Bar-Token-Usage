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
    var displayMetric: DisplayMetric { DisplayMetric(rawValue: metric) ?? .totalTokens }
    var energy: PetEnergy { PetEnergy(rawValue: petEnergy) ?? .normal }
}

enum AppFmt {
    static let hourMinute: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}
