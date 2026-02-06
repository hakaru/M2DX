import AVFoundation
import AudioToolbox

// MARK: - Audio Engine Errors

/// Errors that can occur during audio engine operations
public enum AudioEngineError: LocalizedError {
    case audioSessionSetupFailed(underlying: Error)
    case audioUnitInstantiationFailed(underlying: Error)
    case engineStartFailed(underlying: Error)
    case engineNotRunning

    public var errorDescription: String? {
        switch self {
        case .audioSessionSetupFailed(let error):
            return "Audio session setup failed: \(error.localizedDescription)"
        case .audioUnitInstantiationFailed(let error):
            return "Audio Unit instantiation failed: \(error.localizedDescription)"
        case .engineStartFailed(let error):
            return "Audio engine start failed: \(error.localizedDescription)"
        case .engineNotRunning:
            return "Audio engine is not running"
        }
    }
}

// MARK: - Parameter Address Constants

/// Parameter address constants matching M2DXParameterAddressMap
private enum ParameterAddress {
    static let algorithm: UInt64 = 0
    static let masterVolume: UInt64 = 1

    static let operatorBase: UInt64 = 100
    static let operatorStride: UInt64 = 100

    // Operator parameter offsets
    static let levelOffset: UInt64 = 0
    static let ratioOffset: UInt64 = 1
    static let detuneOffset: UInt64 = 2
    static let feedbackOffset: UInt64 = 3

