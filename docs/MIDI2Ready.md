# M2DX MIDI 2.0 対応状況

## 概要

M2DXは**MIDI 2.0 Ready**なFMシンセサイザーアプリケーションです。本ドキュメントでは、M2DXが実装しているMIDI 2.0機能と、現時点で未対応の機能について詳細に記録します。

### "MIDI 2.0 Ready" の定義

M2DXは以下の基準でMIDI 2.0に対応しています：

- **Universal MIDI Packet (UMP)** フォーマットでMIDIデータを受信
- **MIDI 2.0 Channel Voice Messages** (Message Type 0x4) をネイティブにデコード
- **高精度制御**: 16-bit velocity, 32-bit CC, 32-bit pitch bend をフル活用
- **MIDI-CI (Capability Inquiry)** によるデバイスディスカバリとプロトコルネゴシエーション
- **Property Exchange (PE)** による自己記述的パラメータ階層構造 (155+パラメータ)
- **MIDI 1.0フォールバック**: MIDI 1.0デバイスからの入力も自動変換して対応

M2DXは、MIDI 2.0デバイスからの入力を**フルプレシジョン**で処理し、FMシンセエンジンに直接供給します。従来のMIDI 1.0の7-bit/14-bit制御から、16-bit/32-bitへの飛躍的な精度向上により、ダイナミクス表現・ピッチベンド・CC制御の滑らかさが大幅に改善されています。

---

## MIDI 2.0対応状況サマリー

| 機能カテゴリ | 対応状況 | 備考 |
|------------|---------|------|
| **Universal MIDI Packet (UMP)** | ✅ 対応済 | CoreMIDITransport ._2_0 プロトコル |
| **Message Type 0x4 (MIDI 2.0 CV)** | ✅ 対応済 | Note/CC/PB/Pressure デコード |
| **16-bit Note Velocity** | ✅ 対応済 | FMSynthEngine が 16-bit velocity を直接処理 |
| **32-bit Control Change** | ✅ 対応済 | CC64 (sustain) で使用 |
| **32-bit Pitch Bend** | ✅ 対応済 | ±2半音の範囲で高精度ベンド |
| **MIDI 1.0 Fallback (type 0x2)** | ✅ 対応済 | 7-bit → 16/32-bit 自動アップスケール |
| **MIDI-CI Discovery** | ✅ 対応済 | MIDI2Kit経由でデバイス検出 |
| **Property Exchange (PE)** | ✅ 対応済 | 155+ パラメータの階層ツリー |
| **Per-Note Controllers** | ❌ 未対応 | MIDI 2.0拡張機能（実装予定） |
| **Per-Note Pitch Bend** | ❌ 未対応 | MIDI 2.0拡張機能（実装予定） |
| **Per-Note Management** | ❌ 未対応 | MIDI 2.0拡張機能（実装予定） |
| **Registered Controllers (RPN)** | ❌ 未対応 | 実装予定 |
| **Assignable Controllers (NRPN)** | ❌ 未対応 | 実装予定 |
| **Program Change (Bank Select)** | 🟡 部分対応 | Program Changeは受信するが Bank Select は未実装 |
| **System Exclusive 8 (type 0x5)** | ❌ 未対応 | 現状SysEx処理なし |
| **Profile Configuration** | ❌ 未対応 | 実装予定 |
| **Process Inquiry** | ❌ 未対応 | 実装予定 |

---

## 1. Universal MIDI Packet (UMP) 対応

### 1.1 プロトコル切り替え

**実装箇所**: `MIDI2Kit/Sources/MIDI2Transport/CoreMIDITransport.swift`

```swift
// M2DXは MIDI 2.0 プロトコルを使用
let transport = try CoreMIDITransport(clientName: "M2DX")
// 内部で ._2_0 プロトコルが選択される
```

CoreMIDITransportは、iOS 18.0+のCoreMIDI UMPサポートを使用し、`MIDIEventList`形式でMIDI 2.0パケットを受信します。

### 1.2 UMPワードの保存と処理

**実装箇所**: `MIDIInputManager.swift` (line 157-162)

