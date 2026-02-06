// MIDIInputManager.swift
// External MIDI device input via MIDI2Kit with MIDI 2.0 UMP support

import Foundation
import MIDI2Kit

// MARK: - MIDI Source Types

/// Represents a MIDI input source for the selection UI
public struct MIDISourceItem: Identifiable, Hashable, Sendable {
    public let id: String       // unique identifier (name-based)
    public let name: String     // display name
    public let isOnline: Bool   // connection status
}

/// MIDI source selection mode
public enum MIDISourceMode: Equatable, Sendable {
    case all                    // receive from all sources (Omni)
    case specific(String)       // receive from a specific source by name
}

// MARK: - MIDI Input Manager

/// Manages external MIDI device connections and routes events to the audio engine
@MainActor
@Observable
public final class MIDIInputManager {

    // MARK: - Properties

    /// MIDI2Kit transport
    private var transport: CoreMIDITransport?

    /// Task for receiving MIDI data
    private var receiveTask: Task<Void, Never>?

    /// Whether MIDI is initialized
    public private(set) var isConnected: Bool = false

    /// Connected device names
    public private(set) var connectedDevices: [String] = []

    /// Available MIDI source devices (for selection UI)
    public private(set) var availableSources: [MIDISourceItem] = []

    /// Selected source mode: .all or .specific(name)
    public var selectedSourceMode: MIDISourceMode = .all

    /// Last error message
    public private(set) var errorMessage: String?

    /// MIDI receive channel (0 = Omni, 1-16 = specific)
    public var receiveChannel: Int = 0

    /// Callback for note on events
    public var onNoteOn: ((UInt8, UInt8) -> Void)?

    /// Callback for note off events
    public var onNoteOff: ((UInt8) -> Void)?

    /// Callback for control change events
    public var onControlChange: ((UInt8, UInt8) -> Void)?

    // MARK: - Initialization

    public init() {}

    // MARK: - Start/Stop

    /// Start MIDI input manager
    public func start() {
        do {
            let midi = try CoreMIDITransport(clientName: "M2DX")
            self.transport = midi

            let transportRef = midi
            let mode = selectedSourceMode
            receiveTask = Task { [weak self] in
                // Connect based on selected mode
                switch mode {
                case .all:
                    try? await transportRef.connectToAllSources()
                case .specific(let name):
                    let sources = await transportRef.sources
                    if let match = sources.first(where: { $0.name == name }) {
                        try? await transportRef.connect(to: match.sourceID)
                    } else {
                        // Fallback to all if named source not found
                        try? await transportRef.connectToAllSources()
                    }
                }

                // Listen for MIDI data
                for await received in transportRef.received {
                    guard let self else { break }
                    await self.handleReceivedData(received.data)
                }
            }

            isConnected = true
            errorMessage = nil
            refreshDeviceList()
        } catch {
            errorMessage = "MIDI setup failed: \(error.localizedDescription)"
            isConnected = false
        }
    }

    /// Switch to a different MIDI source (restarts connection)
    public func selectSource(_ mode: MIDISourceMode) {
        selectedSourceMode = mode
        stop()
        start()
    }

    /// Stop MIDI input manager
    public func stop() {
        receiveTask?.cancel()
        receiveTask = nil

        if let transport {
            Task {
                await transport.disconnectAllSources()
                await transport.shutdown()
            }
        }
        transport = nil
        isConnected = false
        connectedDevices = []
    }

    // MARK: - Device List

    /// Refresh the list of connected MIDI devices
    public func refreshDeviceList() {
        guard let transport else {
            connectedDevices = []
            availableSources = []
            return
        }

        Task {
            let sources = await transport.sources
            await MainActor.run {
                self.connectedDevices = sources.map { $0.name }
                self.availableSources = sources.map { source in
                    MIDISourceItem(
                        id: source.name,
                        name: source.name,
                        isOnline: source.isOnline
                    )
                }
            }
        }
    }

    // MARK: - Event Handling

    /// Handle raw MIDI bytes received from CoreMIDITransport
    private func handleReceivedData(_ data: [UInt8]) async {
        // Process MIDI 1.0 byte stream (most common from CoreMIDI PacketList)
        var offset = 0
        while offset < data.count {
            let statusByte = data[offset]

            // Skip non-status bytes (running status not handled for simplicity)
            guard statusByte & 0x80 != 0 else {
                offset += 1
                continue
            }

            let statusNibble = statusByte >> 4
            let channel = statusByte & 0x0F

            // Channel filter: 0 = Omni (accept all), 1-16 = specific
            let passesFilter = receiveChannel == 0 || Int(channel) + 1 == receiveChannel

            switch statusNibble {
            case 0x9: // Note On
                guard offset + 2 < data.count else { break }
                let note = data[offset + 1]
                let velocity = data[offset + 2]
                if passesFilter {
                    if velocity == 0 {
                        await MainActor.run { onNoteOff?(note) }
                    } else {
                        await MainActor.run { onNoteOn?(note, velocity) }
                    }
                }
                offset += 3

            case 0x8: // Note Off
                guard offset + 2 < data.count else { break }
                let note = data[offset + 1]
                if passesFilter {
                    await MainActor.run { onNoteOff?(note) }
                }
                offset += 3

            case 0xB: // Control Change
                guard offset + 2 < data.count else { break }
                let controller = data[offset + 1]
                let value = data[offset + 2]
                if passesFilter {
                    await MainActor.run { onControlChange?(controller, value) }

                    // CC 123 = All Notes Off
                    if controller == 123 {
                        await MainActor.run {
                            for n: UInt8 in 0...127 {
                                onNoteOff?(n)
                            }
                        }
                    }
                }
                offset += 3

            case 0xE: // Pitch Bend
                offset += 3

            case 0xC, 0xD: // Program Change, Channel Pressure
                offset += 2

            case 0xF: // System messages
                switch statusByte {
                case 0xF0: // SysEx start - skip until F7
                    while offset < data.count && data[offset] != 0xF7 {
                        offset += 1
                    }
                    offset += 1
                case 0xF1, 0xF3: offset += 2  // MTC, Song Select
                case 0xF2: offset += 3          // Song Position
                default: offset += 1            // Real-time, etc.
                }

            default:
                offset += 1
            }
        }
    }
}
