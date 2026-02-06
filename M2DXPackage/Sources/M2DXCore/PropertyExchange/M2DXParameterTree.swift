import Foundation

// MARK: - Property Exchange Parameter Definitions

/// MIDI 2.0 Property Exchange parameter value types
public enum PEValueType: String, Sendable {
    case integer
    case float
    case string
    case boolean
    case enumeration
}

/// Type-safe default value for PE parameters
public enum PEDefaultValue: Sendable, Equatable {
    case integer(Int)
    case float(Double)
    case string(String)
    case boolean(Bool)
}

/// Property Exchange parameter definition
public struct PEParameter: Sendable {
    public let path: String
    public let title: String
    public let description: String
    public let type: PEValueType
    public let min: Double?
    public let max: Double?
    public let defaultValue: PEDefaultValue
    public let enumValues: [String]?

    public init(
        path: String,
        title: String,
        description: String = "",
        type: PEValueType,
        min: Double? = nil,
        max: Double? = nil,
        defaultValue: PEDefaultValue,
        enumValues: [String]? = nil
    ) {
        self.path = path
        self.title = title
        self.description = description
        self.type = type
        self.min = min
        self.max = max
        self.defaultValue = defaultValue
        self.enumValues = enumValues
    }
}

// MARK: - M2DX Parameter Tree

/// M2DX Property Exchange Parameter Tree
/// Hierarchical structure for MIDI 2.0 PE compatible parameter access
/// DX7 compatible (6 operators) - 8-operator extension planned for future
public enum M2DXParameterTree {

    /// Number of operators (DX7 compatible = 6, future M2DX extended = 8)
    public static let operatorCount = 6

    // MARK: - Global Parameters

    public static let global: [PEParameter] = [
        PEParameter(
            path: "Global/Algorithm",
            title: "Algorithm",
            description: "FM Algorithm selection (1-32, DX7 compatible)",
            type: .integer,
            min: 1,
            max: 32,
            defaultValue: .integer(1)
        ),
        PEParameter(
            path: "Global/Feedback",
            title: "Feedback",
            description: "Operator feedback amount",
            type: .integer,
            min: 0,
            max: 7,
            defaultValue: .integer(0)
        ),
        PEParameter(
            path: "Global/OscSync",
            title: "Oscillator Sync",
            description: "Oscillator key sync on/off",
            type: .boolean,
            defaultValue: .boolean(true)
        ),
        PEParameter(
            path: "Global/Transpose",
            title: "Transpose",
            description: "Global transpose in semitones",
            type: .integer,
            min: -24,
            max: 24,
            defaultValue: .integer(0)
        ),
        PEParameter(
            path: "Global/VoiceName",
            title: "Voice Name",
            description: "Patch name (10 characters)",
            type: .string,
            defaultValue: .string("INIT VOICE")
        ),
        PEParameter(
            path: "Global/MasterVolume",
            title: "Master Volume",
            description: "Master output volume",
            type: .integer,
            min: 0,
            max: 127,
            defaultValue: .integer(100)
        )
    ]

    // MARK: - Operator Parameters (×6 DX7 compatible)

