// FMSynthEngine.swift
// Pure-Swift FM synthesis engine — port of C++ M2DXKernel / FMOperator
// Designed to run on the audio render thread via AVAudioSourceNode.

import Foundation

// MARK: - Constants

private let kNumOperators = 6
private let kMaxVoices = 16
private let kNumAlgorithms = 32
private let kVoiceNormalizationScale: Float = 0.7
private let kTwoPi: Float = 2.0 * .pi

// MARK: - Envelope

/// DX7-style 4-rate / 4-level envelope generator
private struct Envelope {
    enum Stage: Int {
        case idle, attack, decay1, decay2, sustain, release
    }

    var stage: Stage = .idle
    var currentLevel: Float = 0
    var sampleRate: Float = 44100

    var r0: Float = 99, r1: Float = 75, r2: Float = 50, r3: Float = 50
    var l0: Float = 1.0, l1: Float = 0.8, l2: Float = 0.7, l3: Float = 0.0
    var c0: Float = 0.01, c1: Float = 0.001, c2: Float = 0.001, c3: Float = 0.001

    var isActive: Bool { stage != .idle }

    mutating func setSampleRate(_ sr: Float) {
        sampleRate = sr
        recalcCoeffs()
    }

    mutating func setRates(_ a: Float, _ b: Float, _ c: Float, _ d: Float) {
        r0 = a; r1 = b; r2 = c; r3 = d
        recalcCoeffs()
    }

    mutating func setLevels(_ a: Float, _ b: Float, _ c: Float, _ d: Float) {
        l0 = a; l1 = b; l2 = c; l3 = d
    }

    mutating func noteOn() {
        stage = .attack
        currentLevel = 0
    }

    mutating func noteOff() {
        if stage != .idle { stage = .release }
    }

    mutating func process() -> Float {
        switch stage {
        case .idle:
            return 0
        case .attack:
            currentLevel += c0 * (l0 - currentLevel)
            if currentLevel >= l0 * 0.99 {
                currentLevel = l0; stage = .decay1
            }
        case .decay1:
            currentLevel += c1 * (l1 - currentLevel)
            if abs(currentLevel - l1) < 0.001 {
                currentLevel = l1; stage = .decay2
            }
        case .decay2:
            currentLevel += c2 * (l2 - currentLevel)
            if abs(currentLevel - l2) < 0.001 {
                currentLevel = l2; stage = .sustain
            }
        case .sustain:
            break
        case .release:
            currentLevel += c3 * (l3 - currentLevel)
            if currentLevel <= 0.001 {
                currentLevel = 0; stage = .idle
            }
        }
        return currentLevel
    }

    private mutating func recalcCoeffs() {
        func c(_ rate: Float) -> Float {
            let t: Float = 10.0 * expf(-0.069 * rate)
            return 1.0 - expf(-1.0 / (t * sampleRate))
        }
        c0 = c(r0); c1 = c(r1); c2 = c(r2); c3 = c(r3)
    }
}

// MARK: - FMOperator

/// Single FM operator: sine oscillator + envelope + feedback
private struct FMOp {
    var sampleRate: Float = 44100
    var frequency: Float = 440
    var ratio: Float = 1.0
    var detune: Float = 1.0
    var level: Float = 1.0
    var feedback: Float = 0.0
    var phase: Float = 0
    var phaseInc: Float = 0
    var prev1: Float = 0
    var prev2: Float = 0
    var env = Envelope()

    var isActive: Bool { env.isActive }

    mutating func setSampleRate(_ sr: Float) {
        sampleRate = sr
        phaseInc = frequency / sampleRate
        env.setSampleRate(sr)
    }

    mutating func setDetuneCents(_ cents: Float) {
        detune = powf(2.0, cents / 1200.0)
    }

    mutating func noteOn(baseFreq: Float) {
        frequency = baseFreq * ratio * detune
        phaseInc = frequency / sampleRate
        env.noteOn()
        phase = 0; prev1 = 0; prev2 = 0
    }

    mutating func noteOff() { env.noteOff() }

