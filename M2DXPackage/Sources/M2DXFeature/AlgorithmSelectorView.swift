// AlgorithmSelectorView.swift
// 4-column grid selector for DX7 32 algorithms with mini diagrams

import SwiftUI
import M2DXCore

// MARK: - Algorithm Selector View

/// Full-screen sheet displaying all 32 DX7 algorithms in a 4-column grid
@MainActor
struct AlgorithmSelectorView: View {
    /// Currently selected algorithm (0-31, 0-indexed)
    @Binding var selectedAlgorithm: Int
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(0..<32, id: \.self) { index in
                        AlgorithmMiniView(
                            algorithmNumber: index + 1,
                            isSelected: selectedAlgorithm == index
                        )
                        .onTapGesture {
                            selectedAlgorithm = index
                            dismiss()
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Algorithm")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Algorithm Mini View

/// Mini diagram of a single algorithm for the selector grid
struct AlgorithmMiniView: View {
    let algorithmNumber: Int
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text("\(algorithmNumber)")
                .font(.caption2.bold())

            Canvas { context, size in
                drawAlgorithm(context: context, size: size)
            }
            .frame(height: 60)
        }
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.cyan.opacity(0.15) : Color(white: 0.08))
                .stroke(isSelected ? Color.cyan : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
        }
    }

    private func drawAlgorithm(context: GraphicsContext, size: CGSize) {
        guard let def = DX7Algorithms.definition(for: algorithmNumber) else { return }

        let opSize: CGFloat = 12
        let spacing: CGFloat = 3

        // Calculate operator positions
        let positions = operatorPositions(def: def, size: size, opSize: opSize)

        // Draw connections first (behind operators)
        for conn in def.connections {
            guard let fromPos = positions[conn.from],
                  let toPos = positions[conn.to] else { continue }

            var path = Path()
            path.move(to: fromPos)
            path.addLine(to: toPos)
            context.stroke(path, with: .color(.gray.opacity(0.6)), lineWidth: 1)
        }

        // Draw feedback indicator
        if let fbPos = positions[def.feedbackOp] {
            let fbRadius: CGFloat = opSize * 0.8
            var fbPath = Path()
            fbPath.addArc(
                center: CGPoint(x: fbPos.x + fbRadius, y: fbPos.y - fbRadius * 0.3),
                radius: fbRadius * 0.5,
                startAngle: .degrees(180),
                endAngle: .degrees(0),
                clockwise: false
            )
            context.stroke(fbPath, with: .color(.cyan.opacity(0.4)), lineWidth: 0.8)
        }

        // Draw operators
        for opNum in 1...6 {
            guard let pos = positions[opNum] else { continue }
            let isCarrier = def.carriers.contains(opNum)
            let rect = CGRect(
                x: pos.x - opSize / 2,
                y: pos.y - opSize / 2,
                width: opSize,
                height: opSize
            )

            // Carrier = cyan, modulator = gray
            let color: Color = isCarrier ? .cyan : Color(white: 0.5)
            context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color.opacity(0.8)))
            context.stroke(Path(roundedRect: rect, cornerRadius: 2), with: .color(color), lineWidth: 0.5)

            // Op number
            context.draw(
                Text("\(opNum)")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(isCarrier ? .black : .white),
                at: pos
            )
        }
    }

    /// Calculate operator positions based on algorithm topology
    private func operatorPositions(
        def: DX7AlgorithmDefinition,
        size: CGSize,
        opSize: CGFloat
    ) -> [Int: CGPoint] {
        var positions: [Int: CGPoint] = [:]

        // Build adjacency: who modulates whom
        var children: [Int: [Int]] = [:]
        for conn in def.connections {
            children[conn.from, default: []].append(conn.to)
        }

        // Find root modulators (ops that are not modulated by anyone)
        var modulated = Set<Int>()
        for conn in def.connections {
            modulated.insert(conn.to)
        }

        // Build chains from top
        var chains: [[Int]] = []
        var visited = Set<Int>()

        // Start from carriers (bottom) and trace up
        for carrier in def.carriers.sorted() {
            var chain: [Int] = [carrier]
            visited.insert(carrier)
            // Find who modulates this carrier
            var current = carrier
            while true {
                var foundParent = false
                for conn in def.connections {
                    if conn.to == current && !visited.contains(conn.from) {
                        chain.insert(conn.from, at: 0)
                        visited.insert(conn.from)
                        current = conn.from
                        foundParent = true
                        break
                    }
                }
                if !foundParent { break }
            }
            chains.append(chain)
        }

        // Add any unvisited operators as standalone
        for op in 1...6 {
            if !visited.contains(op) {
                // Find which chain they belong to
                var placed = false
                for conn in def.connections where conn.from == op {
                    for (ci, chain) in chains.enumerated() {
                        if let idx = chain.firstIndex(of: conn.to) {
                            var newChain = chains[ci]
                            newChain.insert(op, at: idx)
                            chains[ci] = newChain
                            visited.insert(op)
                            placed = true
                            break
                        }
                    }
                    if placed { break }
                }
                if !placed {
                    chains.append([op])
                    visited.insert(op)
                }
            }
        }

        // Layout: each chain is a column, ops are placed vertically
        let numChains = max(chains.count, 1)
        let chainSpacing = size.width / CGFloat(numChains + 1)

        for (ci, chain) in chains.enumerated() {
            let x = chainSpacing * CGFloat(ci + 1)
            let numOps = max(chain.count, 1)
            let opSpacing = size.height / CGFloat(numOps + 1)

            for (oi, op) in chain.enumerated() {
                let y = opSpacing * CGFloat(oi + 1)
                positions[op] = CGPoint(x: x, y: y)
            }
        }

        return positions
    }
}
