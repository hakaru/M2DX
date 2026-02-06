import Foundation
import AudioToolbox

// MARK: - PE Bridge

/// Bridges AUParameterTree and M2DXPEResource for bidirectional synchronization
/// Handles value type conversion between AU (Float) and PE (Int/Float/String/Bool)
/// Thread-safe implementation for AUv3 compatibility
public final class M2DXPEBridge: @unchecked Sendable {

    // MARK: - Properties

    /// PE Resource for property exchange
    public let peResource: M2DXPEResource

    /// Weak reference to parameter tree (owned by AudioUnit)
    private weak var parameterTree: AUParameterTree?

    /// Active subscriptions for PE -> AU sync
    private var peSubscriptions: [String: UUID] = [:]

    /// Flag to prevent feedback loops during sync
    private var isSyncing: Bool = false

    /// Lock for thread-safe access
    private let lock = NSLock()

    // MARK: - Initialization

    /// Initialize with PE resource
    public init(peResource: M2DXPEResource = M2DXPEResource()) {
        self.peResource = peResource
    }

    // MARK: - Parameter Tree Connection

    /// Connect to AUParameterTree for bidirectional sync
    /// - Parameter tree: The AUParameterTree to synchronize with
    public func connect(to tree: AUParameterTree) {
        lock.lock()
        defer { lock.unlock() }

        self.parameterTree = tree

        // Set up AU -> PE observation
        setupAUObservation(tree)

        // Set up PE -> AU subscriptions
        setupPESubscriptions()
    }

    /// Disconnect from parameter tree
    public func disconnect() {
        lock.lock()
        defer { lock.unlock() }

        // Remove PE subscriptions
        for (path, subscriptionId) in peSubscriptions {
            peResource.unsubscribe(path, subscriptionId: subscriptionId)
        }
        peSubscriptions.removeAll()

        parameterTree = nil
    }

    // MARK: - AU -> PE Synchronization

    /// Set up observation of AU parameter changes
    private func setupAUObservation(_ tree: AUParameterTree) {
        // Set new observer that syncs to PE
        // Note: We don't chain to original observer as the AU handles its own observation
        tree.implementorValueObserver = { [weak self] param, value in
            guard let self else { return }

            // Sync to PE if not already syncing
            self.lock.lock()
            let shouldSync = !self.isSyncing
            self.lock.unlock()

            if shouldSync {
                self.syncAUToPE(address: param.address, value: value)
            }
        }
    }

    /// Sync AU parameter change to PE resource
    private func syncAUToPE(address: AUParameterAddress, value: AUValue) {
        guard let path = M2DXParameterAddressMap.pathForAddress(address) else { return }

        lock.lock()
        isSyncing = true
        lock.unlock()

        defer {
            lock.lock()
            isSyncing = false
            lock.unlock()
        }

        do {
            try peResource.setPropertyFromFloat(path, floatValue: value)
        } catch {
            // Log error but don't throw - AU changes should not fail
            print("M2DXPEBridge: Failed to sync AU->PE for \(path): \(error)")
        }
    }

    // MARK: - PE -> AU Synchronization

    /// Set up PE subscriptions for PE -> AU sync
    private func setupPESubscriptions() {
        let resources = peResource.getResourceList()

        for resource in resources {
            guard let address = M2DXParameterAddressMap.addressForPath(resource.path) else {
                continue
            }

            let subscriptionId = peResource.subscribe(resource.path) { [weak self] value in
                guard let self else { return }

                // Sync to AU if not already syncing
                self.lock.lock()
                let shouldSync = !self.isSyncing
                self.lock.unlock()

                if shouldSync {
                    self.syncPEToAU(path: resource.path, address: address, value: value)
                }
            }

            if let id = subscriptionId {
                peSubscriptions[resource.path] = id
            }
        }
    }

    /// Sync PE value change to AU parameter
    private func syncPEToAU(path: String, address: UInt64, value: PEValue) {
        lock.lock()
        guard let tree = parameterTree else {
            lock.unlock()
            return
        }
        isSyncing = true
        lock.unlock()

        defer {
            lock.lock()
            isSyncing = false
            lock.unlock()
        }

        let floatValue = convertPEToAU(value)
        tree.parameter(withAddress: address)?.value = floatValue
    }

    // MARK: - Value Conversion