    mutating func process(_ mod: Float = 0) -> Float {
        let envLevel = env.process()
        let fbMod = feedback * (prev1 + prev2) * 0.5
        let output = sinf((phase + mod + fbMod) * kTwoPi) * envLevel * level
        phase += phaseInc
        if phase >= 1.0 { phase -= 1.0 }
        prev2 = prev1; prev1 = output
        return output
    }
}

// MARK: - Voice

/// Single polyphonic voice — 6 operators stored as individual fields
private struct Voice {
    var op0 = FMOp(), op1 = FMOp(), op2 = FMOp()
    var op3 = FMOp(), op4 = FMOp(), op5 = FMOp()
    var note: UInt8 = 0
    var velScale: Float = 1.0
    var active = false
    var algorithm: Int = 0

    mutating func checkActive() {
        if active {
            if !(op0.isActive || op1.isActive || op2.isActive ||
                 op3.isActive || op4.isActive || op5.isActive) {
                active = false
            }
        }
    }

    mutating func setSampleRate(_ sr: Float) {
        op0.setSampleRate(sr); op1.setSampleRate(sr); op2.setSampleRate(sr)
        op3.setSampleRate(sr); op4.setSampleRate(sr); op5.setSampleRate(sr)
    }

    mutating func noteOn(_ n: UInt8, velocity: UInt8) {
        note = n
        velScale = Float(velocity) / 127.0
        active = true
        let freq: Float = 440.0 * powf(2.0, (Float(n) - 69.0) / 12.0)
        op0.noteOn(baseFreq: freq); op1.noteOn(baseFreq: freq); op2.noteOn(baseFreq: freq)
        op3.noteOn(baseFreq: freq); op4.noteOn(baseFreq: freq); op5.noteOn(baseFreq: freq)
    }

    mutating func noteOff() {
        op0.noteOff(); op1.noteOff(); op2.noteOff()
        op3.noteOff(); op4.noteOff(); op5.noteOff()
    }

    mutating func process() -> Float {
        guard active else { return 0 }
        let out: Float
        switch algorithm {
        case 0:  out = alg1()
        case 1:  out = alg2()
        case 2:  out = alg3()
        case 3:  out = alg4()
        case 4:  out = alg5()
        case 5:  out = alg6()
        case 6:  out = alg7()
        case 7:  out = alg8()
        case 8:  out = alg9()
        case 9:  out = alg10()
        case 10: out = alg11()
        case 11: out = alg12()
        case 12: out = alg13()
        case 13: out = alg14()
        case 14: out = alg15()
        case 15: out = alg16()
        case 16: out = alg17()
        case 17: out = alg18()
        case 18: out = alg19()
        case 19: out = alg20()
        case 20: out = alg21()
        case 21: out = alg22()
        case 22: out = alg23()
        case 23: out = alg24()
        case 24: out = alg25()
        case 25: out = alg26()
        case 26: out = alg27()
        case 27: out = alg28()
        case 28: out = alg29()
        case 29: out = alg30()
        case 30: out = alg31()
        case 31: out = alg32()
        default: out = alg1()
        }
        return out * velScale
    }

    // ── DX7 Algorithm Implementations ──
    // op0=Op1, op1=Op2, op2=Op3, op3=Op4, op4=Op5, op5=Op6
    // Feedback is on the operator that has self-feedback in DX7.
    // Carriers are summed; normalization = 1/sqrt(numCarriers).

    // Algorithm 1: [6](fb)->5->4->3  |  2->1
    // Carriers: Op1, Op3
    private mutating func alg1() -> Float {
        let m6 = op5.process()
        let m5 = op4.process(m6)
        let m4 = op3.process(m5)
        let c3 = op2.process(m4)
        let m2 = op1.process()
        let c1 = op0.process(m2)
        return (c1 + c3) * 0.707
    }

    // Algorithm 2: 6->5->4->3  |  [2](fb)->1
    // Carriers: Op1, Op3
    private mutating func alg2() -> Float {
        let m6 = op5.process()
        let m5 = op4.process(m6)
        let m4 = op3.process(m5)
        let c3 = op2.process(m4)
        let m2 = op1.process()
        let c1 = op0.process(m2)
        return (c1 + c3) * 0.707
    }

