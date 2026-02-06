import AVFoundation
import AudioToolbox

// MARK: - M2DX Audio Engine

/// Standalone audio engine that hosts the M2DX AUv3 synthesizer internally
/// Allows the app to produce sound without requiring an external DAW host
@MainActor
@Observable
public final class M2DXAudioEngine {

    // MARK: - Properties

    /// Audio engine for hosting the AU
    private var audioEngine: AVAudioEngine?

    /// The M2DX Audio Unit instance
    private var audioUnit: AUAudioUnit?

    /// Audio Unit node in the engine graph
    private var auNode: AVAudioUnit?

    /// Whether the engine is running
    public private(set) var isRunning: Bool = false

    /// Current algorithm (0-31)
    public var algorithm: Int = 0 {
        didSet {
            setParameter(address: 0, value: Float(algorithm))
        }
    }

    /// Master volume (0-1)
    public var masterVolume: Float = 0.7 {
        didSet {
            setParameter(address: 1, value: masterVolume)
        }
    }

    /// Operator levels (0-1)
    public var operatorLevels: [Float] = [1.0, 1.0, 1.0, 1.0, 0.5, 0.5] {
        didSet {
            for (index, level) in operatorLevels.enumerated() {
                let address = 100 + index * 100  // operatorBase + index * stride
                setParameter(address: UInt64(address), value: level)
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
        do {
            try await setupAudioEngine()
            isRunning = true
            errorMessage = nil
        } catch {
            errorMessage = "Failed to start audio engine: \(error.localizedDescription)"
            print("M2DXAudioEngine: \(errorMessage!)")
        }
    }

    /// Stop the audio engine
    public func stop() {
        audioEngine?.stop()
        isRunning = false
    }

    // MARK: - Audio Engine Setup

    private func setupAudioEngine() async throws {
        // Configure audio session
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)

        // Create audio engine
        let engine = AVAudioEngine()
        self.audioEngine = engine

        // Get the M2DX Audio Unit component description
        let componentDescription = AudioComponentDescription(
            componentType: kAudioUnitType_MusicDevice,
            componentSubType: FourCharCode("m2dx"),
            componentManufacturer: FourCharCode("M2DX"),
            componentFlags: 0,
            componentFlagsMask: 0
        )

        // Instantiate the Audio Unit
        let avAudioUnit = try await AVAudioUnit.instantiate(
            with: componentDescription,
            options: .loadOutOfProcess
        )

        self.auNode = avAudioUnit
        self.audioUnit = avAudioUnit.auAudioUnit

        // Connect AU to output
        engine.attach(avAudioUnit)
        engine.connect(avAudioUnit, to: engine.mainMixerNode, format: nil)

        // Start engine
        try engine.start()

        // Set initial parameters
        setParameter(address: 0, value: Float(algorithm))
        setParameter(address: 1, value: masterVolume)
    }

    // MARK: - MIDI Note Control

    /// Send note on event
    /// - Parameters:
    ///   - note: MIDI note number (0-127)
    ///   - velocity: Note velocity (0-127)
    public func noteOn(_ note: UInt8, velocity: UInt8 = 100) {
        sendMIDI(status: 0x90, data1: note, data2: velocity)
    }

    /// Send note off event
    /// - Parameter note: MIDI note number (0-127)
    public func noteOff(_ note: UInt8) {
        sendMIDI(status: 0x80, data1: note, data2: 0)
    }

    /// Send all notes off
    public func allNotesOff() {
        sendMIDI(status: 0xB0, data1: 123, data2: 0)
    }

    /// Send MIDI message to the Audio Unit
    private func sendMIDI(status: UInt8, data1: UInt8, data2: UInt8) {
        guard let au = audioUnit,
              let midiBlock = au.scheduleMIDIEventBlock else { return }

        // Send immediately (AUEventSampleTimeImmediate = -1)
        var midiData: [UInt8] = [status, data1, data2]
        midiData.withUnsafeMutableBufferPointer { buffer in
            midiBlock(AUEventSampleTimeImmediate, 0, 3, buffer.baseAddress!)
        }
    }

    // MARK: - Parameter Control

    /// Set a parameter value
    /// - Parameters:
    ///   - address: Parameter address
    ///   - value: Parameter value
    public func setParameter(address: UInt64, value: Float) {
        guard let tree = audioUnit?.parameterTree else { return }
        tree.parameter(withAddress: address)?.value = value
    }

    /// Get a parameter value
    /// - Parameter address: Parameter address
    /// - Returns: Current parameter value
    public func getParameter(address: UInt64) -> Float? {
        guard let tree = audioUnit?.parameterTree else { return nil }
        return tree.parameter(withAddress: address)?.value
    }

    /// Set operator level
    public func setOperatorLevel(_ opIndex: Int, level: Float) {
        let address = 100 + opIndex * 100
        setParameter(address: UInt64(address), value: level)
        if opIndex < operatorLevels.count {
            operatorLevels[opIndex] = level
        }
    }

    /// Set operator ratio
    public func setOperatorRatio(_ opIndex: Int, ratio: Float) {
        let address = 100 + opIndex * 100 + 1  // +1 for ratio offset
        setParameter(address: UInt64(address), value: ratio)
    }

    /// Set operator detune
    public func setOperatorDetune(_ opIndex: Int, cents: Float) {
        let address = 100 + opIndex * 100 + 2  // +2 for detune offset
        setParameter(address: UInt64(address), value: cents)
    }

    /// Set operator feedback
    public func setOperatorFeedback(_ opIndex: Int, feedback: Float) {
        let address = 100 + opIndex * 100 + 3  // +3 for feedback offset
        setParameter(address: UInt64(address), value: feedback)
    }
}

// MARK: - FourCharCode Extension

private extension FourCharCode {
    init(_ string: String) {
        var result: FourCharCode = 0
        for char in string.utf8.prefix(4) {
            result = (result << 8) | FourCharCode(char)
        }
        self = result
    }
}
