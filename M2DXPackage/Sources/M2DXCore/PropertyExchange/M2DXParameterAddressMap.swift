import Foundation

// MARK: - Parameter Address Mapping

/// Maps PE paths to AU parameter addresses and vice versa
/// Provides bidirectional conversion between MIDI 2.0 Property Exchange paths
/// and Audio Unit parameter addresses
public enum M2DXParameterAddressMap {

    // MARK: - Address Constants

    /// Global parameter addresses
    public enum Global {
        public static let algorithm: UInt64 = 0
        public static let masterVolume: UInt64 = 1
        public static let globalFeedback: UInt64 = 2
        public static let oscSync: UInt64 = 3
        public static let transpose: UInt64 = 4
    }

    /// Operator parameter structure
    public enum Operator {
        public static let baseAddress: UInt64 = 100
        public static let stride: UInt64 = 100

        // Parameter offsets within each operator
        public static let level: UInt64 = 0
        public static let ratio: UInt64 = 1
        public static let detune: UInt64 = 2
        public static let feedback: UInt64 = 3
        public static let mode: UInt64 = 4
        public static let freqCoarse: UInt64 = 5
        public static let freqFine: UInt64 = 6
        public static let velocitySensitivity: UInt64 = 7
        public static let ampModSensitivity: UInt64 = 8
        public static let rateScaling: UInt64 = 9

        // EG rates (10-13)
        public static let egRate1: UInt64 = 10
        public static let egRate2: UInt64 = 11
        public static let egRate3: UInt64 = 12
        public static let egRate4: UInt64 = 13

        // EG levels (20-23)
        public static let egLevel1: UInt64 = 20
        public static let egLevel2: UInt64 = 21
        public static let egLevel3: UInt64 = 22
        public static let egLevel4: UInt64 = 23

        // Keyboard level scaling (30-35)
        public static let klsBreakPoint: UInt64 = 30
        public static let klsLeftDepth: UInt64 = 31
        public static let klsRightDepth: UInt64 = 32
        public static let klsLeftCurve: UInt64 = 33
        public static let klsRightCurve: UInt64 = 34
    }

    /// LFO parameter addresses
    public enum LFO {
        public static let baseAddress: UInt64 = 700
        public static let speed: UInt64 = 700
        public static let delay: UInt64 = 701
        public static let pitchModDepth: UInt64 = 702
        public static let ampModDepth: UInt64 = 703
        public static let sync: UInt64 = 704
        public static let waveform: UInt64 = 705
        public static let pitchModSensitivity: UInt64 = 706
    }

    /// Pitch EG parameter addresses
    public enum PitchEG {
        public static let baseAddress: UInt64 = 800
        public static let rate1: UInt64 = 800
        public static let rate2: UInt64 = 801
        public static let rate3: UInt64 = 802
        public static let rate4: UInt64 = 803
        public static let level1: UInt64 = 810
        public static let level2: UInt64 = 811
        public static let level3: UInt64 = 812
        public static let level4: UInt64 = 813
    }

    /// Controller parameter addresses
    public enum Controller {
        public static let baseAddress: UInt64 = 900
        // Wheel
        public static let wheelPitch: UInt64 = 900
        public static let wheelAmp: UInt64 = 901
        public static let wheelEGBias: UInt64 = 902
        // Foot
        public static let footPitch: UInt64 = 910
        public static let footAmp: UInt64 = 911
        public static let footEGBias: UInt64 = 912
        // Breath
        public static let breathPitch: UInt64 = 920
        public static let breathAmp: UInt64 = 921
        public static let breathEGBias: UInt64 = 922
        // Aftertouch
        public static let aftertouchPitch: UInt64 = 930
        public static let aftertouchAmp: UInt64 = 931
        public static let aftertouchEGBias: UInt64 = 932
    }

    // MARK: - Helper Methods

    /// Calculate operator parameter address
    public static func operatorAddress(opIndex: Int, offset: UInt64) -> UInt64 {
        return Operator.baseAddress + UInt64(opIndex) * Operator.stride + offset
    }