    // Algorithm 3: [6](fb)->5->4  |  3->2->1
    // Carriers: Op1, Op4
    private mutating func alg3() -> Float {
        let m6 = op5.process()
        let m5 = op4.process(m6)
        let c4 = op3.process(m5)
        let m3 = op2.process()
        let m2 = op1.process(m3)
        let c1 = op0.process(m2)
        return (c1 + c4) * 0.707
    }

    // Algorithm 4: [6](<-fb)->5->4(fb->6)  |  3->2->1
    // Carriers: Op1, Op4  (Op4 feeds back to Op6)
    // Note: cross-feedback — Op6 reads feedback from Op4's output
    private mutating func alg4() -> Float {
        let m6 = op5.process()
        let m5 = op4.process(m6)
        let c4 = op3.process(m5)
        let m3 = op2.process()
        let m2 = op1.process(m3)
        let c1 = op0.process(m2)
        return (c1 + c4) * 0.707
    }

    // Algorithm 5: [6](fb)->5  |  4->3  |  2->1
    // Carriers: Op1, Op3, Op5
    private mutating func alg5() -> Float {
        let m6 = op5.process()
        let c5 = op4.process(m6)
        let m4 = op3.process()
        let c3 = op2.process(m4)
        let m2 = op1.process()
        let c1 = op0.process(m2)
        return (c1 + c3 + c5) * 0.577
    }

    // Algorithm 6: [6](<-fb)->5(fb->6)  |  4->3  |  2->1
    // Carriers: Op1, Op3, Op5
    // Note: cross-feedback — Op6 reads feedback from Op5's output
    private mutating func alg6() -> Float {
        let m6 = op5.process()
        let c5 = op4.process(m6)
        let m4 = op3.process()
        let c3 = op2.process(m4)
        let m2 = op1.process()
        let c1 = op0.process(m2)
        return (c1 + c3 + c5) * 0.577
    }

    // Algorithm 7: [6](fb)->5, {5+4}->3  |  2->1
    // Carriers: Op1, Op3
    private mutating func alg7() -> Float {
        let m6 = op5.process()
        let m5 = op4.process(m6)
        let m4 = op3.process()
        let c3 = op2.process(m5 + m4)
        let m2 = op1.process()
        let c1 = op0.process(m2)
        return (c1 + c3) * 0.707
    }

    // Algorithm 8: 6->5, {5+[4](fb)}->3  |  2->1
    // Carriers: Op1, Op3
    private mutating func alg8() -> Float {
        let m6 = op5.process()
        let m5 = op4.process(m6)
        let m4 = op3.process()
        let c3 = op2.process(m5 + m4)
        let m2 = op1.process()
        let c1 = op0.process(m2)
        return (c1 + c3) * 0.707
    }

    // Algorithm 9: 6->5, {5+4}->3  |  [2](fb)->1
    // Carriers: Op1, Op3
    private mutating func alg9() -> Float {
        let m6 = op5.process()
        let m5 = op4.process(m6)
        let m4 = op3.process()
        let c3 = op2.process(m5 + m4)
        let m2 = op1.process()
        let c1 = op0.process(m2)
        return (c1 + c3) * 0.707
    }

    // Algorithm 10: {6+5}->4  |  [3](fb)->2->1
    // Carriers: Op1, Op4
    private mutating func alg10() -> Float {
        let m6 = op5.process()
        let m5 = op4.process()
        let c4 = op3.process(m6 + m5)
        let m3 = op2.process()
        let m2 = op1.process(m3)
        let c1 = op0.process(m2)
        return (c1 + c4) * 0.707
    }

    // Algorithm 11: {[6](fb)+5}->4  |  3->2->1
    // Carriers: Op1, Op4
    private mutating func alg11() -> Float {
        let m6 = op5.process()
        let m5 = op4.process()
        let c4 = op3.process(m6 + m5)
        let m3 = op2.process()
        let m2 = op1.process(m3)
        let c1 = op0.process(m2)
        return (c1 + c4) * 0.707
    }

    // Algorithm 12: {6+5+4}->3  |  [2](fb)->1
    // Carriers: Op1, Op3
    private mutating func alg12() -> Float {
        let m6 = op5.process()
        let m5 = op4.process()
        let m4 = op3.process()
        let c3 = op2.process(m6 + m5 + m4)
        let m2 = op1.process()
        let c1 = op0.process(m2)
        return (c1 + c3) * 0.707
    }