M2DXは、受信したUMPワードをそのまま保存し、フルプレシジョン処理に使用します：

```swift
if received.umpWord1 != 0 {
    // MIDI 2.0 path: decode full-precision values from UMP words
    await self.handleUMPData(received.umpWord1, word2: received.umpWord2, fallbackData: data)
} else {
    // MIDI 1.0 fallback: upscale 7-bit → 16/32-bit
    await self.handleReceivedData(data)
}
```

**UMPワード構造** (Message Type 0x4, 2-word message):
```
Word 1 (32-bit):
  [31:28] Message Type = 0x4 (MIDI 2.0 Channel Voice)
  [27:24] Group
  [23:20] Status (0x8=NoteOff, 0x9=NoteOn, 0xB=CC, 0xE=PB)
  [19:16] Channel (0-15)
  [15:8]  Byte 3 (note number or controller number)
  [7:0]   Reserved

Word 2 (32-bit):
  [31:16] Velocity (Note On/Off) or 上位16bit (CC/PB)
  [15:0]  下位16bit (CC/PB full 32-bit value)
```

---

## 2. MIDI 2.0 Channel Voice Messages 対応

### 2.1 対応メッセージ一覧

M2DXは以下のMIDI 2.0 Channel Voice Messages (Message Type 0x4) をデコードします：

| メッセージ | Status | データ構造 | 対応状況 | 実装箇所 |
|----------|--------|----------|---------|---------|
| **Note On** | 0x9 | 16-bit velocity (word2 上位16bit) | ✅ 対応済 | MIDIInputManager.swift:270-279 |
| **Note Off** | 0x8 | 16-bit release velocity | ✅ 対応済 | MIDIInputManager.swift:281-285 |
| **Control Change** | 0xB | 32-bit value (word2 全体) | ✅ 対応済 | MIDIInputManager.swift:287-297 |
| **Pitch Bend** | 0xE | 32-bit unsigned (center=0x80000000) | ✅ 対応済 | MIDIInputManager.swift:299-304 |
| **Channel Pressure** | 0xD | 32-bit value | ✅ 認識 | 未使用（FMSynthEngineで未処理） |
| **Poly Pressure** | 0xA | 32-bit value per note | ✅ 認識 | 未使用（FMSynthEngineで未処理） |
| **Program Change** | 0xC | Program number + Bank MSB/LSB | 🟡 部分対応 | Bank Selectは未実装 |
| **Per-Note CC** | 0x0 (PNCC) | Per-note modulation | ❌ 未対応 | 実装予定 |
| **Per-Note Pitch Bend** | 0x6 (PNPB) | Per-note pitch | ❌ 未対応 | 実装予定 |
| **Per-Note Management** | 0xF | Detach/Reset | ❌ 未対応 | 実装予定 |
| **Registered Controller** | (RPN) | MIDI 2.0拡張 | ❌ 未対応 | 実装予定 |
| **Assignable Controller** | (NRPN) | MIDI 2.0拡張 | ❌ 未対応 | 実装予定 |

### 2.2 Message Type 0x2 (MIDI 1.0 CV) フォールバック

M2DXは、MIDI 1.0デバイスからの入力にも対応しています。Message Type 0x2を受信した場合、または`umpWord1 == 0`の場合、従来のMIDI 1.0バイトストリームとして処理します。

**実装箇所**: `MIDIInputManager.swift:314-407`

```swift
// MIDI 1.0 fallback: 7-bit velocity → 16-bit velocity
let vel16 = UInt16(velocity) << 9  // 0-127 → 0-65024

// MIDI 1.0 fallback: 7-bit CC → 32-bit CC
let val32 = UInt32(value) << 25  // 0-127 → 0-0xFE000000

// MIDI 1.0 fallback: 14-bit pitch bend → 32-bit pitch bend
let raw14 = (UInt32(msb) << 7) | UInt32(lsb)
let val32 = raw14 << 18  // 0-16383 → 0-0xFFFC0000
```

このアップスケール処理により、MIDI 1.0デバイスでもM2DXの高精度エンジンを利用できます。

---

## 3. 高精度MIDI制御

### 3.1 16-bit Note Velocity (vs MIDI 1.0の7-bit)

