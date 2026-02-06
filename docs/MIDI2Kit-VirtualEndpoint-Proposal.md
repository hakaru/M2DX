# Feature Proposal: Virtual MIDI Endpoint Support for CoreMIDITransport

## Summary

Add virtual MIDI endpoint (source/destination) creation to `CoreMIDITransport`, enabling inter-app MIDI communication on the same device. This is essential for PEResponder to work with other iOS/macOS apps — currently it can only respond to external hardware devices.

## Motivation

### Problem

`CoreMIDITransport` currently creates:
- `MIDIOutputPortCreate` — for sending to existing destinations
- `MIDIInputPortCreateWithBlock` — for receiving from connected sources

It does **not** create:
- `MIDIDestinationCreate` — virtual endpoint that other apps can send to
- `MIDISourceCreate` — virtual endpoint that other apps can receive from

This means an app using `PEResponder` is invisible to other apps on the same device. DAWs (Logic, AUM, etc.) and MIDI controllers cannot discover or communicate with the app via MIDI-CI Property Exchange.

### Use Case: PEResponder for Inter-App MIDI

```
┌─────────────────────┐     ┌─────────────────────────┐
│  DAW / Controller   │     │  App using PEResponder   │
│  (Logic, AUM, etc.) │     │  (e.g. FM Synth)         │
│                     │     │                           │
│  PE GET "ProgramList"│────▶│  Virtual Destination     │
│                     │     │    → received stream      │
│                     │◀────│    → PEResponder response  │
│                     │     │  Virtual Source            │
└─────────────────────┘     └─────────────────────────┘
```

Without virtual endpoints, PEResponder only works with external USB/BLE MIDI hardware. This severely limits its usefulness, especially on iOS where inter-app MIDI is a primary communication method.

## Proposed API

### 1. MIDITransport Protocol Extension

```swift
/// Protocol for transports that support virtual endpoint creation
public protocol VirtualEndpointCapable: MIDITransport {
    /// Create a virtual MIDI destination (other apps send TO this)
    func createVirtualDestination(name: String) async throws -> MIDIDestinationID

    /// Create a virtual MIDI source (other apps receive FROM this)
    func createVirtualSource(name: String) async throws -> MIDISourceID

    /// Remove a previously created virtual destination
    func removeVirtualDestination(_ id: MIDIDestinationID) async throws

    /// Remove a previously created virtual source
    func removeVirtualSource(_ id: MIDISourceID) async throws

    /// Send data through a virtual source (received by other apps)
    func sendFromVirtualSource(_ data: [UInt8], source: MIDISourceID) async throws
}
```

### 2. CoreMIDITransport Implementation

```swift
extension CoreMIDITransport: VirtualEndpointCapable {

    public func createVirtualDestination(name: String) async throws -> MIDIDestinationID {
        var endpoint: MIDIEndpointRef = 0
        let status = MIDIDestinationCreateWithBlock(
            client,
            name as CFString,
            &endpoint
        ) { [weak self] packetList, srcConnRefCon in
            // Route received packets into the existing `received` AsyncStream
            self?.handlePacketList(packetList, from: nil)
        }
        guard status == noErr else {
            throw MIDITransportError.portCreationFailed(status)
        }
        return MIDIDestinationID(UInt32(endpoint))
    }

    public func createVirtualSource(name: String) async throws -> MIDISourceID {
        var endpoint: MIDIEndpointRef = 0
        let status = MIDISourceCreate(client, name as CFString, &endpoint)
        guard status == noErr else {
            throw MIDITransportError.portCreationFailed(status)
        }
        return MIDISourceID(UInt32(endpoint))
    }

    public func sendFromVirtualSource(_ data: [UInt8], source: MIDISourceID) async throws {
        let sourceRef = MIDIEndpointRef(source.value)
        // Build MIDIPacketList, then:
        MIDIReceived(sourceRef, packetList)
    }

    public func removeVirtualDestination(_ id: MIDIDestinationID) async throws {
        MIDIEndpointDispose(MIDIEndpointRef(id.value))
    }

    public func removeVirtualSource(_ id: MIDISourceID) async throws {
        MIDIEndpointDispose(MIDIEndpointRef(id.value))
    }
}
```

### 3. Key Design Points

#### Merging into `received` AsyncStream

The virtual destination's receive callback should feed into the same `received` AsyncStream that external sources use. This allows existing code (including PEResponder's `handleMessage()`) to work without changes.