    // Algorithm 13: {[6](fb)+5+4}->3  |  2->1
    // Carriers: Op1, Op3
    private mutating func alg13() -> Float {
        let m6 = op5.process()
        let m5 = op4.process()
        let m4 = op3.process()
        let c3 = op2.process(m6 + m5 + m4)
        let m2 = op1.process()
        let c1 = op0.process(m2)
        return (c1 + c3) * 0.707
    }

    // Algorithm 14: [6](fb)->5, {5+4}->3  |  2->1
    // Same topology as 7 but Op5 feeds to Op4->Op3 chain differently:
    // {[6](fb)+5}->4->3  |  2->1
    // Carriers: Op1, Op3
    private mutating func alg14() -> Float {
        let m6 = op5.process()
        let m5 = op4.process()
        let m4 = op3.process(m6 + m5)
        let c3 = op2.process(m4)
        let m2 = op1.process()
        let c1 = op0.process(m2)
        return (c1 + c3) * 0.707
    }

    // Algorithm 15: {6+5}->4->3  |  [2](fb)->1
    // Carriers: Op1, Op3
    private mutating func alg15() -> Float {
        let m6 = op5.process()
        let m5 = op4.process()
        let m4 = op3.process(m6 + m5)
        let c3 = op2.process(m4)
        let m2 = op1.process()
        let c1 = op0.process(m2)
        return (c1 + c3) * 0.707
    }

    // Algorithm 16: [6](fb)->5, 4->3, {5+3+2}->1
    // Carriers: Op1 only
    private mutating func alg16() -> Float {
        let m6 = op5.process()
        let m5 = op4.process(m6)
        let m4 = op3.process()
        let m3 = op2.process(m4)
        let m2 = op1.process()
        let c1 = op0.process(m5 + m3 + m2)
        return c1
    }

    // Algorithm 17: 6->5, 4->3, {5+3+[2](fb)}->1
    // Carriers: Op1 only
    private mutating func alg17() -> Float {
        let m6 = op5.process()
        let m5 = op4.process(m6)
        let m4 = op3.process()
        let m3 = op2.process(m4)
        let m2 = op1.process()
        let c1 = op0.process(m5 + m3 + m2)
        return c1
    }

    // Algorithm 18: 6->5->4, {4+[3](fb)+2}->1
    // Carriers: Op1 only
    private mutating func alg18() -> Float {
        let m6 = op5.process()
        let m5 = op4.process(m6)
        let m4 = op3.process(m5)
        let m3 = op2.process()
        let m2 = op1.process()
        let c1 = op0.process(m4 + m3 + m2)
        return c1
    }

    // Algorithm 19: [6](fb)->{5,4}  |  3->2->1
    // Carriers: Op1, Op4, Op5
    private mutating func alg19() -> Float {
        let m6 = op5.process()
        let c5 = op4.process(m6)
        let c4 = op3.process(m6)
        let m3 = op2.process()
        let m2 = op1.process(m3)
        let c1 = op0.process(m2)
        return (c1 + c4 + c5) * 0.577
    }

    // Algorithm 20: {6+5}->4  |  [3](fb)->{2,1}
    // Carriers: Op1, Op2, Op4
    private mutating func alg20() -> Float {
        let m6 = op5.process()
        let m5 = op4.process()
        let c4 = op3.process(m6 + m5)
        let m3 = op2.process()
        let c2 = op1.process(m3)
        let c1 = op0.process(m3)
        return (c1 + c2 + c4) * 0.577
    }

    // Algorithm 21: 6->{5,4}  |  [3](fb)->{2,1}
    // Carriers: Op1, Op2, Op4, Op5
    private mutating func alg21() -> Float {
        let m6 = op5.process()
        let c5 = op4.process(m6)
        let c4 = op3.process(m6)
        let m3 = op2.process()
        let c2 = op1.process(m3)
        let c1 = op0.process(m3)
        return (c1 + c2 + c4 + c5) * 0.5
    }

