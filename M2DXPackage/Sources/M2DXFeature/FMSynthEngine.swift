// FMSynthEngine.swift
// Pure-Swift FM synthesis engine — port of C++ M2DXKernel / FMOperator
// Designed to run on the audio render thread via AVAudioSourceNode.

import Foundation

// MARK: - Constants

private let kNumOperators = 6
private let kMaxVoices = 16
private let kNumAlgorithms = 32
private let kVoiceNormalizationScale: Float = 3.0
private let kTwoPi: Float = 2.0 * .pi

/// Fast tanh approximation for soft clipping (Pade approximant)
@inline(__always)
private func tanhApprox(_ x: Float) -> Float {
    let x2 = x * x
    return x * (27.0 + x2) / (27.0 + 9.0 * x2)
}

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

    mutating func noteOff(held: Bool = false) {
        if held {
            // Sustain pedal is down — stay in sustain stage
            return
        }
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

    var baseFrequency: Float = 440  // store base frequency for pitch bend

    mutating func noteOn(baseFreq: Float) {
        baseFrequency = baseFreq
        frequency = baseFreq * ratio * detune
        phaseInc = frequency / sampleRate
        env.noteOn()
        phase = 0; prev1 = 0; prev2 = 0
    }

    mutating func applyPitchBend(_ factor: Float) {
        phaseInc = baseFrequency * ratio * detune * factor / sampleRate
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

// MARK: - Algorithm Routing Table

/// Per-operator routing: modulation sources (op indices, -1 = none) and carrier flag
private struct OpRoute {
    var src0: Int8 = -1
    var src1: Int8 = -1
    var src2: Int8 = -1
    var isCarrier: Bool = false
}

/// Complete algorithm definition: routing for 6 operators + normalization
private struct AlgorithmRoute {
    var ops: (OpRoute, OpRoute, OpRoute, OpRoute, OpRoute, OpRoute)
    var norm: Float
}

/// DX7 algorithm routing table (32 algorithms, 0-indexed)
/// Processing order is always op5→op4→op3→op2→op1→op0.
/// Modulation sources reference operator indices whose output is already computed.
private let kAlgorithmTable: [AlgorithmRoute] = {
    // Helper to build an AlgorithmRoute from per-op specs
    func alg(_ o0: OpRoute, _ o1: OpRoute, _ o2: OpRoute,
             _ o3: OpRoute, _ o4: OpRoute, _ o5: OpRoute,
             norm: Float) -> AlgorithmRoute {
        AlgorithmRoute(ops: (o0, o1, o2, o3, o4, o5), norm: norm)
    }
    // c = carrier, m = modulator
    func c(_ s0: Int8 = -1, _ s1: Int8 = -1, _ s2: Int8 = -1) -> OpRoute {
        OpRoute(src0: s0, src1: s1, src2: s2, isCarrier: true)
    }
    func m(_ s0: Int8 = -1, _ s1: Int8 = -1, _ s2: Int8 = -1) -> OpRoute {
        OpRoute(src0: s0, src1: s1, src2: s2, isCarrier: false)
    }

    return [
        // Alg 1:  6->5->4->3 | 2->1     Carriers: 0,2
        alg(c(1), m(), c(3), m(4), m(5), m(), norm: 0.707),
        // Alg 2:  6->5->4->3 | 2->1     Carriers: 0,2  (same flow, different fb)
        alg(c(1), m(), c(3), m(4), m(5), m(), norm: 0.707),
        // Alg 3:  6->5->4 | 3->2->1     Carriers: 0,3
        alg(c(1), m(2), m(), c(4), m(5), m(), norm: 0.707),
        // Alg 4:  6->5->4 | 3->2->1     Carriers: 0,3  (same flow, cross-fb)
        alg(c(1), m(2), m(), c(4), m(5), m(), norm: 0.707),
        // Alg 5:  6->5 | 4->3 | 2->1    Carriers: 0,2,4
        alg(c(1), m(), c(3), m(), c(5), m(), norm: 0.577),
        // Alg 6:  6->5 | 4->3 | 2->1    Carriers: 0,2,4  (same flow, cross-fb)
        alg(c(1), m(), c(3), m(), c(5), m(), norm: 0.577),
        // Alg 7:  6->5, {5+4}->3 | 2->1  Carriers: 0,2
        alg(c(1), m(), c(4, 3), m(), m(5), m(), norm: 0.707),
        // Alg 8:  6->5, {5+4}->3 | 2->1  Carriers: 0,2  (same flow)
        alg(c(1), m(), c(4, 3), m(), m(5), m(), norm: 0.707),
        // Alg 9:  6->5, {5+4}->3 | 2->1  Carriers: 0,2  (same flow)
        alg(c(1), m(), c(4, 3), m(), m(5), m(), norm: 0.707),
        // Alg 10: {6+5}->4 | 3->2->1    Carriers: 0,3
        alg(c(1), m(2), m(), c(5, 4), m(), m(), norm: 0.707),
        // Alg 11: {6+5}->4 | 3->2->1    Carriers: 0,3  (same flow)
        alg(c(1), m(2), m(), c(5, 4), m(), m(), norm: 0.707),
        // Alg 12: {6+5+4}->3 | 2->1     Carriers: 0,2
        alg(c(1), m(), c(5, 4, 3), m(), m(), m(), norm: 0.707),
        // Alg 13: {6+5+4}->3 | 2->1     Carriers: 0,2  (same flow)
        alg(c(1), m(), c(5, 4, 3), m(), m(), m(), norm: 0.707),
        // Alg 14: {6+5}->4->3 | 2->1    Carriers: 0,2
        alg(c(1), m(), c(3), m(5, 4), m(), m(), norm: 0.707),
        // Alg 15: {6+5}->4->3 | 2->1    Carriers: 0,2  (same flow)
        alg(c(1), m(), c(3), m(5, 4), m(), m(), norm: 0.707),
        // Alg 16: 6->5, 4->3, {5+3+2}->1  Carriers: 0
        alg(c(4, 2, 1), m(), m(3), m(), m(5), m(), norm: 1.0),
        // Alg 17: 6->5, 4->3, {5+3+2}->1  Carriers: 0  (same flow)
        alg(c(4, 2, 1), m(), m(3), m(), m(5), m(), norm: 1.0),
        // Alg 18: 6->5->4, {4+3+2}->1   Carriers: 0
        alg(c(3, 2, 1), m(), m(), m(4), m(5), m(), norm: 1.0),
        // Alg 19: 6->{5,4} | 3->2->1    Carriers: 0,3,4
        alg(c(1), m(2), m(), c(5), c(5), m(), norm: 0.577),
        // Alg 20: {6+5}->4 | 3->{2,1}   Carriers: 0,1,3
        alg(c(2), c(2), m(), c(5, 4), m(), m(), norm: 0.577),
        // Alg 21: 6->{5,4} | 3->{2,1}   Carriers: 0,1,3,4
        alg(c(2), c(2), m(), c(5), c(5), m(), norm: 0.5),
        // Alg 22: 6->{5,4,3} | 2->1     Carriers: 0,2,3,4
        alg(c(1), m(), c(5), c(5), c(5), m(), norm: 0.5),
        // Alg 23: 6->{5,4} | 3->2 | 1   Carriers: 0,1,3,4
        alg(c(), c(2), m(), c(5), c(5), m(), norm: 0.5),
        // Alg 24: 6->{5,4,3} | 2 | 1    Carriers: 0,1,2,3,4
        alg(c(), c(), c(5), c(5), c(5), m(), norm: 0.447),
        // Alg 25: 6->{5,4} | 3 | 2 | 1  Carriers: 0,1,2,3,4
        alg(c(), c(), c(), c(5), c(5), m(), norm: 0.447),
        // Alg 26: {6+5}->4 | 3->2 | 1   Carriers: 0,1,3
        alg(c(), c(2), m(), c(5, 4), m(), m(), norm: 0.577),
        // Alg 27: {6+5}->4 | 3->2 | 1   Carriers: 0,1,3  (same flow)
        alg(c(), c(2), m(), c(5, 4), m(), m(), norm: 0.577),
        // Alg 28: 6 | 5->4->3 | 2->1    Carriers: 0,2,5
        alg(c(1), m(), c(3), m(4), m(), c(), norm: 0.577),
        // Alg 29: 6->5 | 4->3 | 2 | 1   Carriers: 0,1,2,4
        alg(c(), c(), c(3), m(), c(5), m(), norm: 0.5),
        // Alg 30: 6 | 5->4->3 | 2 | 1   Carriers: 0,1,2,5
        alg(c(), c(), c(3), m(4), m(), c(), norm: 0.5),
        // Alg 31: 6->5 | 4 | 3 | 2 | 1  Carriers: 0,1,2,3,4
        alg(c(), c(), c(), c(), c(5), m(), norm: 0.447),
        // Alg 32: 6 | 5 | 4 | 3 | 2 | 1 Carriers: all
        alg(c(), c(), c(), c(), c(), c(), norm: 0.408),
    ]
}()

// MARK: - Voice

/// Single polyphonic voice — 6 operators with table-driven algorithm routing
private struct Voice {
    var ops = (FMOp(), FMOp(), FMOp(), FMOp(), FMOp(), FMOp())
    var note: UInt8 = 0
    var velScale: Float = 1.0
    var active = false
    var sustained = false  // held by sustain pedal after noteOff
    var algorithm: Int = 0
    var pitchBendFactor: Float = 1.0  // pitch bend multiplier (1.0 = no bend)

    mutating func checkActive() {
        if active {
            if !(ops.0.isActive || ops.1.isActive || ops.2.isActive ||
                 ops.3.isActive || ops.4.isActive || ops.5.isActive) {
                active = false
            }
        }
    }

    mutating func setSampleRate(_ sr: Float) {
        withOp(0) { $0.setSampleRate(sr) }
        withOp(1) { $0.setSampleRate(sr) }
        withOp(2) { $0.setSampleRate(sr) }
        withOp(3) { $0.setSampleRate(sr) }
        withOp(4) { $0.setSampleRate(sr) }
        withOp(5) { $0.setSampleRate(sr) }
    }

    mutating func noteOn(_ n: UInt8, velocity16: UInt16) {
        note = n
        velScale = Float(velocity16) / 65535.0
        active = true
        let freq: Float = 440.0 * powf(2.0, (Float(n) - 69.0) / 12.0)
        withOp(0) { $0.noteOn(baseFreq: freq) }
        withOp(1) { $0.noteOn(baseFreq: freq) }
        withOp(2) { $0.noteOn(baseFreq: freq) }
        withOp(3) { $0.noteOn(baseFreq: freq) }
        withOp(4) { $0.noteOn(baseFreq: freq) }
        withOp(5) { $0.noteOn(baseFreq: freq) }
    }

    mutating func noteOff(held: Bool = false) {
        if held {
            sustained = true
            return
        }
        sustained = false
        withOp(0) { $0.noteOff() }
        withOp(1) { $0.noteOff() }
        withOp(2) { $0.noteOff() }
        withOp(3) { $0.noteOff() }
        withOp(4) { $0.noteOff() }
        withOp(5) { $0.noteOff() }
    }

    mutating func releaseSustain() {
        if sustained {
            sustained = false
            noteOff()
        }
    }

    mutating func applyPitchBend(_ factor: Float) {
        pitchBendFactor = factor
        withOp(0) { $0.applyPitchBend(factor) }
        withOp(1) { $0.applyPitchBend(factor) }
        withOp(2) { $0.applyPitchBend(factor) }
        withOp(3) { $0.applyPitchBend(factor) }
        withOp(4) { $0.applyPitchBend(factor) }
        withOp(5) { $0.applyPitchBend(factor) }
    }

    // MARK: - Table-driven process

    mutating func process() -> Float {
        guard active else { return 0 }
        let route = kAlgorithmTable[algorithm]

        // Outputs buffer — processed top-down (op5 first)
        var out: (Float, Float, Float, Float, Float, Float) = (0, 0, 0, 0, 0, 0)

        // Process op5 (index 5) — always first, can only have no sources
        let r5 = route.ops.5
        let mod5 = modSum(r5, out)
        out.5 = ops.5.process(mod5)

        // Process op4 (index 4)
        let r4 = route.ops.4
        let mod4 = modSum(r4, out)
        out.4 = ops.4.process(mod4)

        // Process op3 (index 3)
        let r3 = route.ops.3
        let mod3 = modSum(r3, out)
        out.3 = ops.3.process(mod3)

        // Process op2 (index 2)
        let r2 = route.ops.2
        let mod2 = modSum(r2, out)
        out.2 = ops.2.process(mod2)

        // Process op1 (index 1)
        let r1 = route.ops.1
        let mod1 = modSum(r1, out)
        out.1 = ops.1.process(mod1)

        // Process op0 (index 0)
        let r0 = route.ops.0
        let mod0 = modSum(r0, out)
        out.0 = ops.0.process(mod0)

        // Sum carriers
        var sum: Float = 0
        if route.ops.0.isCarrier { sum += out.0 }
        if route.ops.1.isCarrier { sum += out.1 }
        if route.ops.2.isCarrier { sum += out.2 }
        if route.ops.3.isCarrier { sum += out.3 }
        if route.ops.4.isCarrier { sum += out.4 }
        if route.ops.5.isCarrier { sum += out.5 }

        return sum * route.norm * velScale
    }

    /// Sum modulation sources from already-computed operator outputs
    @inline(__always)
    private func modSum(_ r: OpRoute, _ out: (Float, Float, Float, Float, Float, Float)) -> Float {
        var m: Float = 0
        if r.src0 >= 0 { m += outAt(Int(r.src0), out) }
        if r.src1 >= 0 { m += outAt(Int(r.src1), out) }
        if r.src2 >= 0 { m += outAt(Int(r.src2), out) }
        return m
    }

    @inline(__always)
    private func outAt(_ i: Int, _ out: (Float, Float, Float, Float, Float, Float)) -> Float {
        switch i {
        case 0: return out.0
        case 1: return out.1
        case 2: return out.2
        case 3: return out.3
        case 4: return out.4
        case 5: return out.5
        default: return 0
        }
    }

    // MARK: - Indexed operator access

    @inline(__always)
    mutating func withOp(_ i: Int, _ body: (inout FMOp) -> Void) {
        switch i {
        case 0: body(&ops.0)
        case 1: body(&ops.1)
        case 2: body(&ops.2)
        case 3: body(&ops.3)
        case 4: body(&ops.4)
        case 5: body(&ops.5)
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
    private var sustainPedalOn: Bool = false
    private var pitchBendFactor: Float = 1.0  // current pitch bend (semitones ±2)

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
        for i in 0..<kMaxVoices { voices[i].withOp(opIndex) { $0.level = level } }
    }

    func setOperatorRatio(_ opIndex: Int, ratio: Float) {
        guard opIndex >= 0, opIndex < kNumOperators else { return }
        lock.lock(); defer { lock.unlock() }
        for i in 0..<kMaxVoices { voices[i].withOp(opIndex) { $0.ratio = ratio } }
    }

    func setOperatorDetune(_ opIndex: Int, cents: Float) {
        guard opIndex >= 0, opIndex < kNumOperators else { return }
        lock.lock(); defer { lock.unlock() }
        for i in 0..<kMaxVoices { voices[i].withOp(opIndex) { $0.setDetuneCents(cents) } }
    }

    func setOperatorFeedback(_ opIndex: Int, feedback: Float) {
        guard opIndex >= 0, opIndex < kNumOperators else { return }
        lock.lock(); defer { lock.unlock() }
        for i in 0..<kMaxVoices { voices[i].withOp(opIndex) { $0.feedback = feedback } }
    }

    func setOperatorEGRates(_ opIndex: Int, r1: Float, r2: Float, r3: Float, r4: Float) {
        guard opIndex >= 0, opIndex < kNumOperators else { return }
        lock.lock(); defer { lock.unlock() }
        for i in 0..<kMaxVoices { voices[i].withOp(opIndex) { $0.env.setRates(r1, r2, r3, r4) } }
    }

    func setOperatorEGLevels(_ opIndex: Int, l1: Float, l2: Float, l3: Float, l4: Float) {
        guard opIndex >= 0, opIndex < kNumOperators else { return }
        lock.lock(); defer { lock.unlock() }
        for i in 0..<kMaxVoices { voices[i].withOp(opIndex) { $0.env.setLevels(l1, l2, l3, l4) } }
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
                let vel16 = UInt16(event.data2 & 0xFFFF)
                if vel16 == 0 { doNoteOff(event.data1) }
                else { doNoteOn(event.data1, velocity16: vel16) }
            case .noteOff:
                doNoteOff(event.data1)
            case .controlChange:
                doControlChange(event.data1, value32: event.data2)
            case .pitchBend:
                doPitchBend32(event.data2)
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
            // Soft clipping (tanh-style) to prevent harsh digital distortion
            let clipped = sample > 1.0 || sample < -1.0
                ? tanhApprox(sample)
                : sample
            bufferL[frame] = clipped
            bufferR[frame] = clipped
        }
    }

    // MARK: - MIDI handling (must be called under lock)

    private func doNoteOn(_ note: UInt8, velocity16: UInt16) {
        var target = 0
        for i in 0..<kMaxVoices {
            voices[i].checkActive()
            if !voices[i].active { target = i; break }
        }
        voices[target].algorithm = algorithm
        voices[target].noteOn(note, velocity16: velocity16)
        if pitchBendFactor != 1.0 {
            voices[target].applyPitchBend(pitchBendFactor)
        }
    }

    private func doNoteOff(_ note: UInt8) {
        for i in 0..<kMaxVoices {
            if voices[i].active && voices[i].note == note {
                voices[i].noteOff(held: sustainPedalOn)
            }
        }
    }

    private func doControlChange(_ cc: UInt8, value32: UInt32) {
        switch cc {
        case 64: // Sustain pedal: 32-bit threshold at 0x40000000
            let on = value32 >= 0x40000000
            sustainPedalOn = on
            if !on {
                // Release all sustained voices
                for i in 0..<kMaxVoices {
                    voices[i].releaseSustain()
                }
            }
        case 123: // All Notes Off
            doAllNotesOff()
        default:
            break
        }
    }

    private func doPitchBend32(_ value: UInt32) {
        // 32-bit unsigned: center = 0x80000000
        let signed = Int64(value) - 0x80000000
        let semitones = Float(signed) / Float(0x80000000) * 2.0  // ±2 semitones
        pitchBendFactor = powf(2.0, semitones / 12.0)
        for i in 0..<kMaxVoices {
            if voices[i].active {
                voices[i].applyPitchBend(pitchBendFactor)
            }
        }
    }

    private func doAllNotesOff() {
        sustainPedalOn = false
        for i in 0..<kMaxVoices {
            voices[i].sustained = false
            voices[i].noteOff()
        }
    }
}
