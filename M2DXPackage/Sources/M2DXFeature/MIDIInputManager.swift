// MIDIInputManager.swift
// External MIDI device input via MIDI2Kit with MIDI 2.0 UMP support

import Foundation
import M2DXCore
import MIDI2Core
import MIDI2Kit
import os

// MARK: - Logging Infrastructure

/// Subsystem for all M2DX os.Logger output (visible in macOS Console.app)
private let logSubsystem = "com.example.M2DX"

/// os.Logger instances for each category
private let midiLogger = Logger(subsystem: logSubsystem, category: "MIDI")
private let peLogger = Logger(subsystem: logSubsystem, category: "PE")
private let ciLogger = Logger(subsystem: logSubsystem, category: "CI")

/// MIDI2Logger that forwards log messages to an @MainActor buffer callback.
/// Used alongside OSLogMIDI2Logger via CompositeMIDI2Logger so that
/// CIManager/PEManager internal logs appear both in Console.app AND
/// in the app's in-memory debug buffer.
final class BufferMIDI2Logger: MIDI2Core.MIDI2Logger, @unchecked Sendable {
    let minimumLevel: MIDI2Core.MIDI2LogLevel = .debug
    private let onLog: @Sendable (String) -> Void

    init(onLog: @escaping @Sendable (String) -> Void) {
        self.onLog = onLog
    }

    func log(
        level: MIDI2Core.MIDI2LogLevel,
        message: @autoclosure () -> String,
        category: String,
        file: String,
        function: String,
        line: Int
    ) {
        guard shouldLog(level) else { return }
        let text = "[\(category)] \(message())"
        onLog(text)
    }
}

// MARK: - MIDI Source Types

/// Represents a MIDI input source for the selection UI
public struct MIDISourceItem: Identifiable, Hashable, Sendable {
    public let id: String       // unique identifier (name-based)
    public let name: String     // display name
    public let isOnline: Bool   // connection status
}

/// MIDI source selection mode
public enum MIDISourceMode: Equatable, Sendable {
    case all                    // receive from all sources (Omni)
    case specific(String)       // receive from a specific source by name
}

// MARK: - MIDI Input Manager

/// Manages external MIDI device connections and routes events to the audio engine
@MainActor
@Observable
public final class MIDIInputManager {

    // MARK: - Properties

    /// MIDI2Kit transport
    private var transport: CoreMIDITransport?

    /// Task for receiving MIDI data
    private var receiveTask: Task<Void, Never>?

    /// MIDI-CI Property Exchange responder
    private var peResponder: PEResponder?

    /// MIDI-CI Manager (Initiator — for discovering remote PE devices)
    private var ciManager: CIManager?

    /// PE Manager (Initiator — for querying remote PE resources)
    private var peManager: PEManager?

    /// CI event monitoring task
    private var ciEventTask: Task<Void, Never>?

    /// Discovered PE-capable devices
    public private(set) var discoveredPEDevices: [DiscoveredDevice] = []

    /// Remote program list from PE GET
    public private(set) var remoteProgramList: [PEProgramDef] = []

    /// PE query in progress
    public private(set) var isPEQueryInProgress: Bool = false

    /// PE status message
    public private(set) var peStatusMessage: String = ""

    /// PE Capability handshake completion tracking
    private var peCapabilityReady: Set<MUID> = []

    /// MUIDs we've accepted as "old cached versions of us" for MUID rewrite
    /// When KORG sends Cap Inquiry to a cached MUID and we manually reply,
    /// subsequent PE messages to that MUID are rewritten for PEResponder.
    private var acceptedOldMUIDs: Set<MUID> = []

    /// Debounce task for PE Notify — cancel previous before scheduling new
    private var pendingNotifyTask: Task<Void, Never>?

    /// PE Sniffer Mode: disable PE Responder and log all CI SysEx in full hex
    /// Used to observe KORG Module ↔ KeyStage communication passively
    public var peSnifferMode: Bool = false

    /// Composite logger injected into CIManager/PEManager (OSLog + Buffer)
    private var compositeLogger: CompositeMIDI2Logger?

    /// Whether MIDI is initialized
    public private(set) var isConnected: Bool = false

    /// Connected device names
    public private(set) var connectedDevices: [String] = []

    /// Available MIDI source devices (for selection UI)
    public private(set) var availableSources: [MIDISourceItem] = []

    /// Selected source mode: .all or .specific(name)
    public var selectedSourceMode: MIDISourceMode = .all

    /// Last error message
    public private(set) var errorMessage: String?

    /// MIDI receive channel (0 = Omni, 1-16 = specific)
    public var receiveChannel: Int = 0

    /// Callback for note on events (note, velocity16)
    public var onNoteOn: (@MainActor (UInt8, UInt16) -> Void)?

    /// Callback for note off events
    public var onNoteOff: (@MainActor (UInt8) -> Void)?

    /// Callback for control change events (cc, value32)
    public var onControlChange: (@MainActor (UInt8, UInt32) -> Void)?

    /// Callback for pitch bend events (value32, center=0x80000000)
    public var onPitchBend: (@MainActor (UInt32) -> Void)?

    /// Callback for program change events (program number 0-127)
    public var onProgramChange: (@MainActor (UInt8) -> Void)?

    // MARK: - Debug Info (visible on UI)

    /// Debug: detected MIDI source names at connect time
    public private(set) var debugSources: [String] = []

    /// Debug: number of connected sources
    public private(set) var debugConnectedCount: Int = 0

    /// Debug: total received message count
    public private(set) var debugReceiveCount: Int = 0

    /// Debug: last received raw bytes (hex)
    public private(set) var debugLastReceived: String = "(none)"

    /// Debug: last parsed event description
    public private(set) var debugLastEvent: String = "(none)"

    /// Debug: recent MIDI message log (append order, display reversed for newest-first)
    public private(set) var debugLog: [String] = []
    private let debugLogMax = 200

