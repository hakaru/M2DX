import AudioToolbox
import AVFoundation
import CoreAudioKit
import M2DXCore

/// M2DX AUv3 Audio Unit - 6-Operator FM Synthesizer (DX7 Compatible)
public class M2DXAudioUnit: AUAudioUnit {

    // MARK: - Properties

    private var kernel: M2DXKernelBridge!
    private var _parameterTree: AUParameterTree!
    private var _outputBusArray: AUAudioUnitBusArray!

    // MARK: - Property Exchange

    /// Property Exchange resource for MIDI 2.0 PE
    private var _peResource: M2DXPEResource!

    /// Property Exchange bridge for AU ↔ PE synchronization
    private var _peBridge: M2DXPEBridge!

    private var outputBus: AUAudioUnitBus!
    private let maxFramesToRender: UInt32 = 512

    // MARK: - Initialization

    public override init(
        componentDescription: AudioComponentDescription,
        options: AudioComponentInstantiationOptions = []
    ) throws {
        try super.init(componentDescription: componentDescription, options: options)

        // Initialize kernel with default sample rate
        kernel = M2DXKernelBridge(sampleRate: 44100.0)

        // Create output format
        let format = AVAudioFormat(
            standardFormatWithSampleRate: 44100.0,
            channels: 2
        )!

        outputBus = try AUAudioUnitBus(format: format)
        _outputBusArray = AUAudioUnitBusArray(
            audioUnit: self,
            busType: .output,
            busses: [outputBus]
        )

        // Build parameter tree
        _parameterTree = buildParameterTree()

        // Set up parameter observation
        setupParameterObservation()

        // Initialize Property Exchange
        setupPropertyExchange()
    }

    // MARK: - Property Exchange Setup

    private func setupPropertyExchange() {
        _peResource = M2DXPEResource()
        _peBridge = M2DXPEBridge(peResource: _peResource)

        // Connect PE bridge to parameter tree for bidirectional sync
        _peBridge.connect(to: _parameterTree)
    }

    /// Public access to Property Exchange resource
    public var propertyExchangeResource: M2DXPEResource {
        return _peResource
    }

    /// Public access to Property Exchange bridge
    public var propertyExchangeBridge: M2DXPEBridge {
        return _peBridge
    }

    /// Get all available PE resources
    public func getPropertyExchangeResources() -> [PEResourceDescriptor] {
        return _peBridge.getResources()
    }

    /// Get PE value at path
    public func getPropertyExchangeValue(at path: String) throws -> PEValue {
        return try _peBridge.getValue(at: path)
    }

    /// Set PE value at path
    public func setPropertyExchangeValue(_ value: PEValue, at path: String) throws {
        try _peBridge.setValue(value, at: path)
    }

    // MARK: - AUAudioUnit Overrides

    public override var outputBusses: AUAudioUnitBusArray {
        return _outputBusArray
    }

    public override var parameterTree: AUParameterTree? {
        get { return _parameterTree }
        set { _parameterTree = newValue }
    }

    public override var channelCapabilities: [NSNumber]? {
        // Stereo output only
        return [NSNumber(value: 0), NSNumber(value: 2)]
    }

    public override func allocateRenderResources() throws {
        try super.allocateRenderResources()

        let sampleRate = outputBus.format.sampleRate
        kernel.setSampleRate(sampleRate)
    }

    public override func deallocateRenderResources() {
        super.deallocateRenderResources()
    }

    public override var internalRenderBlock: AUInternalRenderBlock {
        // Safely capture kernel reference for render block
        guard let kernel = self.kernel else {
            // Return error block if kernel is not initialized
            return { _, _, _, _, _, _, _ in kAudioUnitErr_Uninitialized }
        }

        return { actionFlags, timestamp, frameCount, outputBusNumber, outputData, realtimeEventListHead, pullInputBlock in

            // Handle MIDI events
            var nextEvent: UnsafePointer<AURenderEvent>? = realtimeEventListHead
            while let event = nextEvent {
                Self.handleMIDIEventStatic(event, kernel: kernel)
                nextEvent = UnsafePointer(event.pointee.head.next)
            }

            // Get output buffer
            let outputBufferList = UnsafeMutableAudioBufferListPointer(outputData)

            // Validate buffer count
            guard outputBufferList.count >= 2 else {
                actionFlags.pointee = AudioUnitRenderActionFlags()
                return kAudioUnitErr_InvalidParameter
            }

            // Validate buffer pointers
            guard let leftBuffer = outputBufferList[0].mData?.assumingMemoryBound(to: Float.self),
                  let rightBuffer = outputBufferList[1].mData?.assumingMemoryBound(to: Float.self) else {
                // Clear buffers if possible to prevent noise output
                if let mData = outputBufferList[0].mData {
                    memset(mData, 0, Int(outputBufferList[0].mDataByteSize))
                }
                if let mData = outputBufferList[1].mData {
                    memset(mData, 0, Int(outputBufferList[1].mDataByteSize))
                }
                return kAudioUnitErr_InvalidParameter
            }

            // Process audio
            kernel.processBufferLeft(leftBuffer, right: rightBuffer, frameCount: Int32(frameCount))

            return noErr
        }
    }