    // MARK: - PE Path to AU Address Conversion

    /// Convert PE path to AU parameter address
    /// - Parameter path: PE path like "Global/Algorithm" or "Operators/Op1/Level"
    /// - Returns: AU parameter address, or nil if path not found
    public static func addressForPath(_ path: String) -> UInt64? {
        // Global parameters
        switch path {
        case "Global/Algorithm":
            return Global.algorithm
        case "Global/MasterVolume":
            return Global.masterVolume
        case "Global/Feedback":
            return Global.globalFeedback
        case "Global/OscSync":
            return Global.oscSync
        case "Global/Transpose":
            return Global.transpose
        default:
            break
        }

        // Operator parameters
        if path.hasPrefix("Operators/Op") {
            return parseOperatorPath(path)
        }

        // LFO parameters
        switch path {
        case "LFO/Speed":
            return LFO.speed
        case "LFO/Delay":
            return LFO.delay
        case "LFO/PitchModDepth":
            return LFO.pitchModDepth
        case "LFO/AmpModDepth":
            return LFO.ampModDepth
        case "LFO/Sync":
            return LFO.sync
        case "LFO/Waveform":
            return LFO.waveform
        case "LFO/PitchModSensitivity":
            return LFO.pitchModSensitivity
        default:
            break
        }

        // PitchEG parameters
        switch path {
        case "PitchEG/Rates/Rate1":
            return PitchEG.rate1
        case "PitchEG/Rates/Rate2":
            return PitchEG.rate2
        case "PitchEG/Rates/Rate3":
            return PitchEG.rate3
        case "PitchEG/Rates/Rate4":
            return PitchEG.rate4
        case "PitchEG/Levels/Level1":
            return PitchEG.level1
        case "PitchEG/Levels/Level2":
            return PitchEG.level2
        case "PitchEG/Levels/Level3":
            return PitchEG.level3
        case "PitchEG/Levels/Level4":
            return PitchEG.level4
        default:
            break
        }

        // Controller parameters
        switch path {
        case "Controller/Wheel/Pitch":
            return Controller.wheelPitch
        case "Controller/Wheel/Amp":
            return Controller.wheelAmp
        case "Controller/Wheel/EGBias":
            return Controller.wheelEGBias
        case "Controller/Foot/Pitch":
            return Controller.footPitch
        case "Controller/Foot/Amp":
            return Controller.footAmp
        case "Controller/Foot/EGBias":
            return Controller.footEGBias
        case "Controller/Breath/Pitch":
            return Controller.breathPitch
        case "Controller/Breath/Amp":
            return Controller.breathAmp
        case "Controller/Breath/EGBias":
            return Controller.breathEGBias
        case "Controller/Aftertouch/Pitch":
            return Controller.aftertouchPitch
        case "Controller/Aftertouch/Amp":
            return Controller.aftertouchAmp
        case "Controller/Aftertouch/EGBias":
            return Controller.aftertouchEGBias
        default:
            break
        }

        return nil
    }

