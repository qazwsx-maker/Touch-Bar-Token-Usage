import AppKit
import SwiftUI
import ServiceManagement
import TBTCore

/// Closures the preferences UI needs from the app layer.
struct PrefsDeps {
    var installHook: (String, Bool) -> String
    var removeHook: () -> String
    var hookInstalled: () -> Bool
    var testApproval: () -> Void
    var serverStatus: () -> String
    var touchBarAvailable: () -> Bool
    var dataDirFound: () -> Bool
}

final class PreferencesWindowController: NSWindowController {
    init(settings: Settings, deps: PrefsDeps) {
        let hosting = NSHostingController(rootView: PrefsRootView(settings: settings, deps: deps))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Touch Bar Token Usage"
        window.styleMask = [.titled, .closable, .miniaturizable]
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if window?.isVisible != true {
            window?.center()
        }
        window?.makeKeyAndOrderFront(nil)
    }
}

struct PrefsRootView: View {
    @ObservedObject var settings: Settings
    let deps: PrefsDeps

    var body: some View {
        TabView {
            SetupTab(settings: settings, deps: deps)
                .tabItem { Label("Setup", systemImage: "checkmark.circle") }
            AppearanceTab(settings: settings)
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            ApprovalsTab(settings: settings, deps: deps)
                .tabItem { Label("Approvals", systemImage: "hand.raised") }
            GeneralTab(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding(12)
        .frame(width: 640, height: 600)
    }
}

// MARK: - Setup

struct SetupTab: View {
    @ObservedObject var settings: Settings
    let deps: PrefsDeps
    @State private var message = ""
    @State private var previewApproval = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("AI token usage on your Touch Bar — with one-tap Accept for Claude Code.")
                    .font(.headline)

                GroupBox(label: Text("Status")) {
                    VStack(alignment: .leading, spacing: 6) {
                        StatusRow(ok: deps.touchBarAvailable(),
                                  okText: "Touch Bar detected",
                                  failText: "No Touch Bar on this Mac — menu bar & on-screen panel still work")
                        StatusRow(ok: deps.dataDirFound(),
                                  okText: "Claude Code data found (~/.claude/projects)",
                                  failText: "~/.claude/projects not found — run Claude Code once, then relaunch")
                        StatusRow(ok: deps.hookInstalled(),
                                  okText: "Approval hook installed",
                                  failText: "Approval hook not installed — see step 2")
                        Text("Server: \(deps.serverStatus())")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox(label: Text("Touch Bar preview")) {
                    VStack(alignment: .leading, spacing: 8) {
                        WidgetPreview(settings: settings, alertDemo: previewApproval)
                            .frame(height: 46)
                        Toggle("Preview an approval request", isOn: $previewApproval)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox(label: Text("Get started")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. Keep this app running (🐾 lives in the menu bar).")
                        HStack(spacing: 8) {
                            Text("2.")
                            Button("Install Claude Code hook") {
                                message = deps.installHook(settings.toolMatcher, settings.notifyOnStop)
                            }
                            Text("→ lets you Accept/Deny from the Touch Bar")
                                .foregroundColor(.secondary)
                        }
                        HStack(spacing: 8) {
                            Text("3.")
                            Button("Send test approval request") { deps.testApproval() }
                            Text("→ should appear on the Touch Bar + panel")
                                .foregroundColor(.secondary)
                        }
                        if !message.isEmpty {
                            Text(message).font(.caption)
                        }
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(8)
        }
    }
}

struct StatusRow: View {
    let ok: Bool
    let okText: String
    let failText: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(ok ? Color.green : Color.orange)
                .frame(width: 9, height: 9)
            Text(ok ? okText : failText)
                .font(.callout)
        }
    }
}

// MARK: - Appearance

struct AppearanceTab: View {
    @ObservedObject var settings: Settings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupBox(label: Text("Preview")) {
                    WidgetPreview(settings: settings, alertDemo: false)
                        .frame(height: 46)
                        .padding(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox(label: Text("Theme")) {
                    VStack(alignment: .leading, spacing: 8) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)],
                                  alignment: .leading, spacing: 8) {
                            ForEach(ThemeSpec.presets) { spec in
                                ThemeSwatch(spec: spec, selected: settings.themeID == spec.id) {
                                    settings.themeID = spec.id
                                }
                            }
                            CustomThemeSwatch(selected: settings.themeID == "custom") {
                                settings.themeID = "custom"
                            }
                        }
                        if settings.themeID == "custom" {
                            HStack(spacing: 14) {
                                ColorPicker("Background", selection: colorBinding(\.customBackground))
                                ColorPicker("Text", selection: colorBinding(\.customText))
                                ColorPicker("Accent", selection: colorBinding(\.customAccent))
                                ColorPicker("Pet", selection: colorBinding(\.customPet))
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox(label: Text("Pet")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            ForEach(PetKind.allCases) { kind in
                                PetCell(settings: settings, kind: kind)
                            }
                        }
                        Picker("Animation energy", selection: $settings.petEnergy) {
                            ForEach(PetEnergy.allCases) { energy in
                                Text(energy.label).tag(energy.rawValue)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        Text("Your pet runs faster while tokens are burning 🔥")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(8)
        }
    }

    private func colorBinding(_ keyPath: ReferenceWritableKeyPath<Settings, String>) -> Binding<Color> {
        Binding<Color>(
            get: { Color(nsColor: NSColor(hexString: settings[keyPath: keyPath])) },
            set: { settings[keyPath: keyPath] = NSColor($0).hexString }
        )
    }
}

struct ThemeSwatch: View {
    let spec: ThemeSpec
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle().fill(color(spec.background))
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.gray.opacity(0.5), lineWidth: 1))
                Circle().fill(color(spec.accent)).frame(width: 14, height: 14)
                Circle().fill(color(spec.pet)).frame(width: 14, height: 14)
                Text(spec.name).font(.callout)
                Spacer(minLength: 0)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Color.accentColor.opacity(0.25) : Color.gray.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2))
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func color(_ hex: String) -> Color {
        Color(nsColor: NSColor(hexString: hex))
    }
}

struct CustomThemeSwatch: View {
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                Text("Custom").font(.callout)
                Spacer(minLength: 0)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Color.accentColor.opacity(0.25) : Color.gray.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct PetCell: View {
    @ObservedObject var settings: Settings
    let kind: PetKind

    private var selected: Bool { settings.petID == kind.rawValue }

    var body: some View {
        VStack(spacing: 4) {
            PetAnimPreview(kind: kind, color: NSColor(hexString: currentPetHex))
                .frame(width: 48, height: 32)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.black))
            Text(kind.displayName).font(.caption)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(selected ? Color.accentColor.opacity(0.25) : Color.gray.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2))
        .onTapGesture { settings.petID = kind.rawValue }
    }