    /// Generate operator parameters for a given operator index (1-8)
    public static func operatorParameters(for opIndex: Int) -> [PEParameter] {
        let prefix = "Operators/Op\(opIndex)"

        return [
            // Frequency Mode
            PEParameter(
                path: "\(prefix)/Mode",
                title: "Op\(opIndex) Mode",
                description: "Frequency mode: Ratio or Fixed",
                type: .enumeration,
                defaultValue: .string("Ratio"),
                enumValues: ["Ratio", "Fixed"]
            ),

            // Frequency Parameters
            PEParameter(
                path: "\(prefix)/Frequency/Coarse",
                title: "Op\(opIndex) Freq Coarse",
                description: "Coarse frequency ratio (0.5, 1, 2, 3...31)",
                type: .integer,
                min: 0,
                max: 31,
                defaultValue: .integer(opIndex)  // Default to harmonic series
            ),
            PEParameter(
                path: "\(prefix)/Frequency/Fine",
                title: "Op\(opIndex) Freq Fine",
                description: "Fine frequency adjustment",
                type: .integer,
                min: 0,
                max: 99,
                defaultValue: .integer(0)
            ),
            PEParameter(
                path: "\(prefix)/Frequency/Detune",
                title: "Op\(opIndex) Detune",
                description: "Fine detune (-7 to +7)",
                type: .integer,
                min: -7,
                max: 7,
                defaultValue: .integer(0)
            ),

            // Output Level
            PEParameter(
                path: "\(prefix)/Level",
                title: "Op\(opIndex) Level",
                description: "Operator output level",
                type: .integer,
                min: 0,
                max: 99,
                defaultValue: .integer(opIndex <= 4 ? 99 : 70)
            ),

            // Velocity Sensitivity
            PEParameter(
                path: "\(prefix)/VelocitySensitivity",
                title: "Op\(opIndex) Vel Sens",
                description: "Velocity sensitivity",
                type: .integer,
                min: 0,
                max: 7,
                defaultValue: .integer(2)
            ),

            // Amplitude Modulation Sensitivity
            PEParameter(
                path: "\(prefix)/AmpModSensitivity",
                title: "Op\(opIndex) AMS",
                description: "Amplitude modulation sensitivity",
                type: .integer,
                min: 0,
                max: 3,
                defaultValue: .integer(0)
            ),

            // Rate Scaling
            PEParameter(
                path: "\(prefix)/RateScaling",
                title: "Op\(opIndex) Rate Scaling",
                description: "Envelope rate scaling by key",
                type: .integer,
                min: 0,
                max: 7,
                defaultValue: .integer(0)
            ),

            // Keyboard Level Scaling
            PEParameter(
                path: "\(prefix)/KeyboardLevelScaling/BreakPoint",
                title: "Op\(opIndex) KLS Break",
                description: "Keyboard level scaling breakpoint",
                type: .integer,
                min: 0,
                max: 99,
                defaultValue: .integer(39)  // C3
            ),
            PEParameter(
                path: "\(prefix)/KeyboardLevelScaling/LeftDepth",
                title: "Op\(opIndex) KLS L Depth",
                description: "Left side scaling depth",
                type: .integer,
                min: 0,
                max: 99,
                defaultValue: .integer(0)
            ),
            PEParameter(
                path: "\(prefix)/KeyboardLevelScaling/RightDepth",
                title: "Op\(opIndex) KLS R Depth",
                description: "Right side scaling depth",
                type: .integer,
                min: 0,
                max: 99,
                defaultValue: .integer(0)
            ),
            PEParameter(
                path: "\(prefix)/KeyboardLevelScaling/LeftCurve",
                title: "Op\(opIndex) KLS L Curve",
                description: "Left side curve type",
                type: .enumeration,
                defaultValue: .string("Linear-"),
                enumValues: ["Linear-", "Linear+", "Exp-", "Exp+"]
            ),
            PEParameter(
                path: "\(prefix)/KeyboardLevelScaling/RightCurve",
                title: "Op\(opIndex) KLS R Curve",
                description: "Right side curve type",
                type: .enumeration,
                defaultValue: .string("Linear-"),
                enumValues: ["Linear-", "Linear+", "Exp-", "Exp+"]
            ),

            // Envelope Generator Rates
            PEParameter(
                path: "\(prefix)/EG/Rates/Rate1",
                title: "Op\(opIndex) EG R1",
                description: "Envelope rate 1 (attack)",
                type: .integer,
                min: 0,
                max: 99,
                defaultValue: .integer(99)
            ),
            PEParameter(
                path: "\(prefix)/EG/Rates/Rate2",
                title: "Op\(opIndex) EG R2",
                description: "Envelope rate 2 (decay 1)",
                type: .integer,
                min: 0,
                max: 99,
                defaultValue: .integer(75)
            ),
            PEParameter(
                path: "\(prefix)/EG/Rates/Rate3",
                title: "Op\(opIndex) EG R3",
                description: "Envelope rate 3 (decay 2)",
                type: .integer,
                min: 0,
                max: 99,
                defaultValue: .integer(50)
            ),
            PEParameter(
                path: "\(prefix)/EG/Rates/Rate4",
                title: "Op\(opIndex) EG R4",
                description: "Envelope rate 4 (release)",
                type: .integer,
                min: 0,
                max: 99,
                defaultValue: .integer(50)
            ),

            // Envelope Generator Levels
            PEParameter(
                path: "\(prefix)/EG/Levels/Level1",
                title: "Op\(opIndex) EG L1",
                description: "Envelope level 1",
                type: .integer,
                min: 0,
                max: 99,
                defaultValue: .integer(99)
            ),
            PEParameter(
                path: "\(prefix)/EG/Levels/Level2",
                title: "Op\(opIndex) EG L2",
                description: "Envelope level 2",
                type: .integer,
                min: 0,
                max: 99,
                defaultValue: .integer(80)
            ),
            PEParameter(
                path: "\(prefix)/EG/Levels/Level3",
                title: "Op\(opIndex) EG L3",
                description: "Envelope level 3 (sustain)",
                type: .integer,
                min: 0,
                max: 99,
                defaultValue: .integer(70)
            ),
            PEParameter(
                path: "\(prefix)/EG/Levels/Level4",
                title: "Op\(opIndex) EG L4",
                description: "Envelope level 4 (end)",
                type: .integer,
                min: 0,
                max: 99,
                defaultValue: .integer(0)
            )
        ]
    }

