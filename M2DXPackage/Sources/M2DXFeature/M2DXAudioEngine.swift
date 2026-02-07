import AVFoundation
#if os(macOS)
import CoreAudio
#endif
import M2DXCore
import os

private let audioLogger = Logger(subsystem: "com.example.M2DX", category: "Audio")

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


// MARK: - M2DX Audio Engine

/// Standalone audio engine that drives a pure-Swift FM synth via AVAudioSourceNode
/// for minimal latency. CoreAudio render callback calls synth directly.
@MainActor
@Observable
public final class M2DXAudioEngine {

    // MARK: - Properties

    private var audioEngine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private let synth = FMSynthEngine()
    private var configObservers: [any NSObjectProtocol] = []

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
    public var masterVolume: Float = 0.8 {
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

    /// Current audio output device name
    public private(set) var currentOutputDevice: String = "Default"

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
            audioLogger.error("\(message, privacy: .public)")
        }
    }

    /// Stop the audio engine and clean up resources
    public func stop() {
        // Remove configuration change observers
        for observer in configObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        configObservers.removeAll()

        // All notes off via the MIDI queue
        synth.midiQueue.enqueue(MIDIEvent(kind: .controlChange, data1: 123, data2: 0))
        activeNotes.removeAll()

        audioEngine?.stop()

        if let node = sourceNode {
            audioEngine?.detach(node)
        }

        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            audioLogger.warning("Failed to deactivate audio session: \(error.localizedDescription, privacy: .public)")
        }
        #endif

        sourceNode = nil
        audioEngine = nil
        isRunning = false
    }

    // MARK: - Audio Engine Setup

    private func setupAudioEngine() throws {
        // Configure audio session (iOS only)
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setPreferredSampleRate(48000)
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
        } catch {
            throw AudioEngineError.audioSessionSetupFailed(underlying: error)
        }
        #endif

        let engine = AVAudioEngine()

        // Use output node's format (deinterleaved stereo)
        let outputFormat = engine.outputNode.outputFormat(forBus: 0)
        let sampleRate = outputFormat.sampleRate

        // Update current output device name
        updateOutputDeviceName()

        // Configure synth
        synth.setSampleRate(Float(sampleRate))
        synth.setAlgorithm(algorithm)
        synth.setMasterVolume(masterVolume)
        for (i, level) in operatorLevels.enumerated() {
            synth.setOperatorLevel(i, level: level)
        }

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

        // Create AVAudioSourceNode — render callback runs directly on CoreAudio's
        // real-time thread, eliminating buffer scheduling latency entirely.
        let synthRef = synth
        let source = Self.makeSourceNode(synth: synthRef, format: format)

        self.sourceNode = source
        self.audioEngine = engine

        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
        } catch {
            throw AudioEngineError.engineStartFailed(underlying: error)
        }

        // Monitor audio configuration changes (output device switch on macOS, route change on iOS)
        configObservers.append(NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleConfigurationChange()
            }
        })

        #if os(iOS)
        // Monitor iOS audio route changes (headphones, Bluetooth, AirPlay)
        configObservers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let changeReason = AVAudioSession.RouteChangeReason(rawValue: reason) else { return }

            switch changeReason {
            case .newDeviceAvailable, .oldDeviceUnavailable, .override:
                Task { @MainActor [weak self] in
                    self?.handleConfigurationChange()
                }
            default:
                break
            }
        })

        // Monitor iOS audio interruptions (phone calls, alarms, etc.)
        configObservers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

            if type == .ended {
                Task { @MainActor [weak self] in
                    self?.handleConfigurationChange()
                }
            }
        })
        #endif
    }

    /// Whether a configuration change restart is already in progress (prevents re-entrant calls)
    private var isRestarting = false

    /// Handle audio configuration change (e.g. output device switched)
    private func handleConfigurationChange() {
        guard !isRestarting else { return }
        isRestarting = true
        audioLogger.info("Configuration changed, restarting engine...")
        let wasRunning = isRunning
        stop()
        if wasRunning {
            Task {
                await start()
                isRestarting = false
            }
        } else {
            isRestarting = false
        }
    }

    /// Update the current output device name
    private func updateOutputDeviceName() {
        #if os(iOS)
        let route = AVAudioSession.sharedInstance().currentRoute
        if let output = route.outputs.first {
            currentOutputDevice = output.portName
        } else {
            currentOutputDevice = "Speaker"
        }
        #elseif os(macOS)
        currentOutputDevice = macOSOutputDeviceName() ?? "Default"
        #endif
    }

    #if os(macOS)
    /// Get the current macOS default output device name via CoreAudio
    private func macOSOutputDeviceName() -> String? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        guard status == noErr else { return nil }

        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var nameSize = UInt32(MemoryLayout<CFString>.size)
        let nameStatus = AudioObjectGetPropertyData(
            deviceID, &nameAddress, 0, nil, &nameSize, &name
        )
        guard nameStatus == noErr else { return nil }
        return name as String
    }

    /// List all available macOS output devices
    public func listMacOutputDevices() -> [(id: AudioDeviceID, name: String)] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        )
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices
        )

        var result: [(id: AudioDeviceID, name: String)] = []
        for deviceID in devices {
            // Check if device has output streams
            var streamAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            AudioObjectGetPropertyDataSize(deviceID, &streamAddress, 0, nil, &streamSize)
            guard streamSize > 0 else { continue }

            // Get device name
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var name: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            let status = AudioObjectGetPropertyData(
                deviceID, &nameAddress, 0, nil, &nameSize, &name
            )
            if status == noErr {
                result.append((id: deviceID, name: name as String))
            }
        }
        return result
    }

    /// Set macOS output device by AudioDeviceID
    public func setMacOutputDevice(_ deviceID: AudioDeviceID) {
        guard let engine = audioEngine else { return }
        let outputNode = engine.outputNode
        let outputUnit = outputNode.audioUnit!

        var id = deviceID
        let status = AudioUnitSetProperty(
            outputUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status == noErr {
            // Restart to apply the new device
            handleConfigurationChange()
        } else {
            audioLogger.error("Failed to set output device: \(status, privacy: .public)")
        }
    }
    #endif

    // MARK: - Source Node Factory

    /// Create AVAudioSourceNode outside @MainActor to avoid Sendable closure issues
    nonisolated private static func makeSourceNode(
        synth: FMSynthEngine,
        format: AVAudioFormat
    ) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard ablPointer.count >= 2,
                  let leftBuffer = ablPointer[0].mData?.assumingMemoryBound(to: Float.self),
                  let rightBuffer = ablPointer[1].mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }

            let frames = Int(frameCount)

            // Zero buffers
            memset(leftBuffer, 0, frames * MemoryLayout<Float>.size)
            memset(rightBuffer, 0, frames * MemoryLayout<Float>.size)

            // Render synth directly into CoreAudio buffers
            synth.render(into: leftBuffer, bufferR: rightBuffer, frameCount: frames)

            return noErr
        }
    }

    // MARK: - MIDI Note Control

    /// Send note on event (16-bit velocity, default 0x7F00 ≈ MIDI 1.0 velocity 127)
    public func noteOn(_ note: UInt8, velocity16: UInt16 = 0x7F00) {
        guard isRunning else { return }
        activeNotes.insert(note)
        synth.midiQueue.enqueue(MIDIEvent(kind: .noteOn, data1: note, data2: UInt32(velocity16)))
    }

    /// Send note off event
    public func noteOff(_ note: UInt8) {
        guard isRunning else { return }
        activeNotes.remove(note)
        synth.midiQueue.enqueue(MIDIEvent(kind: .noteOff, data1: note, data2: 0))
    }

    /// Send control change event (32-bit value)
    public func controlChange(_ controller: UInt8, value32: UInt32) {
        guard isRunning else { return }
        synth.midiQueue.enqueue(MIDIEvent(kind: .controlChange, data1: controller, data2: value32))
    }

    /// Send pitch bend event (32-bit unsigned, center=0x80000000)
    public func pitchBend(_ value32: UInt32) {
        guard isRunning else { return }
        synth.midiQueue.enqueue(MIDIEvent(kind: .pitchBend, data1: 0, data2: value32))
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

    /// Set operator EG rates (DX7 style: R1-R4, range 0-99)
    public func setOperatorEGRates(_ opIndex: Int, r1: Float, r2: Float, r3: Float, r4: Float) {
        guard opIndex >= 0 && opIndex < 6 else { return }
        synth.setOperatorEGRates(opIndex, r1: r1, r2: r2, r3: r3, r4: r4)
    }

    /// Set operator EG levels (DX7 style: L1-L4, range 0.0-1.0)
    public func setOperatorEGLevels(_ opIndex: Int, l1: Float, l2: Float, l3: Float, l4: Float) {
        guard opIndex >= 0 && opIndex < 6 else { return }
        synth.setOperatorEGLevels(opIndex, l1: l1, l2: l2, l3: l3, l4: l4)
    }

    // MARK: - Preset Loading

    /// Load a DX7 preset, applying all parameters to the synth engine
    public func loadPreset(_ preset: DX7Preset) {
        // Stop all playing notes first
        allNotesOff()

        // Set algorithm
        algorithm = preset.algorithm

        // Apply per-operator parameters
        for (i, op) in preset.operators.enumerated() {
            guard i < 6 else { break }

            // Level
            synth.setOperatorLevel(i, level: op.normalizedLevel)
            if i < operatorLevels.count {
                operatorLevels[i] = op.normalizedLevel
            }

            // Frequency ratio
            synth.setOperatorRatio(i, ratio: op.frequencyRatio)

            // Detune
            synth.setOperatorDetune(i, cents: op.detuneCents)

            // Feedback (from the preset's global feedback, applied to the operator that has it)
            let fb = op.feedback > 0 ? Float(op.feedback) / 7.0 : 0
            synth.setOperatorFeedback(i, feedback: fb)

            // EG rates (DX7 native 0-99 values)
            let rates = op.egRatesDX7
            synth.setOperatorEGRates(i, r1: rates.0, r2: rates.1, r3: rates.2, r4: rates.3)

            // EG levels (normalized 0.0-1.0)
            let levels = op.egLevelsNormalized
            synth.setOperatorEGLevels(i, l1: levels.0, l2: levels.1, l3: levels.2, l4: levels.3)
        }
    }
}