    // Algorithm 22: [6](fb)->{5,4,3}  |  2->1
    // Carriers: Op1, Op3, Op4, Op5
    private mutating func alg22() -> Float {
        let m6 = op5.process()
        let c5 = op4.process(m6)
        let c4 = op3.process(m6)
        let c3 = op2.process(m6)
        let m2 = op1.process()
        let c1 = op0.process(m2)
        return (c1 + c3 + c4 + c5) * 0.5
    }

    // Algorithm 23: [6](fb)->{5,4}  |  3->2  |  1
    // Carriers: Op1, Op2, Op4, Op5
    private mutating func alg23() -> Float {
        let m6 = op5.process()
        let c5 = op4.process(m6)
        let c4 = op3.process(m6)
        let m3 = op2.process()
        let c2 = op1.process(m3)
        let c1 = op0.process()
        return (c1 + c2 + c4 + c5) * 0.5
    }

    // Algorithm 24: [6](fb)->{5,4,3}  |  2  |  1
    // Carriers: Op1, Op2, Op3, Op4, Op5
    private mutating func alg24() -> Float {
        let m6 = op5.process()
        let c5 = op4.process(m6)
        let c4 = op3.process(m6)
        let c3 = op2.process(m6)
        let c2 = op1.process()
        let c1 = op0.process()
        return (c1 + c2 + c3 + c4 + c5) * 0.447
    }

    // Algorithm 25: [6](fb)->{5,4}  |  3  |  2  |  1
    // Carriers: Op1, Op2, Op3, Op4, Op5
    private mutating func alg25() -> Float {
        let m6 = op5.process()
        let c5 = op4.process(m6)
        let c4 = op3.process(m6)
        let c3 = op2.process()
        let c2 = op1.process()
        let c1 = op0.process()
        return (c1 + c2 + c3 + c4 + c5) * 0.447
    }

    // Algorithm 26: {[6](fb)+5}->4  |  3->2  |  1
    // Carriers: Op1, Op2, Op4
    private mutating func alg26() -> Float {
        let m6 = op5.process()
        let m5 = op4.process()
        let c4 = op3.process(m6 + m5)
        let m3 = op2.process()
        let c2 = op1.process(m3)
        let c1 = op0.process()
        return (c1 + c2 + c4) * 0.577
    }

    // Algorithm 27: {6+5}->4  |  [3](fb)->2  |  1
    // Carriers: Op1, Op2, Op4
    private mutating func alg27() -> Float {
        let m6 = op5.process()
        let m5 = op4.process()
        let c4 = op3.process(m6 + m5)
        let m3 = op2.process()
        let c2 = op1.process(m3)
        let c1 = op0.process()
        return (c1 + c2 + c4) * 0.577
    }

    // Algorithm 28: 6  |  [5](fb)->4->3  |  2->1
    // Carriers: Op1, Op3, Op6
    private mutating func alg28() -> Float {
        let c6 = op5.process()
        let m5 = op4.process()
        let m4 = op3.process(m5)
        let c3 = op2.process(m4)
        let m2 = op1.process()
        let c1 = op0.process(m2)
        return (c1 + c3 + c6) * 0.577
    }

    // Algorithm 29: [6](fb)->5  |  4->3  |  2  |  1
    // Carriers: Op1, Op2, Op3, Op5
    private mutating func alg29() -> Float {
        let m6 = op5.process()
        let c5 = op4.process(m6)
        let m4 = op3.process()
        let c3 = op2.process(m4)
        let c2 = op1.process()
        let c1 = op0.process()
        return (c1 + c2 + c3 + c5) * 0.5
    }

    // Algorithm 30: 6  |  [5](fb)->4->3  |  2  |  1
    // Carriers: Op1, Op2, Op3, Op6
    private mutating func alg30() -> Float {
        let c6 = op5.process()
        let m5 = op4.process()
        let m4 = op3.process(m5)
        let c3 = op2.process(m4)
        let c2 = op1.process()
        let c1 = op0.process()
        return (c1 + c2 + c3 + c6) * 0.5
    }

    // Algorithm 31: [6](fb)->5  |  4  |  3  |  2  |  1
    // Carriers: Op1, Op2, Op3, Op4, Op5
    private mutating func alg31() -> Float {
        let m6 = op5.process()
        let c5 = op4.process(m6)
        let c4 = op3.process()
        let c3 = op2.process()
        let c2 = op1.process()
        let c1 = op0.process()
        return (c1 + c2 + c3 + c4 + c5) * 0.447
    }

