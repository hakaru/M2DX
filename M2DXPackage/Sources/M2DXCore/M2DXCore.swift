// M2DXCore.swift
// Core module for MIDI 2.0 integration and parameter management

import Foundation

// MARK: - Synth Engine Mode

/// M2DX supports two engine modes
public enum SynthEngineMode: String, CaseIterable, Sendable {
    /// M2DX native 8-operator FM synthesis
    case m2dx8op = "M2DX 8-OP"

    /// TX816 simulation: 8 independent 6-operator modules (multitimbral)
    case tx816 = "TX816"
}

// MARK: - Algorithm Definitions

/// Classic DX7 Algorithm (1-32) for 6-operator mode
public enum DX7Algorithm: Int, CaseIterable, Sendable {
    case algorithm1 = 1, algorithm2, algorithm3, algorithm4
    case algorithm5, algorithm6, algorithm7, algorithm8
    case algorithm9, algorithm10, algorithm11, algorithm12
    case algorithm13, algorithm14, algorithm15, algorithm16
    case algorithm17, algorithm18, algorithm19, algorithm20
    case algorithm21, algorithm22, algorithm23, algorithm24
    case algorithm25, algorithm26, algorithm27, algorithm28
    case algorithm29, algorithm30, algorithm31, algorithm32
}

/// Extended M2DX Algorithm (1-64) for 8-operator mode
public enum M2DXAlgorithm: Int, CaseIterable, Sendable {
    // Classic DX7 algorithms (1-32) adapted for 8-op
    case algorithm1 = 1, algorithm2, algorithm3, algorithm4
    case algorithm5, algorithm6, algorithm7, algorithm8
    case algorithm9, algorithm10, algorithm11, algorithm12
    case algorithm13, algorithm14, algorithm15, algorithm16
    case algorithm17, algorithm18, algorithm19, algorithm20
    case algorithm21, algorithm22, algorithm23, algorithm24
    case algorithm25, algorithm26, algorithm27, algorithm28
    case algorithm29, algorithm30, algorithm31, algorithm32

    // Extended 8-operator algorithms (33-64)
    case algorithm33, algorithm34, algorithm35, algorithm36
    case algorithm37, algorithm38, algorithm39, algorithm40
    case algorithm41, algorithm42, algorithm43, algorithm44
    case algorithm45, algorithm46, algorithm47, algorithm48
    case algorithm49, algorithm50, algorithm51, algorithm52
    case algorithm53, algorithm54, algorithm55, algorithm56
    case algorithm57, algorithm58, algorithm59, algorithm60
    case algorithm61, algorithm62, algorithm63, algorithm64

    /// Whether this is an extended 8-op only algorithm
    public var isExtended: Bool {
        rawValue > 32
    }
}

// MARK: - Operator Parameters

/// FM Operator parameters
public struct OperatorParameters: Sendable, Equatable, Identifiable {
    public let id: Int

    /// Operator level (0-99 in DX7, normalized to 0.0-1.0)
    public var level: Double

    /// Frequency ratio (coarse + fine)
    public var frequencyRatio: Double

    /// Detune (-7 to +7 in DX7, extended to -50...+50 for MIDI 2.0 32-bit)
    public var detune: Int

    /// Fixed frequency mode
    public var fixedFrequency: Bool

    /// Fixed frequency value (Hz) when fixedFrequency is true
    public var fixedFrequencyValue: Double

    /// Envelope Generator rates and levels
    public var envelope: EnvelopeParameters

    /// Key velocity sensitivity (0.0-1.0)
    public var velocitySensitivity: Double

    /// LFO amplitude modulation sensitivity
    public var lfoAmpModSensitivity: Double

    /// Keyboard rate scaling
    public var keyboardRateScaling: Double

    /// Keyboard level scaling
    public var keyboardLevelScaling: KeyboardLevelScaling

    /// Output level for carrier operators
    public var outputLevel: Double

    public init(
        id: Int = 0,
        level: Double = 0.99,
        frequencyRatio: Double = 1.0,
        detune: Int = 0,
        fixedFrequency: Bool = false,
        fixedFrequencyValue: Double = 440.0,
        envelope: EnvelopeParameters = EnvelopeParameters(),
        velocitySensitivity: Double = 0.0,
        lfoAmpModSensitivity: Double = 0.0,
        keyboardRateScaling: Double = 0.0,
        keyboardLevelScaling: KeyboardLevelScaling = KeyboardLevelScaling(),
        outputLevel: Double = 1.0
    ) {
        self.id = id
        self.level = level
        self.frequencyRatio = frequencyRatio
        self.detune = detune
        self.fixedFrequency = fixedFrequency
        self.fixedFrequencyValue = fixedFrequencyValue
        self.envelope = envelope
        self.velocitySensitivity = velocitySensitivity
        self.lfoAmpModSensitivity = lfoAmpModSensitivity
        self.keyboardRateScaling = keyboardRateScaling
        self.keyboardLevelScaling = keyboardLevelScaling
        self.outputLevel = outputLevel
    }

    /// Create default operator with ID
    public static func defaultOperator(id: Int) -> OperatorParameters {
        OperatorParameters(id: id)
    }
}

