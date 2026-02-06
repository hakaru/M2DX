import Testing
@testable import M2DXCore

// MARK: - Parameter Address Map Tests

@Suite("M2DXParameterAddressMap Tests")
struct ParameterAddressMapTests {

    @Test("Global parameter address mapping")
    func globalParameterMapping() {
        // Algorithm
        let algorithmAddress = M2DXParameterAddressMap.addressForPath("Global/Algorithm")
        #expect(algorithmAddress == M2DXParameterAddressMap.Global.algorithm)

        let algorithmPath = M2DXParameterAddressMap.pathForAddress(M2DXParameterAddressMap.Global.algorithm)
        #expect(algorithmPath == "Global/Algorithm")

        // Master Volume
        let volumeAddress = M2DXParameterAddressMap.addressForPath("Global/MasterVolume")
        #expect(volumeAddress == M2DXParameterAddressMap.Global.masterVolume)
    }

    @Test("Operator parameter address calculation")
    func operatorAddressCalculation() {
        // Op1 Level
        let op1LevelAddress = M2DXParameterAddressMap.operatorAddress(opIndex: 0, offset: M2DXParameterAddressMap.Operator.level)
        #expect(op1LevelAddress == 100)

        // Op2 Level
        let op2LevelAddress = M2DXParameterAddressMap.operatorAddress(opIndex: 1, offset: M2DXParameterAddressMap.Operator.level)
        #expect(op2LevelAddress == 200)

        // Op6 EG Rate 1
        let op6EGRate1 = M2DXParameterAddressMap.operatorAddress(opIndex: 5, offset: M2DXParameterAddressMap.Operator.egRate1)
        #expect(op6EGRate1 == 610)
    }

    @Test("Operator path to address conversion")
    func operatorPathToAddress() {
        // Op1 Level
        let op1LevelAddress = M2DXParameterAddressMap.addressForPath("Operators/Op1/Level")
        #expect(op1LevelAddress == 100)

        // Op3 EG Rate 2
        let op3Rate2Address = M2DXParameterAddressMap.addressForPath("Operators/Op3/EG/Rates/Rate2")
        #expect(op3Rate2Address != nil)

        // Op6 Detune
        let op6DetuneAddress = M2DXParameterAddressMap.addressForPath("Operators/Op6/Frequency/Detune")
        #expect(op6DetuneAddress != nil)
    }

    @Test("Address to operator path conversion")
    func addressToOperatorPath() {
        // Op1 Level (address 100)
        let op1LevelPath = M2DXParameterAddressMap.pathForAddress(100)
        #expect(op1LevelPath == "Operators/Op1/Level")

        // Op2 Level (address 200)
        let op2LevelPath = M2DXParameterAddressMap.pathForAddress(200)
        #expect(op2LevelPath == "Operators/Op2/Level")
    }

    @Test("LFO parameter mapping")
    func lfoParameterMapping() {
        let speedAddress = M2DXParameterAddressMap.addressForPath("LFO/Speed")
        #expect(speedAddress == M2DXParameterAddressMap.LFO.speed)

        let waveformPath = M2DXParameterAddressMap.pathForAddress(M2DXParameterAddressMap.LFO.waveform)
        #expect(waveformPath == "LFO/Waveform")
    }

    @Test("Invalid path returns nil")
    func invalidPathReturnsNil() {
        let invalidAddress = M2DXParameterAddressMap.addressForPath("Invalid/Path")
        #expect(invalidAddress == nil)

        let invalidPath = M2DXParameterAddressMap.pathForAddress(999999)
        #expect(invalidPath == nil)
    }

    @Test("All mappings are bidirectional")
    func bidirectionalMappings() {
        for mapping in M2DXParameterAddressMap.allMappings {
            // Path -> Address -> Path should return same path
            guard let address = M2DXParameterAddressMap.addressForPath(mapping.path),
                  let roundtripPath = M2DXParameterAddressMap.pathForAddress(address) else {
                Issue.record("Mapping failed for path: \(mapping.path)")
                continue
            }

            #expect(roundtripPath == mapping.path, "Roundtrip failed for \(mapping.path)")
        }
    }
}