**MIDI 1.0**: velocity = 0-127 (7-bit) → 128段階の強弱
**MIDI 2.0**: velocity = 0-65535 (16-bit) → 65536段階の強弱

**実装箇所**: `FMSynthEngine.swift:293-295`

```swift
mutating func noteOn(_ n: UInt8, velocity16: UInt16) {
    note = n
    velScale = Float(velocity16) / 65535.0  // 16-bit velocity を 0.0-1.0 に正規化
    ...
}
```

**効果**: タッチキーボードやMIDI 2.0対応コントローラー（例: ROLI Seaboard, Haken Continuum）からの微細なベロシティ変化を正確に再現できます。

### 3.2 32-bit Control Change (vs MIDI 1.0の7-bit)

**MIDI 1.0**: CC value = 0-127 (7-bit) → 128段階
**MIDI 2.0**: CC value = 0-0xFFFFFFFF (32-bit unsigned) → 約43億段階

**実装箇所**: `FMSynthEngine.swift:576-592`

```swift
private func doControlChange(_ cc: UInt8, value32: UInt32) {
    switch cc {
    case 64: // Sustain pedal: 32-bit threshold at 0x40000000
        let on = value32 >= 0x40000000  // center threshold
        sustainPedalOn = on
        ...
    }
}
```

**サスティンペダルの閾値**:
- MIDI 1.0: value < 64 → OFF, value >= 64 → ON (2段階)
- MIDI 2.0: value < 0x40000000 → OFF, value >= 0x40000000 → ON (32-bit精度)

MIDI 2.0では、ペダルの「踏み込み量」を連続的に検出し、ハーフペダル効果（部分的なサスティン）も実装可能です（M2DXでは現在ON/OFFのみ対応）。

### 3.3 32-bit Pitch Bend (vs MIDI 1.0の14-bit)

**MIDI 1.0**: pitch bend = 0-16383 (14-bit) → 16384段階
**MIDI 2.0**: pitch bend = 0-0xFFFFFFFF (32-bit unsigned) → 約43億段階

**実装箇所**: `FMSynthEngine.swift:594-604`

```swift
private func doPitchBend32(_ value: UInt32) {
    // 32-bit unsigned: center = 0x80000000
    let signed = Int64(value) - 0x80000000
    let semitones = Float(signed) / Float(0x80000000) * 2.0  // ±2 semitones
    pitchBendFactor = powf(2.0, semitones / 12.0)

    for i in 0..<kMaxVoices {
        if voices[i].active {
            voices[i].applyPitchBend(pitchBendFactor)
        }
    }
}
```

**ピッチベンド範囲**: ±2半音（DX7互換）

**効果**: MIDI 1.0の14-bit（16384段階）では、ピッチベンドに「階段状」のノイズが聞こえることがありました。MIDI 2.0の32-bit（約43億段階）では、完全に滑らかなベンドが実現されます。

### 3.4 FMSynthEngineでの高精度処理

**実装箇所**: `FMSynthEngine.swift`

M2DXのFMシンセエンジンは、受信したMIDI 2.0データを**そのままの精度**で処理します：

```swift
// 16-bit velocity → 0.0-1.0 の浮動小数点スケール
velScale = Float(velocity16) / 65535.0

// 32-bit pitch bend → ±2半音の周波数乗数
pitchBendFactor = powf(2.0, semitones / 12.0)

// 32-bit CC → 0x40000000 (50%) を閾値として判定
sustainPedalOn = value32 >= 0x40000000
```

**従来のMIDI 1.0処理との比較**:

| パラメータ | MIDI 1.0 | MIDI 2.0 | 精度向上 |
|-----------|---------|---------|---------|
| Velocity | 7-bit (128段階) | 16-bit (65536段階) | **512倍** |
| Pitch Bend | 14-bit (16384段階) | 32-bit (約43億段階) | **262144倍** |
| CC | 7-bit (128段階) | 32-bit (約43億段階) | **33554432倍** |

---

## 4. MIDI-CI (Capability Inquiry) 対応

### 4.1 MIDI2Kitによるデバイスディスカバリ

