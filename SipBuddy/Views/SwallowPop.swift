import SwiftUI
import AppKit

/// A "+25 ml" that floats up and fades each time a swallow is counted.
struct SwallowPop: View {
    let count: Int
    let label: String
    var size: CGFloat = 20
    var playSound = false

    @State private var shown: [Int] = []

    var body: some View {
        ZStack {
            ForEach(shown, id: \.self) { n in
                PopText(label: label, size: size).id(n)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: count) { old, new in
            guard new > old else { return }
            shown.append(new)
            if playSound { NSSound(named: "Pop")?.play() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { shown.removeAll { $0 == new } }
        }
    }
}

private struct PopText: View {
    let label: String
    let size: CGFloat
    @State private var up = false

    var body: some View {
        Text(label)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.aqua)
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            .scaleEffect(up ? 1.15 : 0.7)
            .offset(y: up ? -size * 2.2 : 0)
            .opacity(up ? 0 : 1)
            .onAppear { withAnimation(.easeOut(duration: 1.1)) { up = true } }
    }
}
