// M2DXCoreTests.swift
// Tests for M2DXCore module

import Testing
@testable import M2DXCore

@Suite("M2DX Voice Tests")
struct M2DXVoiceTests {

    @Test("M2DX voice has 8 operators")
    func m2dxVoiceHas8Operators() {
        let voice = M2DXVoice()

        #expect(voice.operators.count == 8)
        #expect(M2DXVoice.operatorCount == 8)
    }

    @Test("M2DX has 64 algorithms")
    func m2dxHas64Algorithms() {
        #expect(M2DXAlgorithm.allCases.count == 64)
        #expect(M2DXAlgorithm.algorithm1.rawValue == 1)
        #expect(M2DXAlgorithm.algorithm64.rawValue == 64)
    }

    @Test("Extended algorithms are marked correctly")
    func extendedAlgorithmsMarked() {
        #expect(M2DXAlgorithm.algorithm32.isExtended == false)
        #expect(M2DXAlgorithm.algorithm33.isExtended == true)
        #expect(M2DXAlgorithm.algorithm64.isExtended == true)
    }

    @Test("Default M2DX voice has correct initial values")
    func defaultM2DXVoiceInitialization() {
        let voice = M2DXVoice()

        #expect(voice.name == "INIT M2DX")
        #expect(voice.algorithm == .algorithm1)
        #expect(voice.feedback == 0.0)
        #expect(voice.feedback2 == 0.0)
        #expect(voice.transpose == 0)
    }
}

@Suite("DX7 Voice Tests")
struct DX7VoiceTests {

    @Test("DX7 voice has 6 operators")
    func dx7VoiceHas6Operators() {
        let voice = DX7Voice()

        #expect(voice.operators.count == 6)
        #expect(DX7Voice.operatorCount == 6)
    }

    @Test("DX7 has 32 algorithms")
    func dx7Has32Algorithms() {
        #expect(DX7Algorithm.allCases.count == 32)
        #expect(DX7Algorithm.algorithm1.rawValue == 1)
        #expect(DX7Algorithm.algorithm32.rawValue == 32)
    }

    @Test("Default DX7 voice has correct initial values")
    func defaultDX7VoiceInitialization() {
        let voice = DX7Voice()

        #expect(voice.name == "INIT VOICE")
        #expect(voice.algorithm == .algorithm1)
        #expect(voice.feedback == 0.0)
        #expect(voice.transpose == 0)
    }
}

@Suite("TX816 Configuration Tests")
struct TX816ConfigurationTests {

    @Test("TX816 has 8 modules")
    func tx816Has8Modules() {
        let config = TX816Configuration()

        #expect(config.modules.count == 8)
        #expect(TX816Configuration.moduleCount == 8)
    }

    @Test("Each module has unique ID and default MIDI channel")
    func modulesHaveUniqueIDsAndChannels() {
        let config = TX816Configuration()

        for (index, module) in config.modules.enumerated() {
            #expect(module.id == index + 1)
            #expect(module.midiChannel == index + 1)
        }
    }

    @Test("Each module contains a DX7 voice")
    func modulesContainDX7Voice() {
        let config = TX816Configuration()

        for module in config.modules {
            #expect(module.voice.operators.count == 6)
        }
    }

    @Test("Modules are enabled by default")
    func modulesEnabledByDefault() {
        let config = TX816Configuration()

        for module in config.modules {
            #expect(module.enabled == true)
        }
    }
}

@Suite("Operator Parameters Tests")
struct OperatorParametersTests {

    @Test("Default operator has correct initial values")
    func defaultOperatorInitialization() {
        let op = OperatorParameters()

        #expect(op.level == 0.99)
        #expect(op.frequencyRatio == 1.0)
        #expect(op.detune == 0)
        #expect(op.velocitySensitivity == 0.0)
        #expect(op.fixedFrequency == false)
    }

    @Test("Operator factory creates with correct ID")
    func operatorFactoryCreatesWithID() {
        let op = OperatorParameters.defaultOperator(id: 5)

        #expect(op.id == 5)
    }
}

@Suite("Engine State Tests")
struct EngineStateTests {

    @Test("Default engine state is M2DX 8-OP mode")
    func defaultEngineStateIsM2DX() {
        let state = M2DXEngineState()

        #expect(state.mode == .m2dx8op)
    }

    @Test("Engine state contains both voice types")
    func engineStateContainsBothVoiceTypes() {
        let state = M2DXEngineState()

        #expect(state.m2dxVoice.operators.count == 8)
        #expect(state.tx816Config.modules.count == 8)
    }

    @Test("Synth engine modes are available")
    func synthEngineModesAvailable() {
        #expect(SynthEngineMode.allCases.count == 2)
        #expect(SynthEngineMode.m2dx8op.rawValue == "M2DX 8-OP")
        #expect(SynthEngineMode.tx816.rawValue == "TX816")
    }
}

@Suite("LFO Parameters Tests")
struct LFOParametersTests {

    @Test("All LFO waveforms are available")
    func allLFOWaveformsAvailable() {
        #expect(LFOParameters.LFOWave.allCases.count == 6)
    }

    @Test("Default LFO uses triangle wave")
    func defaultLFOWaveform() {
        let lfo = LFOParameters()

        #expect(lfo.wave == .triangle)
        #expect(lfo.sync == true)
    }
}

@Suite("Modulation Matrix Tests")
struct ModulationMatrixTests {

    @Test("Modulation sources are available")
    func modulationSourcesAvailable() {
        #expect(ModulationSource.allCases.count == 9)
    }

    @Test("Modulation destinations include all 8 operators")
    func modulationDestinationsInclude8Operators() {
        let opDestinations = ModulationDestination.allCases.filter {
            $0.rawValue.contains("OP") && $0.rawValue.contains("Level")
        }

        #expect(opDestinations.count == 8)
    }
}