// MARK: - PE Resource Tests

@Suite("M2DXPEResource Tests")
struct PEResourceTests {

    @Test("Initialize with default values")
    func initializeDefaults() throws {
        let resource = M2DXPEResource()

        // Check algorithm default
        let algorithm = try resource.getProperty("Global/Algorithm")
        #expect(algorithm.intValue == 1)

        // Check LFO Speed default
        let lfoSpeed = try resource.getProperty("LFO/Speed")
        #expect(lfoSpeed.intValue == 35)
    }

    @Test("Get property as float")
    func getPropertyAsFloat() throws {
        let resource = M2DXPEResource()

        let algorithm = try resource.getPropertyAsFloat("Global/Algorithm")
        #expect(algorithm == 1.0)
    }

    @Test("Set property integer")
    func setPropertyInteger() throws {
        let resource = M2DXPEResource()

        try resource.setProperty("Global/Algorithm", value: .integer(15))
        let value = try resource.getProperty("Global/Algorithm")
        #expect(value.intValue == 15)
    }

    @Test("Set property from float")
    func setPropertyFromFloat() throws {
        let resource = M2DXPEResource()

        try resource.setPropertyFromFloat("Global/Algorithm", floatValue: 20.0)
        let value = try resource.getProperty("Global/Algorithm")
        #expect(value.intValue == 20)
    }

    @Test("Value out of range throws error")
    func valueOutOfRange() throws {
        let resource = M2DXPEResource()

        #expect(throws: PEResourceError.self) {
            try resource.setProperty("Global/Algorithm", value: .integer(100))  // Max is 32
        }
    }

    @Test("Invalid path throws error")
    func invalidPath() throws {
        let resource = M2DXPEResource()

        #expect(throws: PEResourceError.self) {
            _ = try resource.getProperty("Invalid/Path")
        }
    }

    @Test("Get resource list returns all parameters")
    func getResourceList() {
        let resource = M2DXPEResource()
        let resources = resource.getResourceList()

        // Should have all parameters from M2DXParameterTree
        #expect(resources.count == M2DXParameterTree.allParameters.count)
    }

    @Test("Subscription receives updates")
    func subscriptionReceivesUpdates() throws {
        let resource = M2DXPEResource()

        var receivedValue: PEValue?
        _ = resource.subscribe("Global/Algorithm") { value in
            receivedValue = value
        }

        try resource.setProperty("Global/Algorithm", value: .integer(10))

        #expect(receivedValue?.intValue == 10)
    }

    @Test("Unsubscribe stops updates")
    func unsubscribeStopsUpdates() throws {
        let resource = M2DXPEResource()

        var callCount = 0
        let subscriptionId = resource.subscribe("Global/Algorithm") { _ in
            callCount += 1
        }

        try resource.setProperty("Global/Algorithm", value: .integer(10))
        #expect(callCount == 1)

        resource.unsubscribe("Global/Algorithm", subscriptionId: subscriptionId!)

        try resource.setProperty("Global/Algorithm", value: .integer(20))
        #expect(callCount == 1)  // Should not increase
    }

    @Test("Get and set value by address")
    func getSetByAddress() throws {
        let resource = M2DXPEResource()

        // Set by address
        try resource.setValueByAddress(M2DXParameterAddressMap.Global.algorithm, value: .integer(25))

        // Get by address
        let value = try resource.getValueByAddress(M2DXParameterAddressMap.Global.algorithm)
        #expect(value.intValue == 25)
    }

    @Test("Reset to defaults")
    func resetToDefaults() throws {
        let resource = M2DXPEResource()

        // Change algorithm
        try resource.setProperty("Global/Algorithm", value: .integer(30))

        // Reset
        resource.resetToDefaults()

        // Should be back to default (1)
        let value = try resource.getProperty("Global/Algorithm")
        #expect(value.intValue == 1)
    }

    @Test("Export as JSON")
    func exportAsJSON() throws {
        let resource = M2DXPEResource()
        let json = try resource.exportAsJSON()

        // Should be valid JSON
        #expect(!json.isEmpty)
        #expect(json.contains("Global/Algorithm"))
    }
}