    /// Parse operator path and return address
    private static func parseOperatorPath(_ path: String) -> UInt64? {
        // Format: Operators/Op{N}/{parameter}
        // Example: Operators/Op1/Level, Operators/Op2/EG/Rates/Rate1

        let components = path.split(separator: "/")
        guard components.count >= 3,
              let opPart = components[1].dropFirst(2).first,
              let opIndex = Int(String(opPart)),
              opIndex >= 1 && opIndex <= 6 else {
            return nil
        }

        let zeroBasedIndex = opIndex - 1
        let paramPath = components.dropFirst(2).joined(separator: "/")

        let offset: UInt64?
        switch paramPath {
        case "Mode":
            offset = Operator.mode
        case "Level":
            offset = Operator.level
        case "Frequency/Coarse":
            offset = Operator.freqCoarse
        case "Frequency/Fine":
            offset = Operator.freqFine
        case "Frequency/Detune":
            offset = Operator.detune
        case "VelocitySensitivity":
            offset = Operator.velocitySensitivity
        case "AmpModSensitivity":
            offset = Operator.ampModSensitivity
        case "RateScaling":
            offset = Operator.rateScaling
        case "EG/Rates/Rate1":
            offset = Operator.egRate1
        case "EG/Rates/Rate2":
            offset = Operator.egRate2
        case "EG/Rates/Rate3":
            offset = Operator.egRate3
        case "EG/Rates/Rate4":
            offset = Operator.egRate4
        case "EG/Levels/Level1":
            offset = Operator.egLevel1
        case "EG/Levels/Level2":
            offset = Operator.egLevel2
        case "EG/Levels/Level3":
            offset = Operator.egLevel3
        case "EG/Levels/Level4":
            offset = Operator.egLevel4
        case "KeyboardLevelScaling/BreakPoint":
            offset = Operator.klsBreakPoint
        case "KeyboardLevelScaling/LeftDepth":
            offset = Operator.klsLeftDepth
        case "KeyboardLevelScaling/RightDepth":
            offset = Operator.klsRightDepth
        case "KeyboardLevelScaling/LeftCurve":
            offset = Operator.klsLeftCurve
        case "KeyboardLevelScaling/RightCurve":
            offset = Operator.klsRightCurve
        default:
            offset = nil
        }

        guard let paramOffset = offset else { return nil }
        return operatorAddress(opIndex: zeroBasedIndex, offset: paramOffset)
    }

    // MARK: - AU Address to PE Path Conversion

    /// Convert AU parameter address to PE path
    /// - Parameter address: AU parameter address
    /// - Returns: PE path string, or nil if address not mapped
    public static func pathForAddress(_ address: UInt64) -> String? {
        // Global parameters
        switch address {
        case Global.algorithm:
            return "Global/Algorithm"
        case Global.masterVolume:
            return "Global/MasterVolume"
        case Global.globalFeedback:
            return "Global/Feedback"
        case Global.oscSync:
            return "Global/OscSync"
        case Global.transpose:
            return "Global/Transpose"
        default:
            break
        }

        // Operator parameters (100-699)
        if address >= Operator.baseAddress && address < LFO.baseAddress {
            return pathForOperatorAddress(address)
        }

        // LFO parameters
        switch address {
        case LFO.speed:
            return "LFO/Speed"
        case LFO.delay:
            return "LFO/Delay"
        case LFO.pitchModDepth:
            return "LFO/PitchModDepth"
        case LFO.ampModDepth:
            return "LFO/AmpModDepth"
        case LFO.sync:
            return "LFO/Sync"
        case LFO.waveform:
            return "LFO/Waveform"
        case LFO.pitchModSensitivity:
            return "LFO/PitchModSensitivity"
        default:
            break
        }

        // PitchEG parameters
        switch address {
        case PitchEG.rate1:
            return "PitchEG/Rates/Rate1"
        case PitchEG.rate2:
            return "PitchEG/Rates/Rate2"
        case PitchEG.rate3:
            return "PitchEG/Rates/Rate3"
        case PitchEG.rate4:
            return "PitchEG/Rates/Rate4"
        case PitchEG.level1:
            return "PitchEG/Levels/Level1"
        case PitchEG.level2:
            return "PitchEG/Levels/Level2"
        case PitchEG.level3:
            return "PitchEG/Levels/Level3"
        case PitchEG.level4:
            return "PitchEG/Levels/Level4"
        default:
            break
        }

        // Controller parameters
        switch address {
        case Controller.wheelPitch:
            return "Controller/Wheel/Pitch"
        case Controller.wheelAmp:
            return "Controller/Wheel/Amp"
        case Controller.wheelEGBias:
            return "Controller/Wheel/EGBias"
        case Controller.footPitch:
            return "Controller/Foot/Pitch"
        case Controller.footAmp:
            return "Controller/Foot/Amp"
        case Controller.footEGBias:
            return "Controller/Foot/EGBias"
        case Controller.breathPitch:
            return "Controller/Breath/Pitch"
        case Controller.breathAmp:
            return "Controller/Breath/Amp"
        case Controller.breathEGBias:
            return "Controller/Breath/EGBias"
        case Controller.aftertouchPitch:
            return "Controller/Aftertouch/Pitch"
        case Controller.aftertouchAmp:
            return "Controller/Aftertouch/Amp"
        case Controller.aftertouchEGBias:
            return "Controller/Aftertouch/EGBias"
        default:
            break
        }

        return nil
    }

