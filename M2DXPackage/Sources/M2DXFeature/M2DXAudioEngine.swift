import AVFoundation
import os

// MARK: - Audio Engine Errors

/// Errors that can occur during audio engine operations
public enum AudioEngineError: LocalizedError {
    case audioSessionSetupFailed(underlying: Error)
    case engineStartFailed(underlying: Error)
    case engineNotRunning

    public var errorDescription: String? {
        switch self {
        case .audioSessionSetupFailed(let error):
            return "Audio session setup failed: \(error.localizedDescription)"
        case .engineStartFailed(let error):
            return "Audio engine start failed: \(error.localizedDescription)"
        case .engineNotRunning:
            return "Audio engine is not running"
        }
    }
}

// MARK: - Render State

/// Shared state between main thread and render thread
private final class RenderState: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: true)

    var isRunning: Bool {
        get { lock.withLock { $0 } }
        set { lock.withLock { $0 = newValue } }
    }
}

// MARK: - M2DX Audio Engine

/// Standalone audio engine that drives a pure-Swift FM synth via AVAudioPlayerNode
/// with double-buffered scheduling. No AUv3 dependency.
@MainActor
@Observable
public final class M2DXAudioEngine {

    // MARK: - Properties

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private let synth = FMSynthEngine()
    private var renderState: RenderState?

    /// Buffer configuration
    private let bufferFrameCount: AVAudioFrameCount = 512

    /// Currently playing notes (for proper cleanup)
    private var activeNotes: Set<UInt8> = []

    /// Whether the engine is running
    public private(set) var isRunning: Bool = false

    /// Current algorithm (0-31)
    public var algorithm: Int = 0 {
        didSet {
            synth.setAlgorithm(algorithm)
        }
    }

    /// Master volume (0-1)
    public var masterVolume: Float = 0.7 {
        didSet {
            synth.setMasterVolume(masterVolume)
        }
    }

    /// Operator levels (0-1)
    public var operatorLevels: [Float] = [1.0, 1.0, 1.0, 1.0, 0.5, 0.5] {
        didSet {
            for (index, level) in operatorLevels.enumerated() {
                synth.setOperatorLevel(index, level: level)
            }
        }
    }

    /// Error message if initialization failed
    public private(set) var errorMessage: String?

    // MARK: - Initialization

    public init() {}

    // MARK: - Engine Control

    /// Start the audio engine
    public func start() async {
        guard !isRunning else { return }

        do {
            try setupAudioEngine()
            isRunning = true
            errorMessage = nil
        } catch {
            let message = (error as? AudioEngineError)?.errorDescription
                ?? "Failed to start audio engine: \(error.localizedDescription)"
            errorMessage = message
            print("M2DXAudioEngine: \(message)")
        }
    }

    /// Stop the audio engine and clean up resources
    public func stop() {
        // Stop render thread
        renderState?.isRunning = false
        renderState = nil

        // All notes off via the MIDI queue
        synth.midiQueue.enqueue(MIDIEvent(kind: .controlChange, data1: 123, data2: 0))
        activeNotes.removeAll()

        playerNode?.stop()
        audioEngine?.stop()

        if let node = playerNode {
            audioEngine?.detach(node)
        }

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("M2DXAudioEngine: Failed to deactivate audio session: \(error)")
        }

