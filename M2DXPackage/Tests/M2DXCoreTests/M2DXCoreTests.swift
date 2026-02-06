// M2DXCoreTests.swift
// Tests for M2DXCore module

import Testing
@testable import M2DXCore

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

    @Test("Default envelope has correct initial values")
    func defaultEnvelopeInitialization() {
        let env = EnvelopeParameters()

        #expect(env.rate1 == 0.99)
        #expect(env.rate2 == 0.99)
        #expect(env.rate3 == 0.99)
        #expect(env.rate4 == 0.99)
        #expect(env.level1 == 0.99)
        #expect(env.level2 == 0.99)
        #expect(env.level3 == 0.99)
        #expect(env.level4 == 0.0)
    }

    @Test("Default keyboard level scaling has correct initial values")
    func defaultKeyboardLevelScalingInitialization() {
        let kls = KeyboardLevelScaling()

        #expect(kls.breakPoint == 60)
        #expect(kls.leftDepth == 0.0)
        #expect(kls.rightDepth == 0.0)
        #expect(kls.leftCurve == .linear)
        #expect(kls.rightCurve == .linear)
    }

    @Test("All scaling curves are available")
    func allScalingCurvesAvailable() {
        #expect(KeyboardLevelScaling.ScalingCurve.allCases.count == 4)
    }
}
