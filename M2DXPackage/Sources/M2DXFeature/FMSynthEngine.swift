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
        case 4:  out = alg5()
        case 31: out = alg32()
        default: out = alg1()
        }
        return out * velScale
    }

    // Algorithm 1: serial OP6→5→4→3→2→1
    private mutating func alg1() -> Float {
        var m = op5.process()
        m = op4.process(m); m = op3.process(m)
        m = op2.process(m); m = op1.process(m)
        return op0.process(m)
    }

    // Algorithm 2: (OP6→5→4→3→2) + OP1
    private mutating func alg2() -> Float {
        var m = op5.process()
        m = op4.process(m); m = op3.process(m); m = op2.process(m)
        return (op1.process(m) + op0.process()) * 0.5
    }

    // Algorithm 5: parallel pairs (OP6→5, OP4→3, OP2→1)
    private mutating func alg5() -> Float {
        let o1 = op4.process(op5.process())
        let o2 = op2.process(op3.process())
        let o3 = op0.process(op1.process())
        return (o1 + o2 + o3) * 0.33
    }

    // Algorithm 32: all carriers
    private mutating func alg32() -> Float {
        let sum = op0.process() + op1.process() + op2.process()
            + op3.process() + op4.process() + op5.process()
        return sum / 6.0
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
