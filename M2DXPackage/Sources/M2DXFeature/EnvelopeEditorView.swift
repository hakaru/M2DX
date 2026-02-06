// EnvelopeEditorView.swift
// DX7-style 4-Rate/4-Level envelope editor with Canvas drawing

import SwiftUI
import M2DXCore

// MARK: - Envelope Editor View

/// DX7-style envelope editor with draggable breakpoints
@MainActor
struct EnvelopeEditorView: View {
    @Binding var envelope: EnvelopeParameters
    var onChanged: ((EnvelopeParameters) -> Void)?

    /// Which breakpoint is currently being dragged (0-3)
    @State private var draggingPoint: Int?

    private let graphHeight: CGFloat = 120
    private let padding: CGFloat = 16

    var body: some View {
        VStack(spacing: 8) {
            Text("ENVELOPE")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)

            // Canvas graph
            Canvas { context, size in
                drawEnvelope(context: context, size: size)
            }
            .frame(height: graphHeight)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(white: 0.08))
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .gesture(envelopeDragGesture)

            // Rate/Level labels
            HStack(spacing: 0) {
                paramLabel("R1", value: Int(envelope.rate1 * 99))
                paramLabel("L1", value: Int(envelope.level1 * 99))
                paramLabel("R2", value: Int(envelope.rate2 * 99))
                paramLabel("L2", value: Int(envelope.level2 * 99))
                paramLabel("R3", value: Int(envelope.rate3 * 99))
                paramLabel("L3", value: Int(envelope.level3 * 99))
                paramLabel("R4", value: Int(envelope.rate4 * 99))
                paramLabel("L4", value: Int(envelope.level4 * 99))
            }
        }
    }

    // MARK: - Drawing

    private func drawEnvelope(context: GraphicsContext, size: CGSize) {
        let inset: CGFloat = 12
        let drawWidth = size.width - inset * 2
        let drawHeight = size.height - inset * 2

        // Calculate breakpoints
        let points = breakpoints(in: CGSize(width: drawWidth, height: drawHeight))

        // Start point (bottom-left)
        let startPoint = CGPoint(x: inset, y: size.height - inset)

        // Offset points by inset
        let offsetPoints = points.map {
            CGPoint(x: $0.x + inset, y: $0.y + inset)
        }

        // Draw sustain region (dotted line between point 2 and point 3)
        if offsetPoints.count >= 4 {
            let sustainY = offsetPoints[2].y
            var sustainPath = Path()
            sustainPath.move(to: offsetPoints[2])
            sustainPath.addLine(to: CGPoint(x: offsetPoints[2].x + 20, y: sustainY))
            context.stroke(
                sustainPath,
                with: .color(.cyan.opacity(0.3)),
                style: StrokeStyle(lineWidth: 1, dash: [4, 4])
            )
        }

        // Draw envelope path
        var path = Path()
        path.move(to: startPoint)
        for point in offsetPoints {
            path.addLine(to: point)
        }
        // Extend to end (release goes to L4)
        let endX = size.width - inset
        if let lastPoint = offsetPoints.last {
            path.addLine(to: CGPoint(x: endX, y: lastPoint.y))
        }

        // Stroke
        context.stroke(
            path,
            with: .color(.cyan),
            lineWidth: 2
        )

        // Fill under curve
        var fillPath = path
        fillPath.addLine(to: CGPoint(x: endX, y: size.height - inset))
        fillPath.addLine(to: startPoint)
        fillPath.closeSubpath()
        context.fill(
            fillPath,
            with: .color(.cyan.opacity(0.1))
        )

        // Draw breakpoints
        for (index, point) in offsetPoints.enumerated() {
            let isActive = draggingPoint == index
            let radius: CGFloat = isActive ? 8 : 6
            let rect = CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.fill(
                Path(ellipseIn: rect),
                with: .color(isActive ? .white : .cyan)
            )
            context.stroke(
                Path(ellipseIn: rect),
                with: .color(.white),
                lineWidth: 1
            )

            // Label
            let label = "L\(index + 1)"
            context.draw(
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.cyan.opacity(0.7)),
                at: CGPoint(x: point.x, y: point.y - 14)
            )
        }
    }

    /// Calculate breakpoint positions within the drawing area
    private func breakpoints(in size: CGSize) -> [CGPoint] {
        // Each rate determines the horizontal distance (higher rate = shorter time)
        // Each level determines the vertical position

        let segmentWidth = size.width / 4.5

        // Rate to width: higher rate = shorter segment
        func rateToWidth(_ rate: Double) -> CGFloat {
            let normalized = 1.0 - (rate / 99.0) * 0.8
            return segmentWidth * CGFloat(max(0.2, normalized))
        }

        func levelToY(_ level: Double) -> CGFloat {
            size.height * CGFloat(1.0 - level)
        }

        var x: CGFloat = 0

        // Point 0: Attack end (R1 → L1)
        x += rateToWidth(envelope.rate1 * 99)
        let p0 = CGPoint(x: x, y: levelToY(envelope.level1))

        // Point 1: Decay1 end (R2 → L2)
        x += rateToWidth(envelope.rate2 * 99)
        let p1 = CGPoint(x: x, y: levelToY(envelope.level2))

        // Point 2: Decay2/Sustain (R3 → L3)
        x += rateToWidth(envelope.rate3 * 99)
        let p2 = CGPoint(x: x, y: levelToY(envelope.level3))

        // Point 3: Release end (R4 → L4)
        x += rateToWidth(envelope.rate4 * 99)
        let p3 = CGPoint(x: x, y: levelToY(envelope.level4))

        return [p0, p1, p2, p3]
    }

    // MARK: - Drag Gesture

    private var envelopeDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let inset: CGFloat = 12
                let drawWidth: CGFloat = 300
                let drawHeight = graphHeight - inset * 2

                if draggingPoint == nil {
                    // Find nearest breakpoint
                    let location = value.startLocation
                    let points = breakpoints(in: CGSize(width: drawWidth, height: drawHeight))
                    var minDist: CGFloat = .infinity
                    var nearest = 0
                    for (i, p) in points.enumerated() {
                        let adjusted = CGPoint(x: p.x + inset, y: p.y + inset)
                        let dist = hypot(location.x - adjusted.x, location.y - adjusted.y)
                        if dist < minDist {
                            minDist = dist
                            nearest = i
                        }
                    }
                    if minDist < 40 {
                        draggingPoint = nearest
                    }
                }

                guard let point = draggingPoint else { return }

                // Map drag translation to parameter changes
                let deltaY = -value.translation.height / drawHeight
                let deltaX = -value.translation.width / drawHeight * 0.5

                switch point {
                case 0:
                    envelope.level1 = clamp01(envelope.level1 + deltaY * 0.02)
                    envelope.rate1 = clamp01(envelope.rate1 + deltaX * 0.02)
                case 1:
                    envelope.level2 = clamp01(envelope.level2 + deltaY * 0.02)
                    envelope.rate2 = clamp01(envelope.rate2 + deltaX * 0.02)
                case 2:
                    envelope.level3 = clamp01(envelope.level3 + deltaY * 0.02)
                    envelope.rate3 = clamp01(envelope.rate3 + deltaX * 0.02)
                case 3:
                    envelope.level4 = clamp01(envelope.level4 + deltaY * 0.02)
                    envelope.rate4 = clamp01(envelope.rate4 + deltaX * 0.02)
                default:
                    break
                }

                onChanged?(envelope)
            }
            .onEnded { _ in
                draggingPoint = nil
            }
    }

    // MARK: - Helpers

    private func clamp01(_ value: Double) -> Double {
        max(0, min(1, value))
    }

    private func paramLabel(_ name: String, value: Int) -> some View {
        VStack(spacing: 2) {
            Text(name)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
    }
}