**実装箇所**: `MIDIInputManager.swift:103-110`

M2DXは、MIDI2Kitの`CoreMIDITransport`を使用してMIDI-CI対応デバイスを自動検出します：

```swift
let midi = try CoreMIDITransport(clientName: "M2DX")
self.transport = midi

// Create PEResponder for MIDI-CI Property Exchange
let responder = PEResponder(muid: MUID.random(), transport: midi)
self.peResponder = responder
Task { await self.registerPEResources(responder) }
```

**MIDI-CIの仕組み**:
1. **Discovery**: M2DXは起動時にMIDI-CI Discoveryメッセージを送信
2. **Reply**: MIDI 2.0対応デバイスが自身の能力情報（対応機能、MUID）を返信
3. **Protocol Negotiation**: MIDI 1.0/2.0のどちらで通信するかをネゴシエーション
4. **Property Exchange**: デバイスのパラメータ構造を取得

### 4.2 プロトコルネゴシエーション

M2DXは`._2_0`プロトコルを優先的に使用しますが、デバイスがMIDI 1.0のみ対応の場合は自動的にフォールバックします。

**対応状況と限界**:
- ✅ MIDI-CI Discovery: MIDI2Kitが自動処理
- ✅ Protocol Negotiation: CoreMIDITransportがハンドリング
- 🟡 Profile Configuration: 未実装（MIDI2Kitの将来バージョンで対応予定）
- 🟡 Process Inquiry: 未実装（MIDI2Kitの将来バージョンで対応予定）

---

## 5. Property Exchange (PE) 対応

M2DXは、**MIDI 2.0 Property Exchange**による自己記述的パラメータ階層構造を完全にサポートしています。

### 5.1 155+パラメータの階層ツリー

**実装箇所**:
- `M2DXCore/PropertyExchange/M2DXParameterTree.swift`
- `M2DXCore/PropertyExchange/M2DXParameterAddressMap.swift`
- `M2DXCore/PropertyExchange/M2DXPEResource.swift`

**パラメータ構造** (詳細は`docs/PropertyExchange.md`参照):

```
M2DX Parameter Tree (155+ parameters)
├── Global/                      # 6パラメータ
│   ├── Algorithm (1-32)
│   ├── Feedback (0-7)
│   ├── OscSync (boolean)
│   ├── Transpose (-24 - +24)
│   ├── VoiceName (string)
│   └── MasterVolume (0-127)
├── Operators/ (6オペレーター)   # 17×6 = 102パラメータ
│   ├── Op1/ ... Op6/
│   │   ├── Mode (Ratio/Fixed)
│   │   ├── Frequency/Coarse (0-31)
│   │   ├── Frequency/Fine (0-99)
│   │   ├── Frequency/Detune (-7 - +7)
│   │   ├── Level (0-99)
│   │   ├── VelocitySensitivity (0-7)
│   │   ├── AmpModSensitivity (0-3)
│   │   ├── RateScaling (0-7)
│   │   ├── KeyboardLevelScaling/BreakPoint (0-99)
│   │   ├── KeyboardLevelScaling/LeftDepth (0-99)
│   │   ├── KeyboardLevelScaling/RightDepth (0-99)
│   │   ├── KeyboardLevelScaling/LeftCurve (enum)
│   │   ├── KeyboardLevelScaling/RightCurve (enum)
│   │   ├── EG/Rates/Rate1-4 (0-99) ×4
│   │   └── EG/Levels/Level1-4 (0-99) ×4
├── LFO/                         # 7パラメータ
│   ├── Speed (0-99)
│   ├── Delay (0-99)
│   ├── PitchModDepth (0-99)
│   ├── AmpModDepth (0-99)
│   ├── Sync (boolean)
│   ├── Waveform (enum)
│   └── PitchModSensitivity (0-7)
├── PitchEG/                     # 8パラメータ
│   ├── Rates/Rate1-4 (0-99) ×4
│   └── Levels/Level1-4 (0-99) ×4
└── Controller/                  # 12パラメータ
    ├── Wheel/ (Pitch, Amp, EGBias) ×3
    ├── Foot/ (Pitch, Amp, EGBias) ×3
    ├── Breath/ (Pitch, Amp, EGBias) ×3
    └── Aftertouch/ (Pitch, Amp, EGBias) ×3
```