// MARK: - Envelope Parameters

/// ADSR-like envelope with 4 rates and 4 levels (DX7 style)
public struct EnvelopeParameters: Sendable, Equatable {
    public var rate1: Double
    public var rate2: Double
    public var rate3: Double
    public var rate4: Double

    public var level1: Double
    public var level2: Double
    public var level3: Double
    public var level4: Double

    public init(
        rate1: Double = 0.99,
        rate2: Double = 0.99,
        rate3: Double = 0.99,
        rate4: Double = 0.99,
        level1: Double = 0.99,
        level2: Double = 0.99,
        level3: Double = 0.99,
        level4: Double = 0.0
    ) {
        self.rate1 = rate1
        self.rate2 = rate2
        self.rate3 = rate3
        self.rate4 = rate4
        self.level1 = level1
        self.level2 = level2
        self.level3 = level3
        self.level4 = level4
    }
}

// MARK: - Keyboard Level Scaling

/// Keyboard level scaling parameters
public struct KeyboardLevelScaling: Sendable, Equatable {
    public var breakPoint: Int
    public var leftDepth: Double
    public var rightDepth: Double
    public var leftCurve: ScalingCurve
    public var rightCurve: ScalingCurve

    public init(
        breakPoint: Int = 60,
        leftDepth: Double = 0.0,
        rightDepth: Double = 0.0,
        leftCurve: ScalingCurve = .linear,
        rightCurve: ScalingCurve = .linear
    ) {
        self.breakPoint = breakPoint
        self.leftDepth = leftDepth
        self.rightDepth = rightDepth
        self.leftCurve = leftCurve
        self.rightCurve = rightCurve
    }

    public enum ScalingCurve: Int, Sendable, CaseIterable {
        case negativeLinear = 0
        case negativeExponential = 1
        case positiveExponential = 2
        case linear = 3
    }
}

// MARK: - LFO Parameters

/// Low Frequency Oscillator parameters
public struct LFOParameters: Sendable, Equatable {
    public var wave: LFOWave
    public var speed: Double
    public var delay: Double
    public var pitchModDepth: Double
    public var ampModDepth: Double
    public var sync: Bool

    public init(
        wave: LFOWave = .triangle,
        speed: Double = 0.35,
        delay: Double = 0.0,
        pitchModDepth: Double = 0.0,
        ampModDepth: Double = 0.0,
        sync: Bool = true
    ) {
        self.wave = wave
        self.speed = speed
        self.delay = delay
        self.pitchModDepth = pitchModDepth
        self.ampModDepth = ampModDepth
        self.sync = sync
    }

    public enum LFOWave: Int, CaseIterable, Sendable {
        case triangle = 0
        case sawDown = 1
        case sawUp = 2
        case square = 3
        case sine = 4
        case sampleAndHold = 5
    }
}

// MARK: - Modulation Matrix (M2DX Extended)

/// Modulation source for matrix routing
public enum ModulationSource: String, CaseIterable, Sendable {
    case velocity = "Velocity"
    case aftertouch = "Aftertouch"
    case modWheel = "Mod Wheel"
    case pitchBend = "Pitch Bend"
    case lfo1 = "LFO 1"
    case lfo2 = "LFO 2"
    case envelope1 = "Envelope 1"
    case envelope2 = "Envelope 2"
    case keyTracking = "Key Tracking"
}

/// Modulation destination for matrix routing
public enum ModulationDestination: String, CaseIterable, Sendable {
    case op1Level = "OP1 Level"
    case op2Level = "OP2 Level"
    case op3Level = "OP3 Level"
    case op4Level = "OP4 Level"
    case op5Level = "OP5 Level"
    case op6Level = "OP6 Level"
    case op7Level = "OP7 Level"
    case op8Level = "OP8 Level"
    case pitch = "Pitch"
    case feedback = "Feedback"
    case lfoSpeed = "LFO Speed"
    case filterCutoff = "Filter Cutoff"
}

/// Single modulation routing
public struct ModulationRouting: Sendable, Equatable, Identifiable {
    public let id: UUID
    public var source: ModulationSource
    public var destination: ModulationDestination
    public var amount: Double // -1.0 to 1.0

    public init(
        id: UUID = UUID(),
        source: ModulationSource = .modWheel,
        destination: ModulationDestination = .pitch,
        amount: Double = 0.0
    ) {
        self.id = id
        self.source = source
        self.destination = destination
        self.amount = amount
    }
}

// MARK: - M2DX Voice (8-Operator)

/// M2DX native 8-operator voice parameters
public struct M2DXVoice: Sendable, Equatable, Identifiable {
    public let id: UUID
    public var name: String
    public var algorithm: M2DXAlgorithm
    public var feedback: Double
    public var feedback2: Double // Second feedback path for 8-op
    public var operators: [OperatorParameters]
    public var lfo: LFOParameters
    public var lfo2: LFOParameters // Second LFO for M2DX
    public var pitchEnvelope: EnvelopeParameters
    public var transpose: Int
    public var modulationMatrix: [ModulationRouting]

