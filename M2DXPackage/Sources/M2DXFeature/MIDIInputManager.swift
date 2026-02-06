// MIDIInputManager.swift
// External MIDI device input via MIDIKit with MIDI 2.0 UMP support

import Foundation
import MIDIKit

// Type alias to disambiguate from local MIDIEvent
private typealias MKEvent = MIDIKitCore.MIDIEvent

// MARK: - MIDI Input Manager

/// Manages external MIDI device connections and routes events to the audio engine
@MainActor
@Observable
public final class MIDIInputManager {

    // MARK: - Properties

    /// MIDIKit manager
    private var midiManager: MIDIManager?

    /// Whether MIDI is initialized
    public private(set) var isConnected: Bool = false

    /// Connected device names
    public private(set) var connectedDevices: [String] = []

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
            let manager = MIDIManager(
                clientName: "M2DX",
                model: "M2DX FM Synthesizer",
                manufacturer: "M2DX"
            )
            try manager.start()
            self.midiManager = manager

            // Create input connection that listens to all sources
            try manager.addInputConnection(
                to: .allOutputs,
                tag: "M2DX-Input",
                receiver: .events { [weak self] events, _, _ in
                    Task { @MainActor in
                        self?.handleMIDIEvents(events)
                    }
                }
            )

            isConnected = true
            errorMessage = nil
            refreshDeviceList()
        } catch {
            errorMessage = "MIDI setup failed: \(error.localizedDescription)"
            isConnected = false
        }
    }

    /// Stop MIDI input manager
    public func stop() {
        midiManager?.removeAll()
        midiManager = nil
        isConnected = false
        connectedDevices = []
    }

    // MARK: - Device List

    /// Refresh the list of connected MIDI devices
    public func refreshDeviceList() {
        guard let manager = midiManager else {
            connectedDevices = []
            return
        }

        connectedDevices = manager.endpoints.outputs.map { $0.displayName }
    }

    // MARK: - Event Handling

    private func handleMIDIEvents(_ events: [MKEvent]) {
        for event in events {
            // Channel filter: 0 = Omni (accept all), 1-16 = specific
            if receiveChannel > 0 {
                if let ch = event.channel?.intValue, ch + 1 != receiveChannel {
                    continue
                }
            }

            switch event {
            case .noteOn(let noteOn):
                let note = noteOn.note.number.uInt8Value
                let velocity = noteOn.velocity.midi1Value.uInt8Value
                if velocity == 0 {
                    onNoteOff?(note)
                } else {
                    onNoteOn?(note, velocity)
                }

            case .noteOff(let noteOff):
                let note = noteOff.note.number.uInt8Value
                onNoteOff?(note)

            case .cc(let cc):
                let controller = cc.controller.number.uInt8Value
                let value = cc.value.midi1Value.uInt8Value
                onControlChange?(controller, value)

                // CC 123 = All Notes Off
                if controller == 123 {
                    for n: UInt8 in 0...127 {
                        onNoteOff?(n)
                    }
                }

            default:
                break
            }
        }
    }
}