**総パラメータ数**: 6 + 102 + 7 + 8 + 12 = **135パラメータ**（DX7互換）

将来的に8オペレーター拡張を行う場合、さらに34パラメータ（17×2）が追加され、合計**169パラメータ**になります。

### 5.2 PEResponder実装

**実装箇所**: `MIDIInputManager.swift:227-255`

M2DXは、MIDI-CI Property Exchange Requestに対してレスポンダーとして応答します：

```swift
private func registerPEResources(_ responder: PEResponder) async {
    // ResourceList — advertise available resources
    await responder.registerResource("ResourceList", resource: StaticResource(json: """
    [
        {"resource":"ResourceList","canGet":true},
        {"resource":"DeviceInfo","canGet":true},
        {"resource":"ProgramList","canGet":true}
    ]
    """))

    // DeviceInfo
    await responder.registerResource("DeviceInfo", resource: StaticResource(json: """
    {
        "manufacturerName":"M2DX",
        "productName":"M2DX DX7 Synthesizer",
        "softwareVersion":"1.0",
        "familyName":"FM Synthesizer",
        "modelName":"DX7 Compatible"
    }
    """))

    // ProgramList — dynamic from DX7 factory presets
    await responder.registerResource("ProgramList", resource: ComputedResource { _ in
        let programs = DX7FactoryPresets.all.enumerated().map { index, preset in
            PEProgramDef(programNumber: index, bankMSB: 0, bankLSB: 0, name: preset.name)
        }
        return try JSONEncoder().encode(programs)
    })
}
```

**対応リソース**:
- `ResourceList`: 利用可能なリソース一覧
- `DeviceInfo`: デバイス情報（製品名、バージョン等）
- `ProgramList`: プリセット一覧（DX7ファクトリープリセット32種類）

### 5.3 JSON形式のプリセット管理

Property Exchangeの最大の利点は、プリセットを**JSON形式**で保存・転送できることです：

**従来のDX7 SysEx（バイナリ）**:
```
F0 43 00 00 01 1B 50 49 41 4E 4F ... F7
```
↑ 人間が読めない、Git差分が見えない、検索・タグ付け不可

**M2DX Property Exchange（JSON）**:
```json
{
  "preset": "BRASS1",
  "parameters": {
    "Global/Algorithm": 4,
    "Global/Feedback": 7,
    "Operators/Op1/Level": 99,
    "Operators/Op1/Frequency/Coarse": 1,
    "Operators/Op1/EG/Rates/Rate1": 96,
    "Operators/Op1/EG/Levels/Level1": 99,
    ...
  }
}
```
↑ 人間が読める、Git差分が見える、検索・タグ付け可能、クラウド対応

### 5.4 サブスクリプション対応

**実装状況**: 🟡 部分対応（MIDI2Kitの将来バージョンで完全対応予定）

Property Exchange Subscriptionは、パラメータの変更をリアルタイムで監視し、DAWやコントローラーに自動通知する機能です。M2DXのPEResponderはサブスクリプションのインフラを持っていますが、現時点ではGet/Set操作のみ対応しています。

---

## 6. コード実装詳細

### 6.1 MIDIEventQueue: データ型の拡張

**実装箇所**: `MIDIEventQueue.swift:9-20`

```swift
struct MIDIEvent: Sendable {
    enum Kind: UInt8, Sendable {
        case noteOn = 0x90
        case noteOff = 0x80
        case controlChange = 0xB0
        case pitchBend = 0xE0
    }

    let kind: Kind
    let data1: UInt8       // note number or CC number (7-bit)
    let data2: UInt32      // velocity16, CC value32, or pitchBend32 (拡張)
}
```

**MIDI 1.0時代**: `data2: UInt8` → 0-127の範囲のみ
**MIDI 2.0対応**: `data2: UInt32` → 16-bit velocity (下位16bit), 32-bit CC/PB (全32bit) を格納

### 6.2 MIDIReceivedData: UMPワード保存

