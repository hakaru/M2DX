# M2DX アーキテクチャ仕様書

## 概要

M2DXは**Pure Swift 6.1+**で実装された、MIDI 2.0準拠のiOS DX7互換FMシンセサイザーです。6オペレーター・32アルゴリズムのFM合成エンジンを持ち、AVAudioSourceNodeによる最小レイテンシ再生と、MIDI2Kit + Property Exchangeによる次世代パラメータ制御を実現しています。

### 技術スタック

- **言語**: Swift 6.1+ (strict concurrency mode)
- **フレームワーク**: SwiftUI, AVFoundation, CoreMIDI
- **プラットフォーム**: iOS 18.0+, macOS 14.0+
- **アーキテクチャパターン**: MV (Model-View) パターン、SwiftUI標準状態管理
- **並行性**: Swift Concurrency (async/await, @MainActor, Actor, NSLock)
- **オーディオAPI**: AVAudioSourceNode (CoreAudio直接レンダー)
- **MIDI**: MIDI2Kit (MIDI 2.0 UMP, MIDI-CI Property Exchange)

---

## システム構成

```
M2DX (iOS/macOS App Shell)
  └── M2DXPackage (Swift Package)
       ├── M2DXCore (Data Models)
       │   ├── OperatorParameters, EnvelopeParameters, KeyboardLevelScaling
       │   ├── DX7Preset, DX7OperatorPreset, PresetCategory
       │   ├── DX7Algorithms (アルゴリズム定義)
       │   ├── DX7FactoryPresets
       │   └── PropertyExchange/
       │       ├── M2DXParameterAddressMap
       │       ├── M2DXParameterTree
       │       ├── M2DXPEBridge
       │       └── M2DXPEResource
       └── M2DXFeature (UI + Engine)
           ├── M2DXRootView (SwiftUI main UI)
           ├── FMSynthEngine (Pure Swift FM synth)
           ├── M2DXAudioEngine (AVAudioSourceNode wrapper)
           ├── MIDIInputManager (MIDI 2.0 via MIDI2Kit)
           ├── MIDIEventQueue (Lock-free MIDI buffer)
           └── UI Views (Algorithm, Envelope, Keyboard, Preset, Settings)
```

---

## 1. データモデル層 (M2DXCore)

### 1.1 プリセットモデル

#### DX7Preset
DX7互換のプリセット全体を表現するモデル。

**主要プロパティ**:
- `name: String` - プリセット名 (最大10文字)
- `operators: [DX7OperatorPreset]` - 6個のオペレータ設定
- `algorithm: Int` - アルゴリズム番号 (1-32)
- `feedback: Int` - フィードバックレベル (0-7)
- `category: PresetCategory` - カテゴリ分類

#### DX7OperatorPreset
単一オペレータの設定。

**主要プロパティ**:
- `outputLevel: Int` - 出力レベル (0-99)
- `frequencyCoarse: Int` - 周波数粗調整 (0-31)
- `frequencyFine: Int` - 周波数微調整 (0-99)
- `detune: Int` - デチューン (-7〜+7)
- `envelope: EnvelopeParameters` - ADSR+エンベロープ
- `keyboardLevelScaling: KeyboardLevelScaling` - KLS設定

#### EnvelopeParameters
DX7スタイル4-Rate/4-Levelエンベロープ。

**プロパティ**:
- `rates: [Int]` - 4つのレート (0-99)
- `levels: [Int]` - 4つのレベル (0-99)

**ステージ遷移**:
```
Level
  L1 ┐
     │╲
     │ ╲
  L2 │  ┐
     │  │╲
  L3 │  │ ┐━━━━━━━━━━━━ (Sustain)
     │  │ │             ╲
  L4 │  │ │             │
   0 └──┴─┴─────────────┴──→ Time
     R1 R2 R3 (Hold)     R4
```

### 1.2 アルゴリズム定義