    /// Convert operator address to PE path
    private static func pathForOperatorAddress(_ address: UInt64) -> String? {
        let relativeAddress = address - Operator.baseAddress
        let opIndex = Int(relativeAddress / Operator.stride) + 1  // 1-based
        let offset = relativeAddress % Operator.stride

        guard opIndex >= 1 && opIndex <= 6 else { return nil }

        let prefix = "Operators/Op\(opIndex)"

        switch offset {
        case Operator.mode:
            return "\(prefix)/Mode"
        case Operator.level:
            return "\(prefix)/Level"
        case Operator.ratio:
            return "\(prefix)/Frequency/Coarse"  // Map ratio to coarse
        case Operator.detune:
            return "\(prefix)/Frequency/Detune"
        case Operator.feedback:
            return "\(prefix)/Feedback"
        case Operator.freqCoarse:
            return "\(prefix)/Frequency/Coarse"
        case Operator.freqFine:
            return "\(prefix)/Frequency/Fine"
        case Operator.velocitySensitivity:
            return "\(prefix)/VelocitySensitivity"
        case Operator.ampModSensitivity:
            return "\(prefix)/AmpModSensitivity"
        case Operator.rateScaling:
            return "\(prefix)/RateScaling"
        case Operator.egRate1:
            return "\(prefix)/EG/Rates/Rate1"
        case Operator.egRate2:
            return "\(prefix)/EG/Rates/Rate2"
        case Operator.egRate3:
            return "\(prefix)/EG/Rates/Rate3"
        case Operator.egRate4:
            return "\(prefix)/EG/Rates/Rate4"
        case Operator.egLevel1:
            return "\(prefix)/EG/Levels/Level1"
        case Operator.egLevel2:
            return "\(prefix)/EG/Levels/Level2"
        case Operator.egLevel3:
            return "\(prefix)/EG/Levels/Level3"
        case Operator.egLevel4:
            return "\(prefix)/EG/Levels/Level4"
        case Operator.klsBreakPoint:
            return "\(prefix)/KeyboardLevelScaling/BreakPoint"
        case Operator.klsLeftDepth:
            return "\(prefix)/KeyboardLevelScaling/LeftDepth"
        case Operator.klsRightDepth:
            return "\(prefix)/KeyboardLevelScaling/RightDepth"
        case Operator.klsLeftCurve:
            return "\(prefix)/KeyboardLevelScaling/LeftCurve"
        case Operator.klsRightCurve:
            return "\(prefix)/KeyboardLevelScaling/RightCurve"
        default:
            return nil
        }
    }

    // MARK: - Batch Operations