    // MARK: - MIDI Handling

    private static func handleMIDIEventStatic(_ eventPtr: UnsafePointer<AURenderEvent>, kernel: M2DXKernelBridge) {
        let event = eventPtr.pointee
        guard event.head.eventType == .MIDI || event.head.eventType == .midiSysEx else { return }

        let midiEvent = event.MIDI
        let status = midiEvent.data.0
        let data1 = midiEvent.data.1
        let data2 = midiEvent.data.2

        let messageType = status & 0xF0

        switch messageType {
        case 0x90: // Note On
            if data2 > 0 {
                kernel.handleNoteOn(data1, velocity: data2)
            } else {
                kernel.handleNoteOff(data1)
            }

        case 0x80: // Note Off
            kernel.handleNoteOff(data1)

        case 0xB0: // Control Change
            handleControlChangeStatic(controller: data1, value: data2, kernel: kernel)

        default:
            break
        }
    }

    private static func handleControlChangeStatic(controller: UInt8, value: UInt8, kernel: M2DXKernelBridge) {
        switch controller {
        case 1: // Modulation wheel
            // Could be mapped to vibrato depth or other modulation
            break

        case 7: // Volume
            kernel.setMasterVolume(Float(value) / 127.0)

        case 123: // All Notes Off
            kernel.allNotesOff()

        default:
            break
        }
    }

    // MARK: - Parameter Tree

    private func buildParameterTree() -> AUParameterTree {
        var parameters: [AUParameter] = []

        // Global parameters
        let algorithm = AUParameterTree.createParameter(
            withIdentifier: "algorithm",
            name: "Algorithm",
            address: AUParameterAddress(M2DXParameterAddressHelper.algorithm),
            min: 0,
            max: 31,  // DX7 compatible: 32 algorithms (0-31)
            unit: .indexed,
            unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable],
            valueStrings: nil,
            dependentParameters: nil
        )
        algorithm.value = 0
        parameters.append(algorithm)