    static func operatorAddress(_ opIndex: Int, offset: UInt64) -> UInt64 {
        return operatorBase + UInt64(opIndex) * operatorStride + offset
    }
}

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

    /// Currently playing notes (for proper cleanup)
    private var activeNotes: Set<UInt8> = []

    /// Whether the engine is running
    public private(set) var isRunning: Bool = false

    /// Current algorithm (0-31)
    public var algorithm: Int = 0 {
        didSet {
            guard isRunning else { return }
            setParameter(address: ParameterAddress.algorithm, value: Float(algorithm))
        }
    }

    /// Master volume (0-1)
    public var masterVolume: Float = 0.7 {
        didSet {
            guard isRunning else { return }
            setParameter(address: ParameterAddress.masterVolume, value: masterVolume)
        }
    }

    /// Operator levels (0-1)
    public var operatorLevels: [Float] = [1.0, 1.0, 1.0, 1.0, 0.5, 0.5] {
        didSet {
            guard isRunning else { return }
            for (index, level) in operatorLevels.enumerated() {
                let address = ParameterAddress.operatorAddress(index, offset: ParameterAddress.levelOffset)
                setParameter(address: address, value: level)
            }
        }
    }

    /// Error message if initialization failed
    public private(set) var errorMessage: String?

    // MARK: - Component Description

    /// Audio Unit component description for M2DX
    private static let componentDescription = AudioComponentDescription(
        componentType: kAudioUnitType_MusicDevice,
        componentSubType: FourCharCode("m2dx"),
        componentManufacturer: FourCharCode("M2DX"),
        componentFlags: 0,
        componentFlagsMask: 0
    )

    // MARK: - Initialization

    public init() {}

    deinit {
        // Note: deinit runs on arbitrary thread, but stop() is @MainActor
        // The caller should ensure stop() is called before deallocation
    }

    // MARK: - Engine Control

    /// Start the audio engine
    public func start() async {
        // Don't restart if already running
        guard !isRunning else { return }

        do {
            try await setupAudioEngine()
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
        guard isRunning else { return }

        // Send note off for all active notes
        for note in activeNotes {
            sendMIDI(status: 0x80, data1: note, data2: 0)
        }
        activeNotes.removeAll()

        // Send all notes off as safety measure
        sendMIDI(status: 0xB0, data1: 123, data2: 0)

        // Stop and clean up engine
        audioEngine?.stop()

        if let auNode = auNode {
            audioEngine?.detach(auNode)
        }

        // Deactivate audio session
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("M2DXAudioEngine: Failed to deactivate audio session: \(error)")
        }

        // Clear references
        audioUnit = nil
        auNode = nil
        audioEngine = nil
        isRunning = false
    }

    // MARK: - Audio Engine Setup

    private func setupAudioEngine() async throws {
        // Configure audio session
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            throw AudioEngineError.audioSessionSetupFailed(underlying: error)
        }

        // Create audio engine
        let engine = AVAudioEngine()
        self.audioEngine = engine

        // Instantiate the Audio Unit
        let avAudioUnit: AVAudioUnit
        do {
            // Use default options for iOS (in-process is default for app extensions)
            avAudioUnit = try await AVAudioUnit.instantiate(
                with: Self.componentDescription,
                options: []
            )
        } catch {
            throw AudioEngineError.audioUnitInstantiationFailed(underlying: error)
        }

        self.auNode = avAudioUnit
        self.audioUnit = avAudioUnit.auAudioUnit

        // Connect AU to output
        engine.attach(avAudioUnit)
        engine.connect(avAudioUnit, to: engine.mainMixerNode, format: nil)

        // Start engine
        do {
            try engine.start()
        } catch {
            throw AudioEngineError.engineStartFailed(underlying: error)
        }

        // Set initial parameters
        setParameter(address: ParameterAddress.algorithm, value: Float(algorithm))
        setParameter(address: ParameterAddress.masterVolume, value: masterVolume)
    }

    // MARK: - MIDI Note Control

    /// Send note on event
    /// - Parameters:
    ///   - note: MIDI note number (0-127)
    ///   - velocity: Note velocity (0-127)
    public func noteOn(_ note: UInt8, velocity: UInt8 = 100) {
        guard isRunning else { return }
        activeNotes.insert(note)
        sendMIDI(status: 0x90, data1: note, data2: velocity)
    }

    /// Send note off event
    /// - Parameter note: MIDI note number (0-127)
    public func noteOff(_ note: UInt8) {
        guard isRunning else { return }
        activeNotes.remove(note)
        sendMIDI(status: 0x80, data1: note, data2: 0)
    }

    /// Send all notes off
    public func allNotesOff() {
        // Turn off only active notes for efficiency
        for note in activeNotes {
            sendMIDI(status: 0x80, data1: note, data2: 0)
        }
        activeNotes.removeAll()

        // Also send CC 123 (All Notes Off) as safety measure
        sendMIDI(status: 0xB0, data1: 123, data2: 0)
    }

    /// Send MIDI message to the Audio Unit
    private func sendMIDI(status: UInt8, data1: UInt8, data2: UInt8) {
        guard let au = audioUnit,
              let midiBlock = au.scheduleMIDIEventBlock else { return }

        // Send immediately (AUEventSampleTimeImmediate = -1)
        var midiData: [UInt8] = [status, data1, data2]
        midiData.withUnsafeMutableBufferPointer { buffer in
            // Safe unwrap - buffer will always have baseAddress for non-empty array
            guard let baseAddress = buffer.baseAddress else { return }
            midiBlock(AUEventSampleTimeImmediate, 0, 3, baseAddress)
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
        guard opIndex >= 0 && opIndex < 6 else { return }
        let address = ParameterAddress.operatorAddress(opIndex, offset: ParameterAddress.levelOffset)
        setParameter(address: address, value: level)
        if opIndex < operatorLevels.count {
            operatorLevels[opIndex] = level
        }
    }

    /// Set operator ratio
    public func setOperatorRatio(_ opIndex: Int, ratio: Float) {
        guard opIndex >= 0 && opIndex < 6 else { return }
        let address = ParameterAddress.operatorAddress(opIndex, offset: ParameterAddress.ratioOffset)
        setParameter(address: address, value: ratio)
    }

    /// Set operator detune
    public func setOperatorDetune(_ opIndex: Int, cents: Float) {
        guard opIndex >= 0 && opIndex < 6 else { return }
        let address = ParameterAddress.operatorAddress(opIndex, offset: ParameterAddress.detuneOffset)
        setParameter(address: address, value: cents)
    }

    /// Set operator feedback
    public func setOperatorFeedback(_ opIndex: Int, feedback: Float) {
        guard opIndex >= 0 && opIndex < 6 else { return }
        let address = ParameterAddress.operatorAddress(opIndex, offset: ParameterAddress.feedbackOffset)
        setParameter(address: address, value: feedback)
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