#### DX7Algorithms
32個のDX7互換アルゴリズムを静的に定義。

**代表例**:
- Algorithm 1: OP6→5→4→3→2→1 (フルシリアルチェーン)
- Algorithm 5: 3ペア並列 (OP6→5, OP4→3, OP2→1)
- Algorithm 32: 全6オペレータ並列

### 1.3 Property Exchange

MIDI 2.0 Property Exchange準拠のパラメータツリー定義。

**主要クラス**:
- `M2DXParameterAddressMap` - パラメータアドレス定義
- `M2DXParameterTree` - 階層構造ツリー
- `M2DXPEBridge` - MIDI-CI PE Responder実装
- `M2DXPEResource` - JSONリソース定義

---

## 2. DSPエンジン層 (FMSynthEngine)

### 2.1 FMSynthEngine

Pure Swift実装のFM合成エンジン (約536行)。

**主要機能**:
- 6オペレータFM合成 (DX7互換)
- 32アルゴリズム (静的ルーティングテーブル)
- 16音ポリフォニー
- サスティンペダル (CC64)対応
- ピッチベンド (±2半音)対応
- ソフトクリッピング (Pade近似tanh)

#### 定数定義

```swift
private let kNumOperators = 6          // DX7互換
private let kNumVoices = 16            // 16音ポリフォニー
private let kSampleRate: Float = 48000.0
private let kVoiceNormalizationScale: Float = 3.0  // ヘッドルーム確保
```

#### アルゴリズムルーティングテーブル

**OpRoute構造体**:
```swift
struct OpRoute {
    let src0: Int?   // 第1変調ソース (オペレータindex)
    let src1: Int?   // 第2変調ソース
    let src2: Int?   // 第3変調ソース
    let isCarrier: Bool  // キャリア判定
}
```

**AlgorithmRoute構造体**:
```swift
struct AlgorithmRoute {
    let ops: (OpRoute, OpRoute, OpRoute, OpRoute, OpRoute, OpRoute)
    let normalizationFactor: Float
}
```

**例: Algorithm 1 (フルシリアル)**:
```swift
AlgorithmRoute(
    ops: (
        OpRoute(src0: 1, src1: nil, src2: nil, isCarrier: true),  // OP1 (carrier)
        OpRoute(src0: 2, src1: nil, src2: nil, isCarrier: false), // OP2
        OpRoute(src0: 3, src1: nil, src2: nil, isCarrier: false), // OP3
        OpRoute(src0: 4, src1: nil, src2: nil, isCarrier: false), // OP4
        OpRoute(src0: 5, src1: nil, src2: nil, isCarrier: false), // OP5
        OpRoute(src0: nil, src1: nil, src2: nil, isCarrier: false) // OP6 (mod)
    ),
    normalizationFactor: 0.707
)
```

#### FMOp (オペレータ)

**プロパティ**:
```swift
struct FMOp {
    var phase: Float = 0.0           // 位相アキュムレータ (0.0-1.0)
    var phaseInc: Float = 0.0        // 位相増分 (frequency/sampleRate)
    var feedback1: Float = 0.0       // 1サイクル遅延バッファ
    var level: Float = 0.0           // 出力レベル (0.0-1.0)
    var baseFrequency: Float = 0.0   // ベース周波数 (ピッチベンド用)
    var envelope = Envelope()        // エンベロープジェネレータ
}
```

**主要メソッド**:
- `mutating func process(mod0: Float, mod1: Float, mod2: Float, fb: Float) -> Float`
  - 3ソース変調 + 自己フィードバック対応
  - サイン波生成: `sin((phase + mod0 + mod1 + mod2 + fb*feedback1) * 2π)`
  - エンベロープ適用: `output *= envelope.process() * level`

- `mutating func applyPitchBend(_ factor: Float)`
  - 周波数を動的に再計算: `phaseInc = baseFrequency * factor / sampleRate`

#### Envelope (エンベロープジェネレータ)