// MARK: - PE Bridge Tests

@Suite("M2DXPEBridge Tests")
struct PEBridgeTests {

    @Test("Initialize with default resource")
    func initializeDefault() {
        let bridge = M2DXPEBridge()
        #expect(bridge.peResource !== nil)
    }

    @Test("Get algorithm convenience method")
    func getAlgorithm() throws {
        let bridge = M2DXPEBridge()

        let algorithm = try bridge.getAlgorithm()
        #expect(algorithm == 1)  // Default
    }

    @Test("Set algorithm convenience method")
    func setAlgorithm() throws {
        let bridge = M2DXPEBridge()

        try bridge.setAlgorithm(15)
        let algorithm = try bridge.getAlgorithm()
        #expect(algorithm == 15)
    }

    @Test("Get operator level")
    func getOperatorLevel() throws {
        let bridge = M2DXPEBridge()

        // Op1 default is 99 (or higher for carriers)
        let level = try bridge.getOperatorLevel(1)
        #expect(level > 0)
    }

    @Test("Set operator level")
    func setOperatorLevel() throws {
        let bridge = M2DXPEBridge()

        try bridge.setOperatorLevel(1, level: 50.0)
        let level = try bridge.getOperatorLevel(1)
        #expect(level == 50.0)
    }

    @Test("Get LFO speed")
    func getLFOSpeed() throws {
        let bridge = M2DXPEBridge()

        let speed = try bridge.getLFOSpeed()
        #expect(speed == 35)  // Default
    }

    @Test("Set LFO speed")
    func setLFOSpeed() throws {
        let bridge = M2DXPEBridge()

        try bridge.setLFOSpeed(70)
        let speed = try bridge.getLFOSpeed()
        #expect(speed == 70)
    }

    @Test("Get resources returns descriptors")
    func getResources() {
        let bridge = M2DXPEBridge()
        let resources = bridge.getResources()

        #expect(!resources.isEmpty)
        #expect(resources.contains { $0.path == "Global/Algorithm" })
    }

    @Test("Reset to defaults")
    func resetToDefaults() throws {
        let bridge = M2DXPEBridge()

        try bridge.setAlgorithm(30)
        bridge.resetToDefaults()

        let algorithm = try bridge.getAlgorithm()
        #expect(algorithm == 1)
    }
}

// MARK: - M2DXParameterTree Tests

@Suite("M2DXParameterTree Tests")
struct ParameterTreeTests {

    @Test("Operator count is 6")
    func operatorCount() {
        #expect(M2DXParameterTree.operatorCount == 6)
    }

    @Test("Total parameter count")
    func totalParameterCount() {
        let count = M2DXParameterTree.totalParameterCount

        // Should have global + 6 operators + LFO + PitchEG + controllers
        // Global: 6, Each Op: ~21, LFO: 7, PitchEG: 8, Controllers: 12
        // Total should be around 155-190
        #expect(count > 100)
        #expect(count < 300)
    }

    @Test("Get parameter by path")
    func getParameterByPath() {
        let algorithm = M2DXParameterTree.parameter(at: "Global/Algorithm")
        #expect(algorithm != nil)
        #expect(algorithm?.title == "Algorithm")
    }

    @Test("Get parameters under prefix")
    func getParametersUnderPrefix() {
        let op1Params = M2DXParameterTree.parameters(under: "Operators/Op1")
        #expect(!op1Params.isEmpty)
        #expect(op1Params.count > 10)  // Should have many operator parameters
    }

    @Test("Export as JSON")
    func exportAsJSON() {
        let json = M2DXParameterTree.exportAsJSON()
        #expect(!json.isEmpty)
        #expect(json.contains("Global/Algorithm"))
    }

    @Test("Operator parameters have correct paths")
    func operatorParameterPaths() {
        let op1Params = M2DXParameterTree.operatorParameters(for: 1)

        #expect(op1Params.contains { $0.path == "Operators/Op1/Level" })
        #expect(op1Params.contains { $0.path == "Operators/Op1/EG/Rates/Rate1" })
        #expect(op1Params.contains { $0.path == "Operators/Op1/Frequency/Coarse" })
    }
}
