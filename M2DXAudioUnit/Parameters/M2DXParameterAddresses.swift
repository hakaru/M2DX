import Foundation

/// Parameter addresses for M2DX Audio Unit
/// Global: 0-99
/// OP1: 100-199, OP2: 200-299, ... OP8: 800-899
public enum M2DXParameterAddress: UInt64 {
    // MARK: - Global Parameters (0-99)
    case algorithm = 0
    case masterVolume = 1
    case feedback = 2

    // MARK: - Operator 1 Parameters (100-199)
    case op1Level = 100
    case op1Ratio = 101
    case op1Detune = 102
    case op1Feedback = 103
    case op1EGRate1 = 110
    case op1EGRate2 = 111
    case op1EGRate3 = 112
    case op1EGRate4 = 113
    case op1EGLevel1 = 120
    case op1EGLevel2 = 121
    case op1EGLevel3 = 122
    case op1EGLevel4 = 123

    // MARK: - Operator 2 Parameters (200-299)
    case op2Level = 200
    case op2Ratio = 201
    case op2Detune = 202
    case op2Feedback = 203
    case op2EGRate1 = 210
    case op2EGRate2 = 211
    case op2EGRate3 = 212
    case op2EGRate4 = 213
    case op2EGLevel1 = 220
    case op2EGLevel2 = 221
    case op2EGLevel3 = 222
    case op2EGLevel4 = 223

    // MARK: - Operator 3 Parameters (300-399)
    case op3Level = 300
    case op3Ratio = 301
    case op3Detune = 302
    case op3Feedback = 303
    case op3EGRate1 = 310
    case op3EGRate2 = 311
    case op3EGRate3 = 312
    case op3EGRate4 = 313
    case op3EGLevel1 = 320
    case op3EGLevel2 = 321
    case op3EGLevel3 = 322
    case op3EGLevel4 = 323

    // MARK: - Operator 4 Parameters (400-499)
    case op4Level = 400
    case op4Ratio = 401
    case op4Detune = 402
    case op4Feedback = 403
    case op4EGRate1 = 410
    case op4EGRate2 = 411
    case op4EGRate3 = 412
    case op4EGRate4 = 413
    case op4EGLevel1 = 420
    case op4EGLevel2 = 421
    case op4EGLevel3 = 422
    case op4EGLevel4 = 423

    // MARK: - Operator 5 Parameters (500-599)
    case op5Level = 500
    case op5Ratio = 501
    case op5Detune = 502
    case op5Feedback = 503
    case op5EGRate1 = 510
    case op5EGRate2 = 511
    case op5EGRate3 = 512
    case op5EGRate4 = 513
    case op5EGLevel1 = 520
    case op5EGLevel2 = 521
    case op5EGLevel3 = 522
    case op5EGLevel4 = 523

    // MARK: - Operator 6 Parameters (600-699)
    case op6Level = 600
    case op6Ratio = 601
    case op6Detune = 602
    case op6Feedback = 603
    case op6EGRate1 = 610
    case op6EGRate2 = 611
    case op6EGRate3 = 612
    case op6EGRate4 = 613
    case op6EGLevel1 = 620
    case op6EGLevel2 = 621
    case op6EGLevel3 = 622
    case op6EGLevel4 = 623

    // MARK: - Operator 7 Parameters (700-799)
    case op7Level = 700
    case op7Ratio = 701
    case op7Detune = 702
    case op7Feedback = 703
    case op7EGRate1 = 710
    case op7EGRate2 = 711
    case op7EGRate3 = 712
    case op7EGRate4 = 713
    case op7EGLevel1 = 720
    case op7EGLevel2 = 721
    case op7EGLevel3 = 722
    case op7EGLevel4 = 723

    // MARK: - Operator 8 Parameters (800-899)
    case op8Level = 800
    case op8Ratio = 801
    case op8Detune = 802
    case op8Feedback = 803
    case op8EGRate1 = 810
    case op8EGRate2 = 811
    case op8EGRate3 = 812
    case op8EGRate4 = 813
    case op8EGLevel1 = 820
    case op8EGLevel2 = 821
    case op8EGLevel3 = 822
    case op8EGLevel4 = 823
}

/// Helper to get operator index from parameter address
public extension M2DXParameterAddress {
    var operatorIndex: Int? {
        let rawValue = self.rawValue
        if rawValue >= 100 && rawValue < 900 {
            return Int((rawValue - 100) / 100)
        }
        return nil
    }

    static func levelAddress(forOperator index: Int) -> UInt64 {
        UInt64(100 + index * 100)
    }

    static func ratioAddress(forOperator index: Int) -> UInt64 {
        UInt64(101 + index * 100)
    }

    static func detuneAddress(forOperator index: Int) -> UInt64 {
        UInt64(102 + index * 100)
    }

    static func feedbackAddress(forOperator index: Int) -> UInt64 {
        UInt64(103 + index * 100)
    }

    static func egRateAddresses(forOperator index: Int) -> [UInt64] {
        let base = UInt64(110 + index * 100)
        return [base, base + 1, base + 2, base + 3]
    }

    static func egLevelAddresses(forOperator index: Int) -> [UInt64] {
        let base = UInt64(120 + index * 100)
        return [base, base + 1, base + 2, base + 3]
    }
}