**ステージ定義**:
```swift
enum EnvStage {
    case idle, attack, decay1, decay2, sustain, release
}
```

**レート→係数変換** (DX7互換):
```swift
func calcCoeff(_ rate: Float) -> Float {
    let timeInSeconds = 10.0 * exp(-0.069 * rate)
    return 1.0 - exp(-1.0 / (timeInSeconds * kSampleRate))
}
```

- Rate 99 (最速): 約0.01秒
- Rate 0 (最遅): 約10秒

**エンベロープ処理** (1次ローパス近似):
```swift
level += coeff * (target - level)
```

#### Voice (ボイス)

**プロパティ**:
```swift
struct Voice {
    var note: UInt8 = 0
    var velocity16: UInt16 = 0
    var active = false
    var sustained = false              // サスティンペダル状態
    var pitchBendFactor: Float = 1.0   // ピッチベンド係数
    var ops = (FMOp(), FMOp(), FMOp(), FMOp(), FMOp(), FMOp())  // 6オペレータ
}
```

**主要メソッド**:
- `mutating func process() -> Float`
  - アルゴリズムルーティングテーブルからオペレータ接続情報を取得
  - 6オペレータを順次処理
  - 正規化係数を適用

- `mutating func noteOn(note: UInt8, velocity16: UInt16, algorithm: Int, ...)`
  - 全オペレータのエンベロープをトリガー
  - 周波数計算: `baseFreq = 440.0 * pow(2.0, (note - 69) / 12.0)`

#### FMSynthEngine本体

**スレッドセーフ**:
```swift
private let lock = NSLock()  // render()とパラメータ変更メソッドで共有
```

**主要メソッド**:
- `func render(buffer: UnsafeMutablePointer<Float>, count: Int)`
  - MIDIEventQueueから全イベントをdrain
  - 全ボイスを処理: `output += voice.process()`
  - 動的正規化: `output /= sqrt(activeCount) * kVoiceNormalizationScale`
  - ソフトクリッピング: `output = tanhApprox(output) * masterVolume`

- ボイススティーリング:
  ```swift
  private func allocateVoice() -> Int {
      // 1. 非アクティブボイスを検索
      // 2. なければsustained=falseかつ最小エンベロープレベルのボイス
      // 3. なければ最古のボイス
  }
  ```

### 2.2 ソフトクリッピング

Pade近似による高速tanh:
```swift
private func tanhApprox(_ x: Float) -> Float {
    let x2 = x * x
    return x * (27.0 + x2) / (27.0 + 9.0 * x2)
}
```

- 入力範囲: -∞〜+∞
- 出力範囲: -1.0〜+1.0
- 飽和特性により自然なオーバードライブ感

---

## 3. オーディオエンジン層 (M2DXAudioEngine)

### 3.1 M2DXAudioEngine

**役割**: AVAudioEngineとFMSynthEngineの統合管理。

**アクター隔離**: `@Observable @MainActor`

**主要プロパティ**:
```swift
@Observable @MainActor
class M2DXAudioEngine {
    private let engine = AVAudioEngine()
    private let synthEngine = FMSynthEngine()
    private let eventQueue = MIDIEventQueue()
    private var sourceNode: AVAudioSourceNode?

    var isRunning = false
    var selectedOutputDevice: String? = nil
}
```

**初期化**:
```swift
init() {
    setupAudioSession()  // 48kHz, 5ms IOBufferDuration
    setupSourceNode()    // AVAudioSourceNode作成
    setupOutputDeviceObserver()
}
```

