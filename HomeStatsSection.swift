import SwiftUI
import Combine

struct HomeStatsSection: View {
    @StateObject private var progress = ReadingProgressStore.shared
    @Environment(\.horizontalSizeClass) private var hSizeClass

    @State private var showConfetti = false
    @State private var confettiItems: [ConfettiParticle] = []

    private var isCompact: Bool { hSizeClass == .compact }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 12) {
                // Tappable title with confetti
                Text("Stats")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .onTapGesture {
                        // trigger confetti burst
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                            showConfetti = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                            // size will be resolved in overlay Canvas using GeometryReader
                            showConfetti = true
                        }
                    }

                if isCompact {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            StatCard(
                                title: "Streak",
                                value: "\(progress.currentStreak()) days",
                                subtitle: "Current streak",
                                systemImage: "flame"
                            )
                            .frame(width: 180)

                            StatCard(
                                title: "Longest",
                                value: "\(progress.longestStreak()) days",
                                subtitle: "Longest streak",
                                systemImage: "crown"
                            )
                            .frame(width: 180)

                            StatCard(
                                title: "Today",
                                value: minutesText(progress.minutesReadTodayTotal()),
                                subtitle: "Reading time",
                                systemImage: "clock"
                            )
                            .frame(width: 180)

                            StatCard(
                                title: "Finished",
                                value: "\(progress.completedBooksTotal())",
                                subtitle: "Completed books",
                                systemImage: "checkmark.seal"
                            )
                            .frame(width: 180)

                            StatCard(
                                title: "This year",
                                value: "\(progress.booksFinishedThisYear())",
                                subtitle: "Books finished",
                                systemImage: "calendar"
                            )
                            .frame(width: 180)
                        }
                        .padding(.horizontal, 18)
                    }
                } else {
                    HStack(spacing: 12) {
                        StatCard(
                            title: "Streak",
                            value: "\(progress.currentStreak()) days",
                            subtitle: "Current streak",
                            systemImage: "flame"
                        )

                        StatCard(
                            title: "Longest",
                            value: "\(progress.longestStreak()) days",
                            subtitle: "Longest streak",
                            systemImage: "crown"
                        )

                        StatCard(
                            title: "Today",
                            value: minutesText(progress.minutesReadTodayTotal()),
                            subtitle: "Reading time",
                            systemImage: "clock"
                        )

                        StatCard(
                            title: "Finished",
                            value: "\(progress.completedBooksTotal())",
                            subtitle: "Completed books",
                            systemImage: "checkmark.seal"
                        )

                        StatCard(
                            title: "This year",
                            value: "\(progress.booksFinishedThisYear())",
                            subtitle: "Books finished",
                            systemImage: "calendar"
                        )
                    }
                    .padding(.horizontal, 18)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                }
            }

            GeometryReader { geo in
                if showConfetti {
                    Canvas { context, size in
                        // Simple gravity-like motion
                        for i in confettiItems.indices {
                            var p = confettiItems[i]
                            p.x += p.dx
                            p.y += p.dy
                            p.rotation += .degrees(Double.random(in: -4...4))
                            confettiItems[i] = p

                            let point = CGPoint(x: p.x, y: p.y)
                            var symbol = context.resolve(Text(Image(systemName: p.symbol)).font(.system(size: 10)))
                            context.opacity = 0.95
                            context.translateBy(x: point.x, y: point.y)
                            context.rotate(by: p.rotation)
                            context.scaleBy(x: 1.0, y: 1.0)
                            context.draw(symbol, at: .zero, anchor: .center)
                            context.transform = .identity
                        }

                        // Remove when offscreen
                        confettiItems.removeAll { $0.y > size.height + 40 || $0.x < -40 || $0.x > size.width + 40 }

                        if confettiItems.isEmpty {
                            showConfetti = false
                        }
                    }
                    .ignoresSafeArea()
                    .onAppear {
                        makeBurst(in: geo.size)
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    private func minutesText(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    private struct ConfettiParticle: Identifiable {
        let id = UUID()
        var x: CGFloat
        var y: CGFloat
        var dx: CGFloat
        var dy: CGFloat
        var rotation: Angle
        var color: Color
        var symbol: String
    }

    private func makeBurst(in size: CGSize) {
        confettiItems = (0..<22).map { _ in
            ConfettiParticle(
                x: size.width / 2,
                y: 0,
                dx: CGFloat.random(in: -2...2),
                dy: CGFloat.random(in: 0.5...2.5),
                rotation: .degrees(Double.random(in: 0...360)),
                color: [Color.pink, .orange, .yellow, .green, .mint, .cyan, .blue, .purple].randomElement()!,
                symbol: ["sparkles", "star.fill", "circle.fill", "heart.fill", "triangle.fill"].randomElement()!
            )
        }
        showConfetti = true
    }
}

private struct StatCard: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass

    @State private var tilt: CGSize = .zero
    @State private var shimmerPhase: CGFloat = 0

    let title: String
    let value: String
    let subtitle: String
    let systemImage: String

    private var isCompact: Bool { hSizeClass == .compact }
    private var titleFont: Font { .system(size: isCompact ? 13 : 14, weight: .semibold) }
    private var valueFont: Font { .system(size: isCompact ? 18 : 22, weight: .bold) }
    private var subtitleFont: Font { .system(size: isCompact ? 12 : 13, weight: .semibold) }
    private var pad: CGFloat { isCompact ? 12 : 14 }
    private var minHeight: CGFloat { isCompact ? 84 : 92 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))

                Text(title)
                    .font(titleFont)
                    .foregroundStyle(.white.opacity(0.9))
            }

            Text(value)
                .font(valueFont)
                .foregroundStyle(.white)

            Text(subtitle)
                .font(subtitleFont)
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(pad)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
        .background(
            ZStack {
                // Animated gradient background
                LinearGradient(
                    colors: [Color.white.opacity(0.06), Color.white.opacity(0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            .clear,
                            Color.white.opacity(0.05),
                            .clear
                        ]),
                        center: .center
                    )
                    .blur(radius: 24)
                )

                // Shimmer highlight
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                .clear,
                                Color.white.opacity(0.25),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .blendMode(.screen)
                    .rotationEffect(.degrees(20))
                    .offset(x: shimmerPhase * 220 - 110)
                    .onAppear {
                        withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
                            shimmerPhase = 1
                        }
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .rotation3DEffect(.degrees(Double(tilt.width) / -40), axis: (x: 0, y: 1, z: 0))
        .rotation3DEffect(.degrees(Double(tilt.height) / 40), axis: (x: 1, y: 0, z: 0))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        tilt = CGSize(width: v.translation.width.clamped(to: -12...12),
                                      height: v.translation.height.clamped(to: -12...12))
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        tilt = .zero
                    }
                }
        )
    }
}
private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

