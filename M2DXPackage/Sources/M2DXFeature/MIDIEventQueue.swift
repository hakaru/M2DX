// MIDIEventQueue.swift
// Lock-free ring buffer for passing MIDI events from UI thread to audio thread

import os

// MARK: - MIDI Event

/// A lightweight MIDI event for the audio thread
struct MIDIEvent: Sendable {
    enum Kind: UInt8, Sendable {
        case noteOn = 0x90
        case noteOff = 0x80
        case controlChange = 0xB0
        case pitchBend = 0xE0
    }

    let kind: Kind
    let data1: UInt8
    let data2: UInt8
}

// MARK: - MIDI Event Queue

/// Thread-safe queue for passing MIDI events from the UI thread to the audio render thread.
///
/// Uses `OSAllocatedUnfairLock` for minimal-overhead synchronization.
/// The queue has a fixed capacity and silently drops events when full
/// (acceptable for real-time audio — dropping is better than blocking).
final class MIDIEventQueue: @unchecked Sendable {

    private let capacity: Int
    private let lock = OSAllocatedUnfairLock(initialState: [MIDIEvent]())

    init(capacity: Int = 256) {
        self.capacity = capacity
    }

    /// Enqueue a MIDI event (called from UI / main thread).
    /// Drops the event silently if the queue is full.
    func enqueue(_ event: MIDIEvent) {
        lock.withLock { buffer in
            guard buffer.count < capacity else { return }
            buffer.append(event)
        }
    }

    /// Drain all pending events (called from the audio render thread).
    /// Returns the events and clears the internal buffer.
    func drain() -> [MIDIEvent] {
        lock.withLock { buffer in
            guard !buffer.isEmpty else { return [] }
            let events = buffer
            buffer.removeAll(keepingCapacity: true)
            return events
        }
    }
}