**AVAudioSourceNode生成** (nonisolated static):
```swift
nonisolated static func makeSourceNode(
    synthEngine: FMSynthEngine,
    eventQueue: MIDIEventQueue
) -> AVAudioSourceNode {
    let format = AVAudioFormat(
        standardFormatWithSampleRate: 48000,
        channels: 2
    )!

    return AVAudioSourceNode(format: format) { (isSilence, timeStamp, frameCount, outputData) -> OSStatus in
        let buffer = outputData.pointee.mBuffers
        let left = buffer.mData!.assumingMemoryBound(to: Float.self)
        let right = left.advanced(by: Int(frameCount))

        synthEngine.render(buffer: left, count: Int(frameCount))
        // Stereo copy
        for i in 0..<Int(frameCount) {
            right[i] = left[i]
        }

        isSilence.pointee = false
        return noErr
    }
}
```

**オーディオセッション設定**:
```swift
func setupAudioSession() {
    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(.playback, mode: .default)
    try? session.setPreferredSampleRate(48000.0)
    try? session.setPreferredIOBufferDuration(0.005)  // 5ms = 最小レイテンシ
    try? session.setActive(true)
}
```

**MIDI処理メソッド**:
```swift
func noteOn(note: UInt8, velocity16: UInt16) {
    eventQueue.enqueue(.noteOn, data1: note, data2: UInt32(velocity16))
}

func noteOff(note: UInt8) {
    eventQueue.enqueue(.noteOff, data1: note, data2: 0)
}

func controlChange(cc: UInt8, value32: UInt32) {
    eventQueue.enqueue(.controlChange, data1: cc, data2: value32)
}

func pitchBend(value32: UInt32) {
    eventQueue.enqueue(.pitchBend, data1: 0, data2: value32)
}
```

**プリセット読み込み**:
```swift
func loadPreset(_ preset: DX7Preset) {
    synthEngine.setAlgorithm(preset.algorithm)
    for (i, op) in preset.operators.enumerated() {
        synthEngine.setOpLevel(i, Float(op.outputLevel) / 99.0)
        synthEngine.setOpRatio(i, op.frequencyRatio)
        // ... エンベロープ等
    }
}
```

---

## 4. MIDI入力層 (MIDIInputManager)

### 4.1 MIDIInputManager

**役割**: CoreMIDI経由のMIDI 2.0 UMP受信、デコード、コールバック配信。

**アクター隔離**: `@Observable @MainAactor`

**依存関係**: MIDI2Kit (../../MIDI2Kit)

**主要プロパティ**:
```swift
@Observable @MainActor
class MIDIInputManager {
    private var transport: CoreMIDITransport?
    var onNoteOn: ((UInt8, UInt16) -> Void)?        // (note, velocity16)
    var onNoteOff: ((UInt8) -> Void)?
    var onControlChange: ((UInt8, UInt32) -> Void)?  // (cc, value32)
    var onPitchBend: ((UInt32) -> Void)?             // (value32)

    var connectedSources: [String] = []
    var debugMessages: [String] = []
}
```

**初期化** (MIDI 2.0プロトコル):
```swift
init() {
    transport = CoreMIDITransport(
        mode: .device,
        protocol: ._2_0  // MIDI 2.0 UMP
    )
    transport?.connect()
    connectToAllSources()
}
```

**MIDI 2.0 UMP デコード**:
```swift
private func handleReceivedData(_ data: MIDIReceivedData) {
    // MIDI 2.0 Channel Voice (type 0x4)
    if data.umpWord1 != 0 {
        handleUMPData(data.umpWord1, data.umpWord2)
        return
    }

    // MIDI 1.0フォールバック (type 0x2)
    handleMIDI1Data(data.bytes)
}
```

**handleUMPData** (MIDI 2.0 フルプレシジョン):
```swift
private func handleUMPData(_ word1: UInt32, _ word2: UInt32) {
    let mt = (word1 >> 28) & 0xF
    guard mt == 0x4 else { return }  // Channel Voice type

    let status = (word1 >> 16) & 0xFF
    let channel = (word1 >> 16) & 0x0F
    let data1 = UInt8((word1 >> 8) & 0xFF)

    switch status & 0xF0 {
    case 0x90:  // Note On
        let velocity16 = UInt16(word2 >> 16)  // 16-bit velocity
        onNoteOn?(data1, velocity16)

    case 0x80:  // Note Off
        onNoteOff?(data1)

    case 0xB0:  // Control Change
        let value32 = word2  // 32-bit CC value
        onControlChange?(data1, value32)

    case 0xE0:  // Pitch Bend
        let value32 = word2  // 32-bit pitch bend
        onPitchBend?(value32)

    default:
        break
    }
}
```

