import SwiftUI

// MARK: - Circular Progress

struct CircularProgressView: View {
    let percent: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .inset(by: 2)
                .stroke(Color.gray.opacity(0.2), lineWidth: 3)
            Circle()
                .inset(by: 2)
                .trim(from: 0, to: CGFloat(min(percent, 1.0)))
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: percent)
            Text("\(Int(percent * 100))%")
                .font(.system(size: 9, weight: .bold))
                .monospacedDigit()
        }
    }
}

// MARK: - Multi-Segment Ring

struct RingSegment: Identifiable {
    let id = UUID()
    let name: String
    let value: Double
    let color: Color
}

struct RingArc: Identifiable {
    let id = UUID()
    let start: Double
    let end: Double
    let color: Color
}

struct MultiSegmentRingView: View {
    let segments: [RingSegment]

    var body: some View {
        ZStack {
            Circle()
                .inset(by: 4)
                .stroke(Color.gray.opacity(0.15), lineWidth: 6)

            ForEach(arcs()) { arc in
                Circle()
                    .inset(by: 4)
                    .trim(from: CGFloat(arc.start), to: CGFloat(arc.end))
                    .stroke(arc.color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: arc.end)
            }
        }
    }

    private func arcs() -> [RingArc] {
        let normalized = normalizedSegments()
        var start: Double = 0
        return normalized.map { segment in
            let end = start + segment.value
            let arc = RingArc(start: start, end: end, color: segment.color)
            start = end
            return arc
        }
    }

    private func normalizedSegments() -> [RingSegment] {
        let total = segments.reduce(0) { $0 + max(0, $1.value) }
        guard total > 0 else { return segments }
        return segments.map {
            RingSegment(name: $0.name, value: max(0, $0.value) / total, color: $0.color)
        }
    }
}
