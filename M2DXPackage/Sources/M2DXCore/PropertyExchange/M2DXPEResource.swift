import Foundation

// MARK: - PE Resource Descriptor

/// Describes a Property Exchange resource for MIDI 2.0 PE
public struct PEResourceDescriptor: Sendable, Equatable {
    public let path: String
    public let title: String
    public let description: String
    public let type: PEValueType
    public let canRead: Bool
    public let canWrite: Bool
    public let canSubscribe: Bool

    public init(
        path: String,
        title: String,
        description: String = "",
        type: PEValueType,
        canRead: Bool = true,
        canWrite: Bool = true,
        canSubscribe: Bool = true
    ) {
        self.path = path
        self.title = title
        self.description = description
        self.type = type
        self.canRead = canRead
        self.canWrite = canWrite
        self.canSubscribe = canSubscribe
    }
}

// MARK: - PE Value

/// Type-safe PE value wrapper
public enum PEValue: Sendable, Equatable {
    case integer(Int)
    case float(Float)
    case string(String)
    case boolean(Bool)

    public var intValue: Int? {
        if case .integer(let v) = self { return v }
        if case .float(let v) = self { return Int(v) }
        return nil
    }

    public var floatValue: Float? {
        if case .float(let v) = self { return v }
        if case .integer(let v) = self { return Float(v) }
        return nil
    }

    public var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    public var boolValue: Bool? {
        if case .boolean(let v) = self { return v }
        return nil
    }
}

// MARK: - PE Resource Errors

/// Errors that can occur during PE operations
public enum PEResourceError: Error, Sendable {
    case invalidPath(String)
    case typeMismatch(expected: PEValueType, got: String)
    case valueOutOfRange(path: String, value: Double, min: Double, max: Double)
    case readOnly(path: String)
    case notSubscribable(path: String)
    case internalError(String)
}

// MARK: - Subscription Handler

/// Handler for PE value change notifications
public typealias PESubscriptionHandler = @Sendable (PEValue) -> Void

// MARK: - PE Resource

/// MIDI 2.0 Property Exchange Resource implementation for M2DX
/// Provides get/set/subscribe operations for FM synth parameters
/// Thread-safe implementation using locks for AUv3 compatibility
public final class M2DXPEResource: @unchecked Sendable {

    /// Lock for thread-safe access
    private let lock = NSLock()

    // MARK: - Properties

    /// Current parameter values (path -> value)
    private var values: [String: PEValue] = [:]

    /// Subscription handlers (path -> handlers)
    private var subscriptions: [String: [UUID: PESubscriptionHandler]] = [:]

    /// Parameter definitions cache
    private var parameterCache: [String: PEParameter]?

    // MARK: - Initialization

    public init() {
        initializeDefaults()
    }

    /// Initialize all parameters with default values
    private func initializeDefaults() {
        for param in M2DXParameterTree.allParameters {
            let value = convertDefaultValue(param.defaultValue, type: param.type)
            values[param.path] = value
        }
    }

    /// Convert PEDefaultValue to PEValue
    private func convertDefaultValue(_ defaultValue: PEDefaultValue, type: PEValueType) -> PEValue {
        switch defaultValue {
        case .integer(let v):
            return .integer(v)
        case .float(let v):
            return .float(Float(v))
        case .string(let v):
            return type == .boolean ? .boolean(v.lowercased() == "true") : .string(v)
        case .boolean(let v):
            return .boolean(v)
        }
    }

    // MARK: - Parameter Cache

    /// Get parameter definition for path
    private func parameter(at path: String) -> PEParameter? {
        if parameterCache == nil {
            var cache: [String: PEParameter] = [:]
            for param in M2DXParameterTree.allParameters {
                cache[param.path] = param
            }
            parameterCache = cache
        }
        return parameterCache?[path]
    }

    // MARK: - Get Property

    /// Get property value at path
    /// - Parameter path: PE path (e.g., "Global/Algorithm")
    /// - Returns: Current value
    /// - Throws: PEResourceError if path is invalid
    public func getProperty(_ path: String) throws -> PEValue {
        lock.lock()
        defer { lock.unlock() }

        guard parameter(at: path) != nil else {
            throw PEResourceError.invalidPath(path)
        }

        if let value = values[path] {
            return value
        }

        throw PEResourceError.internalError("Value not found for path: \(path)")
    }