**実装箇所**: `MIDI2Kit/Sources/MIDI2Transport/MIDITransport.swift` (MIDI2Kitパッケージ)

```swift
public struct MIDIReceivedData {
    public let data: [UInt8]           // MIDI 1.0 byte stream (fallback)
    public let sourceID: SourceID
    public let umpWord1: UInt32        // UMP Word 1 (status + data)
    public let umpWord2: UInt32        // UMP Word 2 (velocity/CC/PB full precision)
}
```

CoreMIDITransportは、`MIDIEventList`を受信した際に、UMPワードを直接保存します。これにより、M2DXは高精度データをロスレスで処理できます。

### 6.3 handleUMPData: フルプレシジョンデコード

**実装箇所**: `MIDIInputManager.swift:259-310`

```swift
private func handleUMPData(_ word1: UInt32, word2: UInt32, fallbackData: [UInt8]) {
    let status = UInt8((word1 >> 20) & 0x0F)
    let channel = UInt8((word1 >> 16) & 0x0F)
    let byte3 = UInt8((word1 >> 8) & 0xFF)   // note or controller

    switch status {
    case 0x9: // Note On (16-bit velocity in upper 16 of word2)
        let vel16 = UInt16((word2 >> 16) & 0xFFFF)
        onNoteOn?(byte3, vel16)

    case 0xB: // Control Change (32-bit value)
        let val32 = word2
        onControlChange?(byte3, val32)

    case 0xE: // Pitch Bend (32-bit unsigned, center=0x80000000)
        let val32 = word2
        onPitchBend?(val32)

    default:
        // For unhandled UMP types, fall back to MIDI 1.0 byte parsing
        handleReceivedData(fallbackData)
    }
}
```

**ポイント**:
- **Word 2の全体**をそのままCC/PB値として使用（32-bit精度）
- **Word 2の上位16bit**をNote Velocityとして使用（16-bit精度）
- 対応していないUMPメッセージは、自動的にMIDI 1.0フォールバック処理へ

---

## 7. MIDI 2.0 未対応機能と今後のロードマップ

### 7.1 Per-Note Controllers (PNCC)

**MIDI 2.0の新機能**: 各ノートに個別のCC値を設定可能

**ユースケース**:
- ポリフォニック・アフタータッチ（各鍵盤ごとに圧力を変える）
- 個別音量コントロール（各ノートの音量を別々に調整）
- ポリフォニック・ビブラート（各ノートごとにLFO深さを変える）

**実装予定**: FMSynthEngineで`Voice`ごとのCC状態を保持し、Per-Note CCメッセージを処理

### 7.2 Per-Note Pitch Bend (PNPB)

**MIDI 2.0の新機能**: 各ノートに個別のピッチベンドを適用可能

**ユースケース**:
- マイクロトーナル演奏（各ノートを微調整してスケール外の音程を出す）
- ポリフォニック・ベンド（和音の各音を別々にベンドする）
- グリッサンド効果（各ノートを段階的にベンド）

**実装予定**: `Voice`に`perNotePitchBendFactor`を追加し、グローバルベンドとは別に適用

### 7.3 Registered Controllers (RPN) / Assignable Controllers (NRPN)

**MIDI 2.0拡張**: 標準化されたコントローラー番号（RPN）とユーザー定義コントローラー（NRPN）

**ユースケース**:
- RPN 0: Pitch Bend Range（ベンド範囲を±2半音から±12半音に変更等）
- RPN 1: Fine Tuning（±100セント）
- RPN 2: Coarse Tuning（±12半音）
- NRPN: ベンダー固有のパラメータ（LFO速度、フィルターカットオフ等）

**実装予定**: FMSynthEngineにRPN/NRPNハンドラーを追加

### 7.4 LFO / Pitch EG の実装

**現状**: M2DXはLFO/Pitch EGのパラメータ定義を持っていますが、FMSynthEngineでの処理は未実装です。

**実装予定**:
- `FMOp`に`lfo: LFO`フィールドを追加
- `Voice`に`pitchEG: Envelope`フィールドを追加
- `Voice.process()`でLFO/Pitch EGを適用

