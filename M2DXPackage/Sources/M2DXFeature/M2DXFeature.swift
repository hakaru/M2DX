// M2DXFeature.swift
// Main UI module for M2DX synthesizer

import SwiftUI
import M2DXCore

// MARK: - Main Content View

/// Root view for M2DX synthesizer
@MainActor
public struct M2DXRootView: View {
    @State private var engineState = M2DXEngineState()
    @State private var selectedOperator: Int = 1
    @State private var selectedModule: Int = 1

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Mode selector
                Picker("Engine Mode", selection: $engineState.mode) {
                    ForEach(SynthEngineMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                Divider()
                    .padding(.top, 8)

                // Content based on mode
                switch engineState.mode {
                case .m2dx8op:
                    M2DX8OpView(
                        voice: $engineState.m2dxVoice,
                        selectedOperator: $selectedOperator
                    )
                case .tx816:
                    TX816View(
                        config: $engineState.tx816Config,
                        selectedModule: $selectedModule
                    )
                }
            }
            .navigationTitle("M2DX")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Init Voice") {
                            initializeVoice()
                        }
                        Divider()
                        Button("Load Preset...") { }
                        Button("Save Preset...") { }
                    } label: {
                        Image(systemName: "doc.badge.gearshape")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Text(currentVoiceName)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var currentVoiceName: String {
        switch engineState.mode {
        case .m2dx8op:
            return engineState.m2dxVoice.name
        case .tx816:
            return "TX816"
        }
    }

    private func initializeVoice() {
        switch engineState.mode {
        case .m2dx8op:
            engineState.m2dxVoice = M2DXVoice()
        case .tx816:
            engineState.tx816Config = TX816Configuration()
        }
    }
}

// MARK: - M2DX 8-Operator View

/// View for M2DX native 8-operator mode
struct M2DX8OpView: View {
    @Binding var voice: M2DXVoice
    @Binding var selectedOperator: Int

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Algorithm display
                AlgorithmView(
                    algorithm: voice.algorithm,
                    operatorCount: 8
                )
                .frame(height: 100)
                .padding(.horizontal)

                Divider()

                // 8 Operator grid (2 rows × 4 columns)
                OperatorGridView8Op(
                    operators: $voice.operators,
                    selectedOperator: $selectedOperator
                )
                .padding(.horizontal)

                Divider()

                // Parameter section
                if let opIndex = voice.operators.firstIndex(where: { $0.id == selectedOperator }) {
                    OperatorDetailView(
                        op: $voice.operators[opIndex]
                    )
                    .padding(.horizontal)
                }

                Spacer(minLength: 20)
            }
            .padding(.top)
        }
    }
}

// MARK: - TX816 View

/// View for TX816 simulation mode
struct TX816View: View {
    @Binding var config: TX816Configuration
    @Binding var selectedModule: Int

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Module rack display
                TX816RackView(
                    modules: $config.modules,
                    selectedModule: $selectedModule
                )
                .padding(.horizontal)

                Divider()

                // Selected module detail
                if let moduleIndex = config.modules.firstIndex(where: { $0.id == selectedModule }) {
                    TX816ModuleDetailView(
                        module: $config.modules[moduleIndex]
                    )
                    .padding(.horizontal)
                }

                Spacer(minLength: 20)
            }
            .padding(.top)
        }
    }
}

// MARK: - Algorithm View

/// Displays the current FM algorithm routing
struct AlgorithmView: View {
    let algorithm: M2DXAlgorithm
    let operatorCount: Int

    var body: some View {
        VStack {
            HStack {
                Text("Algorithm \(algorithm.rawValue)")
                    .font(.title3)
                    .fontWeight(.semibold)

                if algorithm.isExtended {
                    Text("8-OP")
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }

            // Placeholder for algorithm diagram
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
                .overlay {
                    Text("\(operatorCount)-OP Algorithm Diagram")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
        }
    }
}

// MARK: - 8-Operator Grid View

/// Grid displaying all 8 operators (2×4 layout)
struct OperatorGridView8Op: View {
    @Binding var operators: [OperatorParameters]
    @Binding var selectedOperator: Int

    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(0..<8, id: \.self) { index in
                if index < operators.count {
                    OperatorCell(
                        operatorIndex: index + 1,
                        parameters: $operators[index],
                        isSelected: selectedOperator == index + 1
                    )
                    .onTapGesture {
                        selectedOperator = index + 1
                    }
                }
            }
        }
    }
}

// MARK: - Operator Cell

/// Single operator display cell
struct OperatorCell: View {
    let operatorIndex: Int
    @Binding var parameters: OperatorParameters
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            Text("OP\(operatorIndex)")
                .font(.caption)
                .fontWeight(.bold)

            // Level indicator
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.quaternary)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(operatorColor.gradient)
                        .frame(height: geometry.size.height * parameters.level)
                }
            }
            .frame(width: 24, height: 50)

            Text("\(Int(parameters.level * 99))")
                .font(.caption2.monospacedDigit())

            Text("×\(parameters.frequencyRatio, specifier: "%.1f")")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? operatorColor.opacity(0.15) : Color.clear)
                .stroke(isSelected ? operatorColor : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
        }
    }

    private var operatorColor: Color {
        switch operatorIndex {
        case 1, 2: return .blue
        case 3, 4: return .cyan
        case 5, 6: return .teal
        case 7, 8: return .mint
        default: return .blue
        }
    }
}