        playerNode = nil
        audioEngine = nil
        isRunning = false
    }

    // MARK: - Audio Engine Setup

    private func setupAudioEngine() throws {
        // Configure audio session
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setPreferredSampleRate(48000)
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
        } catch {
            throw AudioEngineError.audioSessionSetupFailed(underlying: error)
        }

        let engine = AVAudioEngine()

        // Use output node's format (deinterleaved stereo)
        let outputFormat = engine.outputNode.outputFormat(forBus: 0)
        let sampleRate = outputFormat.sampleRate

        // Configure synth
        synth.setSampleRate(Float(sampleRate))
        synth.setAlgorithm(algorithm)
        synth.setMasterVolume(masterVolume)
        for (i, level) in operatorLevels.enumerated() {
            synth.setOperatorLevel(i, level: level)
        }

        // Create player node
        let player = AVAudioPlayerNode()

        // Use the standard deinterleaved format that AVAudioEngine expects
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 2
        ) else {
            throw AudioEngineError.engineStartFailed(
                underlying: NSError(domain: "M2DX", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to create audio format"
                ])
            )
        }

        self.playerNode = player
        self.audioEngine = engine

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
        } catch {
            throw AudioEngineError.engineStartFailed(underlying: error)
        }

        // Start playback
        player.play()

        // Start render thread for continuous buffer scheduling
        let state = RenderState()
        self.renderState = state

        let synthRef = synth
        let frameCount = bufferFrameCount

        let thread = Thread {
            Self.renderLoop(
                synth: synthRef,
                player: player,
                format: format,
                frameCount: frameCount,
                state: state
            )
        }
        thread.name = "M2DX-Render"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    // MARK: - Render Loop (runs on dedicated thread)

    nonisolated private static func renderLoop(
        synth: FMSynthEngine,
        player: AVAudioPlayerNode,
        format: AVAudioFormat,
        frameCount: AVAudioFrameCount,
        state: RenderState
    ) {
        while state.isRunning {
            guard player.isPlaying else {
                Thread.sleep(forTimeInterval: 0.001)
                continue
            }

            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: frameCount
            ) else { continue }

            buffer.frameLength = frameCount

            // Render into deinterleaved buffers
            guard let floatChannelData = buffer.floatChannelData else { continue }
            let leftChannel = floatChannelData[0]
            let rightChannel = floatChannelData[1]

            // Zero buffers
            memset(leftChannel, 0, Int(frameCount) * MemoryLayout<Float>.size)
            memset(rightChannel, 0, Int(frameCount) * MemoryLayout<Float>.size)

            // Render synth
            synth.render(
                into: leftChannel,
                bufferR: rightChannel,
                frameCount: Int(frameCount)
            )

            // Schedule buffer and wait for completion
            let semaphore = DispatchSemaphore(value: 0)
            player.scheduleBuffer(buffer) {
                semaphore.signal()
            }
            semaphore.wait()
        }
    }

    // MARK: - MIDI Note Control

    /// Send note on event
    public func noteOn(_ note: UInt8, velocity: UInt8 = 100) {
        guard isRunning else { return }
        activeNotes.insert(note)
        synth.midiQueue.enqueue(MIDIEvent(kind: .noteOn, data1: note, data2: velocity))
    }

    /// Send note off event
    public func noteOff(_ note: UInt8) {
        guard isRunning else { return }
        activeNotes.remove(note)
        synth.midiQueue.enqueue(MIDIEvent(kind: .noteOff, data1: note, data2: 0))
    }

    /// Send all notes off
    public func allNotesOff() {
        for note in activeNotes {
            synth.midiQueue.enqueue(MIDIEvent(kind: .noteOff, data1: note, data2: 0))
        }
        activeNotes.removeAll()
        synth.midiQueue.enqueue(MIDIEvent(kind: .controlChange, data1: 123, data2: 0))
    }

    // MARK: - Parameter Control

    /// Set operator level
    public func setOperatorLevel(_ opIndex: Int, level: Float) {
        guard opIndex >= 0 && opIndex < 6 else { return }
        synth.setOperatorLevel(opIndex, level: level)
        if opIndex < operatorLevels.count {
            operatorLevels[opIndex] = level
        }
    }

    /// Set operator ratio
    public func setOperatorRatio(_ opIndex: Int, ratio: Float) {
        guard opIndex >= 0 && opIndex < 6 else { return }
        synth.setOperatorRatio(opIndex, ratio: ratio)
    }

    /// Set operator detune
    public func setOperatorDetune(_ opIndex: Int, cents: Float) {
        guard opIndex >= 0 && opIndex < 6 else { return }
        synth.setOperatorDetune(opIndex, cents: cents)
    }

    /// Set operator feedback
    public func setOperatorFeedback(_ opIndex: Int, feedback: Float) {
        guard opIndex >= 0 && opIndex < 6 else { return }
        synth.setOperatorFeedback(opIndex, feedback: feedback)
    }
}
