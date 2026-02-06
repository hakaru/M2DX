// M2DXCore.swift
// Core module for MIDI 2.0 integration and parameter management

import Foundation

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