**handleMIDI1Data** (MIDI 1.0 → フルプレシジョンへアップスケール):
```swift
private func handleMIDI1Data(_ bytes: [UInt8]) {
    guard bytes.count >= 2 else { return }
    let status = bytes[0] & 0xF0
    let data1 = bytes[1]

    switch status {
    case 0x90:
        let velocity7 = bytes[2]
        let velocity16 = UInt16(velocity7) << 9  // 7→16bit変換
        onNoteOn?(data1, velocity16)

    case 0xB0:
        let value7 = bytes[2]
        let value32 = UInt32(value7) << 25  // 7→32bit変換
        onControlChange?(data1, value32)

    case 0xE0:
        let lsb = bytes[2]
        let msb = bytes[3]
        let value14 = UInt32(lsb) | (UInt32(msb) << 7)
        let value32 = value14 << 18  // 14→32bit変換
        onPitchBend?(value32)

    default:
        break
    }
}
```

### 4.2 MIDI-CI Property Exchange

**M2DXPEBridge**:
- MIDI-CI PE Responder実装
- パラメータツリーJSON配信
- Get/Set Property Exchange対応

**対応プロパティ**:
- `X-M2DX-ParameterTree` - 全パラメータ階層構造
- `X-M2DX-CurrentPreset` - 現在のプリセット状態

---

## 5. MIDIイベントキュー (MIDIEventQueue)

### 5.1 設計

**ロックフリー実装** (OSAllocatedUnfairLock):
```swift
final class MIDIEventQueue {
    private let lock = OSAllocatedUnfairLock()
    private var buffer: [MIDIEvent] = []
    private let capacity = 256
}
```

**イベント定義**:
```swift
struct MIDIEvent {
    enum Kind {
        case noteOn, noteOff, controlChange, pitchBend
    }
    let kind: Kind
    let data1: UInt8   // note, cc number
    let data2: UInt32  // velocity16, cc32, pitchBend32
}
```

**主要メソッド**:
```swift
func enqueue(_ kind: Kind, data1: UInt8, data2: UInt32) {
    lock.withLock {
        guard buffer.count < capacity else { return }  // silent overflow drop
        buffer.append(MIDIEvent(kind: kind, data1: data1, data2: data2))
    }
}

func drain() -> [MIDIEvent] {
    lock.withLock {
        let events = buffer
        buffer.removeAll(keepingCapacity: true)
        return events
    }
}
```

---

## 6. データフロー

### 6.1 MIDI入力パス

```
External MIDI Controller (MIDI 2.0 UMP)
  → CoreMIDI
  → CoreMIDITransport (MIDI2Kit, ._2_0 protocol)
  → handleEventList (type 0x4 Channel Voice)
  → MIDIInputManager.handleUMPData()
  → callbacks (onNoteOn/Off/CC/PitchBend)
  → M2DXAudioEngine.noteOn/Off/controlChange/pitchBend()
  → MIDIEventQueue.enqueue()
```

### 6.2 オーディオレンダーパス

```
AVAudioSourceNode render callback (CoreAudio thread)
  → MIDIEventQueue.drain()  // lock.withLock
  → FMSynthEngine.render()  // NSLock
  → Voice.process() × 16
  → FMOp.process() × 6
  → Envelope.process()
  → 動的正規化 (sqrt(activeCount) * kVoiceNormalizationScale)
  → ソフトクリッピング (tanhApprox)
  → masterVolume適用
  → CoreAudio output buffer
```

### 6.3 タッチキーボードパス