    private var currentPetHex: String {
        if settings.themeID == "custom" { return settings.customPet }
        let spec = ThemeSpec.presets.first { $0.id == settings.themeID } ?? ThemeSpec.presets[0]
        return spec.pet
    }
}

struct PetAnimPreview: NSViewRepresentable {
    let kind: PetKind
    let color: NSColor

    func makeNSView(context: Context) -> AnimatedPetView {
        let view = AnimatedPetView(frame: NSRect(x: 0, y: 0, width: 48, height: 32))
        view.kind = kind
        view.color = color
        view.fps = 6
        view.running = true
        view.start()
        return view
    }

    func updateNSView(_ view: AnimatedPetView, context: Context) {
        view.kind = kind
        view.color = color
    }
}

/// Live rendering of the Control Strip widget, so themes/pets can be tuned
/// on any Mac (no Touch Bar needed).
struct WidgetPreview: NSViewRepresentable {
    @ObservedObject var settings: Settings
    var alertDemo: Bool

    func makeNSView(context: Context) -> WidgetPreviewView {
        WidgetPreviewView(settings: settings)
    }

    func updateNSView(_ view: WidgetPreviewView, context: Context) {
        view.alertDemo = alertDemo
        view.refresh()
    }
}

final class WidgetPreviewView: NSView {
    private let settings: Settings
    var alertDemo = false

    private var timer: Timer?
    private var frameIdx = 0
    private var phase = false
    private let imageView = NSImageView()

    init(settings: Settings) {
        self.settings = settings
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 44))
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = 8

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleNone
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        let t = Timer(timeInterval: 0.18, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.frameIdx += 1
            self.phase.toggle()
            self.refresh()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 320, height: 44) }

    func refresh() {
        let theme = settings.theme
        let pet = PetSprites.image(kind: settings.pet,
                                   frame: frameIdx,
                                   running: true,
                                   color: alertDemo ? .white : theme.pet)
        let content = WidgetRenderer.Content(
            line1: alertDemo ? "Bash · my-project" : "1.28M",
            line2: alertDemo ? "tap to review" : "$4.32 · 8.1K/m",
            alert: alertDemo,
            alertPhase: phase,
            toast: nil)
        imageView.image = WidgetRenderer.stripImage(theme: theme, petImage: pet, content: content)
    }

    deinit {
        timer?.invalidate()
    }
}

// MARK: - Approvals

