// M2DXFeature.swift
// Main UI module for M2DX synthesizer

import SwiftUI
import M2DXCore

// MARK: - Main Content View

/// Root view for M2DX synthesizer with standalone audio capability
@MainActor
public struct M2DXRootView: View {
    @State private var audioEngine = M2DXAudioEngine()
    @State private var midiInput = MIDIInputManager()
    @State private var selectedOperator: Int = 1
    @State private var keyboardOctave: Int = 4
    @State private var showAlgorithmSelector = false
    @State private var showSettings = false
    @State private var showPresetPicker = false
    @State private var showKeyboard = true
    @State private var selectedPreset: DX7Preset?
    @State private var midiChannel: Int = 0
    @State private var masterTuning: Double = 0
    @State private var volumeCC: Double = 100
    @State private var expressionCC: Double = 127
    /// Guard to prevent feedback loop: MIDI CC → @State → onChange → updateCC
    @State private var ccFromMIDI = false
    @State private var feedbackValues: [Float] = Array(repeating: 0, count: 6)

    @State private var operatorEnvelopes: [EnvelopeParameters] = (0..<6).map { _ in
        EnvelopeParameters()
    }
    @State private var operators: [OperatorParameters] = (0..<6).map {
        OperatorParameters.defaultOperator(id: $0 + 1)
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // ── Scrollable content ──
            ScrollView {
                VStack(spacing: 10) {
                    headerBar
                    operatorStrip
                    operatorDetail
                    envelopeSection
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 12)
            }

            // ── Global Controls ──
            globalControlSection

            // ── Keyboard (show/hide) ──
            if showKeyboard {
                keyboardSection
            }
        }
        .background(Color.m2dxBackground)
        .task {
            // Apply INIT VOICE preset on launch
            let initPreset = DX7FactoryPresets.initVoice
            applyPreset(initPreset)
            selectedPreset = initPreset

            await audioEngine.start()
            midiInput.onNoteOn = { note, velocity16 in
                audioEngine.noteOn(note, velocity16: velocity16)
            }
            midiInput.onNoteOff = { note in
                audioEngine.noteOff(note)
            }
            midiInput.onControlChange = { controller, value32 in
                audioEngine.controlChange(controller, value32: value32)
                let normalized = Double(value32) / Double(UInt32.max) * 127.0
                ccFromMIDI = true
                switch controller {
                case 7: volumeCC = normalized
                case 11: expressionCC = normalized
                default: break
                }
                ccFromMIDI = false
            }
            midiInput.onPitchBend = { value32 in
                audioEngine.pitchBend(value32)
            }
            midiInput.onProgramChange = { program in
                let presets = DX7FactoryPresets.all
                let index = max(0, Int(program) - 1)
                guard index < presets.count else { return }
                let preset = presets[index]
                applyPreset(preset)
                selectedPreset = preset
            }
            midiInput.start()

            // Send initial CC values
            audioEngine.controlChange(7, value32: UInt32(volumeCC / 127.0 * Double(UInt32.max)))
            audioEngine.controlChange(11, value32: UInt32(expressionCC / 127.0 * Double(UInt32.max)))

            // Keep alive until view disappears (.task cancels automatically)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(86400))
            }
            midiInput.stop()
            audioEngine.stop()
        }
        .sheet(isPresented: $showAlgorithmSelector) {
            AlgorithmSelectorView(selectedAlgorithm: .init(
                get: { audioEngine.algorithm },
                set: { audioEngine.algorithm = $0 }
            ))
        }
        .sheet(isPresented: $showPresetPicker) {
            PresetPickerView(
                selectedPreset: $selectedPreset,
                onSelect: { preset in
                    applyPreset(preset)
                }
            )
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                audioEngine: audioEngine,
                midiInput: midiInput,
                midiChannel: $midiChannel,
                masterTuning: $masterTuning
            )
        }
        .onChange(of: midiChannel) { _, newValue in
            midiInput.receiveChannel = newValue
        }
    }

    // MARK: - Header Bar (single compact row)

    private var headerBar: some View {
        HStack(spacing: 8) {
            // Preset name
            Button {
                showPresetPicker = true
            } label: {
                Text(selectedPreset?.name ?? "INIT VOICE")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.cyan)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.cyan.opacity(0.1)))
            }

            // Algorithm
            Button {
                showAlgorithmSelector = true
            } label: {
                HStack(spacing: 4) {
                    Text("ALG")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(audioEngine.algorithm + 1)")
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(.cyan)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(.cyan.opacity(0.1)))
            }

            Spacer()

            // Status indicators
            HStack(spacing: 6) {
                // MIDI
                Image(systemName: "pianokeys")
                    .font(.system(size: 10))
                    .foregroundStyle(midiInput.isConnected ? .cyan : .secondary.opacity(0.4))

                // Audio
                Image(systemName: audioEngine.isRunning ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(audioEngine.isRunning ? .green : .red)
            }

            // Keyboard toggle
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showKeyboard.toggle()
                }
            } label: {
                Image(systemName: showKeyboard ? "pianokeys.inverse" : "pianokeys")
                    .font(.system(size: 12))
                    .foregroundStyle(showKeyboard ? .cyan : .secondary)
            }

            // Settings
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Operator Strip (horizontal 1x6)

    private var operatorStrip: some View {
        HStack(spacing: 6) {
            ForEach(0..<6, id: \.self) { index in
                CompactOperatorCell(
                    index: index + 1,
                    level: operators[index].level,
                    ratio: operators[index].frequencyRatio,
                    isSelected: selectedOperator == index + 1
                )
                .onTapGesture {
                    selectedOperator = index + 1
                }
            }
        }
    }

    // MARK: - Operator Detail

    private var operatorDetail: some View {
        let i = selectedOperator - 1
        return VStack(spacing: 8) {
            // Title row
            HStack {
                Text("OP\(selectedOperator)")
                    .font(.caption.bold())
                    .foregroundStyle(.cyan)
                Spacer()
            }

            // Level + Ratio
            HStack(spacing: 12) {
                paramSlider(label: "Level", value: $operators[i].level, range: 0...1,
                            display: "\(Int(operators[i].level * 99))") {
                    audioEngine.setOperatorLevel(i, level: Float($0))
                }
                paramSlider(label: "Ratio", value: $operators[i].frequencyRatio, range: 0.5...16,
                            display: "\u{00D7}\(String(format: "%.2f", operators[i].frequencyRatio))") {
                    audioEngine.setOperatorRatio(i, ratio: Float($0))
                }
            }

            // Detune + Feedback
            HStack(spacing: 12) {
                // Detune
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Detune")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(operators[i].detune > 0 ? "+" : "")\(operators[i].detune)")
                            .font(.system(size: 9, design: .monospaced))
                    }
                    Slider(value: .init(
                        get: { Double(operators[i].detune) },
                        set: { operators[i].detune = Int($0) }
                    ), in: -50...50, step: 1)
                    .controlSize(.mini)
                    .onChange(of: operators[i].detune) { _, newValue in
                        audioEngine.setOperatorDetune(i, cents: Float(newValue))
                    }
                }

                // Feedback
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Feedback")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(feedbackValues[i], specifier: "%.2f")")
                            .font(.system(size: 9, design: .monospaced))
                    }
                    Slider(value: feedbackBinding(for: i), in: 0...1)
                        .controlSize(.mini)
                }
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.m2dxSecondaryBackground)
        }
    }

    // MARK: - Envelope Section

    private var envelopeSection: some View {
        let i = selectedOperator - 1
        return EnvelopeEditorView(
            envelope: $operatorEnvelopes[i],
            onChanged: { env in
                audioEngine.setOperatorEGRates(
                    i,
                    r1: Float(env.rate1 * 99),
                    r2: Float(env.rate2 * 99),
                    r3: Float(env.rate3 * 99),
                    r4: Float(env.rate4 * 99)
                )
                audioEngine.setOperatorEGLevels(
                    i,
                    l1: Float(env.level1),
                    l2: Float(env.level2),
                    l3: Float(env.level3),
                    l4: Float(env.level4)
                )
            }
        )
    }

    // MARK: - Global Control Section

    private var globalControlSection: some View {
        VStack(spacing: 4) {
            Divider()
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Text("Vol")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .trailing)
                    Slider(value: $volumeCC, in: 0...127, step: 1)
                        .frame(minWidth: 80)
                    Text("\(Int(volumeCC))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)
                }
                HStack(spacing: 6) {
                    Text("Exp")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .trailing)
                    Slider(value: $expressionCC, in: 0...127, step: 1)
                        .frame(minWidth: 80)
                    Text("\(Int(expressionCC))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)
                }
                Button {
                    midiInput.stop()
                    midiInput.start()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .background(Color.m2dxSecondaryBackground)
        .onChange(of: volumeCC) { _, newValue in
            guard !ccFromMIDI else { return }
            let v32 = UInt32(newValue / 127.0 * Double(UInt32.max))
            audioEngine.controlChange(7, value32: v32)
            midiInput.updateCC(7, value: Int(newValue))
        }
        .onChange(of: expressionCC) { _, newValue in
            guard !ccFromMIDI else { return }
            let v32 = UInt32(newValue / 127.0 * Double(UInt32.max))
            audioEngine.controlChange(11, value32: v32)
            midiInput.updateCC(11, value: Int(newValue))
        }
    }

    // MARK: - Keyboard Section

    private var keyboardSection: some View {
        VStack(spacing: 0) {
            Divider()
            if audioEngine.isRunning {
                MIDIKeyboardView(
                    octave: $keyboardOctave,
                    octaveCount: 2,
                    onNoteOn: { note, velocity in
                        audioEngine.noteOn(note, velocity16: UInt16(velocity) << 9)
                    },
                    onNoteOff: { note in
                        audioEngine.noteOff(note)
                    }
                )
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            } else if let error = audioEngine.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(8)
            } else {
                ProgressView("Starting...")
                    .font(.caption)
                    .padding(8)
            }
        }
        .background(Color.m2dxSecondaryBackground)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Helpers

    private func paramSlider(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        display: String,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(display)
                    .font(.system(size: 9, design: .monospaced))
            }
            Slider(value: value, in: range)
                .controlSize(.mini)
                .onChange(of: value.wrappedValue) { _, newValue in
                    onChange(newValue)
                }
        }
    }

    private func feedbackBinding(for opIndex: Int) -> Binding<Double> {
        .init(
            get: { Double(feedbackValues[opIndex]) },
            set: { newValue in
                feedbackValues[opIndex] = Float(newValue)
                audioEngine.setOperatorFeedback(opIndex, feedback: Float(newValue))
            }
        )
    }

    // MARK: - Preset Application

    /// Apply a DX7 preset to the audio engine and update all UI state
    private func applyPreset(_ preset: DX7Preset) {
        // Load into audio engine
        audioEngine.loadPreset(preset)

        // Update UI state to reflect preset parameters
        for (i, op) in preset.operators.enumerated() {
            guard i < 6 else { break }

            // Operator parameters
            operators[i] = OperatorParameters(
                id: i + 1,
                level: Double(op.normalizedLevel),
                frequencyRatio: Double(op.frequencyRatio),
                detune: Int(op.detuneCents)
            )

            // Envelope parameters (normalized 0.0-1.0 for UI)
            operatorEnvelopes[i] = EnvelopeParameters(
                rate1: Double(op.egRate1) / 99.0,
                rate2: Double(op.egRate2) / 99.0,
                rate3: Double(op.egRate3) / 99.0,
                rate4: Double(op.egRate4) / 99.0,
                level1: Double(op.egLevel1) / 99.0,
                level2: Double(op.egLevel2) / 99.0,
                level3: Double(op.egLevel3) / 99.0,
                level4: Double(op.egLevel4) / 99.0
            )

            // Feedback values
            feedbackValues[i] = op.feedback > 0 ? Float(op.feedback) / 7.0 : 0
        }
    }
}

// MARK: - Compact Operator Cell (horizontal strip)

/// Slim operator cell for horizontal 1x6 layout
struct CompactOperatorCell: View {
    let index: Int
    let level: Double
    let ratio: Double
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 3) {
            Text("OP\(index)")
                .font(.system(size: 8, weight: .bold))

            // Level bar
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.quaternary)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.gradient)
                        .frame(height: geo.size.height * level)
                }
            }
            .frame(height: 32)

            Text("\(Int(level * 99))")
                .font(.system(size: 8, design: .monospaced))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .padding(.horizontal, 2)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? color.opacity(0.15) : Color.clear)
                .stroke(isSelected ? color : Color.secondary.opacity(0.2), lineWidth: isSelected ? 1.5 : 0.5)
        }
    }

    private var color: Color {
        switch index {
        case 1, 2: return .blue
        case 3, 4: return .cyan
        case 5, 6: return .teal
        default: return .blue
        }
    }
}

// MARK: - Preview

#Preview("M2DX Synthesizer") {
    M2DXRootView()
}