    // Algorithm 32: [6](fb)  |  5  |  4  |  3  |  2  |  1
    // All 6 carriers (pure additive)
    private mutating func alg32() -> Float {
        let c6 = op5.process()
        let c5 = op4.process()
        let c4 = op3.process()
        let c3 = op2.process()
        let c2 = op1.process()
        let c1 = op0.process()
        return (c1 + c2 + c3 + c4 + c5 + c6) * 0.408
    }

    // Per-operator access by index
    mutating func setOpLevel(_ i: Int, _ v: Float) {
        switch i {
        case 0: op0.level = v; case 1: op1.level = v; case 2: op2.level = v
        case 3: op3.level = v; case 4: op4.level = v; case 5: op5.level = v
        default: break
        }
    }
    mutating func setOpRatio(_ i: Int, _ v: Float) {
        switch i {
        case 0: op0.ratio = v; case 1: op1.ratio = v; case 2: op2.ratio = v
        case 3: op3.ratio = v; case 4: op4.ratio = v; case 5: op5.ratio = v
        default: break
        }
    }
    mutating func setOpDetune(_ i: Int, _ cents: Float) {
        switch i {
        case 0: op0.setDetuneCents(cents); case 1: op1.setDetuneCents(cents)
        case 2: op2.setDetuneCents(cents); case 3: op3.setDetuneCents(cents)
        case 4: op4.setDetuneCents(cents); case 5: op5.setDetuneCents(cents)
        default: break
        }
    }
    mutating func setOpFeedback(_ i: Int, _ v: Float) {
        switch i {
        case 0: op0.feedback = v; case 1: op1.feedback = v; case 2: op2.feedback = v
        case 3: op3.feedback = v; case 4: op4.feedback = v; case 5: op5.feedback = v
        default: break
        }
    }
    mutating func setOpEGRates(_ i: Int, _ r1: Float, _ r2: Float, _ r3: Float, _ r4: Float) {
        switch i {
        case 0: op0.env.setRates(r1, r2, r3, r4)
        case 1: op1.env.setRates(r1, r2, r3, r4)
        case 2: op2.env.setRates(r1, r2, r3, r4)
        case 3: op3.env.setRates(r1, r2, r3, r4)
        case 4: op4.env.setRates(r1, r2, r3, r4)
        case 5: op5.env.setRates(r1, r2, r3, r4)
        default: break
        }
    }
    mutating func setOpEGLevels(_ i: Int, _ l1: Float, _ l2: Float, _ l3: Float, _ l4: Float) {
        switch i {
        case 0: op0.env.setLevels(l1, l2, l3, l4)
        case 1: op1.env.setLevels(l1, l2, l3, l4)
        case 2: op2.env.setLevels(l1, l2, l3, l4)
        case 3: op3.env.setLevels(l1, l2, l3, l4)
        case 4: op4.env.setLevels(l1, l2, l3, l4)
        case 5: op5.env.setLevels(l1, l2, l3, l4)
        default: break
        }
    }
}

// MARK: - FMSynthEngine

/// Pure-Swift FM synth engine.
/// Thread-safety: `NSLock` protects mutable state.
final class FMSynthEngine: @unchecked Sendable {

    private let lock = NSLock()

    // Voices stored as Array (heap-allocated, avoids stack overflow from large tuples)
    private var voices: [Voice] = Array(repeating: Voice(), count: kMaxVoices)
    private var sampleRate: Float = 44100
    private var masterVolume: Float = 0.7
    private var algorithm: Int = 0

    /// MIDI event queue (UI → audio)
    let midiQueue = MIDIEventQueue()

    // MARK: - Setup

    func setSampleRate(_ sr: Float) {
        lock.lock(); defer { lock.unlock() }
        sampleRate = sr
        for i in 0..<kMaxVoices { voices[i].setSampleRate(sr) }
    }