        let masterVolume = AUParameterTree.createParameter(
            withIdentifier: "masterVolume",
            name: "Master Volume",
            address: AUParameterAddress(M2DXParameterAddressHelper.masterVolume),
            min: 0,
            max: 1,
            unit: .linearGain,
            unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable],
            valueStrings: nil,
            dependentParameters: nil
        )
        masterVolume.value = 0.7
        parameters.append(masterVolume)

        // Operator parameters (6 operators, DX7 compatible)
        for opIndex in 0..<6 {
            let opParams = createOperatorParameters(index: opIndex)
            parameters.append(contentsOf: opParams)
        }

        return AUParameterTree.createTree(withChildren: parameters)
    }

    private func createOperatorParameters(index: Int) -> [AUParameter] {
        let prefix = "op\(index + 1)"
        var params: [AUParameter] = []

        // Level
        let level = AUParameterTree.createParameter(
            withIdentifier: "\(prefix)Level",
            name: "OP\(index + 1) Level",
            address: AUParameterAddress(M2DXParameterAddressHelper.operatorLevelAddress(index: index)),
            min: 0,
            max: 1,
            unit: .linearGain,
            unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable],
            valueStrings: nil,
            dependentParameters: nil
        )
        level.value = index < 4 ? 1.0 : 0.5
        params.append(level)

        // Ratio
        let ratio = AUParameterTree.createParameter(
            withIdentifier: "\(prefix)Ratio",
            name: "OP\(index + 1) Ratio",
            address: AUParameterAddress(M2DXParameterAddressHelper.operatorRatioAddress(index: index)),
            min: 0.5,
            max: 32,
            unit: .ratio,
            unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable],
            valueStrings: nil,
            dependentParameters: nil
        )
        ratio.value = Float(index + 1)
        params.append(ratio)

        // Detune
        let detune = AUParameterTree.createParameter(
            withIdentifier: "\(prefix)Detune",
            name: "OP\(index + 1) Detune",
            address: AUParameterAddress(M2DXParameterAddressHelper.operatorDetuneAddress(index: index)),
            min: -100,
            max: 100,
            unit: .cents,
            unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable],
            valueStrings: nil,
            dependentParameters: nil
        )
        detune.value = 0
        params.append(detune)

        // Feedback
        let feedback = AUParameterTree.createParameter(
            withIdentifier: "\(prefix)Feedback",
            name: "OP\(index + 1) Feedback",
            address: AUParameterAddress(M2DXParameterAddressHelper.operatorFeedbackAddress(index: index)),
            min: 0,
            max: 1,
            unit: .generic,
            unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable],
            valueStrings: nil,
            dependentParameters: nil
        )
        feedback.value = index == 5 ? 0.3 : 0.0
        params.append(feedback)

        // EG Rates
        for rateIndex in 0..<4 {
            let rate = AUParameterTree.createParameter(
                withIdentifier: "\(prefix)EGRate\(rateIndex + 1)",
                name: "OP\(index + 1) EG Rate \(rateIndex + 1)",
                address: AUParameterAddress(M2DXParameterAddressHelper.operatorEGRateAddress(index: index, rateIndex: rateIndex)),
                min: 0,
                max: 99,
                unit: .generic,
                unitName: nil,
                flags: [.flag_IsReadable, .flag_IsWritable],
                valueStrings: nil,
                dependentParameters: nil
            )
            rate.value = [99, 75, 50, 50][rateIndex]
            params.append(rate)
        }

        // EG Levels
        for levelIndex in 0..<4 {
            let egLevel = AUParameterTree.createParameter(
                withIdentifier: "\(prefix)EGLevel\(levelIndex + 1)",
                name: "OP\(index + 1) EG Level \(levelIndex + 1)",
                address: AUParameterAddress(M2DXParameterAddressHelper.operatorEGLevelAddress(index: index, levelIndex: levelIndex)),
                min: 0,
                max: 1,
                unit: .linearGain,
                unitName: nil,
                flags: [.flag_IsReadable, .flag_IsWritable],
                valueStrings: nil,
                dependentParameters: nil
            )
            egLevel.value = [1.0, 0.8, 0.6, 0.0][levelIndex]
            params.append(egLevel)
        }

        return params
    }

    private func setupParameterObservation() {
        _parameterTree.implementorValueObserver = { [weak self] param, value in
            self?.handleParameterChange(address: param.address, value: value)
        }

        _parameterTree.implementorValueProvider = { [weak self] param in
            return self?.getParameterValue(address: param.address) ?? param.value
        }
    }

    private func handleParameterChange(address: AUParameterAddress, value: AUValue) {
        // Global parameters
        if address == AUParameterAddress(M2DXParameterAddressHelper.algorithm) {
            kernel.setAlgorithm(Int32(value))
            return
        }

        if address == AUParameterAddress(M2DXParameterAddressHelper.masterVolume) {
            kernel.setMasterVolume(value)
            return
        }

        // Operator parameters
        let operatorBase = M2DXParameterAddressHelper.operatorBase
        let operatorStride = M2DXParameterAddressHelper.operatorStride

        if address >= operatorBase && address < operatorBase + operatorStride * 6 {
            let opIndex = Int32((address - operatorBase) / operatorStride)
            let paramOffset = (address - operatorBase) % operatorStride

            switch paramOffset {
            case M2DXParameterAddressHelper.operatorLevelOffset:
                kernel.setOperatorLevel(opIndex, level: value)
            case M2DXParameterAddressHelper.operatorRatioOffset:
                kernel.setOperatorRatio(opIndex, ratio: value)
            case M2DXParameterAddressHelper.operatorDetuneOffset:
                kernel.setOperatorDetune(opIndex, detuneCents: value)
            case M2DXParameterAddressHelper.operatorFeedbackOffset:
                kernel.setOperatorFeedback(opIndex, feedback: value)
            case M2DXParameterAddressHelper.operatorEGRateBase...M2DXParameterAddressHelper.operatorEGRateBase + 3:
                updateEnvelopeRates(opIndex: opIndex)
            case M2DXParameterAddressHelper.operatorEGLevelBase...M2DXParameterAddressHelper.operatorEGLevelBase + 3:
                updateEnvelopeLevels(opIndex: opIndex)
            default:
                break
            }
        }
    }

    private func updateEnvelopeRates(opIndex: Int32) {
        let r1 = _parameterTree.parameter(withAddress: AUParameterAddress(M2DXParameterAddressHelper.operatorEGRateAddress(index: Int(opIndex), rateIndex: 0)))?.value ?? 99
        let r2 = _parameterTree.parameter(withAddress: AUParameterAddress(M2DXParameterAddressHelper.operatorEGRateAddress(index: Int(opIndex), rateIndex: 1)))?.value ?? 75
        let r3 = _parameterTree.parameter(withAddress: AUParameterAddress(M2DXParameterAddressHelper.operatorEGRateAddress(index: Int(opIndex), rateIndex: 2)))?.value ?? 50
        let r4 = _parameterTree.parameter(withAddress: AUParameterAddress(M2DXParameterAddressHelper.operatorEGRateAddress(index: Int(opIndex), rateIndex: 3)))?.value ?? 50
        kernel.setOperatorEnvelopeRates(opIndex, r1: r1, r2: r2, r3: r3, r4: r4)
    }

    private func updateEnvelopeLevels(opIndex: Int32) {
        let l1 = _parameterTree.parameter(withAddress: AUParameterAddress(M2DXParameterAddressHelper.operatorEGLevelAddress(index: Int(opIndex), levelIndex: 0)))?.value ?? 1.0
        let l2 = _parameterTree.parameter(withAddress: AUParameterAddress(M2DXParameterAddressHelper.operatorEGLevelAddress(index: Int(opIndex), levelIndex: 1)))?.value ?? 0.8
        let l3 = _parameterTree.parameter(withAddress: AUParameterAddress(M2DXParameterAddressHelper.operatorEGLevelAddress(index: Int(opIndex), levelIndex: 2)))?.value ?? 0.6
        let l4 = _parameterTree.parameter(withAddress: AUParameterAddress(M2DXParameterAddressHelper.operatorEGLevelAddress(index: Int(opIndex), levelIndex: 3)))?.value ?? 0.0
        kernel.setOperatorEnvelopeLevels(opIndex, l1: l1, l2: l2, l3: l3, l4: l4)
    }

    private func getParameterValue(address: AUParameterAddress) -> AUValue {
        // Return cached parameter value from tree
        return _parameterTree.parameter(withAddress: address)?.value ?? 0
    }
}

