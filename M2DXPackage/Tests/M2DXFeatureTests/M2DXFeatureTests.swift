// M2DXFeatureTests.swift
// Tests for M2DXFeature module

import Testing
@testable import M2DXFeature
@testable import M2DXCore

@Suite("M2DX Feature Tests")
struct M2DXFeatureTests {

    @Test("M2DXRootView can be instantiated")
    @MainActor
    func rootViewInstantiation() {
        let view = M2DXRootView()
        #expect(view != nil)
    }
}
