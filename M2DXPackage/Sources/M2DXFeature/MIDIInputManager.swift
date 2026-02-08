// MIDIInputManager.swift
// External MIDI device input via MIDI2Kit with MIDI 2.0 UMP support

import CoreMIDI
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
///
/// Safety: @unchecked Sendable is safe because `onLog` is a `@Sendable` closure
/// set once at init and never mutated. `minimumLevel` is a `let` constant.
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

    /// CC value state for PE X-ProgramEdit currentValues (7-bit, 0-127)
    private var ccValues: [UInt8: Int] = [7: 100, 11: 127, 74: 64]

    /// Resolved PE reply destinations (CTRL port only) — used for ALL CI/PE sends
    private var peReplyDestinations: [MIDIDestinationID] = []

    #if os(macOS)
    /// Foreign MIDI-CI MUIDs detected from messages not addressed to us.
    /// On macOS, CoreMIDI creates a built-in MIDI-CI entity that competes
    /// with M2DX for KeyStage's PE session, causing hangs.
    /// We detect its MUID from incoming CI messages and send Invalidate MUID
    /// to make KeyStage forget it.
    private var detectedForeignCIMUIDs: Set<MUID> = []
    #endif

    /// Debounce task for PE Notify — cancel previous before scheduling new
    private var pendingNotifyTask: Task<Void, Never>?

    #if DEBUG
    /// PE Sniffer Mode: disable PE Responder and log all CI SysEx in full hex
    /// Used to observe KORG Module ↔ KeyStage communication passively
    public var peSnifferMode: Bool = false
    #endif

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
        debugLog.append(line)
        if debugLog.count > debugLogMax {
            debugLog.removeFirst()
        }
        // PE/CI/SNIFF lines also go to peFlowLog — cheap first-char check
        let first = line.first
        if first == "P" || first == "C" || first == "S" {
            peFlowLog.append(line)
            if peFlowLog.count > peFlowLogMax { peFlowLog.removeFirst() }
            if first == "P" { peLogger.info("\(line, privacy: .public)") }
            else if first == "C" { ciLogger.info("\(line, privacy: .public)") }
            else { peLogger.notice("\(line, privacy: .public)") }
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

            #if DEBUG
            let snifferActive = peSnifferMode
            #else
            let snifferActive = false
            #endif
            if snifferActive {
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
                // Pre-resolve PE reply destination BEFORE Discovery to avoid broadcasting
                // to all USB ports which causes KeyStage LCD hang.
                // KORG USB: "CTRL" port only. Bluetooth: "Module" port.
                let (peReplyDests, destNames) = Self.resolvePEDestinations()
                self.peReplyDestinations = peReplyDests
                appendDebugLog("PE: MIDI dests=[\(destNames.joined(separator: ", "))]")

                let ci = CIManager(
                    transport: midi,
                    muid: sharedMUID,
                    configuration: CIManagerConfiguration(
                        autoStartDiscovery: false,
                        respondToDiscovery: true,
                        registerFromInquiry: true,
                        categorySupport: .propertyExchange,
                        deviceIdentity: korgIdentity
                    ),
                    logger: logger
                )
                // Set targeted destinations for CI Discovery Reply
                Task {
                    if !peReplyDests.isEmpty {
                        await ci.setReplyDestinations(peReplyDests)
                    }
                }
                self.ciManager = ci
                appendDebugLog("PE: CIManager.muid=\(ci.muid)")

                // PEResponder + PEManager
                let responder = PEResponder(
                    muid: sharedMUID,
                    transport: midi,
                    logger: logger,
                    replyDestinations: peReplyDests.isEmpty ? nil : peReplyDests
                )
                self.peResponder = responder
                if peReplyDests.isEmpty {
                    appendDebugLog("PE-Resp: broadcast mode (no PE dest found)")
                } else {
                    appendDebugLog("PE-Resp: targeted \(peReplyDests.count) dest(s) id=\(peReplyDests.map { String($0.value) }.joined(separator: ","))")
                }

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

                // Send Discovery Inquiry
                // Minimal delay — must beat KeyStage's own Discovery to be Initiator
                // When M2DX discovers first, KeyStage properly GETs our resources + subscribes
                Task {
                    try? await Task.sleep(for: .milliseconds(100))
                    await ci.sendDiscoveryInquiry()
                    await MainActor.run {
                        self.appendDebugLog("PE: Sent Discovery Inquiry")
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
                    self?.appendDebugLog("MIDI: \(allDests.count) destinations available")
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

                        #if DEBUG
                        let snifferActive = self.peSnifferMode
                        #else
                        let snifferActive = false
                        #endif

                        if snifferActive {
                            #if DEBUG
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
                            #endif
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
                            #if os(macOS)
                            // Detect foreign MIDI-CI MUIDs (e.g. macOS built-in entity)
                            // and send Invalidate MUID to prevent KeyStage PE session interference.
                            if let parsed = CIMessageParser.parse(data),
                               parsed.destinationMUID != MUID.broadcast {
                                let ourMUID = MUID(rawValue: 0x5404629)!
                                let dest = parsed.destinationMUID
                                if dest != ourMUID && !self.detectedForeignCIMUIDs.contains(dest) {
                                    self.detectedForeignCIMUIDs.insert(dest)
                                    await MainActor.run {
                                        self.appendDebugLog("CI: foreign MUID \(dest) detected — sending Invalidate")
                                    }
                                    // Send Invalidate MUID pretending to be the foreign entity
                                    // so KeyStage and other devices forget it
                                    let invalidateMsg = CIMessageBuilder.invalidateMUID(
                                        sourceMUID: dest,
                                        targetMUID: dest
                                    )
                                    // Targeted send (CTRL only) — broadcast to DAW OUT causes KeyStage LCD hang
                                    if let midi = self.transport {
                                        let dests = await MainActor.run { self.peReplyDestinations }
                                        if dests.isEmpty {
                                            try? await midi.broadcast(invalidateMsg)
                                        } else {
                                            for dest in dests {
                                                try? await midi.send(invalidateMsg, to: dest)
                                            }
                                        }
                                    }
                                    await MainActor.run {
                                        self.appendDebugLog("CI: Invalidate MUID sent for \(dest)")
                                    }
                                }
                            }
                            #endif

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
                                    let isNew = !self.discoveredPEDevices.contains(where: { $0.muid == device.muid })
                                    if isNew {
                                        self.discoveredPEDevices.append(device)
                                    }
                                    self.updatePEReplyDestinations()
                                    // Clean up stale subscriptions from old MUIDs (e.g. KeyStage power restart)
                                    if let responder = self.peResponder {
                                        let activeMUIDs = Set(self.discoveredPEDevices.map(\.muid))
                                        Task {
                                            await responder.removeSubscriptions(notIn: activeMUIDs)
                                        }
                                    }
                                }
                            case .deviceLost(let muid):
                                self.appendDebugLog("CI: Lost \(muid)")
                                self.discoveredPEDevices.removeAll { $0.muid == muid }
                                self.updatePEReplyDestinations()
                                // Clean up subscriptions for lost device
                                if let responder = self.peResponder {
                                    let activeMUIDs = Set(self.discoveredPEDevices.map(\.muid))
                                    Task {
                                        await responder.removeSubscriptions(notIn: activeMUIDs)
                                    }
                                }
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
        // Targeted to CTRL only — broadcast to DAW OUT causes KeyStage LCD hang
        if let ci = ciManager, let transport {
            let dests = peReplyDestinations
            Task {
                if dests.isEmpty {
                    await ci.invalidateMUID()
                } else {
                    let msg = CIMessageBuilder.invalidateMUID(
                        sourceMUID: ci.muid,
                        targetMUID: MUID.broadcast
                    )
                    for dest in dests {
                        try? await transport.send(msg, to: dest)
                    }
                }
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

    /// Register PE resources (standard + KORG custom) on the PEResponder.
    private func registerPEResources(_ responder: PEResponder) async {
        // ResourceList — advertise all 5 resources with Subscribe support
        let resourceListJSON = "[{\"resource\":\"DeviceInfo\"},{\"resource\":\"ChannelList\",\"canSubscribe\":true},{\"resource\":\"ProgramList\",\"canSubscribe\":true},{\"resource\":\"X-ParameterList\",\"canSubscribe\":true},{\"resource\":\"X-ProgramEdit\",\"canSubscribe\":true}]"

        await responder.registerResource("ResourceList", resource: ComputedResource(
            get: { _ in Data(resourceListJSON.utf8) },
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

        // ChannelList — single channel with Subscribe support
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

        // ProgramList — DX7 factory presets (supports offset/limit pagination)
        let allPresets = DX7FactoryPresets.all
        let presetCount = allPresets.count
        await responder.registerResource("ProgramList", resource: ComputedResource(
            supportsSubscription: true,
            get: { header in
                let offset = header.offset ?? 0
                let limit = header.limit ?? presetCount
                let startIndex = max(0, min(offset, presetCount))
                let endIndex = min(startIndex + limit, presetCount)
                let slice = allPresets[startIndex..<endIndex]
                let entries = slice.enumerated().map { i, preset in
                    let globalIndex = startIndex + i
                    return "{\"title\":\"\(globalIndex + 1):\(preset.name)\",\"bankPC\":[0,0,\(globalIndex + 1)]}"
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
                let json = await MainActor.run {
                    self?.xProgramEditJSON ?? "{}"
                }
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
                    "{\"name\":\"Volume\",\"controlcc\":7,\"default\":100}",
                    "{\"name\":\"Expression\",\"controlcc\":11,\"default\":127}",
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

    /// Current program name with 1-based number prefix (e.g. "1:E.PIANO 1")
    /// KORG Module uses "N:Name" format (1-based) — we match it for KeyStage LCD display.
    private var currentProgramName: String {
        let presets = DX7FactoryPresets.all
        if currentProgramIndex < presets.count {
            return "\(currentProgramIndex + 1):\(presets[currentProgramIndex].name)"
        }
        return "1:INIT VOICE"
    }

    /// Build currentValues JSON array from ccValues state
    private var currentValuesJSON: String {
        let entries: [(String, UInt8)] = [
            ("Volume", 7), ("Expression", 11), ("Brightness", 74)
        ]
        let items = entries.map { name, cc in
            let v = ccValues[cc] ?? 0
            return "{\"name\":\"\(name)\",\"value\":\(v),\"displayValue\":\"\(v)\",\"displayUnit\":\"\"}"
        }
        return "[\(items.joined(separator: ","))]"
    }

    /// Build X-ProgramEdit JSON body from current state
    private var xProgramEditJSON: String {
        let name = currentProgramName
        let idx = currentProgramIndex
        return "{\"name\":\"\(name)\",\"bankPC\":[0,0,\(idx + 1)],\"currentValues\":\(currentValuesJSON)}"
    }

    /// Update a CC value from UI and notify KeyStage via PE
    public func updateCC(_ cc: UInt8, value: Int) {
        guard ccValues.keys.contains(cc) else { return }
        ccValues[cc] = value
        notifyCCChange()
    }

    // MARK: - PE Reply Destination Management

    /// Synchronously resolve the PE reply destination from CoreMIDI endpoints.
    /// Must run BEFORE CIManager.start() to avoid broadcasting PE replies to all ports.
    /// KORG USB: "CTRL" port. KORG Bluetooth: "Module" port.
    private static func resolvePEDestinations() -> (destinations: [MIDIDestinationID], names: [String]) {
        let count = MIDIGetNumberOfDestinations()
        guard count > 0 else { return ([], []) }

        struct DestInfo { let id: MIDIDestinationID; let name: String }
        var dests: [DestInfo] = []
        for i in 0..<count {
            let ref = MIDIGetDestination(i)
            guard ref != 0 else { continue }
            var cfName: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(ref, kMIDIPropertyName, &cfName)
            let name = (cfName?.takeRetainedValue() as String?) ?? ""
            dests.append(DestInfo(id: MIDIDestinationID(UInt32(ref)), name: name))
        }

        let allNames = dests.map(\.name)

        // Bluetooth KORG: "Module" port only
        if let d = dests.first(where: { $0.name.lowercased().contains("module") }) {
            return ([d.id], allNames)
        }

        // USB KORG: CTRL port only for PE/CI.
        // Session 1 and DAW OUT cause KeyStage LCD hang when receiving CI messages.
        if let d = dests.first(where: { $0.name.lowercased().contains("ctrl") }) {
            return ([d.id], allNames)
        }
        // Fallback: "DAW" port
        if let d = dests.first(where: { $0.name.lowercased().contains("daw") }) {
            return ([d.id], allNames)
        }

        // Fallback: "Keystage" or "keystage" — pick the first one
        if let d = dests.first(where: { $0.name.lowercased().contains("keystage") }) {
            return ([d.id], allNames)
        }
        // Fallback: first non-KBD, non-Session destination
        let nonKbd = dests.filter {
            let n = $0.name.lowercased()
            return !n.contains("kbd") && !n.contains("session")
        }
        if let d = nonKbd.first {
            return ([d.id], allNames)
        }
        // Last resort: first destination
        if let d = dests.first {
            return ([d.id], allNames)
        }
        return ([], allNames)
    }

    /// Update PEResponder's replyDestinations from discoveredPEDevices.
    /// Targeted send uses legacy MIDISend (not UMP SysEx7) to avoid KeyStage hangs.
    /// This prevents broadcasting PE replies to all 3 destinations (KBD/CTRL/Module).
    private func updatePEReplyDestinations() {
        guard let responder = peResponder, let ci = ciManager else { return }
        let devices = discoveredPEDevices
        Task {
            var seen = Set<UInt32>()
            var destinations: [MIDIDestinationID] = []
            for device in devices {
                if let dest = await ci.destination(for: device.muid) {
                    if seen.insert(dest.value).inserted {
                        destinations.append(dest)
                    }
                }
            }
            await responder.setReplyDestinations(destinations)
            await MainActor.run {
                if destinations.isEmpty {
                    self.appendDebugLog("PE: replyDestinations cleared")
                } else {
                    self.appendDebugLog("PE: replyDestinations=\(destinations.map { String($0.value) }.joined(separator: ","))")
                }
            }
        }
    }

    // MARK: - PE Notify (subscription updates on Program Change)

    /// Handle program change: update internal state and send PE Notify to subscribers.
    private func notifyProgramChange(programIndex: UInt8) {
        // KeyStage sends 1-based bankPC values as PC numbers, convert to 0-based array index
        currentProgramIndex = max(0, Int(programIndex) - 1)
        let name = currentProgramName
        let idx = currentProgramIndex
        appendDebugLog("PC: program=\(idx) name=\(name)")
        peLogger.info("PC: program=\(idx) name=\(name, privacy: .public)")

        guard let responder = peResponder else { return }

        // Capture values needed off-MainActor before launching Task
        let knownMUIDs = Set(discoveredPEDevices.map(\.muid))

        // Pre-build notify bodies on MainActor (cheap string ops)
        let channelListBody = Data("[{\"channel\":1,\"title\":\"Channel 1\",\"programTitle\":\"\(name)\"}]".utf8)
        let xProgramEditBody = Data(xProgramEditJSON.utf8)

        appendDebugLog("PE-Notify: program=\(idx) name=\(name)")

        // Send PE Notify to subscribers — KeyStage REQUIRES Notify after PC or it hangs.
        // excludeMUIDs: exclude macOS entities (not in discoveredPEDevices), keep KeyStage.
        Task {
            // Brief wait to ensure KeyStage has processed the PC message
            try? await Task.sleep(for: .milliseconds(50))

            // Exclude non-KORG MUIDs (e.g. macOS built-in MIDI-CI entity)
            let excludeMUIDs = await responder.subscriberMUIDs().subtracting(knownMUIDs)

            await responder.notify(resource: "ChannelList", data: channelListBody, excludeMUIDs: excludeMUIDs)
            await responder.notify(resource: "X-ProgramEdit", data: xProgramEditBody, excludeMUIDs: excludeMUIDs)

            await MainActor.run { [weak self] in
                self?.appendDebugLog("PE-Notify: sent OK")
            }
        }
    }

    // MARK: - PE Notify (CC value changes)

    private func notifyCCChange() {
        // Disabled: PE Notify for CC changes causes KeyStage hang
        // TODO: Fix PE Notify format/timing before re-enabling
        appendDebugLog("CC-state: \(ccValues)")
    }

    // MARK: - Sniffer Helpers

    #if DEBUG
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
    #endif

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
        return "hdr=\(jsonParts[0]) body=\(String(jsonParts[1].prefix(2000)))"
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
        let mt = UInt8((word1 >> 28) & 0x0F)
        let status = UInt8((word1 >> 20) & 0x0F)
        let channel = UInt8((word1 >> 16) & 0x0F)
        let byte3 = UInt8((word1 >> 8) & 0xFF)   // note or controller

        // Log non-Note messages for debugging
        if status != 0x9 && status != 0x8 {
            appendDebugLog(String(format: "UMP-DBG mt=%d st=0x%X ch=%d b3=%d w2=0x%08X", mt, status, channel, byte3, word2))
        }

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
                // Update CC state and notify KeyStage
                if ccValues.keys.contains(byte3) {
                    let val7 = Int(Double(val32) / Double(UInt32.max) * 127.0)
                    ccValues[byte3] = val7
                    notifyCCChange()
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
        // Log MIDI 1.0 path entry for debugging
        if let first = data.first, (first >> 4) == 0xB || (first >> 4) == 0xC {
            let hex = data.prefix(4).map { String(format: "%02X", $0) }.joined(separator: " ")
            appendDebugLog("M1-DBG: \(hex)")
        }
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
                    // Update CC state and notify KeyStage
                    if ccValues.keys.contains(controller) {
                        ccValues[controller] = Int(value)
                        notifyCCChange()
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
