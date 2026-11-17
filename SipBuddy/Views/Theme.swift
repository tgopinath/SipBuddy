import SwiftUI
import AppKit

enum Theme {
    /// White in light mode, deep navy in dark mode.
    static let background = dynamic(light: NSColor.white,
                                    dark: NSColor(red: 0.04, green: 0.07, blue: 0.15, alpha: 1))
    static let card = dynamic(light: NSColor(red: 0.95, green: 0.97, blue: 0.99, alpha: 1),
                              dark: NSColor(red: 0.08, green: 0.13, blue: 0.24, alpha: 1))
    static let cardBorder = dynamic(light: NSColor(red: 0.86, green: 0.91, blue: 0.96, alpha: 1),
                                    dark: NSColor(red: 0.15, green: 0.22, blue: 0.36, alpha: 1))
    static let track = dynamic(light: NSColor(red: 0.88, green: 0.93, blue: 0.98, alpha: 1),
                               dark: NSColor(red: 0.13, green: 0.20, blue: 0.33, alpha: 1))
    static let aqua = Color(red: 0.36, green: 0.84, blue: 0.94)

    static func waterGradient(_ accent: Color) -> LinearGradient {
        LinearGradient(colors: [aqua, accent], startPoint: .top, endPoint: .bottom)
    }

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

struct CardModifier: ViewModifier {
    var padding: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.cardBorder, lineWidth: 1))
            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}

extension View {
    func card(padding: CGFloat = 14) -> some View { modifier(CardModifier(padding: padding)) }
}

/// Soft, tinted pill button with a little press bounce.
struct SoftButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .foregroundStyle(prominent ? AnyShapeStyle(Color.white) : AnyShapeStyle(.tint))
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(prominent ? AnyShapeStyle(.tint) : AnyShapeStyle(.tint.opacity(configuration.isPressed ? 0.22 : 0.12)))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

// MARK: - Water drop

struct DropShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r = rect.width / 2
        let cy = rect.maxY - r
        let k: CGFloat = 0.5523
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addCurve(to: CGPoint(x: rect.maxX, y: cy),
                   control1: CGPoint(x: rect.midX + r * 0.25, y: rect.minY + (cy - rect.minY) * 0.35),
                   control2: CGPoint(x: rect.maxX, y: cy - r * 0.75))
        p.addCurve(to: CGPoint(x: rect.midX, y: rect.maxY),
                   control1: CGPoint(x: rect.maxX, y: cy + r * k),
                   control2: CGPoint(x: rect.midX + r * k, y: rect.maxY))
        p.addCurve(to: CGPoint(x: rect.minX, y: cy),
                   control1: CGPoint(x: rect.midX - r * k, y: rect.maxY),
                   control2: CGPoint(x: rect.minX, y: cy + r * k))
        p.addCurve(to: CGPoint(x: rect.midX, y: rect.minY),
                   control1: CGPoint(x: rect.minX, y: cy - r * 0.75),
                   control2: CGPoint(x: rect.midX - r * 0.25, y: rect.minY + (cy - rect.minY) * 0.35))
        p.closeSubpath()
        return p
    }
}

/// The app's blue water drop, used wherever a drop icon appears.
struct BlueDrop: View {
    var size: CGFloat = 12
    var body: some View {
        DropShape()
            .fill(LinearGradient(colors: [Theme.aqua, Color(red: 0.14, green: 0.48, blue: 0.95)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: size * 0.76, height: size)
            .accessibilityHidden(true)
    }
}

struct WaveShape: Shape {
    var level: Double      // 0…1
    var phase: Double
    var amplitude: CGFloat = 3.5

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let clamped = min(max(level, 0), 1)
        let y0 = rect.maxY - rect.height * clamped
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        let steps = 40
        for i in 0...steps {
            let x = rect.minX + rect.width * CGFloat(i) / CGFloat(steps)
            let angle = (Double(i) / Double(steps)) * 2 * .pi * 1.3 + phase
            let amp = clamped <= 0 || clamped >= 1 ? 0 : amplitude
            p.addLine(to: CGPoint(x: x, y: y0 + CGFloat(sin(angle)) * amp))
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// A water drop that fills with a gently moving wave.
struct WaterDropView: View {
    var progress: Double
    var accent: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                DropShape().fill(Theme.track)
                WaveShape(level: progress, phase: t * 2.2, amplitude: 3)
                    .fill(Theme.aqua.opacity(0.55))
                    .clipShape(DropShape())
                WaveShape(level: progress, phase: t * 1.6 + 1.5)
                    .fill(Theme.waterGradient(accent))
                    .clipShape(DropShape())
                DropShape().stroke(accent.opacity(0.35), lineWidth: 1.5)
                // Highlight
                Capsule()
                    .fill(.white.opacity(0.55))
                    .frame(width: 5, height: 14)
                    .rotationEffect(.degrees(20))
                    .offset(x: -9, y: 4)
            }
        }
        .animation(.spring(response: 0.9, dampingFraction: 0.75), value: progress)
        .accessibilityLabel("Water level \(Int(progress * 100)) percent")
    }
}

struct ProgressRing: View {
    var progress: Double
    var accent: Color
    var lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            Circle().stroke(Theme.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(progress, 1))
                .stroke(AngularGradient(colors: [Theme.aqua, accent, Theme.aqua], center: .center),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.spring(response: 0.8, dampingFraction: 0.8), value: progress)
    }
}

// MARK: - Celebration

/// Drops and sparkles raining down when the daily goal is reached.
struct CelebrationView: View {
    private struct Particle {
        let x: CGFloat, delay: Double, speed: Double, size: CGFloat, symbol: String, spin: Double
    }
    private let particles: [Particle] = (0..<34).map { _ in
        Particle(x: .random(in: 0...1), delay: .random(in: 0...0.9), speed: .random(in: 180...320),
                 size: .random(in: 10...20), symbol: ["💧", "✨", "🎉", "💙"].randomElement()!,
                 spin: .random(in: -180...180))
    }
    @State private var start = Date()

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { context in
                let elapsed = context.date.timeIntervalSince(start)
                ZStack {
                    ForEach(particles.indices, id: \.self) { i in
                        let p = particles[i]
                        let t = max(0, elapsed - p.delay)
                        Text(p.symbol)
                            .font(.system(size: p.size))
                            .rotationEffect(.degrees(p.spin * t))
                            .position(x: p.x * geo.size.width, y: -20 + CGFloat(t * p.speed))
                            .opacity(t > 0 ? max(0, 1 - t / 3) : 0)
                    }
                }
            }
        }
        .onAppear { start = Date() }
    }
}