    /// Debug log displayed newest-first (computed from append-order storage)
    public var debugLogReversed: [String] { debugLog.reversed() }

    /// PE flow log: dedicated buffer for PE communication only (oldest first, max 2000)
    public private(set) var peFlowLog: [String] = []
    private let peFlowLogMax = 2000

    /// Append a line to the debug log buffer (and route PE/CI to os.Logger)
    private func appendDebugLog(_ line: String) {
        print("[M2DX] \(line)")  // TEMP: devicectl --console 用
        debugLog.append(line)
        if debugLog.count > debugLogMax {
            debugLog.removeFirst()
        }
        // PE/CI lines also go to peFlowLog for full history + os.Logger
        if line.hasPrefix("PE") {
            peFlowLog.append(line)
            if peFlowLog.count > peFlowLogMax { peFlowLog.removeFirst() }
            peLogger.info("\(line, privacy: .public)")
        } else if line.hasPrefix("CI") {
            peFlowLog.append(line)
            if peFlowLog.count > peFlowLogMax { peFlowLog.removeFirst() }
            ciLogger.info("\(line, privacy: .public)")
        } else if line.hasPrefix("SNIFF") {
            peFlowLog.append(line)
            if peFlowLog.count > peFlowLogMax { peFlowLog.removeFirst() }
            peLogger.notice("\(line, privacy: .public)")
        } else {
            midiLogger.debug("\(line, privacy: .public)")
        }
    }

    /// Clear the debug log
    public func clearDebugLog() {
        debugLog.removeAll()
    }

    /// Clear the PE flow log
    public func clearPEFlowLog() {
        peFlowLog.removeAll()
    }

    /// Get PE flow log as a single string for clipboard copy
    public var peFlowLogText: String {
        peFlowLog.joined(separator: "\n")
    }

    /// Debug: CoreMIDI callback count (from transport)
    public var debugTransportCallback: String {
        guard let transport else { return "no transport" }
        return "cb=\(transport.debugCallbackCount) words=\(transport.debugWordCount) last=\(transport.debugLastCallback)\nword=\(transport.debugLastWord)"
    }

    // MARK: - Initialization

    public init() {}

    // MARK: - Start/Stop

