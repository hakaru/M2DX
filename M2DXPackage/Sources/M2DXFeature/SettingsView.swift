// SettingsView.swift
// Settings screen: Bluetooth MIDI, MIDI channel, tuning, audio, etc.

import SwiftUI
#if os(iOS)
import CoreAudioKit
#endif

// MARK: - Settings View

@MainActor
struct SettingsView: View {
    var audioEngine: M2DXAudioEngine
    var midiInput: MIDIInputManager
    @Environment(\.dismiss) private var dismiss

    /// MIDI receive channel (0 = Omni, 1-16 = specific channel)
    @Binding var midiChannel: Int

    /// Master tuning offset in cents (-100 to +100)
    @Binding var masterTuning: Double

    #if os(iOS)
    /// Show Bluetooth MIDI sheet
    @State private var showBluetoothMIDI = false
    #endif

    var body: some View {
        NavigationStack {
            List {
                // ── MIDI Section ──
                midiSection

                // ── Audio Section ──
                audioSection

                // ── Tuning Section ──
                tuningSection

                // ── Connected Devices ──
                devicesSection

                // ── About ──
                aboutSection
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            #if os(iOS)
            .sheet(isPresented: $showBluetoothMIDI) {
                BluetoothMIDIView()
            }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 500)
        #endif
    }

    // MARK: - MIDI Section

    private var midiSection: some View {
        Section {
            #if os(iOS)
            // Bluetooth MIDI (iOS only)
            Button {
                showBluetoothMIDI = true
            } label: {
                HStack {
                    Label("Bluetooth MIDI", systemImage: "antenna.radiowaves.left.and.right")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
            #endif

            // MIDI Channel
            Picker(selection: $midiChannel) {
                Text("Omni (All)").tag(0)
                ForEach(1...16, id: \.self) { ch in
                    Text("Ch \(ch)").tag(ch)
                }
            } label: {
                Label("MIDI Channel", systemImage: "pianokeys")
            }
        } header: {
            Text("MIDI")
        } footer: {
            Text("Omni receives on all channels. Select a specific channel to filter.")
        }
    }

    // MARK: - Audio Section

    private var audioSection: some View {
        Section {
            // Master Volume
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label("Master Volume", systemImage: "speaker.wave.2")
                    Spacer()
                    Text("\(Int(audioEngine.masterVolume * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { Double(audioEngine.masterVolume) },
                        set: { audioEngine.masterVolume = Float($0) }
                    ),
                    in: 0...1
                )
            }

            // Engine status
            HStack {
                Label("Audio Engine", systemImage: "waveform")
                Spacer()
                Text(audioEngine.isRunning ? "Running" : "Stopped")
                    .foregroundStyle(audioEngine.isRunning ? .green : .red)
                    .font(.caption)
                Image(systemName: audioEngine.isRunning ? "circle.fill" : "circle")
                    .foregroundStyle(audioEngine.isRunning ? .green : .red)
                    .font(.system(size: 8))
            }
        } header: {
            Text("Audio")
        }
    }

    // MARK: - Tuning Section

    private var tuningSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label("Master Tuning", systemImage: "tuningfork")
                    Spacer()
                    Text("A4 = \(440.0 + masterTuning * 0.44, specifier: "%.1f") Hz")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $masterTuning, in: -100...100, step: 1)
                HStack {
                    Text("-100 ct")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if abs(masterTuning) > 0.5 {
                        Button("Reset") {
                            masterTuning = 0
                        }
                        .font(.caption)
                    }
                    Spacer()
                    Text("+100 ct")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Tuning")
        } footer: {
            Text("Adjust master tuning in cents. 0 = A4 at 440 Hz.")
        }
    }

    // MARK: - Devices Section

    private var devicesSection: some View {
        Section {
            if midiInput.connectedDevices.isEmpty {
                HStack {
                    Image(systemName: "cable.connector")
                        .foregroundStyle(.secondary)
                    Text("No MIDI devices connected")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(midiInput.connectedDevices, id: \.self) { device in
                    HStack {
                        Image(systemName: "cable.connector")
                            .foregroundStyle(.cyan)
                        Text(device)
                    }
                }
            }

            Button {
                midiInput.refreshDeviceList()
            } label: {
                Label("Refresh Devices", systemImage: "arrow.clockwise")
            }
        } header: {
            Text("Connected MIDI Devices")
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Build")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Engine")
                Spacer()
                Text("6-OP FM (DX7 Compatible)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            HStack {
                Text("Algorithms")
                Spacer()
                Text("32")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Polyphony")
                Spacer()
                Text("16 voices")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("About M2DX")
        }
    }
}

// MARK: - Bluetooth MIDI View (iOS only)

#if os(iOS)
/// Wraps CoreAudioKit's CABTMIDICentralViewController for Bluetooth MIDI pairing
struct BluetoothMIDIView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UINavigationController {
        let btVC = CABTMIDICentralViewController()
        let navVC = UINavigationController(rootViewController: btVC)
        navVC.navigationBar.prefersLargeTitles = false
        btVC.navigationItem.title = "Bluetooth MIDI"
        return navVC
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}
#endif