    // MARK: - LFO Parameters

    public static let lfo: [PEParameter] = [
        PEParameter(
            path: "LFO/Speed",
            title: "LFO Speed",
            description: "LFO rate",
            type: .integer,
            min: 0,
            max: 99,
            defaultValue: .integer(35)
        ),
        PEParameter(
            path: "LFO/Delay",
            title: "LFO Delay",
            description: "LFO delay time",
            type: .integer,
            min: 0,
            max: 99,
            defaultValue: .integer(0)
        ),
        PEParameter(
            path: "LFO/PitchModDepth",
            title: "LFO PMD",
            description: "LFO pitch modulation depth",
            type: .integer,
            min: 0,
            max: 99,
            defaultValue: .integer(0)
        ),
        PEParameter(
            path: "LFO/AmpModDepth",
            title: "LFO AMD",
            description: "LFO amplitude modulation depth",
            type: .integer,
            min: 0,
            max: 99,
            defaultValue: .integer(0)
        ),
        PEParameter(
            path: "LFO/Sync",
            title: "LFO Sync",
            description: "LFO key sync",
            type: .boolean,
            defaultValue: .boolean(true)
        ),
        PEParameter(
            path: "LFO/Waveform",
            title: "LFO Wave",
            description: "LFO waveform",
            type: .enumeration,
            defaultValue: .string("Triangle"),
            enumValues: ["Triangle", "Saw Down", "Saw Up", "Square", "Sine", "S&H"]
        ),
        PEParameter(
            path: "LFO/PitchModSensitivity",
            title: "LFO PMS",
            description: "Pitch modulation sensitivity",
            type: .integer,
            min: 0,
            max: 7,
            defaultValue: .integer(3)
        )
    ]

    // MARK: - Pitch Envelope

    public static let pitchEG: [PEParameter] = [
        // Rates
        PEParameter(
            path: "PitchEG/Rates/Rate1",
            title: "Pitch EG R1",
            description: "Pitch envelope rate 1",
            type: .integer,
            min: 0,
            max: 99,
            defaultValue: .integer(99)
        ),
        PEParameter(
            path: "PitchEG/Rates/Rate2",
            title: "Pitch EG R2",
            description: "Pitch envelope rate 2",
            type: .integer,
            min: 0,
            max: 99,
            defaultValue: .integer(99)
        ),
        PEParameter(
            path: "PitchEG/Rates/Rate3",
            title: "Pitch EG R3",
            description: "Pitch envelope rate 3",
            type: .integer,
            min: 0,
            max: 99,
            defaultValue: .integer(99)
        ),
        PEParameter(
            path: "PitchEG/Rates/Rate4",
            title: "Pitch EG R4",
            description: "Pitch envelope rate 4",
            type: .integer,
            min: 0,
            max: 99,
            defaultValue: .integer(99)
        ),
        // Levels (centered at 50)
        PEParameter(
            path: "PitchEG/Levels/Level1",
            title: "Pitch EG L1",
            description: "Pitch envelope level 1",
            type: .integer,
            min: 0,
            max: 99,
            defaultValue: .integer(50)
        ),
        PEParameter(
            path: "PitchEG/Levels/Level2",
            title: "Pitch EG L2",
            description: "Pitch envelope level 2",
            type: .integer,
            min: 0,
            max: 99,
            defaultValue: .integer(50)
        ),
        PEParameter(
            path: "PitchEG/Levels/Level3",
            title: "Pitch EG L3",
            description: "Pitch envelope level 3",
            type: .integer,
            min: 0,
            max: 99,
            defaultValue: .integer(50)
        ),
        PEParameter(
            path: "PitchEG/Levels/Level4",
            title: "Pitch EG L4",
            description: "Pitch envelope level 4",
            type: .integer,
            min: 0,
            max: 99,
            defaultValue: .integer(50)
        )
    ]

    // MARK: - Controller Parameters

