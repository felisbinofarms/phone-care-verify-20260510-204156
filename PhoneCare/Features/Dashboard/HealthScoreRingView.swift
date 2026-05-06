import SwiftUI

struct HealthScoreRingView: View {
    let score: Int
    let lineWidth: CGFloat
    let size: CGFloat

    @State private var animatedProgress: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(score: Int, lineWidth: CGFloat = 12, size: CGFloat = 160) {
        self.score = score
        self.lineWidth = lineWidth
        self.size = size
    }

    private var targetProgress: Double {
        Double(max(0, min(100, score))) / 100.0
    }

    private var ringColor: Color {
        healthColor(for: score)
    }

    var body: some View {
        ZStack {
            // Background track
            Circle()
                .stroke(Color.pcBorder.opacity(0.3), lineWidth: lineWidth)

            // Progress arc
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // Center content
            VStack(spacing: PCTheme.Spacing.xs) {
                Text("\(score)")
                    .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
                    .foregroundStyle(ringColor)
                    .contentTransition(.numericText())
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)

                Text("Health Score")
                    .typography(.caption, color: .pcTextSecondary)
            }
        }
        .frame(width: size, height: size)
        .animation(reduceMotion ? .none : .easeOut(duration: 0.6), value: score)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Health score: \(score) out of 100")
        .accessibilityValue(scoreAccessibilityDescription)
        .onAppear {
            withAnimation(reduceMotion ? .none : .easeOut(duration: 1.0)) {
                animatedProgress = targetProgress
            }
        }
        .onChange(of: score) { _, newScore in
            // The outer .animation(value: score) modifier above drives the
            // transaction; assigning here lets the trim animate in the SAME
            // transaction as the ring color, eliminating the color-flash desync.
            animatedProgress = Double(max(0, min(100, newScore))) / 100.0
        }
    }

    private var scoreAccessibilityDescription: String {
        if score >= 76 {
            return "Excellent. Your phone is in great shape."
        } else if score >= HealthScoreCalculator.goodThreshold {
            return "Good. A few things could be tidied up."
        } else {
            return "Could be better. Some areas need attention."
        }
    }
}