```swift
// In MIDIDestinationCreateWithBlock callback:
let received = MIDIReceivedData(data: bytes, sourceID: nil, timestamp: mach_absolute_time())
receivedContinuation?.yield(received)
```

#### PEResponder Response Path

When PEResponder calls `transport.send()`, the response needs to reach the requesting app. Two approaches:

**Option A: Auto-route via virtual source**
```swift
// transport.send() detects virtual-originated messages and routes through virtual source
func send(_ data: [UInt8], to destination: MIDIDestinationID) async throws {
    if isVirtualSourceActive {
        // Use MIDIReceived() to send through virtual source
        try await sendFromVirtualSource(data, source: virtualSourceID)
    } else {
        // Existing: MIDISend(outputPort, destRef, packetList)
    }
}
```

**Option B: Explicit virtual source send (preferred)**
```swift
// PEResponder is configured with a virtual source for responses
let responder = PEResponder(muid: muid, transport: transport, responseSource: virtualSourceID)
```

#### MIDI 2.0 Protocol Support

For MIDI 2.0 UMP-native communication, use the newer CoreMIDI APIs:

```swift
// iOS 16+ / macOS 13+
MIDIDestinationCreateWithProtocol(
    client,
    name as CFString,
    ._2_0,          // MIDIProtocolID
    &endpoint
) { eventList, srcConnRefCon in
    // Handle MIDIEventList (UMP packets)
}

MIDISourceCreateWithProtocol(
    client,
    name as CFString,
    ._2_0,
    &endpoint
)
```

This would enable native MIDI 2.0 UMP inter-app communication, bypassing the MIDI 1.0 byte stream layer entirely.

## Alternative: Convenience API

For the common case of "make my app visible as a MIDI device":

```swift
extension CoreMIDITransport {
    /// Publish this transport as a virtual MIDI device visible to other apps
    /// Creates both a virtual source and destination with the given name
    public func publishVirtualDevice(
        name: String
    ) async throws -> VirtualDevice {
        let destination = try await createVirtualDestination(name: name)
        let source = try await createVirtualSource(name: name)
        return VirtualDevice(
            name: name,
            destinationID: destination,  // other apps send here
            sourceID: source              // other apps receive from here
        )
    }

    /// Remove a previously published virtual device
    public func unpublishVirtualDevice(_ device: VirtualDevice) async throws {
        try await removeVirtualDestination(device.destinationID)
        try await removeVirtualSource(device.sourceID)
    }
}

public struct VirtualDevice: Sendable {
    public let name: String
    public let destinationID: MIDIDestinationID
    public let sourceID: MIDISourceID
}
```

### Usage with PEResponder

```swift
let transport = try CoreMIDITransport(clientName: "MyApp")
let device = try await transport.publishVirtualDevice(name: "MyApp MIDI")

let responder = PEResponder(muid: MUID.random(), transport: transport)
await responder.registerResource("ProgramList", resource: myResource)
await responder.start()

// Now other apps on the same device can:
// 1. See "MyApp MIDI" in their MIDI source/destination list
// 2. Send CI SysEx to it
// 3. Receive PE responses from it
```

## Scope of Changes

| File | Change |
|------|--------|
| `MIDITransport.swift` | Add `VirtualEndpointCapable` protocol |
| `CoreMIDITransport.swift` | Implement virtual endpoint creation, merge into received stream |
| `MockMIDITransport.swift` | Add mock virtual endpoint support (for testing) |

No changes needed to:
- `PEResponder` — already uses `transport.send()` for responses
- `PEManager` — already uses `transport.received` for incoming data
- `MIDITransport` base protocol — virtual support is opt-in via `VirtualEndpointCapable`

## Platform Requirements

- `MIDIDestinationCreateWithBlock`: iOS 4.2+ / macOS 10.11+
- `MIDISourceCreate`: iOS 4.2+ / macOS 10.0+
- `MIDIDestinationCreateWithProtocol` (MIDI 2.0): iOS 16+ / macOS 13+
- `MIDISourceCreateWithProtocol` (MIDI 2.0): iOS 16+ / macOS 13+

All within MIDI2Kit's minimum deployment targets (iOS 17 / macOS 14).

## Impact

This feature would enable:
- **Inter-app PE communication** on iOS/macOS (DAW ↔ synth app)
- **Virtual instrument hosting** (app appears as MIDI device to other apps)
- **MIDI-CI device emulation** for testing without hardware
- **AUv3 host integration** (host communicates with AU via MIDI-CI PE on same device)