    /// Convert PE value to AU value (Float)
    private func convertPEToAU(_ value: PEValue) -> AUValue {
        switch value {
        case .integer(let v):
            return AUValue(v)
        case .float(let v):
            return v
        case .boolean(let v):
            return v ? 1.0 : 0.0
        case .string(let v):
            // For enums, try to find index
            // This is a simplified conversion - in production,
            // you'd need the parameter definition to map properly
            return AUValue(v.hashValue % 100)  // Fallback
        }
    }

    /// Convert AU value to PE value with type hint
    private func convertAUToPE(_ value: AUValue, type: PEValueType) -> PEValue {
        switch type {
        case .integer:
            return .integer(Int(value))
        case .float:
            return .float(value)
        case .boolean:
            return .boolean(value >= 0.5)
        case .string, .enumeration:
            return .string(String(Int(value)))  // Index as string
        }
    }

    // MARK: - Bulk Sync

    /// Sync all AU parameters to PE resource
    public func syncAllAUToPE() {
        lock.lock()
        guard let tree = parameterTree else {
            lock.unlock()
            return
        }
        isSyncing = true
        lock.unlock()

        defer {
            lock.lock()
            isSyncing = false
            lock.unlock()
        }

        for mapping in M2DXParameterAddressMap.allMappings {
            if let param = tree.parameter(withAddress: mapping.address) {
                do {
                    try peResource.setPropertyFromFloat(mapping.path, floatValue: param.value)
                } catch {
                    print("M2DXPEBridge: Failed to sync \(mapping.path): \(error)")
                }
            }
        }
    }

    /// Sync all PE values to AU parameters
    public func syncAllPEToAU() {
        lock.lock()
        guard let tree = parameterTree else {
            lock.unlock()
            return
        }
        isSyncing = true
        lock.unlock()

        defer {
            lock.lock()
            isSyncing = false
            lock.unlock()
        }

        for mapping in M2DXParameterAddressMap.allMappings {
            do {
                let value = try peResource.getProperty(mapping.path)
                let floatValue = convertPEToAU(value)
                tree.parameter(withAddress: mapping.address)?.value = floatValue
            } catch {
                // Parameter might not exist in tree, that's OK
            }
        }
    }

    // MARK: - Direct Access

    /// Get PE value directly (bypassing AU)
    public func getValue(at path: String) throws -> PEValue {
        return try peResource.getProperty(path)
    }

    /// Set PE value directly (will sync to AU)
    public func setValue(_ value: PEValue, at path: String) throws {
        try peResource.setProperty(path, value: value)
    }

    /// Get all PE resources
    public func getResources() -> [PEResourceDescriptor] {
        return peResource.getResourceList()
    }

    /// Reset all to defaults (syncs to AU)
    public func resetToDefaults() {
        peResource.resetToDefaults()
        syncAllPEToAU()
    }
}

// MARK: - Convenience Extensions

extension M2DXPEBridge {

    /// Get algorithm value
    public func getAlgorithm() throws -> Int {
        let value = try peResource.getProperty("Global/Algorithm")
        return value.intValue ?? 1
    }

    /// Set algorithm value
    public func setAlgorithm(_ algorithm: Int) throws {
        try peResource.setProperty("Global/Algorithm", value: .integer(algorithm))
    }

    /// Get operator level
    public func getOperatorLevel(_ opIndex: Int) throws -> Float {
        let path = "Operators/Op\(opIndex)/Level"
        return try peResource.getPropertyAsFloat(path)
    }

    /// Set operator level
    public func setOperatorLevel(_ opIndex: Int, level: Float) throws {
        let path = "Operators/Op\(opIndex)/Level"
        try peResource.setProperty(path, value: .float(level))
    }

    /// Get EG rate for operator
    public func getEGRate(_ opIndex: Int, rateIndex: Int) throws -> Int {
        let path = "Operators/Op\(opIndex)/EG/Rates/Rate\(rateIndex)"
        let value = try peResource.getProperty(path)
        return value.intValue ?? 50
    }

    /// Set EG rate for operator
    public func setEGRate(_ opIndex: Int, rateIndex: Int, rate: Int) throws {
        let path = "Operators/Op\(opIndex)/EG/Rates/Rate\(rateIndex)"
        try peResource.setProperty(path, value: .integer(rate))
    }

    /// Get LFO speed
    public func getLFOSpeed() throws -> Int {
        let value = try peResource.getProperty("LFO/Speed")
        return value.intValue ?? 35
    }

    /// Set LFO speed
    public func setLFOSpeed(_ speed: Int) throws {
        try peResource.setProperty("LFO/Speed", value: .integer(speed))
    }
}