    /// Get property value as Float (for AU integration)
    public func getPropertyAsFloat(_ path: String) throws -> Float {
        let value = try getProperty(path)
        switch value {
        case .integer(let v):
            return Float(v)
        case .float(let v):
            return v
        case .boolean(let v):
            return v ? 1.0 : 0.0
        case .string:
            throw PEResourceError.typeMismatch(expected: .float, got: "string")
        }
    }

    // MARK: - Set Property

    /// Set property value at path
    /// - Parameters:
    ///   - path: PE path
    ///   - value: New value
    /// - Throws: PEResourceError if path invalid, type mismatch, or out of range
    public func setProperty(_ path: String, value: PEValue) throws {
        var handlersToNotify: [UUID: PESubscriptionHandler]?

        lock.lock()
        do {
            guard let param = parameter(at: path) else {
                lock.unlock()
                throw PEResourceError.invalidPath(path)
            }

            // Validate type
            try validateType(value: value, expectedType: param.type, path: path)

            // Validate range
            try validateRange(value: value, param: param)

            // Store value
            values[path] = value

            // Capture handlers for notification outside lock
            handlersToNotify = subscriptions[path]
        } catch {
            lock.unlock()
            throw error
        }
        lock.unlock()

        // Notify subscribers outside lock to prevent deadlock
        if let handlers = handlersToNotify {
            for (_, handler) in handlers {
                handler(value)
            }
        }
    }

    /// Set property from Float value (for AU integration)
    public func setPropertyFromFloat(_ path: String, floatValue: Float) throws {
        guard let param = parameter(at: path) else {
            throw PEResourceError.invalidPath(path)
        }

        let value: PEValue
        switch param.type {
        case .integer:
            value = .integer(Int(floatValue))
        case .float:
            value = .float(floatValue)
        case .boolean:
            value = .boolean(floatValue >= 0.5)
        case .string, .enumeration:
            // For enum, try to map float index to enum value
            if let enumValues = param.enumValues {
                let index = Int(floatValue)
                if index >= 0 && index < enumValues.count {
                    value = .string(enumValues[index])
                } else {
                    throw PEResourceError.valueOutOfRange(path: path, value: Double(floatValue), min: 0, max: Double(enumValues.count - 1))
                }
            } else {
                throw PEResourceError.typeMismatch(expected: param.type, got: "float")
            }
        }

        try setProperty(path, value: value)
    }

    // MARK: - Validation

    /// Validate value type matches expected type
    private func validateType(value: PEValue, expectedType: PEValueType, path: String) throws {
        let valid: Bool
        switch (value, expectedType) {
        case (.integer, .integer), (.integer, .float):
            valid = true
        case (.float, .float), (.float, .integer):
            valid = true
        case (.string, .string), (.string, .enumeration):
            valid = true
        case (.boolean, .boolean):
            valid = true
        default:
            valid = false
        }

        if !valid {
            let gotType: String
            switch value {
            case .integer: gotType = "integer"
            case .float: gotType = "float"
            case .string: gotType = "string"
            case .boolean: gotType = "boolean"
            }
            throw PEResourceError.typeMismatch(expected: expectedType, got: gotType)
        }
    }

    /// Validate value is within range
    private func validateRange(value: PEValue, param: PEParameter) throws {
        guard let min = param.min, let max = param.max else { return }

        let numericValue: Double
        switch value {
        case .integer(let v):
            numericValue = Double(v)
        case .float(let v):
            numericValue = Double(v)
        case .boolean, .string:
            return  // No range check for boolean/string
        }

        if numericValue < min || numericValue > max {
            throw PEResourceError.valueOutOfRange(
                path: param.path,
                value: numericValue,
                min: min,
                max: max
            )
        }
    }

    // MARK: - Resource List

    /// Get list of all available resources
    public func getResourceList() -> [PEResourceDescriptor] {
        return M2DXParameterTree.allParameters.map { param in
            PEResourceDescriptor(
                path: param.path,
                title: param.title,
                description: param.description,
                type: param.type,
                canRead: true,
                canWrite: true,
                canSubscribe: true
            )
        }
    }