// MARK: - Operator Detail View

/// Detailed parameter view for selected operator
struct OperatorDetailView: View {
    @Binding var op: OperatorParameters

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Operator \(op.id)")
                .font(.headline)

            // Level & Ratio
            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("Level")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $op.level, in: 0...1)
                    Text("\(Int(op.level * 99))")
                        .font(.caption.monospacedDigit())
                }

                VStack(alignment: .leading) {
                    Text("Ratio")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $op.frequencyRatio, in: 0.5...16)
                    Text("×\(op.frequencyRatio, specifier: "%.2f")")
                        .font(.caption.monospacedDigit())
                }
            }

            // Detune & Velocity
            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("Detune")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: .init(
                        get: { Double(op.detune) },
                        set: { op.detune = Int($0) }
                    ), in: -50...50, step: 1)
                    Text("\(op.detune > 0 ? "+" : "")\(op.detune)")
                        .font(.caption.monospacedDigit())
                }

                VStack(alignment: .leading) {
                    Text("Vel Sens")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $op.velocitySensitivity, in: 0...1)
                    Text("\(Int(op.velocitySensitivity * 100))%")
                        .font(.caption.monospacedDigit())
                }
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary.opacity(0.5))
        }
    }
}

// MARK: - TX816 Rack View

/// Display of 8 TX816 modules
struct TX816RackView: View {
    @Binding var modules: [TX816Module]
    @Binding var selectedModule: Int

    var body: some View {
        VStack(spacing: 8) {
            Text("TX816 RACK")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(0..<8, id: \.self) { index in
                    if index < modules.count {
                        TX816ModuleCell(
                            module: $modules[index],
                            isSelected: selectedModule == index + 1
                        )
                        .onTapGesture {
                            selectedModule = index + 1
                        }
                    }
                }
            }
        }
    }
}

// MARK: - TX816 Module Cell

/// Single TX816 module cell
struct TX816ModuleCell: View {
    @Binding var module: TX816Module
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text("TF\(module.id)")
                .font(.caption2)
                .fontWeight(.bold)

            // Volume meter
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.quaternary)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(module.enabled ? Color.green.gradient : Color.gray.gradient)
                        .frame(height: geometry.size.height * module.volume)
                }
            }
            .frame(width: 16, height: 40)

            Text("CH\(module.midiChannel)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

            // Enable toggle
            Image(systemName: module.enabled ? "power.circle.fill" : "power.circle")
                .font(.caption)
                .foregroundStyle(module.enabled ? .green : .secondary)
        }
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.orange.opacity(0.15) : Color.clear)
                .stroke(isSelected ? Color.orange : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
        }
    }
}

// MARK: - TX816 Module Detail View

/// Detailed view for selected TX816 module
struct TX816ModuleDetailView: View {
    @Binding var module: TX816Module

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Module TF\(module.id)")
                    .font(.headline)

                Spacer()

                Toggle("Enabled", isOn: $module.enabled)
                    .labelsHidden()
            }

            // Voice name
            Text(module.voice.name)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Volume & Pan
            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("Volume")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $module.volume, in: 0...1)
                    Text("\(Int(module.volume * 100))%")
                        .font(.caption.monospacedDigit())
                }

                VStack(alignment: .leading) {
                    Text("Pan")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $module.pan, in: -1...1)
                    Text(panLabel)
                        .font(.caption.monospacedDigit())
                }
            }

            // MIDI Channel & Note Shift
            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("MIDI Ch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $module.midiChannel) {
                        ForEach(1...16, id: \.self) { ch in
                            Text("\(ch)").tag(ch)
                        }
                    }
                    .pickerStyle(.menu)
                }

                VStack(alignment: .leading) {
                    Text("Note Shift")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: .init(
                        get: { Double(module.noteShift) },
                        set: { module.noteShift = Int($0) }
                    ), in: -24...24, step: 1)
                    Text("\(module.noteShift > 0 ? "+" : "")\(module.noteShift)")
                        .font(.caption.monospacedDigit())
                }
            }

            // 6-operator preview
            HStack(spacing: 4) {
                ForEach(0..<6, id: \.self) { index in
                    if index < module.voice.operators.count {
                        MiniOperatorView(
                            level: module.voice.operators[index].level
                        )
                    }
                }
            }
            .padding(.top, 8)
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary.opacity(0.5))
        }
    }

    private var panLabel: String {
        if module.pan < -0.05 {
            return "L\(Int(abs(module.pan) * 100))"
        } else if module.pan > 0.05 {
            return "R\(Int(module.pan * 100))"
        } else {
            return "C"
        }
    }
}

// MARK: - Mini Operator View

/// Minimal operator view for TX816 module preview
struct MiniOperatorView: View {
    let level: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.quaternary)

                RoundedRectangle(cornerRadius: 2)
                    .fill(.blue.gradient)
                    .frame(height: geometry.size.height * level)
            }
        }
        .frame(width: 12, height: 30)
    }
}

// MARK: - Preview

#Preview("M2DX 8-OP") {
    M2DXRootView()
}
