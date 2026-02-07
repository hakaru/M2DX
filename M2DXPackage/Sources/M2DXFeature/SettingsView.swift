// SettingsView.swift
// Settings screen: Bluetooth MIDI, MIDI channel, tuning, audio, etc.

import SwiftUI
import AVFoundation
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

                // ── MIDI-CI Property Exchange ──
                propertyExchangeSection

                // ── MIDI Debug ──
                midiDebugSection

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

            // MIDI Input Source selection
            MIDIInputSourcePicker(midiInput: midiInput)

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

            // Output device
            HStack {
                Label("Output", systemImage: "speaker.badge.exclamationmark")
                Spacer()
                Text(audioEngine.currentOutputDevice)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            #if os(iOS)
            // iOS: AirPlay / Bluetooth output route picker
            AudioRoutePickerRow()
            #endif

            #if os(macOS)
            // macOS: Output device selection
            MacOutputDevicePicker(audioEngine: audioEngine)
            #endif

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

    // MARK: - Property Exchange Section

    private var propertyExchangeSection: some View {
        Section {
            // Discover button
            Button {
                Task { await midiInput.startCIDiscovery() }
            } label: {
                Label("Discover MIDI-CI Devices", systemImage: "magnifyingglass")
            }

            // Discovered PE devices
            if midiInput.discoveredPEDevices.isEmpty {
                HStack {
                    Image(systemName: "pianokeys.inverse")
                        .foregroundStyle(.secondary)
                    Text("No PE devices found")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            } else {
                ForEach(midiInput.discoveredPEDevices) { device in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.displayName)
                                .font(.body)
                            Text("MUID: \(device.muid)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Query") {
                            Task { await midiInput.queryRemoteProgramList(device: device) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(midiInput.isPEQueryInProgress)
                    }
                }
            }

            // PE status
            if !midiInput.peStatusMessage.isEmpty {
                HStack {
                    if midiInput.isPEQueryInProgress {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(midiInput.peStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Remote program list
            if !midiInput.remoteProgramList.isEmpty {
                DisclosureGroup("Programs (\(midiInput.remoteProgramList.count))") {
                    ForEach(midiInput.remoteProgramList) { program in
                        HStack {
                            Text("\(program.programNumber)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 30, alignment: .trailing)
                            Text(program.displayName)
                                .font(.body)
                        }
                    }
                }
            }
            // Sniffer mode toggle
            Toggle(isOn: Binding(
                get: { midiInput.peSnifferMode },
                set: { newValue in
                    midiInput.peSnifferMode = newValue
                    // Restart MIDI to apply mode change
                    midiInput.stop()
                    midiInput.start()
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PE Sniffer Mode")
                    Text("Disable PE Responder and log all CI traffic. Run alongside KORG Module to observe.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("MIDI-CI Property Exchange")
        } footer: {
            if midiInput.peSnifferMode {
                Text("Sniffer mode ON — PE Responder disabled. Use Console.app (subsystem: com.example.M2DX) to view logs.")
            } else {
                Text("Discover and query MIDI-CI PE devices for program lists.")
            }
        }
    }

    // MARK: - MIDI Debug Section

    private var midiDebugSection: some View {
        Section {
            // Detected sources
            VStack(alignment: .leading, spacing: 2) {
                Text("Sources at connect")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if midiInput.debugSources.isEmpty {
                    Text("(none detected)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.orange)
                } else {
                    ForEach(midiInput.debugSources, id: \.self) { src in
                        Text(src)
                            .font(.caption.monospaced())
                    }
                }
            }

            HStack {
                Text("Connected")
                Spacer()
                Text("\(midiInput.debugConnectedCount)")
                    .font(.caption.monospaced())
                    .foregroundStyle(midiInput.debugConnectedCount > 0 ? .green : .orange)
            }

            HStack {
                Text("Received msgs")
                Spacer()
                Text("\(midiInput.debugReceiveCount)")
                    .font(.caption.monospaced())
                    .foregroundStyle(midiInput.debugReceiveCount > 0 ? .green : .secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Last raw data")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(midiInput.debugLastReceived)
                    .font(.caption.monospaced())
                    .lineLimit(2)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Last event")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(midiInput.debugLastEvent)
                    .font(.caption.monospaced())
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Transport callback")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(midiInput.debugTransportCallback)
                    .font(.caption.monospaced())
                    .lineLimit(5)
            }

            // MIDI Message Log
            DisclosureGroup("Message Log (\(midiInput.debugLog.count))") {
                if midiInput.debugLog.isEmpty {
                    Text("(no messages)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(midiInput.debugLogReversed.prefix(100).enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 9, design: .monospaced))
                                .lineLimit(2)
                        }
                    }
                }
                HStack {
                    Button("Copy Log") {
                        let text = midiInput.debugLogReversed.joined(separator: "\n")
                        #if os(iOS)
                        UIPasteboard.general.string = text
                        #endif
                    }
                    .font(.caption)
                    Button("Clear Log") {
                        midiInput.clearDebugLog()
                    }
                    .font(.caption)
                }
            }

            // PE Flow Log — dedicated PE/CI communication history
            DisclosureGroup("PE Flow Log (\(midiInput.peFlowLog.count))") {
                if midiInput.peFlowLog.isEmpty {
                    Text("(no PE/CI traffic)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(midiInput.peFlowLog.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 9, design: .monospaced))
                                .lineLimit(3)
                        }
                    }
                }
                HStack {
                    Button("Copy PE Log") {
                        #if os(iOS)
                        UIPasteboard.general.string = midiInput.peFlowLogText
                        #endif
                    }
                    .font(.caption)
                    Button("Clear") {
                        midiInput.clearPEFlowLog()
                    }
                    .font(.caption)
                }
            }

            Button {
                midiInput.stop()
                midiInput.start()
            } label: {
                Label("Reconnect MIDI", systemImage: "arrow.triangle.2.circlepath")
            }
        } header: {
            Text("MIDI Debug")
        } footer: {
            Text("Diagnostic info for troubleshooting MIDI input.")
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

// MARK: - MIDI Input Source Picker

/// Picker for selecting which MIDI input device to receive from
struct MIDIInputSourcePicker: View {
    var midiInput: MIDIInputManager
    @State private var selectedName: String = "All"

    var body: some View {
        Picker(selection: Binding(
            get: { selectedName },
            set: { name in
                selectedName = name
                if name == "All" {
                    midiInput.selectSource(.all)
                } else {
                    midiInput.selectSource(.specific(name))
                }
            }
        )) {
            Text("All Sources").tag("All")
            ForEach(midiInput.availableSources) { source in
                HStack {
                    Text(source.name)
                    if source.isOnline {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(.green)
                    }
                }
                .tag(source.name)
            }
        } label: {
            Label("MIDI Input", systemImage: "cable.connector")
        }
        .onAppear {
            midiInput.refreshDeviceList()
            switch midiInput.selectedSourceMode {
            case .all:
                selectedName = "All"
            case .specific(let name):
                selectedName = name
            }
        }
    }
}

// MARK: - Audio Route Picker (iOS)

#if os(iOS)
import AVKit

/// Row that embeds the system AVRoutePickerView for AirPlay / Bluetooth output selection
struct AudioRoutePickerRow: View {
    var body: some View {
        HStack {
            Label("Output Route", systemImage: "airplayaudio")
            Spacer()
            RoutePickerViewWrapper()
                .frame(width: 40, height: 30)
        }
    }
}

/// Wraps AVRoutePickerView for SwiftUI
struct RoutePickerViewWrapper: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .systemCyan
        picker.activeTintColor = .systemCyan
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#endif

// MARK: - Output Device Picker (macOS)

#if os(macOS)
import CoreAudio

/// macOS output device picker using CoreAudio device enumeration
struct MacOutputDevicePicker: View {
    var audioEngine: M2DXAudioEngine
    @State private var devices: [(id: AudioDeviceID, name: String)] = []
    @State private var selectedDeviceName: String = ""

    var body: some View {
        Picker(selection: Binding(
            get: { selectedDeviceName },
            set: { name in
                selectedDeviceName = name
                if let device = devices.first(where: { $0.name == name }) {
                    audioEngine.setMacOutputDevice(device.id)
                }
            }
        )) {
            ForEach(devices, id: \.name) { device in
                Text(device.name).tag(device.name)
            }
        } label: {
            Label("Output Device", systemImage: "hifispeaker")
        }
        .onAppear {
            devices = audioEngine.listMacOutputDevices()
            selectedDeviceName = audioEngine.currentOutputDevice
        }
    }
}
#endif

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