    /// Get all address-path mappings
    public static var allMappings: [(address: UInt64, path: String)] {
        var mappings: [(UInt64, String)] = []

        // Global
        mappings.append((Global.algorithm, "Global/Algorithm"))
        mappings.append((Global.masterVolume, "Global/MasterVolume"))
        mappings.append((Global.globalFeedback, "Global/Feedback"))
        mappings.append((Global.oscSync, "Global/OscSync"))
        mappings.append((Global.transpose, "Global/Transpose"))

        // Operators
        for opIndex in 1...6 {
            let prefix = "Operators/Op\(opIndex)"
            let base = operatorAddress(opIndex: opIndex - 1, offset: 0)

            mappings.append((base + Operator.mode, "\(prefix)/Mode"))
            mappings.append((base + Operator.level, "\(prefix)/Level"))
            mappings.append((base + Operator.freqCoarse, "\(prefix)/Frequency/Coarse"))
            mappings.append((base + Operator.freqFine, "\(prefix)/Frequency/Fine"))
            mappings.append((base + Operator.detune, "\(prefix)/Frequency/Detune"))
            mappings.append((base + Operator.velocitySensitivity, "\(prefix)/VelocitySensitivity"))
            mappings.append((base + Operator.ampModSensitivity, "\(prefix)/AmpModSensitivity"))
            mappings.append((base + Operator.rateScaling, "\(prefix)/RateScaling"))
            mappings.append((base + Operator.egRate1, "\(prefix)/EG/Rates/Rate1"))
            mappings.append((base + Operator.egRate2, "\(prefix)/EG/Rates/Rate2"))
            mappings.append((base + Operator.egRate3, "\(prefix)/EG/Rates/Rate3"))
            mappings.append((base + Operator.egRate4, "\(prefix)/EG/Rates/Rate4"))
            mappings.append((base + Operator.egLevel1, "\(prefix)/EG/Levels/Level1"))
            mappings.append((base + Operator.egLevel2, "\(prefix)/EG/Levels/Level2"))
            mappings.append((base + Operator.egLevel3, "\(prefix)/EG/Levels/Level3"))
            mappings.append((base + Operator.egLevel4, "\(prefix)/EG/Levels/Level4"))
            mappings.append((base + Operator.klsBreakPoint, "\(prefix)/KeyboardLevelScaling/BreakPoint"))
            mappings.append((base + Operator.klsLeftDepth, "\(prefix)/KeyboardLevelScaling/LeftDepth"))
            mappings.append((base + Operator.klsRightDepth, "\(prefix)/KeyboardLevelScaling/RightDepth"))
            mappings.append((base + Operator.klsLeftCurve, "\(prefix)/KeyboardLevelScaling/LeftCurve"))
            mappings.append((base + Operator.klsRightCurve, "\(prefix)/KeyboardLevelScaling/RightCurve"))
        }

        // LFO
        mappings.append((LFO.speed, "LFO/Speed"))
        mappings.append((LFO.delay, "LFO/Delay"))
        mappings.append((LFO.pitchModDepth, "LFO/PitchModDepth"))
        mappings.append((LFO.ampModDepth, "LFO/AmpModDepth"))
        mappings.append((LFO.sync, "LFO/Sync"))
        mappings.append((LFO.waveform, "LFO/Waveform"))
        mappings.append((LFO.pitchModSensitivity, "LFO/PitchModSensitivity"))

        // PitchEG
        mappings.append((PitchEG.rate1, "PitchEG/Rates/Rate1"))
        mappings.append((PitchEG.rate2, "PitchEG/Rates/Rate2"))
        mappings.append((PitchEG.rate3, "PitchEG/Rates/Rate3"))
        mappings.append((PitchEG.rate4, "PitchEG/Rates/Rate4"))
        mappings.append((PitchEG.level1, "PitchEG/Levels/Level1"))
        mappings.append((PitchEG.level2, "PitchEG/Levels/Level2"))
        mappings.append((PitchEG.level3, "PitchEG/Levels/Level3"))
        mappings.append((PitchEG.level4, "PitchEG/Levels/Level4"))

        // Controllers
        mappings.append((Controller.wheelPitch, "Controller/Wheel/Pitch"))
        mappings.append((Controller.wheelAmp, "Controller/Wheel/Amp"))
        mappings.append((Controller.wheelEGBias, "Controller/Wheel/EGBias"))
        mappings.append((Controller.footPitch, "Controller/Foot/Pitch"))
        mappings.append((Controller.footAmp, "Controller/Foot/Amp"))
        mappings.append((Controller.footEGBias, "Controller/Foot/EGBias"))
        mappings.append((Controller.breathPitch, "Controller/Breath/Pitch"))
        mappings.append((Controller.breathAmp, "Controller/Breath/Amp"))
        mappings.append((Controller.breathEGBias, "Controller/Breath/EGBias"))
        mappings.append((Controller.aftertouchPitch, "Controller/Aftertouch/Pitch"))
        mappings.append((Controller.aftertouchAmp, "Controller/Aftertouch/Amp"))
        mappings.append((Controller.aftertouchEGBias, "Controller/Aftertouch/EGBias"))

        return mappings
    }
}
