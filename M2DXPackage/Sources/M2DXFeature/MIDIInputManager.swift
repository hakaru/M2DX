// MIDIInputManager.swift
// External MIDI device input via MIDI2Kit with MIDI 2.0 UMP support

import Foundation
import M2DXCore
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

    /// MIDI-CI Property Exchange responder
    private var peResponder: PEResponder?

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

    /// Callback for note on events (note, velocity16)
    public var onNoteOn: ((UInt8, UInt16) -> Void)?

    /// Callback for note off events
    public var onNoteOff: ((UInt8) -> Void)?

    /// Callback for control change events (cc, value32)
    public var onControlChange: ((UInt8, UInt32) -> Void)?

    /// Callback for pitch bend events (value32, center=0x80000000)
    public var onPitchBend: ((UInt32) -> Void)?

    /// Callback for program change events (program number 0-127)
    public var onProgramChange: ((UInt8) -> Void)?

    // MARK: - Debug Info (visible on UI)

    /// Debug: detected MIDI source names at connect time
    public private(set) var debugSources: [String] = []

    /// Debug: number of connected sources
    public private(set) var debugConnectedCount: Int = 0

    /// Debug: total received message count
    public private(set) var debugReceiveCount: Int = 0

    /// Debug: last received raw bytes (hex)
    public private(set) var debugLastReceived: String = "(none)"

    /// Debug: last parsed event description
    public private(set) var debugLastEvent: String = "(none)"

    /// Debug: recent MIDI message log (newest first, max 50)
    public private(set) var debugLog: [String] = []
    private let debugLogMax = 50

    /// Append a line to the debug log buffer
    private func appendDebugLog(_ line: String) {
        debugLog.insert(line, at: 0)
        if debugLog.count > debugLogMax {
            debugLog.removeLast()
        }
    }

    /// Clear the debug log
    public func clearDebugLog() {
        debugLog.removeAll()
    }

    /// Debug: CoreMIDI callback count (from transport)
    public var debugTransportCallback: String {
        guard let transport else { return "no transport" }
        return "cb=\(transport.debugCallbackCount) words=\(transport.debugWordCount) last=\(transport.debugLastCallback)\nword=\(transport.debugLastWord)"
    }

    // MARK: - Initialization

    public init() {}

    // MARK: - Start/Stop

    /// Start MIDI input manager
    public func start() {
        do {
            let midi = try CoreMIDITransport(clientName: "M2DX")
            self.transport = midi

            // Create PEResponder for MIDI-CI Property Exchange
            let responder = PEResponder(muid: MUID.random(), transport: midi)
            self.peResponder = responder
            Task { await self.registerPEResources(responder) }

            let transportRef = midi
            let mode = selectedSourceMode
            receiveTask = Task { [weak self] in
                // Enumerate available sources
                let detectedSources = await transportRef.sources
                await MainActor.run {
                    self?.debugSources = detectedSources.map { "\($0.name) (\($0.isOnline ? "online" : "offline"))" }
                }

                // Connect based on selected mode
                switch mode {
                case .all:
                    try? await transportRef.connectToAllSources()
                case .specific(let name):
                    let sources = await transportRef.sources
                    if let match = sources.first(where: { $0.name == name }) {
                        try? await transportRef.connect(to: match.sourceID)
                    } else {
                        try? await transportRef.connectToAllSources()
                    }
                }

                let connCount = await transportRef.connectedSourceCount
                await MainActor.run {
                    self?.debugConnectedCount = connCount
                }

                // Listen for MIDI data
                for await received in transportRef.received {
                    guard let self else { break }
                    let data = received.data
                    let hex = data.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " ")

                    let w1 = received.umpWord1
                    let w2 = received.umpWord2
                    let umpStr = w1 != 0
                        ? String(format: "UMP 0x%08X 0x%08X mt=%d st=%d", w1, w2, (w1 >> 28) & 0xF, (w1 >> 20) & 0xF)
                        : "M1"
                    let logLine = "\(umpStr) [\(hex)]"

                    await MainActor.run {
                        self.debugReceiveCount += 1
                        self.debugLastReceived = "\(data.count)B: \(hex)"
                        self.appendDebugLog(logLine)
                    }

                    // CI SysEx: F0 7E <deviceID> 0D <sub-ID2> ...
                    if data.count >= 4 && data[0] == 0xF0 && data[1] == 0x7E && data[3] == 0x0D {
                        await MainActor.run {
                            self.debugLastEvent = "CI SysEx (\(data.count)B)"
                        }
                        if let resp = self.peResponder {
                            await resp.handleMessage(data)
                        }
                    } else if received.umpWord1 != 0 {
                        // MIDI 2.0 path: decode full-precision values from UMP words
                        await self.handleUMPData(received.umpWord1, word2: received.umpWord2, fallbackData: data)
                    } else {
                        await self.handleReceivedData(data)
                    }
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
        peResponder = nil

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

    // MARK: - Property Exchange

    /// Register PE resources (ResourceList, DeviceInfo, ProgramList)
    private func registerPEResources(_ responder: PEResponder) async {
        // ResourceList — advertise available resources
        await responder.registerResource("ResourceList", resource: StaticResource(json: """
        [
            {"resource":"ResourceList","canGet":true},
            {"resource":"DeviceInfo","canGet":true},
            {"resource":"ProgramList","canGet":true}
        ]
        """))

        // DeviceInfo
        await responder.registerResource("DeviceInfo", resource: StaticResource(json: """
        {
            "manufacturerName":"M2DX",
            "productName":"M2DX DX7 Synthesizer",
            "softwareVersion":"1.0",
            "familyName":"FM Synthesizer",
            "modelName":"DX7 Compatible"
        }
        """))

        // ProgramList — dynamic from DX7 factory presets
        await responder.registerResource("ProgramList", resource: ComputedResource { _ in
            let programs = DX7FactoryPresets.all.enumerated().map { index, preset in
                PEProgramDef(programNumber: index, bankMSB: 0, bankLSB: 0, name: preset.name)
            }
            return try JSONEncoder().encode(programs)
        })
    }

    // MARK: - Event Handling

    /// Handle MIDI 2.0 UMP words with full precision
    /// Already on MainActor (class is @MainActor)
    private func handleUMPData(_ word1: UInt32, word2: UInt32, fallbackData: [UInt8]) {
        let status = UInt8((word1 >> 20) & 0x0F)
        let channel = UInt8((word1 >> 16) & 0x0F)
        let byte3 = UInt8((word1 >> 8) & 0xFF)   // note or controller

        // Channel filter: 0 = Omni (accept all), 1-16 = specific
        let passesFilter = receiveChannel == 0 || Int(channel) + 1 == receiveChannel

        switch status {
        case 0x9: // Note On (16-bit velocity in upper 16 of word2)
            let vel16 = UInt16((word2 >> 16) & 0xFFFF)
            debugLastEvent = "NoteOn(UMP) ch=\(channel) n=\(byte3) v16=\(vel16)"
            if passesFilter {
                if vel16 == 0 {
                    onNoteOff?(byte3)
                } else {
                    onNoteOn?(byte3, vel16)
                }
            }

        case 0x8: // Note Off
            debugLastEvent = "NoteOff(UMP) ch=\(channel) n=\(byte3)"
            if passesFilter {
                onNoteOff?(byte3)
            }

        case 0xB: // Control Change (32-bit value)
            let val32 = word2
            debugLastEvent = "CC(UMP) ch=\(channel) cc=\(byte3) v32=\(val32)"
            if passesFilter {
                onControlChange?(byte3, val32)
                if byte3 == 123 {
                    for n: UInt8 in 0...127 {
                        onNoteOff?(n)
                    }
                }
            }

        case 0xE: // Pitch Bend (32-bit unsigned, center=0x80000000)
            let val32 = word2
            debugLastEvent = "PB(UMP) ch=\(channel) v32=\(val32)"
            if passesFilter {
                onPitchBend?(val32)
            }

        case 0xC: // Program Change (program at bits 31-24 of word2)
            let program = UInt8((word2 >> 24) & 0x7F)
            debugLastEvent = "PC(UMP) ch=\(channel) p=\(program)"
            if passesFilter {
                onProgramChange?(program)
            }

        default:
            // For unhandled UMP types, fall back to MIDI 1.0 byte parsing
            handleReceivedData(fallbackData)
        }
    }

    /// Handle raw MIDI bytes received from CoreMIDITransport (MIDI 1.0 fallback)
    /// Already on MainActor (class is @MainActor, called via await self.handleReceivedData)
    private func handleReceivedData(_ data: [UInt8]) {
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
                debugLastEvent = "NoteOn ch=\(channel) n=\(note) v=\(velocity)"
                if passesFilter {
                    if velocity == 0 {
                        onNoteOff?(note)
                    } else {
                        // Upscale 7-bit → 16-bit velocity
                        let vel16 = UInt16(velocity) << 9
                        onNoteOn?(note, vel16)
                    }
                }
                offset += 3

            case 0x8: // Note Off
                guard offset + 2 < data.count else { break }
                let note = data[offset + 1]
                if passesFilter {
                    onNoteOff?(note)
                }
                offset += 3

            case 0xB: // Control Change
                guard offset + 2 < data.count else { break }
                let controller = data[offset + 1]
                let value = data[offset + 2]
                if passesFilter {
                    // Upscale 7-bit → 32-bit CC value
                    let val32 = UInt32(value) << 25
                    onControlChange?(controller, val32)

                    // CC 123 = All Notes Off
                    if controller == 123 {
                        for n: UInt8 in 0...127 {
                            onNoteOff?(n)
                        }
                    }
                }
                offset += 3

            case 0xE: // Pitch Bend
                guard offset + 2 < data.count else { break }
                let lsb = data[offset + 1]
                let msb = data[offset + 2]
                debugLastEvent = "PitchBend ch=\(channel) lsb=\(lsb) msb=\(msb)"
                if passesFilter {
                    // Upscale 14-bit → 32-bit pitch bend
                    let raw14 = (UInt32(msb) << 7) | UInt32(lsb)
                    let val32 = raw14 << 18
                    onPitchBend?(val32)
                }
                offset += 3

            case 0xC: // Program Change
                guard offset + 1 < data.count else { break }
                let program = data[offset + 1]
                debugLastEvent = "PC ch=\(channel) p=\(program)"
                if passesFilter {
                    onProgramChange?(program)
                }
                offset += 2

            case 0xD: // Channel Pressure
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