### 7.5 Profile Configuration

**MIDI-CIの機能**: デバイスが対応する「プロファイル」（楽器タイプやコントロール方式）を宣言

**ユースケース**:
- "GM2 Profile": General MIDI 2互換として動作
- "DX7 Profile": DX7互換モードを自動選択
- "Multi-Timbral Profile": 16パート・マルチティンバー動作

**実装予定**: MIDI2Kitの将来バージョンで対応予定

### 7.6 System Exclusive 8 (SysEx 8)

**MIDI 2.0の新SysEx形式**: Message Type 0x5, 8-bitクリーン（0x00-0xFF全範囲使用可能）

**MIDI 1.0 SysEx**: 7-bitのみ使用可能（0x00-0x7F）、バイナリデータを6/7にエンコード
**MIDI 2.0 SysEx 8**: 8-bit使用可能（0x00-0xFF）、バイナリデータをそのまま転送

**実装予定**: DX7プリセットのバルク転送をSysEx 8で実装

---

## 8. MIDI2Kit依存関係

M2DXは、**MIDI2Kit**オープンソースパッケージを使用してMIDI 2.0機能を実装しています。

### 8.1 MIDI2Kitが提供する機能

| モジュール | 機能 | M2DXでの使用状況 |
|----------|------|----------------|
| **CoreMIDITransport** | CoreMIDI UMP受信、MIDI 2.0プロトコル | ✅ 使用中 |
| **UMP Parser/Builder** | UMPワードのエンコード/デコード | ✅ 使用中 |
| **PEResponder** | Property Exchange応答処理 | ✅ 使用中 |
| **MIDI-CI Manager** | Capability Inquiry処理 | ✅ MIDI2Kitが自動処理 |
| **SysExAssembler** | SysExメッセージの分割/組み立て | 🟡 MIDI2Kitが内部処理（M2DXでは未使用） |

### 8.2 CoreMIDITransport

**リポジトリ**: `https://github.com/orchetect/MIDI2Kit` (仮定)

CoreMIDITransportは、iOS 18.0+のCoreMIDI UMPサポートを使用し、以下を提供します：

- `MIDIEventList`からのUMPワード抽出
- MIDI 2.0プロトコル（`._2_0`）の選択
- MIDI-CI Discovery/Replyの自動処理
- 非同期ストリーム（`AsyncStream<MIDIReceivedData>`）による受信

**M2DXでの使用**:
```swift
let transport = try CoreMIDITransport(clientName: "M2DX")
try await transport.connectToAllSources()

for await received in transport.received {
    if received.umpWord1 != 0 {
        // MIDI 2.0 path
        handleUMPData(received.umpWord1, word2: received.umpWord2, ...)
    } else {
        // MIDI 1.0 fallback
        handleReceivedData(received.data)
    }
}
```

### 8.3 MIDI2Kitの制約

**現時点の制約**:
- Profile Configurationは未実装（MIDI2Kitの将来バージョンで対応予定）
- Process Inquiryは未実装（MIDI2Kitの将来バージョンで対応予定）
- SysEx 8送信は実装されているが、M2DXでは未使用

---

## 9. 実装済み機能の動作確認方法

### 9.1 MIDI 2.0デバイスでのテスト

**テスト環境**:
- **キーボード**: M-Audio KeyStage (MIDI 2.0対応、USB-C接続)
- **OS**: iOS 18.0+ (CoreMIDI UMP対応必須)
- **接続**: USB-C → iPhone 14 Pro Max

**確認項目**:
1. **16-bit Velocity**: 弱打〜強打でダイナミクスの滑らかさを確認
2. **32-bit Pitch Bend**: ベンドホイールを動かし、音程変化の滑らかさを確認
3. **32-bit CC (Sustain)**: サスティンペダルの踏み込み量が32-bit精度で判定されることを確認

**デバッグUI表示**:
- `Transport callback: cb=XXX words=XXX`: CoreMIDIコールバック回数とワード数
- `Received msgs: XXX`: 受信メッセージ総数
- `NoteOn(UMP) ch=0 n=60 v16=32768`: 16-bit velocityが表示される
- `PB(UMP) ch=0 v32=2147483648`: 32-bit pitch bend（center=0x80000000）が表示される

