// DX7Preset.swift
// DX7 preset data model with parameter conversion

import Foundation

// MARK: - Preset Category

/// Categories for organizing presets
public enum PresetCategory: String, Codable, CaseIterable, Sendable {
    case keys, bass, brass, strings, organ, percussion, woodwind, other
}

// MARK: - DX7 Operator Preset

/// DX7-native operator parameters (all values in DX7 range)
public struct DX7OperatorPreset: Codable, Sendable, Equatable {
    public let outputLevel: Int      // 0-99
    public let frequencyCoarse: Int  // 0-31
    public let frequencyFine: Int    // 0-99
    public let detune: Int           // 0-14 (7=center)
    public let feedback: Int         // 0-7 (only effective on feedback OP)
    public let egRate1: Int          // 0-99
    public let egRate2: Int          // 0-99
    public let egRate3: Int          // 0-99
    public let egRate4: Int          // 0-99
    public let egLevel1: Int         // 0-99
    public let egLevel2: Int         // 0-99
    public let egLevel3: Int         // 0-99
    public let egLevel4: Int         // 0-99

    public init(
        outputLevel: Int = 99,
        frequencyCoarse: Int = 1,
        frequencyFine: Int = 0,
        detune: Int = 7,
        feedback: Int = 0,
        egRate1: Int = 99, egRate2: Int = 99, egRate3: Int = 99, egRate4: Int = 99,
        egLevel1: Int = 99, egLevel2: Int = 99, egLevel3: Int = 99, egLevel4: Int = 0
    ) {
        self.outputLevel = outputLevel
        self.frequencyCoarse = frequencyCoarse
        self.frequencyFine = frequencyFine
        self.detune = detune
        self.feedback = feedback
        self.egRate1 = egRate1
        self.egRate2 = egRate2
        self.egRate3 = egRate3
        self.egRate4 = egRate4
        self.egLevel1 = egLevel1
        self.egLevel2 = egLevel2
        self.egLevel3 = egLevel3
        self.egLevel4 = egLevel4
    }
}

// MARK: - DX7 Preset

/// Complete DX7 voice preset
public struct DX7Preset: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let name: String           // DX7-compatible 10-char name
    public let algorithm: Int         // 0-31 (0-indexed)
    public let feedback: Int          // 0-7
    public let operators: [DX7OperatorPreset]  // 6 operators
    public let category: PresetCategory

    public init(
        id: UUID = UUID(),
        name: String,
        algorithm: Int,
        feedback: Int,
        operators: [DX7OperatorPreset],
        category: PresetCategory
    ) {
        self.id = id
        self.name = name
        self.algorithm = algorithm
        self.feedback = feedback
        self.operators = operators
        self.category = category
    }
}

// MARK: - DX7 → M2DX Parameter Conversion

extension DX7OperatorPreset {
    /// Convert DX7 output level (0-99) to normalized amplitude (0.0-1.0)
    /// DX7 uses a logarithmic curve: ~0.75 dB per step from max (99)
    /// OL 99 = 0 dB (amplitude 1.0), OL 0 = ~-74 dB (near silence)
    public var normalizedLevel: Float {
        guard outputLevel > 0 else { return 0 }
        guard outputLevel < 99 else { return 1.0 }
        // DX7 level curve: each step below 99 reduces by ~0.75 dB
        let dB = Float(99 - outputLevel) * -0.75
        return powf(10.0, dB / 20.0)
    }

    /// Convert DX7 frequency coarse + fine to ratio
    /// Coarse: 0→0.5, 1→1.0, N→N.0
    /// Fine: multiplies by (1 + fine/100)
    public var frequencyRatio: Float {
        let coarse: Float = frequencyCoarse == 0 ? 0.5 : Float(frequencyCoarse)
        return coarse * (1.0 + Float(frequencyFine) / 100.0)
    }

    /// Convert DX7 detune (0-14, 7=center) to cents offset
    public var detuneCents: Float {
        Float(detune - 7)
    }

    /// Convert DX7 feedback (0-7) to normalized feedback (0.0-1.0)
    public var normalizedFeedback: Float {
        Float(feedback) / 7.0
    }

    /// EG rates as DX7 native values (0-99) for direct use
    public var egRatesDX7: (Float, Float, Float, Float) {
        (Float(egRate1), Float(egRate2), Float(egRate3), Float(egRate4))
    }

    /// EG levels normalized (0.0-1.0)
    public var egLevelsNormalized: (Float, Float, Float, Float) {
        (Float(egLevel1) / 99.0, Float(egLevel2) / 99.0,
         Float(egLevel3) / 99.0, Float(egLevel4) / 99.0)
    }
}

extension DX7Preset {
    /// Convert DX7 feedback (0-7) to normalized (0.0-1.0)
    public var normalizedFeedback: Float {
        Float(feedback) / 7.0
    }
}