struct ApprovalsTab: View {
    @ObservedObject var settings: Settings
    let deps: PrefsDeps
    @State private var message = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupBox(label: Text("Touch Bar approvals")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Enable Accept / Deny from Touch Bar", isOn: $settings.approvalsEnabled)
                        HStack {
                            Text("Wait for decision: \(Int(settings.approvalTimeout))s")
                                .frame(width: 165, alignment: .leading)
                            Slider(value: $settings.approvalTimeout, in: 5...55, step: 5)
                        }
                        Text("While waiting, Claude holds the tool call. If you don't tap anything, it falls back to the normal terminal prompt.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Toggle("Auto-open the Touch Bar panel on request", isOn: $settings.autoPresentOnRequest)
                        Toggle("Also show an on-screen panel", isOn: $settings.showPanel)
                        Toggle("Play a sound on new request", isOn: $settings.playSound)
                        Toggle("Toast when Claude finishes / notifies", isOn: $settings.notifyOnStop)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox(label: Text("Filters")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Tools (regex):")
                            TextField(Settings.defaultMatcher, text: $settings.toolMatcher)
                        }
                        HStack {
                            Text("Auto-pass Bash prefixes:")
                            TextField("git status, ls", text: $settings.autoPassPrefixes)
                        }
                        Text("Auto-passed commands skip the Touch Bar and use the normal permission flow immediately. Re-run “Install / Update Hook” after changing the tools regex.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox(label: Text("Claude Code hook")) {
                    VStack(alignment: .leading, spacing: 8) {
                        StatusRow(ok: deps.hookInstalled(),
                                  okText: "Hook installed in ~/.claude/settings.json",
                                  failText: "Hook not installed yet")
                        HStack(spacing: 8) {
                            Button("Install / Update Hook") {
                                message = deps.installHook(settings.toolMatcher, settings.notifyOnStop)
                            }
                            Button("Remove Hook") {
                                message = deps.removeHook()
                            }
                            Button("Send Test Request") { deps.testApproval() }
                        }
                        HStack {
                            Text("Local port:")
                            TextField("43917", text: portBinding)
                                .frame(width: 80)
                            Text(deps.serverStatus())
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if !message.isEmpty {
                            Text(message).font(.caption)
                        }
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(8)
        }
    }

    private var portBinding: Binding<String> {
        Binding(
            get: { String(settings.port) },
            set: { settings.port = Int($0) ?? Settings.defaultPort }
        )
    }
}

// MARK: - General

struct GeneralTab: View {
    @ObservedObject var settings: Settings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupBox(label: Text("Touch Bar widget")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Show widget on Touch Bar", isOn: $settings.showWidget)
                        Picker("Main line shows", selection: $settings.metric) {
                            ForEach(DisplayMetric.allCases) { metric in
                                Text(metric.label).tag(metric.rawValue)
                            }
                        }
                        Toggle("Second line: today's cost", isOn: $settings.showCostLine)
                        Toggle("Second line: burn rate", isOn: $settings.showRateLine)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox(label: Text("Menu bar")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Show token count next to the paw icon", isOn: $settings.menuBarShowsTokens)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox(label: Text("Startup")) {
                    VStack(alignment: .leading, spacing: 8) {
                        if #available(macOS 13.0, *) {
                            LaunchAtLoginToggle()
                        } else {
                            Text("Launch at login needs macOS 13+. On this macOS, add the app in System Preferences → Users & Groups → Login Items.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(8)
        }
    }
}

@available(macOS 13.0, *)
struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Launch at login", isOn: Binding(
            get: { enabled },
            set: { on in
                do {
                    if on {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    enabled = on
                } catch {
                    enabled = SMAppService.mainApp.status == .enabled
                }
            }
        ))
    }
}

// MARK: - About

struct AboutTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Touch Bar Token Usage").font(.title2).bold()
            Text("Version \(AppDelegate.version)")
                .foregroundColor(.secondary)
            Text("Shows Claude Code token usage on the MacBook Pro Touch Bar, with one-tap Accept/Deny for permission requests, themes, and a pixel pet that runs while your tokens burn.")
                .fixedSize(horizontal: false, vertical: true)
            Button("GitHub — qazwsx-maker/Touch-Bar-Token-Usage") {
                if let url = URL(string: "https://github.com/qazwsx-maker/Touch-Bar-Token-Usage") {
                    NSWorkspace.shared.open(url)
                }
            }
            Divider()
            Text("Uninstall: click “Remove Hook” in the Approvals tab, quit the app, delete it from /Applications, then remove ~/.claude/touchbar-usage.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Note: the Control Strip widget uses the same private DFRFoundation API as Pock/MTMR. If you run Pock, disable one of them.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