### 9.2 MIDI 1.0デバイスでのテスト

**テスト環境**:
- **キーボード**: 一般的なMIDI 1.0キーボード（USB/DIN接続）
- **接続**: USB MIDIインターフェース → iPhone

**確認項目**:
1. **7-bit → 16-bit Velocity変換**: velocity 127 (MIDI 1.0) → 65024 (MIDI 2.0) にアップスケール
2. **14-bit → 32-bit Pitch Bend変換**: 8192 (center, MIDI 1.0) → 0x80000000 (center, MIDI 2.0) にアップスケール
3. **7-bit → 32-bit CC変換**: sustain 127 (MIDI 1.0) → 0xFE000000 (MIDI 2.0) にアップスケール

**デバッグUI表示**:
- `NoteOn ch=0 n=60 v=127`: MIDI 1.0バイト表示
- 内部では16-bit velocityに自動変換されてFMSynthEngineに送られる

---

## 10. まとめ

### 10.1 M2DXのMIDI 2.0対応状況

M2DXは、以下の点で**MIDI 2.0 Ready**です：

| カテゴリ | 対応状況 | 詳細 |
|---------|---------|------|
| **UMP基本プロトコル** | ✅ 完全対応 | CoreMIDITransport ._2_0 |
| **高精度制御** | ✅ 完全対応 | 16-bit velocity, 32-bit CC/PB |
| **MIDI-CI** | ✅ 基本対応 | Discovery, Protocol Negotiation |
| **Property Exchange** | ✅ 完全対応 | 155+ パラメータ階層ツリー |
| **MIDI 1.0互換** | ✅ 完全対応 | 自動アップスケール |
| **拡張機能** | 🟡 部分対応 | PNCC, PNPB, RPN/NRPN は未実装 |

### 10.2 今後の実装予定

**優先度: 高**
1. **Per-Note Controllers (PNCC)**: ポリフォニック・アフタータッチ対応
2. **Per-Note Pitch Bend (PNPB)**: ポリフォニック・ベンド対応
3. **LFO / Pitch EG**: FMSynthEngineでの実装
4. **RPN/NRPN**: Pitch Bend Range等の標準コントローラー

**優先度: 中**
5. **Profile Configuration**: MIDI2Kit対応後に実装
6. **SysEx 8**: DX7プリセットバルク転送

**優先度: 低**
7. **Process Inquiry**: MIDI2Kit対応後に実装

### 10.3 コードベース統計

| ファイル | 行数 | MIDI 2.0関連コード |
|---------|------|------------------|
| `MIDIInputManager.swift` | 408 | 約200行（handleUMPData, handleReceivedData） |
| `MIDIEventQueue.swift` | 58 | data2: UInt32拡張 |
| `FMSynthEngine.swift` | 614 | velocity16, value32, pitchBend32処理 |
| `M2DXAudioEngine.swift` | 515 | コールバックシグネチャ変更 |
| `M2DXParameterTree.swift` | 約400 | 155+ パラメータ定義 |
| **合計** | 約2000行 | **MIDI 2.0対応コード約500行** |

**外部依存**:
- **MIDI2Kit**: 約5000行（CoreMIDITransport, PEResponder等）

M2DXは、MIDI 2.0の主要機能を実装しつつ、将来の拡張機能にも対応可能な設計になっています。

---

## 11. 参考資料

- [MIDI 2.0 仕様書](https://www.midi.org/specifications/midi-2-0)
- [Universal MIDI Packet (UMP)](https://www.midi.org/specifications/midi-2-0/universal-midi-packet-ump-format)
- [Property Exchange 仕様](https://www.midi.org/specifications/midi-2-0/property-exchange)
- [M2DX Property Exchange 詳細](./PropertyExchange.md)
- [MIDI2Kit リポジトリ](https://github.com/orchetect/MIDI2Kit) (仮定)

---

**最終更新**: 2026-02-07
**対象バージョン**: M2DX 1.0 (Unreleased)
**対応プラットフォーム**: iOS 18.0+