    /// Get resources under a prefix
    public func getResources(under prefix: String) -> [PEResourceDescriptor] {
        return M2DXParameterTree.parameters(under: prefix).map { param in
            PEResourceDescriptor(
                path: param.path,
                title: param.title,
                description: param.description,
                type: param.type,
                canRead: true,
                canWrite: true,
                canSubscribe: true
            )
        }
    }

    // MARK: - Subscriptions

    /// Subscribe to value changes at path
    /// - Parameters:
    ///   - path: PE path to subscribe to
    ///   - handler: Handler called when value changes
    /// - Returns: Subscription ID for unsubscribing
    @discardableResult
    public func subscribe(_ path: String, handler: @escaping PESubscriptionHandler) -> UUID? {
        guard parameter(at: path) != nil else {
            return nil
        }

        let subscriptionId = UUID()
        if subscriptions[path] == nil {
            subscriptions[path] = [:]
        }
        subscriptions[path]?[subscriptionId] = handler

        return subscriptionId
    }

    /// Unsubscribe from value changes
    /// - Parameters:
    ///   - path: PE path
    ///   - subscriptionId: ID returned from subscribe
    public func unsubscribe(_ path: String, subscriptionId: UUID) {
        subscriptions[path]?.removeValue(forKey: subscriptionId)
    }

    /// Notify all subscribers of a value change
    private func notifySubscribers(path: String, value: PEValue) {
        guard let handlers = subscriptions[path] else { return }
        for (_, handler) in handlers {
            handler(value)
        }
    }

    // MARK: - Bulk Operations

    /// Get all current values
    public func getAllValues() -> [String: PEValue] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }

    /// Set multiple values at once
    public func setMultipleProperties(_ updates: [String: PEValue]) throws {
        for (path, value) in updates {
            try setProperty(path, value: value)
        }
    }

    /// Reset all values to defaults
    public func resetToDefaults() {
        lock.lock()
        initializeDefaults()
        let currentValues = values
        lock.unlock()

        // Notify all subscribers
        for (path, value) in currentValues {
            notifySubscribers(path: path, value: value)
        }
    }

    // MARK: - AU Address Integration

    /// Get value by AU parameter address
    public func getValueByAddress(_ address: UInt64) throws -> PEValue {
        guard let path = M2DXParameterAddressMap.pathForAddress(address) else {
            throw PEResourceError.invalidPath("Address \(address) not mapped")
        }
        return try getProperty(path)
    }

    /// Set value by AU parameter address
    public func setValueByAddress(_ address: UInt64, value: PEValue) throws {
        guard let path = M2DXParameterAddressMap.pathForAddress(address) else {
            throw PEResourceError.invalidPath("Address \(address) not mapped")
        }
        try setProperty(path, value: value)
    }

    /// Set value by AU parameter address from Float
    public func setValueByAddressFromFloat(_ address: UInt64, floatValue: Float) throws {
        guard let path = M2DXParameterAddressMap.pathForAddress(address) else {
            throw PEResourceError.invalidPath("Address \(address) not mapped")
        }
        try setPropertyFromFloat(path, floatValue: floatValue)
    }
}

// MARK: - JSON Export

extension M2DXPEResource {

    /// Export current state as JSON for MIDI 2.0 PE
    public func exportAsJSON() throws -> String {
        lock.lock()
        let currentValues = values
        lock.unlock()

        var json: [[String: Any]] = []

        for (path, value) in currentValues {
            guard let param = parameter(at: path) else { continue }

            var entry: [String: Any] = [
                "path": path,
                "type": param.type.rawValue
            ]

            switch value {
            case .integer(let v):
                entry["value"] = v
            case .float(let v):
                entry["value"] = v
            case .string(let v):
                entry["value"] = v
            case .boolean(let v):
                entry["value"] = v
            }

            json.append(entry)
        }

        guard let data = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
              let jsonString = String(data: data, encoding: .utf8) else {
            throw PEResourceError.internalError("Failed to serialize JSON")
        }

        return jsonString
    }
}