    public static let controllers: [PEParameter] = [
        // Mod Wheel
        PEParameter(
            path: "Controller/Wheel/Pitch",
            title: "Wheel → Pitch",
            description: "Mod wheel to pitch depth",
            type: .integer,
            min: 0,
            max: 99,
            defaultValue: .integer(50)
        ),
        PEParameter(
            path: "Controller/Wheel/Amp",
            title: "Wheel → Amp",
            description: "Mod wheel to amplitude depth",
            type: .integer,
            min: 0,
            max: 99,
            defaultValue: .integer(0)
        ),
        PEParameter(
            path: "Controller/Wheel/EGBias",
            title: "Wheel → EG Bias",
            description: "Mod wheel to EG bias depth",
            type: .integer,
            min: 0,
            max: 99,
            defaultValue: .integer(0)
        ),

        // Foot Controller
        PEParameter(
            path: "Controller/Foot/Pitch",
            title: "Foot → Pitch",
            description: "Foot controller to pitch depth",
            type: .integer,
            min: 0,
            max: 99,
            defaultValue: .integer(0)
        ),
        PEParameter(
            path: "Controller/Foot/Amp",
            title: "Foot → Amp",
            description: "Foot controller to amplitude depth",
            type: .integer,
            min: 0,
            max: 99,
            defaultValue: .integer(0)
        ),
        PEParameter(
            path: "Controller/Foot/EGBias",
            title: "Foot → EG Bias",
            description: "Foot controller to EG bias depth",
            type: .integer,
            min: 0,
            max: 99,
            defaultValue: .integer(0)
        ),

        // Breath Controller
        PEParameter(
            path: "Controller/Breath/Pitch",
            title: "Breath → Pitch",
            description: "Breath controller to pitch depth",
            type: .integer,
            min: 0,
            max: 99,
            defaultValue: .integer(0)
        ),
        PEParameter(
            path: "Controller/Breath/Amp",
            title: "Breath → Amp",
            description: "Breath controller to amplitude depth",
            type: .integer,
            min: 0,
            max: 99,
            defaultValue: .integer(0)
        ),
        PEParameter(
            path: "Controller/Breath/EGBias",
            title: "Breath → EG Bias",
            description: "Breath controller to EG bias depth",
            type: .integer,
            min: 0,
            max: 99,
            defaultValue: .integer(0)
        ),

        // Aftertouch
        PEParameter(
            path: "Controller/Aftertouch/Pitch",
            title: "AT → Pitch",
            description: "Aftertouch to pitch depth",
            type: .integer,
            min: 0,
            max: 99,
            defaultValue: .integer(0)
        ),
        PEParameter(
            path: "Controller/Aftertouch/Amp",
            title: "AT → Amp",
            description: "Aftertouch to amplitude depth",
            type: .integer,
            min: 0,
            max: 99,
            defaultValue: .integer(0)
        ),
        PEParameter(
            path: "Controller/Aftertouch/EGBias",
            title: "AT → EG Bias",
            description: "Aftertouch to EG bias depth",
            type: .integer,
            min: 0,
            max: 99,
            defaultValue: .integer(0)
        )
    ]

    // MARK: - Complete Parameter Tree

    /// Get all parameters as a flat list
    public static var allParameters: [PEParameter] {
        var params = global

        // Add 6 operators (DX7 compatible)
        // Future: extend to 8 operators for M2DX extended mode
        for op in 1...operatorCount {
            params.append(contentsOf: operatorParameters(for: op))
        }

        params.append(contentsOf: lfo)
        params.append(contentsOf: pitchEG)
        params.append(contentsOf: controllers)

        return params
    }

    /// Get parameter by path
    public static func parameter(at path: String) -> PEParameter? {
        allParameters.first { $0.path == path }
    }

    /// Get all parameters under a given prefix
    public static func parameters(under prefix: String) -> [PEParameter] {
        allParameters.filter { $0.path.hasPrefix(prefix) }
    }

    /// Total parameter count
    public static var totalParameterCount: Int {
        allParameters.count
    }
}

// MARK: - Parameter Tree JSON Export

extension M2DXParameterTree {

    /// Export parameter tree as JSON for MIDI 2.0 Property Exchange
    public static func exportAsJSON() -> String {
        var json: [[String: Any]] = []

        for param in allParameters {
            var entry: [String: Any] = [
                "path": param.path,
                "title": param.title,
                "type": param.type.rawValue
            ]

            if !param.description.isEmpty {
                entry["description"] = param.description
            }
            if let min = param.min {
                entry["min"] = min
            }
            if let max = param.max {
                entry["max"] = max
            }
            if let enums = param.enumValues {
                entry["values"] = enums
            }

            json.append(entry)
        }

        guard let data = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
              let jsonString = String(data: data, encoding: .utf8) else {
            return "[]"
        }

        return jsonString
    }
}
