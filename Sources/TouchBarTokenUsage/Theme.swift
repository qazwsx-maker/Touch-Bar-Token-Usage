import AppKit
import TBTCore

struct Theme {
    let background: NSColor
    let text: NSColor
    let secondaryText: NSColor
    let accent: NSColor
    let good: NSColor
    let bad: NSColor
    let pet: NSColor

    init(background: NSColor, text: NSColor, secondaryText: NSColor,
         accent: NSColor, good: NSColor, bad: NSColor, pet: NSColor) {
        self.background = background
        self.text = text
        self.secondaryText = secondaryText
        self.accent = accent
        self.good = good
        self.bad = bad
        self.pet = pet
    }

    init(spec: ThemeSpec) {
        self.init(background: NSColor(hexString: spec.background),
                  text: NSColor(hexString: spec.text),
                  secondaryText: NSColor(hexString: spec.secondaryText),
                  accent: NSColor(hexString: spec.accent),
                  good: NSColor(hexString: spec.good),
                  bad: NSColor(hexString: spec.bad),
                  pet: NSColor(hexString: spec.pet))
    }

    static func resolve(settings: Settings) -> Theme {
        if settings.themeID == "custom" {
            let text = NSColor(hexString: settings.customText)
            return Theme(background: NSColor(hexString: settings.customBackground),
                         text: text,
                         secondaryText: text.withAlphaComponent(0.55),
                         accent: NSColor(hexString: settings.customAccent),
                         good: .systemGreen,
                         bad: .systemRed,
                         pet: NSColor(hexString: settings.customPet))
        }
        let spec = ThemeSpec.presets.first { $0.id == settings.themeID } ?? ThemeSpec.presets[0]
        return Theme(spec: spec)
    }
}

extension NSColor {
    convenience init(hexString: String) {
        let c = HexColor.parse(hexString)
        self.init(srgbRed: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: CGFloat(c.a))
    }

    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        return HexColor.format(r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent))
    }
}
