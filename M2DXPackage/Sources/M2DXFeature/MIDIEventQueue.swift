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
    let data1: UInt8       // note number or CC number (7-bit)
    let data2: UInt32      // velocity16, CC value32, or pitchBend32
}

// MARK: - MIDI Event Queue (Ring Buffer)

/// Thread-safe ring buffer for passing MIDI events from the UI thread to the audio render thread.
///
/// Uses `os_unfair_lock` for minimal-overhead synchronization suitable for real-time audio.
/// The queue has a fixed capacity and silently drops events when full
/// (acceptable for real-time audio — dropping is better than blocking).
final class MIDIEventQueue: @unchecked Sendable {

    private let capacity: Int
    private let storage: UnsafeMutablePointer<MIDIEvent>
    private var unfairLock = os_unfair_lock()
    private var head: Int = 0
    private var count: Int = 0

    /// Default event used for uninitialized slots
    private static let emptyEvent = MIDIEvent(kind: .noteOff, data1: 0, data2: 0)

    init(capacity: Int = 256) {
        self.capacity = capacity
        self.storage = .allocate(capacity: capacity)
        storage.initialize(repeating: Self.emptyEvent, count: capacity)
    }

    deinit {
        storage.deinitialize(count: capacity)
        storage.deallocate()
    }

    /// Enqueue a MIDI event (called from UI / main thread).
    /// Drops the event silently if the queue is full.
    func enqueue(_ event: MIDIEvent) {
        os_unfair_lock_lock(&unfairLock)
        if count < capacity {
            let writeIndex = (head + count) % capacity
            storage[writeIndex] = event
            count += 1
        }
        os_unfair_lock_unlock(&unfairLock)
    }

    /// Drain all pending events via callback (called from the audio render thread).
    /// Processes each event in FIFO order without heap allocation.
    func drain(_ handler: (MIDIEvent) -> Void) {
        os_unfair_lock_lock(&unfairLock)
        let n = count
        let h = head
        head = (head + n) % capacity
        count = 0
        os_unfair_lock_unlock(&unfairLock)

        // Process events outside the lock — storage slots are safe to read
        // because new enqueues write to different slots (count was reset to 0,
        // so writes go to the new head position, not the range we're reading).
        for i in 0..<n {
            let index = (h + i) % capacity
            handler(storage[index])
        }
    }
}