    public init(
        id: UUID = UUID(),
        name: String = "INIT M2DX",
        algorithm: M2DXAlgorithm = .algorithm1,
        feedback: Double = 0.0,
        feedback2: Double = 0.0,
        operators: [OperatorParameters]? = nil,
        lfo: LFOParameters = LFOParameters(),
        lfo2: LFOParameters = LFOParameters(),
        pitchEnvelope: EnvelopeParameters = EnvelopeParameters(
            rate1: 0.99, rate2: 0.99, rate3: 0.99, rate4: 0.99,
            level1: 0.5, level2: 0.5, level3: 0.5, level4: 0.5
        ),
        transpose: Int = 0,
        modulationMatrix: [ModulationRouting] = []
    ) {
        self.id = id
        self.name = name
        self.algorithm = algorithm
        self.feedback = feedback
        self.feedback2 = feedback2
        self.operators = operators ?? (0..<6).map { OperatorParameters.defaultOperator(id: $0 + 1) }
        self.lfo = lfo
        self.lfo2 = lfo2
        self.pitchEnvelope = pitchEnvelope
        self.transpose = transpose
        self.modulationMatrix = modulationMatrix
    }

    /// Number of operators (DX7 compatible: 6)
    public static let operatorCount = 6
}

// MARK: - DX7 Voice (6-Operator, TX816 Compatible)

/// Classic DX7 6-operator voice parameters (used in TX816 mode)
public struct DX7Voice: Sendable, Equatable, Identifiable {
    public let id: UUID
    public var name: String
    public var algorithm: DX7Algorithm
    public var feedback: Double
    public var operators: [OperatorParameters]
    public var lfo: LFOParameters
    public var pitchEnvelope: EnvelopeParameters
    public var transpose: Int

    public init(
        id: UUID = UUID(),
        name: String = "INIT VOICE",
        algorithm: DX7Algorithm = .algorithm1,
        feedback: Double = 0.0,
        operators: [OperatorParameters]? = nil,
        lfo: LFOParameters = LFOParameters(),
        pitchEnvelope: EnvelopeParameters = EnvelopeParameters(
            rate1: 0.99, rate2: 0.99, rate3: 0.99, rate4: 0.99,
            level1: 0.5, level2: 0.5, level3: 0.5, level4: 0.5
        ),
        transpose: Int = 0
    ) {
        self.id = id
        self.name = name
        self.algorithm = algorithm
        self.feedback = feedback
        self.operators = operators ?? (0..<6).map { OperatorParameters.defaultOperator(id: $0 + 1) }
        self.lfo = lfo
        self.pitchEnvelope = pitchEnvelope
        self.transpose = transpose
    }

    /// Number of operators (always 6 for DX7)
    public static let operatorCount = 6
}

// MARK: - TX816 Module

/// Single TX816 module (TF1 equivalent)
public struct TX816Module: Sendable, Equatable, Identifiable {
    public let id: Int // 1-8
    public var voice: DX7Voice
    public var midiChannel: Int // 1-16
    public var volume: Double // 0.0-1.0
    public var pan: Double // -1.0 (L) to 1.0 (R)
    public var detune: Int // Module-level detune
    public var noteShift: Int // -24 to +24
    public var enabled: Bool

    public init(
        id: Int,
        voice: DX7Voice = DX7Voice(),
        midiChannel: Int = 1,
        volume: Double = 1.0,
        pan: Double = 0.0,
        detune: Int = 0,
        noteShift: Int = 0,
        enabled: Bool = true
    ) {
        self.id = id
        self.voice = voice
        self.midiChannel = midiChannel
        self.volume = volume
        self.pan = pan
        self.detune = detune
        self.noteShift = noteShift
        self.enabled = enabled
    }
}

// MARK: - TX816 Configuration

/// TX816 rack configuration (8 modules)
public struct TX816Configuration: Sendable, Equatable {
    public var modules: [TX816Module]
    public var masterVolume: Double
    public var masterTune: Double // -1.0 to 1.0 (semitone range)

    public init(
        modules: [TX816Module]? = nil,
        masterVolume: Double = 1.0,
        masterTune: Double = 0.0
    ) {
        self.modules = modules ?? (1...8).map { TX816Module(id: $0, midiChannel: $0) }
        self.masterVolume = masterVolume
        self.masterTune = masterTune
    }

    /// Number of modules (always 8 for TX816)
    public static let moduleCount = 8
}

// MARK: - M2DX Engine State

/// Complete M2DX engine state
public struct M2DXEngineState: Sendable, Equatable {
    public var mode: SynthEngineMode
    public var m2dxVoice: M2DXVoice
    public var tx816Config: TX816Configuration

    public init(
        mode: SynthEngineMode = .m2dx8op,
        m2dxVoice: M2DXVoice = M2DXVoice(),
        tx816Config: TX816Configuration = TX816Configuration()
    ) {
        self.mode = mode
        self.m2dxVoice = m2dxVoice
        self.tx816Config = tx816Config
    }
}

// MARK: - Legacy Compatibility

/// Legacy VoiceParameters for backward compatibility
public typealias VoiceParameters = DX7Voice