```
SwiftUI TouchKeyboardView (onTap)
  → M2DXAudioEngine.noteOn(note, UInt16(velocity) << 9)
  → MIDIEventQueue.enqueue(.noteOn, ...)
  → (同じrender path)
```

---

## 7. 並行性モデル

### 7.1 アクター隔離

| クラス | 隔離 | 理由 |
|-------|------|------|
| M2DXAudioEngine | @MainActor | UI状態更新、AVAudioEngine操作 |
| MIDIInputManager | @MainActor | コールバック配信、UI表示更新 |
| FMSynthEngine | NSLock | オーディオスレッド・UIスレッド共有 |
| MIDIEventQueue | OSAllocatedUnfairLock | UI→Audio スレッド間通信 |
| UI Views | @MainActor | SwiftUI標準 |

### 7.2 スレッド構成

```
Main Thread (@MainActor)
  - SwiftUI UI更新
  - M2DXAudioEngine.noteOn/Off()
  - MIDIInputManager.handleReceivedData()
  - MIDIEventQueue.enqueue()  ← OSAllocatedUnfairLock

CoreMIDI Callback Thread
  - handleEventList()
  - receivedContinuation.yield()  → Main Thread

CoreAudio Render Thread (Realtime)
  - AVAudioSourceNode renderBlock
  - MIDIEventQueue.drain()  ← OSAllocatedUnfairLock
  - FMSynthEngine.render()  ← NSLock
  - Voice.process() × 16
```

### 7.3 ロック戦略

**NSLock (FMSynthEngine)**:
- `render()`: オーディオスレッドから呼び出し
- パラメータ変更メソッド: UIスレッドから呼び出し
- 保持時間: 数マイクロ秒 (パラメータコピーのみ)

**OSAllocatedUnfairLock (MIDIEventQueue)**:
- `enqueue()`: UIスレッド
- `drain()`: オーディオスレッド
- 保持時間: 数ナノ秒 (配列操作のみ)

---

## 8. 依存関係

### 8.1 外部依存

**MIDI2Kit** (local: ../../MIDI2Kit):
- CoreMIDITransport: MIDI 2.0 UMP受信
- Property Exchange: MIDI-CI PE Responder
- AsyncStream: MIDIデータ配信

**標準フレームワーク**:
- AVFoundation: AVAudioEngine, AVAudioSourceNode
- CoreMIDI: MIDIPacketList (MIDI2Kitが使用)
- SwiftUI: UI全般

### 8.2 内部依存

```
M2DXFeature (UI + Engine)
  → M2DXCore (Data Models)

M2DXAudioEngine
  → FMSynthEngine
  → MIDIEventQueue

MIDIInputManager
  → MIDI2Kit (CoreMIDITransport)
  → M2DXPEBridge

FMSynthEngine
  ← (no external dependency, pure Swift)
```

---

## 9. ビルド設定

### 9.1 プロジェクト構造

```
M2DX.xcworkspace/
├── M2DX.xcodeproj/           (App shell)
├── M2DXPackage/              (Swift Package)
│   ├── Package.swift
│   ├── Sources/
│   │   ├── M2DXCore/
│   │   └── M2DXFeature/
│   └── Tests/
│       └── M2DXCoreTests/
└── Config/
    ├── Debug.xcconfig
    ├── Release.xcconfig
    ├── Shared.xcconfig
    └── M2DX.entitlements
```

### 9.2 Swift設定

**Package.swift**:
```swift
// Swift 6.1+, strict concurrency
swiftSettings: [
    .enableExperimentalFeature("StrictConcurrency")
]
```

**プラットフォーム**:
- iOS 18.0+
- macOS 14.0+

### 9.3 Entitlements

```xml
<key>com.apple.security.app-sandbox</key>
<false/>
<key>com.apple.developer.audio.core-midi</key>
<true/>
```

---

## 10. パフォーマンス最適化

### 10.1 最小レイテンシ

