import SwiftUI

enum Theme {
    static let bg      = Color(red: 0.020, green: 0.027, blue: 0.039)
    static let panel   = Color(red: 0.055, green: 0.078, blue: 0.094)
    static let glass   = Color(red: 0.070, green: 0.102, blue: 0.125).opacity(0.72)
    static let glass2  = Color(red: 0.094, green: 0.133, blue: 0.165).opacity(0.55)
    static let stroke  = Color(red: 0.24, green: 1.0, blue: 0.66).opacity(0.16)
    static let stroke2 = Color.white.opacity(0.07)
    static let green   = Color(red: 0.24, green: 1.0, blue: 0.66)
    static let greenDim = Color(red: 0.12, green: 0.62, blue: 0.41)
    static let text    = Color(red: 0.84, green: 0.90, blue: 0.87)
    static let bright  = Color(red: 0.92, green: 1.0, blue: 0.96)
    static let muted   = Color(red: 0.44, green: 0.54, blue: 0.50)
    static let red     = Color(red: 1.0, green: 0.42, blue: 0.42)
    static let warn    = Color(red: 1.0, green: 0.71, blue: 0.33)

    static let mono = "SF Mono"
    static func f(_ size: CGFloat, _ w: Font.Weight = .regular) -> Font {
        .system(size: size, weight: w, design: .monospaced)
    }
}

/// Glasflaeche mit Rand und Innenglanz.
struct GlassBG: ViewModifier {
    var radius: CGFloat = 14
    var fill: Color = Theme.glass
    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(fill)
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Theme.stroke, lineWidth: 1)
                )
        )
    }
}
extension View {
    func glass(_ radius: CGFloat = 14, fill: Color = Theme.glass) -> some View {
        modifier(GlassBG(radius: radius, fill: fill))
    }
}

/// Animierter Hintergrund: Verlauf plus Raster.
struct BackdropView: View {
    @State private var drift = false
    var body: some View {
        ZStack {
            Theme.bg
            RadialGradient(colors: [Theme.green.opacity(0.13), .clear],
                           center: .init(x: 0.22, y: 0.18), startRadius: 10, endRadius: 620)
            RadialGradient(colors: [Color(red: 0, green: 0.7, blue: 1).opacity(0.10), .clear],
                           center: .init(x: 0.82, y: 0.74), startRadius: 10, endRadius: 560)
            GridPattern()
                .stroke(Theme.green.opacity(0.075), lineWidth: 1)
                .mask(RadialGradient(colors: [.black, .clear],
                                     center: .center, startRadius: 60, endRadius: 720))
        }
        .ignoresSafeArea()
    }
}

struct GridPattern: Shape {
    var step: CGFloat = 44
    func path(in rect: CGRect) -> Path {
        var p = Path()
        var x: CGFloat = 0
        while x < rect.width { p.move(to: .init(x: x, y: 0)); p.addLine(to: .init(x: x, y: rect.height)); x += step }
        var y: CGFloat = 0
        while y < rect.height { p.move(to: .init(x: 0, y: y)); p.addLine(to: .init(x: rect.width, y: y)); y += step }
        return p
    }
}

/// Knopf im Terminal-Stil.
struct JPButton: ButtonStyle {
    var prominent = false
    var danger = false
    func makeBody(configuration: Configuration) -> some View {
        let accent = danger ? Theme.red : Theme.green
        configuration.label
            .font(Theme.f(11.5))
            .foregroundColor(prominent || danger ? accent : Theme.muted)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(prominent || danger
                          ? accent.opacity(configuration.isPressed ? 0.28 : 0.16)
                          : Color.white.opacity(configuration.isPressed ? 0.07 : 0.02))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(prominent || danger ? accent.opacity(0.4) : Theme.stroke2, lineWidth: 1))
            )
            .contentShape(Rectangle())
    }
}