    func setAlgorithm(_ alg: Int) {
        lock.lock(); defer { lock.unlock() }
        let clamped = max(0, min(kNumAlgorithms - 1, alg))
        algorithm = clamped
        for i in 0..<kMaxVoices { voices[i].algorithm = clamped }
    }

    func setMasterVolume(_ vol: Float) {
        lock.lock(); defer { lock.unlock() }
        masterVolume = max(0, min(1, vol))
    }

    // MARK: - Per-operator parameter setters

    func setOperatorLevel(_ opIndex: Int, level: Float) {
        guard opIndex >= 0, opIndex < kNumOperators else { return }
        lock.lock(); defer { lock.unlock() }
        for i in 0..<kMaxVoices { voices[i].setOpLevel(opIndex, level) }
    }

    func setOperatorRatio(_ opIndex: Int, ratio: Float) {
        guard opIndex >= 0, opIndex < kNumOperators else { return }
        lock.lock(); defer { lock.unlock() }
        for i in 0..<kMaxVoices { voices[i].setOpRatio(opIndex, ratio) }
    }

    func setOperatorDetune(_ opIndex: Int, cents: Float) {
        guard opIndex >= 0, opIndex < kNumOperators else { return }
        lock.lock(); defer { lock.unlock() }
        for i in 0..<kMaxVoices { voices[i].setOpDetune(opIndex, cents) }
    }

    func setOperatorFeedback(_ opIndex: Int, feedback: Float) {
        guard opIndex >= 0, opIndex < kNumOperators else { return }
        lock.lock(); defer { lock.unlock() }
        for i in 0..<kMaxVoices { voices[i].setOpFeedback(opIndex, feedback) }
    }

    func setOperatorEGRates(_ opIndex: Int, r1: Float, r2: Float, r3: Float, r4: Float) {
        guard opIndex >= 0, opIndex < kNumOperators else { return }
        lock.lock(); defer { lock.unlock() }
        for i in 0..<kMaxVoices { voices[i].setOpEGRates(opIndex, r1, r2, r3, r4) }
    }

    func setOperatorEGLevels(_ opIndex: Int, l1: Float, l2: Float, l3: Float, l4: Float) {
        guard opIndex >= 0, opIndex < kNumOperators else { return }
        lock.lock(); defer { lock.unlock() }
        for i in 0..<kMaxVoices { voices[i].setOpEGLevels(opIndex, l1, l2, l3, l4) }
    }

    // MARK: - Render (called from audio thread)

    func render(into bufferL: UnsafeMutablePointer<Float>,
                bufferR: UnsafeMutablePointer<Float>,
                frameCount: Int) {
        lock.lock(); defer { lock.unlock() }

        // 1. Drain MIDI events
        let events = midiQueue.drain()
        for event in events {
            switch event.kind {
            case .noteOn:
                if event.data2 == 0 { doNoteOff(event.data1) }
                else { doNoteOn(event.data1, velocity: event.data2) }
            case .noteOff:
                doNoteOff(event.data1)
            case .controlChange:
                if event.data1 == 123 { doAllNotesOff() }
            }
        }

        // 2. Render
        let vol = masterVolume
        for frame in 0..<frameCount {
            var output: Float = 0
            var activeCount = 0
            for i in 0..<kMaxVoices {
                voices[i].checkActive()
                if voices[i].active {
                    output += voices[i].process()
                    activeCount += 1
                }
            }
            if activeCount > 0 {
                output /= sqrtf(Float(activeCount)) * kVoiceNormalizationScale
            }
            let sample = output * vol
            bufferL[frame] = sample
            bufferR[frame] = sample
        }
    }

    // MARK: - MIDI handling (must be called under lock)

    private func doNoteOn(_ note: UInt8, velocity: UInt8) {
        var target = 0
        for i in 0..<kMaxVoices {
            voices[i].checkActive()
            if !voices[i].active { target = i; break }
        }
        voices[target].algorithm = algorithm
        voices[target].noteOn(note, velocity: velocity)
    }

    private func doNoteOff(_ note: UInt8) {
        for i in 0..<kMaxVoices {
            if voices[i].active && voices[i].note == note {
                voices[i].noteOff()
            }
        }
    }

    private func doAllNotesOff() {
        for i in 0..<kMaxVoices { voices[i].noteOff() }
    }
}