**AVAudioSourceNode採用理由**:
- CoreAudioレンダーコールバック直接利用
- バッファキューイングオーバーヘッドゼロ
- IOBufferDuration (5ms) がそのままレイテンシになる

**旧方式 (AVAudioPlayerNode)**:
- バッファスケジューリング: 256フレーム × 2 = 約10.7ms
- Task{}非同期ホップ: 数ms追加
- 合計: 約15ms

**新方式 (AVAudioSourceNode)**:
- IOBufferDuration: 5ms
- 直接yield: ≈0ms
- 合計: 約5ms

### 10.2 メモリ最適化

**Tupleベースのオペレータ配列**:
```swift
var ops = (FMOp(), FMOp(), FMOp(), FMOp(), FMOp(), FMOp())
```
- スタック配列 (ヒープアロケーションなし)
- キャッシュ効率良好

**静的ルーティングテーブル**:
```swift
private let kAlgorithmTable: [AlgorithmRoute] = [ ... ]
```
- 実行時アルゴリズム切り替えなしでルーティング変更
- 分岐予測最適化

### 10.3 リアルタイム安全性

**オーディオスレッドで禁止されている操作を回避**:
- メモリアロケーション: なし (事前確保済み)
- ロック: NSLock最小限使用 (数μs)
- System Call: なし

---

## 11. 技術的特徴

### 11.1 Pure Swift実装

**利点**:
- 型安全性: コンパイル時エラー検出
- メモリ安全性: ARC、所有権管理
- 並行性: Swift Concurrency統合
- デバッグ容易性: LLDBフル対応

**課題と対策**:
- パフォーマンス: `-O` 最適化で C++ と同等
- リアルタイム性: NSLock最小化、ロックフリーキュー

### 11.2 MIDI 2.0対応

**フルプレシジョン処理**:
- 16-bit velocity (0-65535)
- 32-bit CC (0-4294967295)
- 32-bit pitch bend (center=0x80000000)

**MIDI 1.0互換**:
- 7/14-bit → 16/32-bitアップスケール
- CoreMIDIが自動プロトコル変換

### 11.3 DX7互換性

**プリセット互換**:
- 32アルゴリズム (DX7と同一)
- 6オペレータ構成
- 4-Rate/4-Level Envelope
- SysExフォーマット互換 (予定)

---

## 12. 今後の拡張計画

### 12.1 実装予定機能

- **LFO**: Pitch, Amplitude, Filter Cutoff変調
- **Velocity Sensitivity**: オペレータごとのベロシティカーブ
- **Portamento**: グライド効果
- **SysEx Import/Export**: DX7バンクファイル読み込み
- **AU/AUv3対応**: DAW統合

### 12.2 最適化予定

- **SIMD化**: 複数オペレータ並列処理
- **Accelerate Framework**: vDSP使用
- **Metal DSP**: GPU FM合成 (実験的)

---

## 13. まとめ

M2DXは以下の技術要素で構成されています:

**言語・フレームワーク**:
- Pure Swift 6.1+ (strict concurrency)
- SwiftUI (MV pattern)
- AVFoundation (AVAudioSourceNode)
- MIDI2Kit (MIDI 2.0 UMP, PE)

**DSP実装**:
- FMSynthEngine: 6-op, 32-algorithm, 16-voice
- DX7互換エンベロープ
- ソフトクリッピング
- 動的正規化

**並行性**:
- @MainActor: UI + マネージャー層
- NSLock: FMSynthEngine (最小限)
- OSAllocatedUnfairLock: MIDIEventQueue (ロックフリー)

**最小レイテンシ**:
- AVAudioSourceNode: CoreAudio直接レンダー
- 約5ms (IOBufferDuration)

DX7互換のFM合成を保ちつつ、Swift 6の型安全性・並行性とMIDI 2.0の高解像度制御を実現した、次世代Pure Swiftシンセサイザーのリファレンス実装です。
