import SwiftUI
import UIKit

// Open Health: layered navy surfaces, mint accents and rounded system type.
// Color is semantic, not decorative: gray when nothing is going on, green when
// something is genuinely good, orange/red when there is a problem.

enum Obs {
    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { trait in
            let hex = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xff) / 255,
                green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255,
                alpha: 1)
        })
    }

    static let onAccent = adaptive(light: 0xffffff, dark: 0x090f1c)
    static let surface = adaptive(light: 0xffffff, dark: 0x141e30)
    static let elevated = adaptive(light: 0xe9f1fa, dark: 0x1b2940)
    static let lavender = adaptive(light: 0x7160bd, dark: 0xb8a9f6)
    static let coral = adaptive(light: 0xbd535f, dark: 0xf39ca8)
    static let blue = adaptive(light: 0x3d79bf, dark: 0x88b9fa)

    // Adaptive foregrounds retain contrast on both surfaces.
    static let paper = adaptive(light: 0xf3f6fb, dark: 0x090f1c)
    static let ink = adaptive(light: 0x17243a, dark: 0xf3f6fc)
    static let ink2 = adaptive(light: 0x485c76, dark: 0xc3cee0)
    static let muted = adaptive(light: 0x61738c, dark: 0x93a5c0)
    static let link = adaptive(light: 0x167568, dark: 0x80e0cc)
    static let rule = adaptive(light: 0xdce4ef, dark: 0x26334a)

    // Diagrams sit in the same ink family. Status uses the investing-post green/orange.
    static let chart = adaptive(light: 0x61738c, dark: 0x93a5c0)
    static let good = adaptive(light: 0x16826d, dark: 0x69dbbd)
    static let bad = adaptive(light: 0xb76523, dark: 0xf2b677)
    static let alert = adaptive(light: 0xbb4a48, dark: 0xff9296)

    // Back-compat names. `teal` is the quiet chart color; `yellow` is a problem.
    static var teal: Color { chart }
    static var yellow: Color { bad }
    static var warn: Color { bad }
    static var black: Color { paper }
    static var base: Color { paper }
    static var baseLow: Color { paper }
    static var trace: Color { rule }

    static var canvas: some View { paper.ignoresSafeArea() }

    // Sleep stages keep distinct hues (deep / light / REM / wake). Other charts
    // stay gray unless a value is actually good or a problem.
    static let deep = adaptive(light: 0x6358c5, dark: 0xa99cf6)
    static let light = adaptive(light: 0x8d9fe6, dark: 0x98b7f4)
    static let rem = adaptive(light: 0x16826d, dark: 0x69dbbd)
    static let wake = adaptive(light: 0xbe7b28, dark: 0xf0bd79)
    static func stage(_ s: Int) -> Color {
        switch s { case 1: return deep; case 2: return light; case 3: return rem; default: return wake }
    }

    /// Color a delta only when it is large enough to be worth noticing.
    static func tone(delta: Double?, goodWhenPositive: Bool = true, threshold: Double = 8) -> Color {
        guard let d = delta else { return chart }
        let isGood = d >= 0 ? goodWhenPositive : !goodWhenPositive
        if abs(d) < threshold { return chart }
        return isGood ? good : bad
    }

    static func debt(_ state: String) -> Color {
        switch state {
        case "none": return good
        case "low": return chart
        case "moderate": return bad
        case "high": return alert
        default: return chart
        }
    }

    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static func prose(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

struct ObsTag: View {
    let text: String
    var icon: String? = nil
    init(_ text: String, icon: String? = nil) { self.text = text; self.icon = icon }
    var body: some View {
        HStack(spacing: 7) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Obs.muted)
            }
            Text(text)
                .font(Obs.prose(12, .semibold))
                .tracking(0.3)
                .foregroundStyle(Obs.muted)
        }
    }
}

/// Hairline between home sections — the thomas.md rule, with air on both sides.
struct ObsRule: View {
    var body: some View {
        Rectangle().fill(Obs.rule).frame(height: 1)
            .padding(.top, 6).padding(.bottom, 2)
    }
}

struct ObsCard: ViewModifier {
    var padding: CGFloat = 18
    var radius: CGFloat = 24
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Obs.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Obs.rule, lineWidth: 1)
            )
    }
}

extension View {
    func obsCard(padding: CGFloat = 20, radius: CGFloat = 24) -> some View {
        modifier(ObsCard(padding: padding, radius: radius))
    }
}

struct ObsStat: View {
    let label: String
    let value: String
    var accent: Color = Obs.ink
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(Obs.mono(13)).foregroundStyle(Obs.ink2)
            Spacer(minLength: 16)
            Text(value).font(Obs.mono(15, .medium)).foregroundStyle(accent)
                .monospacedDigit()
        }
    }
}