    /// Start MIDI input manager
    public func start() {
        // Reset program index for PE ChannelList programTitle
        currentProgramIndex = 0

        do {
            let midi = try CoreMIDITransport(clientName: "M2DX")
            self.transport = midi

            // Build composite logger: OSLog (Console.app) + Buffer (in-app debug log)
            let bufferLogger = BufferMIDI2Logger { [weak self] line in
                Task { @MainActor in
                    self?.appendDebugLog(line)
                }
            }
            let osLogger = OSLogMIDI2Logger(subsystem: logSubsystem, minimumLevel: .debug)
            let logger = CompositeMIDI2Logger(loggers: [osLogger, bufferLogger])
            self.compositeLogger = logger

            // DEBUG: Step-by-step PE/CI isolation to find KeyStage LCD hang cause
            // Step 0: PE completely disabled (MIDI only) — CONFIRMED: no hang
            // Step 1: CIManager only (no Discovery Inquiry, no PEResponder/PEManager)
            // Step 2: CIManager + Discovery Inquiry (no PEResponder/PEManager)
            // Step 3: Full PE/CI (original code)
            let peIsolationStep = 3  // Full PE/CI with Subscribe disabled in ResourceList
            if peIsolationStep == 0 || peSnifferMode {
                appendDebugLog("SNIFF: Sniffer mode ON — PE Responder disabled")
            } else {
                let sharedMUID = MUID(rawValue: 0x5404629)!
                appendDebugLog("PE: sharedMUID=\(sharedMUID)")

                let korgIdentity = DeviceIdentity(
                    manufacturerID: .korg,
                    familyID: 0x0001,
                    modelID: 0x0001,
                    versionID: 0x00010000
                )
                let ci = CIManager(
                    transport: midi,
                    muid: sharedMUID,
                    configuration: CIManagerConfiguration(
                        autoStartDiscovery: false,
                        respondToDiscovery: true,
                        registerFromInquiry: true,
                        categorySupport: peIsolationStep >= 3 ? .propertyExchange : [],  // Step<3: no PE advertised
                        deviceIdentity: korgIdentity
                    ),
                    logger: logger
                )
                self.ciManager = ci
                appendDebugLog("PE: CIManager.muid=\(ci.muid) [step=\(peIsolationStep)]")

                if peIsolationStep >= 2 && peIsolationStep < 25 {
                    // Step 2+: Add PEResponder + PEManager
                    let responder = PEResponder(muid: sharedMUID, transport: midi, logger: logger)
                    self.peResponder = responder
                    Task { [weak self] in
                        await responder.setLogCallback { resource, body, replySize in
                            Task { @MainActor in
                                self?.appendDebugLog("PE-Resp: \(resource) body=\(body.prefix(150)) reply=\(replySize)B")
                            }
                        }
                    }
                    Task { await self.registerPEResources(responder) }

                    let pe = PEManager(transport: midi, sourceMUID: sharedMUID, sendStrategy: .single, logger: logger)
                    self.peManager = pe
                    Task { await pe.resetForExternalDispatch() }
                }

                if peIsolationStep == 25 || peIsolationStep >= 3 {
                    // Step 2.5/3: Send Discovery Inquiry
                    // Minimal delay — must beat KeyStage's own Discovery to be Initiator
                    // When M2DX discovers first, KeyStage properly GETs our resources + subscribes
                    Task {
                        try? await Task.sleep(for: .milliseconds(100))
                        await ci.sendDiscoveryInquiry()
                        await MainActor.run {
                            self.appendDebugLog("PE: Sent Discovery Inquiry [step=\(peIsolationStep)]")
                        }
                    }
                }
            }

            let transportRef = midi
            let mode = selectedSourceMode
            receiveTask = Task { [weak self] in
                // Enumerate available sources
                let detectedSources = await transportRef.sources
                await MainActor.run {
                    self?.debugSources = detectedSources.map { "\($0.name) (\($0.isOnline ? "online" : "offline"))" }
                }

                // Connect based on selected mode
                switch mode {
                case .all:
                    try? await transportRef.connectToAllSources()
                case .specific(let name):
                    let sources = await transportRef.sources
                    if let match = sources.first(where: { $0.name == name }) {
                        try? await transportRef.connect(to: match.sourceID)
                    } else {
                        try? await transportRef.connectToAllSources()
                    }
                }

                let connCount = await transportRef.connectedSourceCount
                await MainActor.run {
                    self?.debugConnectedCount = connCount
                }

                // Log available destinations for debugging
                let allDests = await transportRef.destinations
                await MainActor.run {
                    self?.appendDebugLog("PE-Resp: \(allDests.count) dests (broadcast mode)")
                }

                // Listen for MIDI data
                for await received in transportRef.received {
                    guard let self else { break }
                    let data = received.data
                    let hex = data.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " ")

                    let w1 = received.umpWord1
                    let w2 = received.umpWord2
                    let umpStr = w1 != 0
                        ? String(format: "UMP 0x%08X 0x%08X mt=%d st=%d", w1, w2, (w1 >> 28) & 0xF, (w1 >> 20) & 0xF)
                        : "M1"
                    let logLine = "\(umpStr) [\(hex)]"

                    await MainActor.run {
                        self.debugReceiveCount += 1
                        self.debugLastReceived = "\(data.count)B: \(hex)"
                        // Filter out MIDI real-time messages (F8=clock, FE=active sensing, etc.)
                        let firstByte = data.first ?? 0
                        if firstByte < 0xF8 {
                            self.appendDebugLog(logLine)
                        }
                    }

                    // CI SysEx: F0 7E <deviceID> 0D <sub-ID2> ...
                    if data.count >= 4 && data[0] == 0xF0 && data[1] == 0x7E && data[3] == 0x0D {
                        let subID2 = data.count > 4 ? String(format: "0x%02X", data[4]) : "?"
                        let subID2Val = data.count > 4 ? data[4] : 0

                        if self.peSnifferMode {
                            // ── Sniffer Mode: full hex + decoded sub-ID2 name ──
                            let fullHex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
                            let subName = Self.ciSubID2Name(subID2Val)
                            let headerInfo = Self.parseCIHeader(data)
                            let logMsg = "SNIFF \(subName) \(data.count)B src=\(headerInfo.src) dst=\(headerInfo.dst)"
                            await MainActor.run {
                                self.debugLastEvent = logMsg
                                self.appendDebugLog(logMsg)
                            }
                            // Full hex to os.Logger (visible in Console.app)
                            peLogger.notice("\(logMsg, privacy: .public)")
                            peLogger.debug("SNIFF-HEX: \(fullHex, privacy: .public)")
                            // Try to decode PE header/body for GET/Reply/Notify
                            if subID2Val >= 0x34 && subID2Val <= 0x3F {
                                let decoded = Self.decodePEPayload(data)
                                if !decoded.isEmpty {
                                    await MainActor.run {
                                        self.appendDebugLog("SNIFF-PE: \(decoded)")
                                    }
                                    peLogger.notice("SNIFF-PE: \(decoded, privacy: .public)")
                                }
                            }
                        } else {
                            // ── Normal Mode ──
                            await MainActor.run {
                                self.debugLastEvent = "CI SysEx sub=\(subID2) (\(data.count)B)"
                            }
                            // Log PE-related sub-ID2 values (0x30+=PE messages) with MUID info
                            if subID2Val >= 0x30 && subID2Val <= 0x3F {
                                var extra = ""
                                if let parsed = CIMessageParser.parse(data) {
                                    extra = " src=\(parsed.sourceMUID) dst=\(parsed.destinationMUID)"
                                    // For GET (0x34), extract resource name
                                    if subID2Val == 0x34, let inquiry = CIMessageParser.parseFullPEGetInquiry(data) {
                                        extra += " res=\(inquiry.resource ?? "?")"
                                    }
                                    // For Subscribe (0x38), extract resource name + command
                                    if subID2Val == 0x38, let sub = CIMessageParser.parseFullPESubscribeInquiry(data) {
                                        extra += " res=\(sub.resource ?? "?") cmd=\(sub.command ?? "start")"
                                    }
                                }
                                await MainActor.run {
                                    self.appendDebugLog("PE-RX sub=\(subID2) \(data.count)B\(extra)")
                                }
                            }
                            // Multi-dispatch: PEResponder, CIManager, PEManager
                            if let resp = self.peResponder {
                                // PEResponder handles MUID filtering and 0x39 drop internally
                                await resp.handleMessage(data)
                                // Log what PEResponder processed
                                if subID2Val == 0x34 {
                                    if let inquiry = CIMessageParser.parseFullPEGetInquiry(data) {
                                        await MainActor.run {
                                            self.appendDebugLog("PE-Resp: replied GET \(inquiry.resource ?? "?")")
                                        }
                                    }
                                }
                                if subID2Val == 0x36 {
                                    let bodyStr = Self.decodePEPayload(data)
                                    await MainActor.run {
                                        self.appendDebugLog("PE-Resp: handled SET \(bodyStr)")
                                    }
                                }
                                if subID2Val == 0x38 {
                                    if let sub = CIMessageParser.parseFullPESubscribeInquiry(data) {
                                        await MainActor.run {
                                            self.appendDebugLog("PE-Resp: handled Sub \(sub.resource ?? "?") cmd=\(sub.command ?? "start")")
                                        }
                                    }
                                }
                            }
                            if let ci = self.ciManager {
                                await ci.handleReceivedExternal(received)
                            }
                            if let pe = self.peManager {
                                await pe.handleReceivedExternal(data)
                            }

                            // Handle PE Capability Inquiry (0x30) — track PE-ready sources
                            if subID2Val == 0x30 {
                                if let parsed = CIMessageParser.parse(data) {
                                    await MainActor.run {
                                        self.peCapabilityReady.insert(parsed.sourceMUID)
                                    }
                                }
                            }

                            // Handle Discovery Inquiry (0x70) from KORG —
                            // Re-send our own Discovery Inquiry so KeyStage discovers M2DX as PE Responder.
                            // Also invalidate macOS's built-in MIDI-CI MUID that intercepts PE flow.
                            if subID2Val == 0x70 {
                                if let ci = self.ciManager, let parsed = CIMessageParser.parse(data) {
                                    let korgMUID = parsed.sourceMUID
                                    await MainActor.run {
                                        self.appendDebugLog("PE: Received Discovery from \(korgMUID), re-sending our Discovery")
                                    }
                                    // Brief delay to let KeyStage finish its Discovery broadcast
                                    try? await Task.sleep(for: .milliseconds(200))
                                    await ci.sendDiscoveryInquiry()
                                    await MainActor.run {
                                        self.appendDebugLog("PE: Re-sent Discovery Inquiry (triggered by KORG Discovery)")
                                    }
                                }
                            }

                            // Handle PE Capability Reply (0x31) — marks device as PE-ready
                            if subID2Val == 0x31, let ci = self.ciManager {
                                if let parsed = CIMessageParser.parse(data) {
                                    let ciMUID = ci.muid
                                    if parsed.destinationMUID == ciMUID {
                                        await MainActor.run {
                                            self.peCapabilityReady.insert(parsed.sourceMUID)
                                            self.appendDebugLog("PE: Cap Reply from \(parsed.sourceMUID) — ready")
                                        }
                                    }
                                }
                            }
                        }
                    } else if received.umpWord1 != 0 {
                        // MIDI 2.0 path: decode full-precision values from UMP words
                        await self.handleUMPData(received.umpWord1, word2: received.umpWord2, fallbackData: data)
                    } else {
                        await self.handleReceivedData(data)
                    }
                }
            }

            // Monitor CI events for device discovery (skip in sniffer mode)
            if let ci = self.ciManager {
                let ciEventsStream = ci.events
                ciEventTask = Task { [weak self] in
                    for await event in ciEventsStream {
                        guard let self else { break }
                        await MainActor.run {
                            switch event {
                            case .deviceDiscovered(let device):
                                self.appendDebugLog("CI: Discovered \(device.displayName)")
                                if device.supportsPropertyExchange {
                                    if !self.discoveredPEDevices.contains(where: { $0.muid == device.muid }) {
                                        self.discoveredPEDevices.append(device)
                                    }
                                }
                            case .deviceLost(let muid):
                                self.appendDebugLog("CI: Lost \(muid)")
                                self.discoveredPEDevices.removeAll { $0.muid == muid }
                            case .deviceUpdated(let device):
                                self.appendDebugLog("CI: Updated \(device.displayName)")
                            default:
                                break
                            }
                        }
                    }
                }
            }

            isConnected = true
            errorMessage = nil
            refreshDeviceList()
        } catch {
            errorMessage = "MIDI setup failed: \(error.localizedDescription)"
            isConnected = false
        }
    }

    /// Switch to a different MIDI source (restarts connection)
    public func selectSource(_ mode: MIDISourceMode) {
        selectedSourceMode = mode
        stop()
        start()
    }

    /// Stop MIDI input manager
    public func stop() {
        receiveTask?.cancel()
        receiveTask = nil
        ciEventTask?.cancel()
        ciEventTask = nil

        // Send Invalidate MUID before cleanup so KORG removes cached MUID
        if let ci = ciManager, let transport {
            Task {
                await ci.invalidateMUID()
            }
        }

        peResponder = nil
        ciManager = nil
        peManager = nil
        compositeLogger = nil
        discoveredPEDevices = []
        remoteProgramList = []
        isPEQueryInProgress = false
        peStatusMessage = ""
        peCapabilityReady = []
        acceptedOldMUIDs = []

        if let transport {
            Task {
                await transport.disconnectAllSources()
                await transport.shutdown()
            }
        }
        transport = nil
        isConnected = false
        connectedDevices = []
    }

    // MARK: - Device List

    /// Refresh the list of connected MIDI devices
    public func refreshDeviceList() {
        guard let transport else {
            connectedDevices = []
            availableSources = []
            return
        }

        Task {
            let sources = await transport.sources
            await MainActor.run {
                self.connectedDevices = sources.map { $0.name }
                self.availableSources = sources.map { source in
                    MIDISourceItem(
                        id: source.name,
                        name: source.name,
                        isOnline: source.isOnline
                    )
                }
            }
        }
    }

    // MARK: - Property Exchange

    /// Current program index (for ChannelList programTitle in PE GET)
    private var currentProgramIndex: Int = 0

    /// Register PE resources (standard + KORG custom)
    private func registerPEResources(_ responder: PEResponder) async {
        // ResourceList — 5 resources (X-ProgramEdit restored for LCD program name display)
        // KeyStage LCD uses X-ProgramEdit.name for program name display, not ChannelList.programTitle.
        // Previous hangs with 5 resources were caused by combination of MUID rewrite + fast Notify timing.
        // Now: MUID DROP + 500ms delay should prevent hangs.
        await responder.registerResource("ResourceList", resource: ComputedResource(
            get: { _ in
                Data("""
                [{"resource":"DeviceInfo"},{"resource":"ChannelList","canSubscribe":true},{"resource":"ProgramList","canSubscribe":true},{"resource":"X-ParameterList","canSubscribe":true},{"resource":"X-ProgramEdit","canSubscribe":true}]
                """.utf8)
            },
            responseHeader: { _, _ in
                Data("{\"status\":200,\"totalCount\":5}".utf8)
            }
        ))

        // DeviceInfo
        // KORG KeyStage checks manufacturerName to decide whether to request KORG-specific
        // resources (X-ParameterList). Using "KORG" to enable full PE flow.
        await responder.registerResource("DeviceInfo", resource: StaticResource(json: """
        {"manufacturerName":"KORG","productName":"M2DX DX7 Synthesizer","softwareVersion":"1.0","familyName":"FM Synthesizer","modelName":"DX7 Compatible"}
        """))

        // ChannelList — single channel
        await responder.registerResource("ChannelList", resource: ComputedResource(
            supportsSubscription: true,
            get: { [weak self] _ in
                let name = await MainActor.run { self?.currentProgramName ?? "INIT VOICE" }
                return Data("[{\"channel\":1,\"title\":\"Channel 1\",\"programTitle\":\"\(name)\"}]".utf8)
            },
            responseHeader: { _, _ in
                Data("{\"status\":200,\"totalCount\":1}".utf8)
            }
        ))

        // ProgramList — DX7 factory presets
        let presetCount = DX7FactoryPresets.all.count
        await responder.registerResource("ProgramList", resource: ComputedResource(
            supportsSubscription: true,
            get: { _ in
                let entries = DX7FactoryPresets.all.enumerated().map { index, preset in
                    "{\"title\":\"\(preset.name)\",\"bankPC\":[0,0,\(index)]}"
                }
                return Data("[\(entries.joined(separator: ","))]".utf8)
            },
            responseHeader: { _, _ in
                Data("{\"status\":200,\"totalCount\":\(presetCount)}".utf8)
            }
        ))

        // MARK: KORG Custom Resources

        // X-ProgramEdit — current program state (name + currentValues)
        // KeyStage LCD displays program name from X-ProgramEdit.name field.
        await responder.registerResource("X-ProgramEdit", resource: ComputedResource(
            supportsSubscription: true,
            get: { [weak self] _ in
                let (name, idx) = await MainActor.run {
                    (self?.currentProgramName ?? "INIT VOICE", self?.currentProgramIndex ?? 0)
                }
                let json = "{\"name\":\"\(name)\",\"bankPC\":[0,0,\(idx)],\"currentValues\":[{\"name\":\"Mod Wheel\",\"value\":0,\"displayValue\":\"0\",\"displayUnit\":\"\"},{\"name\":\"Volume\",\"value\":100,\"displayValue\":\"100\",\"displayUnit\":\"\"},{\"name\":\"Expression\",\"value\":127,\"displayValue\":\"127\",\"displayUnit\":\"\"},{\"name\":\"Sustain\",\"value\":0,\"displayValue\":\"0\",\"displayUnit\":\"\"},{\"name\":\"Brightness\",\"value\":64,\"displayValue\":\"64\",\"displayUnit\":\"\"}]}"
                return Data(json.utf8)
            }
        ))

        // X-ParameterList — CC parameter definitions for KeyStage display
        // X-ParameterList — KeyStage expects {"name":"...","controlcc":N,"default":N} format
        // per Keystage_PE_ResourceList v1.0 spec (no min/max fields)
        await responder.registerResource("X-ParameterList", resource: ComputedResource(
            supportsSubscription: true,
            get: { _ in
                let params = [
                    "{\"name\":\"Mod Wheel\",\"controlcc\":1,\"default\":0}",
                    "{\"name\":\"Volume\",\"controlcc\":7,\"default\":100}",
                    "{\"name\":\"Expression\",\"controlcc\":11,\"default\":127}",
                    "{\"name\":\"Sustain\",\"controlcc\":64,\"default\":0}",
                    "{\"name\":\"Brightness\",\"controlcc\":74,\"default\":64}"
                ]
                return Data("[\(params.joined(separator: ","))]".utf8)
            },
            responseHeader: { _, bodyData in
                let count = (try? JSONSerialization.jsonObject(with: bodyData) as? [Any])?.count ?? 0
                return Data("{\"status\":200,\"totalCount\":\(count)}".utf8)
            }
        ))

        // JSONSchema — schema definitions for KORG custom resources
        // KeyStage requests resId:"parameterListSchema" and resId:"programEditSchema"
        await responder.registerResource("JSONSchema", resource: ComputedResource(
            get: { [weak self] header in
                let resId = header.resId ?? ""
                let rawStr = String(data: header.rawData, encoding: .utf8) ?? "(nil)"
                await MainActor.run {
                    self?.appendDebugLog("PE-Schema: resId='\(resId)' raw=\(rawStr)")
                }
                switch resId {
                case "parameterListSchema":
                    // KeyStage expects name/controlcc/default schema per official spec
                    return Data("""
                    {"type":"array","items":{"type":"object","properties":{"name":{"title":"Parameter Name","description":"Parameter Name","type":"string"},"controlcc":{"title":"Control CC","description":"CC number to control this parameter","type":"integer","minimum":0,"maximum":127},"default":{"title":"Default Value","description":"Default value for this parameter","type":"integer","minimum":0,"maximum":127}}}}
                    """.utf8)
                case "programEditSchema":
                    // KeyStage expects currentValues-based schema per official spec
                    return Data("""
                    {"type":"object","properties":{"currentValues":{"type":"array","items":{"type":"object","properties":{"name":{"title":"Parameter Name","description":"Parameter Name","type":"string"},"value":{"title":"Current Value","description":"Current value (Control Change value)","type":"integer","minimum":0,"maximum":127},"displayValue":{"title":"Display Value","description":"Current Value displayed on the UI (actual value)","type":"string"},"displayUnit":{"title":"Display Unit","description":"Unit text for this parameter","type":"string"}}}}}}
                    """.utf8)
                default:
                    return Data("{}".utf8)
                }
            }
        ))
    }

    /// Current program name (derived from currentProgramIndex)
    private var currentProgramName: String {
        let presets = DX7FactoryPresets.all
        if currentProgramIndex < presets.count {
            return presets[currentProgramIndex].name
        }
        return "INIT VOICE"
    }

    // MARK: - PE Notify (subscription updates on Program Change)

    /// Handle program change: update internal state and send PE Notify to subscribers.
    private func notifyProgramChange(programIndex: UInt8) {
        currentProgramIndex = Int(programIndex)
        let name = currentProgramName
        let idx = Int(programIndex)
        appendDebugLog("PC: program=\(idx) name=\(name)")
        peLogger.info("PC: program=\(idx) name=\(name, privacy: .public)")

        guard let responder = peResponder else {
            appendDebugLog("PE-Notify: no responder")
            return
        }
        Task { [weak self] in
            guard let self else { return }
            // Wait 500ms to ensure KeyStage has processed the PC message
            try? await Task.sleep(for: .milliseconds(500))

            // Build exclude set: only send Notify to discovered PE devices (i.e. KORG KeyStage).
            // macOS built-in MIDI-CI entity also subscribes but is not in discoveredPEDevices,
            // so it gets excluded. Sending Notify to macOS entity causes spurious 0x39 replies.
            let knownMUIDs = await MainActor.run {
                Set(self.discoveredPEDevices.map(\.muid))
            }
            let excludeMUIDs = await responder.subscriberMUIDs().subtracting(knownMUIDs)
            if !excludeMUIDs.isEmpty {
                peLogger.info("PE-Notify: excluding \(excludeMUIDs.count) non-KORG MUIDs: \(excludeMUIDs.map { String(describing: $0) }.joined(separator: ","), privacy: .public)")
            }

            // Notify ChannelList (programTitle update)
            let channelListBody = Data("[{\"channel\":1,\"title\":\"Channel 1\",\"programTitle\":\"\(name)\"}]".utf8)
            await MainActor.run {
                self.appendDebugLog("PE-Notify: sending ChannelList programTitle=\(name)")
            }
            peLogger.info("PE-Notify: ChannelList body=\(String(data: channelListBody, encoding: .utf8) ?? "?", privacy: .public)")
            await responder.notify(resource: "ChannelList", data: channelListBody, excludeMUIDs: excludeMUIDs)
            peLogger.info("PE-Notify: ChannelList sent OK")

            // Notify X-ProgramEdit (name + currentValues for LCD update)
            // Uses 0x38 (Subscription) with command:notify header per MIDI-CI PE v1.1.
            let xProgramEditBody = Data("{\"name\":\"\(name)\",\"bankPC\":[0,0,\(idx)],\"currentValues\":[{\"name\":\"Mod Wheel\",\"value\":0,\"displayValue\":\"0\",\"displayUnit\":\"\"},{\"name\":\"Volume\",\"value\":100,\"displayValue\":\"100\",\"displayUnit\":\"\"},{\"name\":\"Expression\",\"value\":127,\"displayValue\":\"127\",\"displayUnit\":\"\"},{\"name\":\"Sustain\",\"value\":0,\"displayValue\":\"0\",\"displayUnit\":\"\"},{\"name\":\"Brightness\",\"value\":64,\"displayValue\":\"64\",\"displayUnit\":\"\"}]}".utf8)
            await MainActor.run {
                self.appendDebugLog("PE-Notify: sending X-ProgramEdit name=\(name)")
            }
            peLogger.info("PE-Notify: X-ProgramEdit body=\(String(data: xProgramEditBody, encoding: .utf8) ?? "?", privacy: .public)")
            await responder.notify(resource: "X-ProgramEdit", data: xProgramEditBody, excludeMUIDs: excludeMUIDs)

            await MainActor.run {
                self.appendDebugLog("PE-Notify: all sent OK")
            }
            peLogger.info("PE-Notify: all sent OK")
        }
    }

    // MARK: - Sniffer Helpers

    /// Human-readable name for CI sub-ID2 values
    private static func ciSubID2Name(_ val: UInt8) -> String {
        switch val {
        case 0x70: return "Discovery"
        case 0x71: return "DiscoveryReply"
        case 0x72: return "InvalidateMUID"
        case 0x73: return "NAK"
        case 0x30: return "PE-CapInquiry"
        case 0x31: return "PE-CapReply"
        case 0x34: return "PE-GET"
        case 0x35: return "PE-GET-Reply"
        case 0x36: return "PE-SET"
        case 0x37: return "PE-SET-Reply"
        case 0x38: return "PE-Subscribe"
        case 0x39: return "PE-SubscribeReply"
        case 0x3F: return "PE-Notify"
        default: return String(format: "CI-0x%02X", val)
        }
    }

    /// Parse CI SysEx header to extract source/destination MUID (28-bit LE)
    private static func parseCIHeader(_ data: [UInt8]) -> (src: String, dst: String) {
        // CI SysEx: F0 7E <devID> 0D <sub> <src4> <dst4> ...
        guard data.count >= 13 else { return ("?", "?") }
        let s0 = UInt32(data[5]), s1 = UInt32(data[6]), s2 = UInt32(data[7]), s3 = UInt32(data[8])
        let src = s0 | (s1 << 7) | (s2 << 14) | (s3 << 21)
        let d0 = UInt32(data[9]), d1 = UInt32(data[10]), d2 = UInt32(data[11]), d3 = UInt32(data[12])
        let dst = d0 | (d1 << 7) | (d2 << 14) | (d3 << 21)
        return (String(format: "MUID(0x%07X)", src), String(format: "MUID(0x%07X)", dst))
    }

    /// Decode PE payload by finding JSON content directly (robust against CI version differences)
    private static func decodePEPayload(_ data: [UInt8]) -> String {
        guard data.count > 15 else { return "" }
        // Find all JSON objects/arrays in the SysEx data (after MUID fields)
        var jsonParts: [String] = []
        var i = 13 // start searching after src+dst MUIDs
        while i < data.count - 1 {
            let b = data[i]
            if b == 0x7B || b == 0x5B { // '{' or '['
                let endByte: UInt8 = b == 0x7B ? 0x7D : 0x5D // '}' or ']'
                var depth = 1
                var j = i + 1
                while j < data.count - 1 && depth > 0 {
                    if data[j] == b { depth += 1 }
                    if data[j] == endByte { depth -= 1 }
                    j += 1
                }
                if depth == 0 {
                    let jsonBytes = Array(data[i..<j])
                    if let str = String(bytes: jsonBytes, encoding: .utf8) {
                        jsonParts.append(str)
                    }
                    i = j
                } else {
                    break
                }
            } else {
                i += 1
            }
        }
        if jsonParts.isEmpty { return "" }
        // First JSON = header, second (if any) = body
        if jsonParts.count == 1 {
            return "hdr=\(jsonParts[0])"
        }
        return "hdr=\(jsonParts[0]) body=\(String(jsonParts[1].prefix(300)))"
    }

    // MARK: - PE Initiator (Remote Device Query)

    /// Send MIDI-CI Discovery Inquiry to find remote devices
    public func startCIDiscovery() async {
        guard let ci = ciManager else { return }
        await ci.sendDiscoveryInquiry()
        appendDebugLog("CI: Discovery sent")
    }

    /// Query ProgramList from a discovered PE device
    /// Tries each destination individually with .single send strategy
    public func queryRemoteProgramList(device: DiscoveredDevice) async {
        guard let ci = ciManager, let pe = peManager, let midi = transport else {
            appendDebugLog("PE: ciManager/peManager/transport nil")
            return
        }

        // Clear log so PE debug info is visible
        clearDebugLog()
        isPEQueryInProgress = true
        peStatusMessage = "Querying \(device.displayName)..."

        // Log available destinations
        let dests = await midi.destinations
        appendDebugLog("PE: \(dests.count) dests available")
        for d in dests {
            appendDebugLog("PE: dest=\(d.destinationID.value) \(d.name)")
        }

        // Check if Cap handshake already done (auto-detected at startup)
        if peCapabilityReady.contains(device.muid) {
            appendDebugLog("PE: Cap already done (startup handshake)")
        } else {
            appendDebugLog("PE: Cap NOT done — sending Cap Inquiry")
            let capInquiry = CIMessageBuilder.peCapabilityInquiry(
                sourceMUID: ci.muid,
                destinationMUID: device.muid,
                numSimultaneousRequests: 4
            )
            let hex = capInquiry.prefix(20).map { String(format: "%02X", $0) }.joined(separator: " ")
            appendDebugLog("PE: Cap Inquiry bytes: \(hex)")
            try? await midi.broadcast(capInquiry)

            let deadline = ContinuousClock.now + .seconds(3)
            while !peCapabilityReady.contains(device.muid) && ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(100))
            }
            if peCapabilityReady.contains(device.muid) {
                appendDebugLog("PE: Cap handshake complete")
            } else {
                appendDebugLog("PE: Cap timeout — KORG may be Initiator-only")
            }
        }

        // Resolve CIManager destination (from Discovery)
        let ciDest = await ci.destination(for: device.muid)
        appendDebugLog("PE: CI resolved dest=\(ciDest?.value.description ?? "nil")")

        // Build ordered list of destinations to try:
        // 1. CI-resolved destination first
        // 2. Then all other destinations
        var destsToTry: [MIDIDestinationID] = []
        if let d = ciDest {
            destsToTry.append(d)
        }
        for d in dests where !destsToTry.contains(d.destinationID) {
            destsToTry.append(d.destinationID)
        }

        // Try PE GET ResourceList on each destination
        var gotResponse = false
        for destID in destsToTry {
            let destName = dests.first(where: { $0.destinationID == destID })?.name ?? "?"
            appendDebugLog("PE: Trying GET ResourceList → \(destName) (\(destID.value))")

            let handle = PEDeviceHandle(muid: device.muid, destination: destID, name: device.displayName)

            do {
                let rlResponse = try await pe.get("ResourceList", from: handle, timeout: .seconds(5))
                appendDebugLog("PE: RL status=\(rlResponse.status) \(rlResponse.decodedBody.count)B")
                if rlResponse.isSuccess {
                    let bodyStr = String(data: rlResponse.decodedBody, encoding: .utf8) ?? "(decode fail)"
                    appendDebugLog("PE: RL body=\(bodyStr.prefix(200))")

                    // This destination works! Now get ProgramList
                    appendDebugLog("PE: GET ProgramList → \(destName)")
                    let plResponse = try await pe.get("ProgramList", from: handle, timeout: .seconds(10))
                    if plResponse.isSuccess {
                        let programs = try JSONDecoder().decode([PEProgramDef].self, from: plResponse.decodedBody)
                        remoteProgramList = programs
                        peStatusMessage = "\(programs.count) programs from \(device.displayName)"
                        appendDebugLog("PE: Got \(programs.count) programs")
                    } else {
                        peStatusMessage = "ProgramList failed (status \(plResponse.status))"
                        appendDebugLog("PE: PL status=\(plResponse.status)")
                    }
                    gotResponse = true
                    break
                }
            } catch {
                appendDebugLog("PE: \(destName) error: \(error)")
            }
        }

        if !gotResponse {
            peStatusMessage = "No PE response from \(device.displayName) — device may be PE Initiator only"
            appendDebugLog("PE: All dests tried, no response. KORG likely PE Initiator-only.")
            appendDebugLog("PE: (KORG queries US, but doesn't respond to PE GET)")
        }

        isPEQueryInProgress = false
    }

    // MARK: - Event Handling

    /// Handle MIDI 2.0 UMP words with full precision
    /// Already on MainActor (class is @MainActor)
    private func handleUMPData(_ word1: UInt32, word2: UInt32, fallbackData: [UInt8]) {
        let status = UInt8((word1 >> 20) & 0x0F)
        let channel = UInt8((word1 >> 16) & 0x0F)
        let byte3 = UInt8((word1 >> 8) & 0xFF)   // note or controller

        // Channel filter: 0 = Omni (accept all), 1-16 = specific
        let passesFilter = receiveChannel == 0 || Int(channel) + 1 == receiveChannel

        switch status {
        case 0x9: // Note On (16-bit velocity in upper 16 of word2)
            let vel16 = UInt16((word2 >> 16) & 0xFFFF)
            debugLastEvent = "NoteOn(UMP) ch=\(channel) n=\(byte3) v16=\(vel16)"
            if passesFilter {
                if vel16 == 0 {
                    onNoteOff?(byte3)
                } else {
                    onNoteOn?(byte3, vel16)
                }
            }

        case 0x8: // Note Off
            debugLastEvent = "NoteOff(UMP) ch=\(channel) n=\(byte3)"
            if passesFilter {
                onNoteOff?(byte3)
            }

        case 0xB: // Control Change (32-bit value)
            let val32 = word2
            debugLastEvent = "CC(UMP) ch=\(channel) cc=\(byte3) v32=\(val32)"
            if passesFilter {
                onControlChange?(byte3, val32)
                if byte3 == 123 {
                    for n: UInt8 in 0...127 {
                        onNoteOff?(n)
                    }
                }
            }

        case 0xE: // Pitch Bend (32-bit unsigned, center=0x80000000)
            let val32 = word2
            debugLastEvent = "PB(UMP) ch=\(channel) v32=\(val32)"
            if passesFilter {
                onPitchBend?(val32)
            }

        case 0xC: // Program Change (program at bits 31-24 of word2)
            let program = UInt8((word2 >> 24) & 0x7F)
            debugLastEvent = "PC(UMP) ch=\(channel) p=\(program)"
            if passesFilter {
                onProgramChange?(program)
                notifyProgramChange(programIndex: program)
            }

        default:
            // For unhandled UMP types, fall back to MIDI 1.0 byte parsing
            handleReceivedData(fallbackData)
        }
    }

    /// Handle raw MIDI bytes received from CoreMIDITransport (MIDI 1.0 fallback)
    /// Already on MainActor (class is @MainActor, called via await self.handleReceivedData)
    private func handleReceivedData(_ data: [UInt8]) {
        // Process MIDI 1.0 byte stream (most common from CoreMIDI PacketList)
        var offset = 0
        while offset < data.count {
            let statusByte = data[offset]

            // Skip non-status bytes (running status not handled for simplicity)
            guard statusByte & 0x80 != 0 else {
                offset += 1
                continue
            }

            let statusNibble = statusByte >> 4
            let channel = statusByte & 0x0F

            // Channel filter: 0 = Omni (accept all), 1-16 = specific
            let passesFilter = receiveChannel == 0 || Int(channel) + 1 == receiveChannel

            switch statusNibble {
            case 0x9: // Note On
                guard offset + 2 < data.count else { break }
                let note = data[offset + 1]
                let velocity = data[offset + 2]
                debugLastEvent = "NoteOn ch=\(channel) n=\(note) v=\(velocity)"
                if passesFilter {
                    if velocity == 0 {
                        onNoteOff?(note)
                    } else {
                        // Upscale 7-bit → 16-bit velocity
                        let vel16 = UInt16(velocity) << 9
                        onNoteOn?(note, vel16)
                    }
                }
                offset += 3

            case 0x8: // Note Off
                guard offset + 2 < data.count else { break }
                let note = data[offset + 1]
                if passesFilter {
                    onNoteOff?(note)
                }
                offset += 3

            case 0xB: // Control Change
                guard offset + 2 < data.count else { break }
                let controller = data[offset + 1]
                let value = data[offset + 2]
                if passesFilter {
                    // Upscale 7-bit → 32-bit CC value
                    let val32 = UInt32(value) << 25
                    onControlChange?(controller, val32)

                    // CC 123 = All Notes Off
                    if controller == 123 {
                        for n: UInt8 in 0...127 {
                            onNoteOff?(n)
                        }
                    }
                }
                offset += 3

            case 0xE: // Pitch Bend
                guard offset + 2 < data.count else { break }
                let lsb = data[offset + 1]
                let msb = data[offset + 2]
                debugLastEvent = "PitchBend ch=\(channel) lsb=\(lsb) msb=\(msb)"
                if passesFilter {
                    // Upscale 14-bit → 32-bit pitch bend
                    let raw14 = (UInt32(msb) << 7) | UInt32(lsb)
                    let val32 = raw14 << 18
                    onPitchBend?(val32)
                }
                offset += 3

            case 0xC: // Program Change
                guard offset + 1 < data.count else { break }
                let program = data[offset + 1]
                debugLastEvent = "PC ch=\(channel) p=\(program)"
                if passesFilter {
                    onProgramChange?(program)
                    notifyProgramChange(programIndex: program)
                }
                offset += 2

            case 0xD: // Channel Pressure
                offset += 2

            case 0xF: // System messages
                switch statusByte {
                case 0xF0: // SysEx start - skip until F7
                    while offset < data.count && data[offset] != 0xF7 {
                        offset += 1
                    }
                    offset += 1
                case 0xF1, 0xF3: offset += 2  // MTC, Song Select
                case 0xF2: offset += 3          // Song Position
                default: offset += 1            // Real-time, etc.
                }

            default:
                offset += 1
            }
        }
    }
}