// MARK: - Parameter Address Constants

/// Parameter address structure matching DX7Constants.hpp
/// Provides type-safe access to parameter addresses with helper methods
/// Note: This is an internal helper structure, distinct from the public M2DXParameterAddress enum
enum M2DXParameterAddressHelper {
    // Global parameters
    static let algorithm: UInt64 = 0
    static let masterVolume: UInt64 = 1
    static let globalFeedback: UInt64 = 2

    // Operator parameter structure
    static let operatorBase: UInt64 = 100
    static let operatorStride: UInt64 = 100

    // Operator parameter offsets
    static let operatorLevelOffset: UInt64 = 0
    static let operatorRatioOffset: UInt64 = 1
    static let operatorDetuneOffset: UInt64 = 2
    static let operatorFeedbackOffset: UInt64 = 3
    static let operatorEGRateBase: UInt64 = 10
    static let operatorEGLevelBase: UInt64 = 20

    // Helper methods for operator parameter addresses
    static func operatorAddress(index: Int, offset: UInt64) -> UInt64 {
        return operatorBase + UInt64(index) * operatorStride + offset
    }

    static func operatorLevelAddress(index: Int) -> UInt64 {
        return operatorAddress(index: index, offset: operatorLevelOffset)
    }

    static func operatorRatioAddress(index: Int) -> UInt64 {
        return operatorAddress(index: index, offset: operatorRatioOffset)
    }

    static func operatorDetuneAddress(index: Int) -> UInt64 {
        return operatorAddress(index: index, offset: operatorDetuneOffset)
    }

    static func operatorFeedbackAddress(index: Int) -> UInt64 {
        return operatorAddress(index: index, offset: operatorFeedbackOffset)
    }

    static func operatorEGRateAddress(index: Int, rateIndex: Int) -> UInt64 {
        return operatorAddress(index: index, offset: operatorEGRateBase + UInt64(rateIndex))
    }

    static func operatorEGLevelAddress(index: Int, levelIndex: Int) -> UInt64 {
        return operatorAddress(index: index, offset: operatorEGLevelBase + UInt64(levelIndex))
    }
}

// MARK: - Factory Function

/// Factory function called by Audio Unit host - must be a global function
public func M2DXAudioUnitFactory(
    componentDescription: UnsafePointer<AudioComponentDescription>
) -> AUAudioUnit? {
    do {
        return try M2DXAudioUnit(componentDescription: componentDescription.pointee)
    } catch {
        print("M2DXAudioUnit factory error: \(error)")
        return nil
    }
}
