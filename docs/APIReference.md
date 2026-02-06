# M2DX API リファレンス

本ドキュメントは、M2DXプロジェクトの主要な公開APIを説明します。

---

## 目次

- [M2DXFeature モジュール](#m2dxfeature-モジュール)
  - [FMSynthEngine](#fmsynthengine)
  - [M2DXAudioEngine](#m2dxaudioengine)
  - [MIDIInputManager](#midiinputmanager)
  - [MIDIEventQueue](#midieventqueue)
- [M2DXCore モジュール](#m2dxcore-モジュール)
  - [OperatorParameters](#operatorparameters)
  - [EnvelopeParameters](#envelopeparameters)
  - [KeyboardLevelScaling](#keyboardlevelscaling)
  - [DX7Preset](#dx7preset)
  - [DX7OperatorPreset](#dx7operatorpreset)

---

## M2DXFeature モジュール

### FMSynthEngine

Pure-Swift FM合成エンジン。AVAudioSourceNodeのレンダーコールバックから呼び出され、最小レイテンシで動作します。

**スレッドセーフティ**: `NSLock` による保護。複数スレッドから安全にアクセス可能です。

#### 主要プロパティ

```swift
let midiQueue: MIDIEventQueue
```

MIDI イベントキュー（UI → オーディオスレッド）。

#### セットアップメソッド

```swift
func setSampleRate(_ sr: Float)
```

サンプルレートを設定します。全ボイスのエンベロープ計算が更新されます。

**パラメータ**:
- `sr`: サンプルレート（例: 48000.0）

---

```swift
func setAlgorithm(_ alg: Int)
```

アルゴリズムを設定します（0-31、DX7互換）。

**パラメータ**:
- `alg`: アルゴリズム番号（0-31）。範囲外の値は自動的にクランプされます。

---

```swift
func setMasterVolume(_ vol: Float)
```

マスターボリュームを設定します。

**パラメータ**:
- `vol`: ボリューム（0.0-1.0）。範囲外の値は自動的にクランプされます。

---

#### オペレータパラメータ設定メソッド

```swift
func setOperatorLevel(_ opIndex: Int, level: Float)
```

指定オペレータのレベルを設定します。

**パラメータ**:
- `opIndex`: オペレータ番号（0-5、0=OP1）
- `level`: レベル（0.0-1.0）

---

```swift
func setOperatorRatio(_ opIndex: Int, ratio: Float)
```

指定オペレータの周波数比率を設定します。

**パラメータ**:
- `opIndex`: オペレータ番号（0-5）
- `ratio`: 周波数比率（例: 1.0 = 基本周波数、2.0 = 1オクターブ上）

---

```swift
func setOperatorDetune(_ opIndex: Int, cents: Float)
```

指定オペレータのデチューンを設定します。

**パラメータ**:
- `opIndex`: オペレータ番号（0-5）
- `cents`: デチューン量（セント単位、±50推奨）

---

```swift
func setOperatorFeedback(_ opIndex: Int, feedback: Float)
```

指定オペレータのフィードバックを設定します。

**パラメータ**:
- `opIndex`: オペレータ番号（0-5）
- `feedback`: フィードバック量（0.0-1.0）

---

```swift
func setOperatorEGRates(_ opIndex: Int, r1: Float, r2: Float, r3: Float, r4: Float)
```

指定オペレータのエンベロープレートを設定します（DX7形式）。

**パラメータ**:
- `opIndex`: オペレータ番号（0-5）
- `r1`, `r2`, `r3`, `r4`: エンベロープレート（0-99、DX7互換）

---

```swift
func setOperatorEGLevels(_ opIndex: Int, l1: Float, l2: Float, l3: Float, l4: Float)
```

指定オペレータのエンベロープレベルを設定します。

**パラメータ**:
- `opIndex`: オペレータ番号（0-5）
- `l1`, `l2`, `l3`, `l4`: エンベロープレベル（0.0-1.0）

---

#### レンダリングメソッド

```swift
func render(into bufferL: UnsafeMutablePointer<Float>,
            bufferR: UnsafeMutablePointer<Float>,
            frameCount: Int)
```

オーディオフレームをレンダリングします。CoreAudioのリアルタイムスレッドから呼び出されます。

**スレッドセーフティ**: このメソッドは内部でロックを取得するため、オーディオスレッドから安全に呼び出せます。

**パラメータ**:
- `bufferL`: 左チャンネルバッファ（Float配列へのポインタ）
- `bufferR`: 右チャンネルバッファ（Float配列へのポインタ）
- `frameCount`: レンダリングするフレーム数

**動作**:
1. MIDIイベントキューからイベントをドレイン
2. ノートオン/オフ、CC、ピッチベンドを処理
3. 全アクティブボイスをレンダリング
4. ソフトクリッピング（tanh近似）を適用

---

#### 内部型

##### `Envelope`

DX7形式の4レート/4レベルエンベロープジェネレータ。

**ステージ**: `idle`, `attack`, `decay1`, `decay2`, `sustain`, `release`

##### `FMOp`

単一のFMオペレータ（サイン波オシレータ + エンベロープ + フィードバック）。

##### `Voice`

ポリフォニックボイス（6オペレータ、テーブル駆動アルゴリズムルーティング）。

##### `OpRoute`

オペレータルーティング情報（変調ソース3つ + キャリアフラグ）。

##### `AlgorithmRoute`

完全なアルゴリズム定義（6オペレータ分のルーティング + 正規化係数）。

---

### M2DXAudioEngine

スタンドアロンオーディオエンジン。AVAudioSourceNode経由でFMSynthEngineを駆動し、最小レイテンシを実現します。

**スレッドセーフティ**: `@MainActor` 隔離。すべてのメソッドはメインスレッドから呼び出す必要があります。

**Observable**: SwiftUIの `@Observable` マクロを使用。プロパティ変更が自動的にUIに反映されます。

#### 監視可能プロパティ

```swift
private(set) var isRunning: Bool
```

エンジンが動作中かどうか。

---

```swift
var algorithm: Int
```

現在のアルゴリズム（0-31）。変更すると自動的に `synth.setAlgorithm()` が呼ばれます。

---

```swift
var masterVolume: Float
```

マスターボリューム（0.0-1.0）。変更すると自動的に `synth.setMasterVolume()` が呼ばれます。

---

```swift
var operatorLevels: [Float]
```

オペレータレベル配列（6要素、各0.0-1.0）。変更すると自動的に全オペレータのレベルが更新されます。

---

```swift
private(set) var errorMessage: String?
```

初期化エラーメッセージ（エラーがない場合は `nil`）。

---

```swift
private(set) var currentOutputDevice: String
```

現在のオーディオ出力デバイス名。

---

#### エンジン制御メソッド

```swift
func start() async
```

オーディオエンジンを開始します。

**動作**:
- iOS: AVAudioSessionを `.playback` カテゴリで構成（48kHz、5msバッファ）
- AVAudioEngineを作成し、AVAudioSourceNodeを接続
- FMSynthEngineのサンプルレート・アルゴリズム・ボリューム・オペレータレベルを初期化
- エラー時は `errorMessage` にメッセージを設定

---

```swift
func stop()
```

オーディオエンジンを停止し、リソースをクリーンアップします。

**動作**:
- All Notes Off を送信
- AVAudioEngineを停止
- AVAudioSessionを非アクティブ化（iOS）
- 監視用Notification observerを削除

---

#### MIDI ノート制御メソッド

```swift
func noteOn(_ note: UInt8, velocity16: UInt16 = 0x7F00)
```

ノートオンイベントを送信します。

**パラメータ**:
- `note`: MIDIノート番号（0-127）
- `velocity16`: 16ビットベロシティ（デフォルト: 0x7F00 ≈ MIDI 1.0の127）

---

```swift
func noteOff(_ note: UInt8)
```

ノートオフイベントを送信します。

**パラメータ**:
- `note`: MIDIノート番号（0-127）

---

```swift
func controlChange(_ controller: UInt8, value32: UInt32)
```

コントロールチェンジイベントを送信します（32ビット値、MIDI 2.0対応）。

**パラメータ**:
- `controller`: コントローラ番号（0-127）
- `value32`: 32ビット値（MIDI 2.0形式）

**例**:
- CC64（サスティンペダル）: `value32 >= 0x40000000` でオン
- CC123（All Notes Off）

---

```swift
func pitchBend(_ value32: UInt32)
```

ピッチベンドイベントを送信します（32ビット符号なし、MIDI 2.0形式）。

**パラメータ**:
- `value32`: 32ビット符号なし値（中央値 = 0x80000000、範囲 ±2半音）

---

```swift
func allNotesOff()
```

全ノートオフ。アクティブなノート全てをオフにし、CC123を送信します。

---

#### パラメータ制御メソッド

```swift
func setOperatorLevel(_ opIndex: Int, level: Float)
```

オペレータレベルを設定します（内部 `operatorLevels` 配列も更新）。

---

```swift
func setOperatorRatio(_ opIndex: Int, ratio: Float)
```

オペレータ周波数比率を設定します。

---

```swift
func setOperatorDetune(_ opIndex: Int, cents: Float)
```

オペレータデチューンを設定します。

---

```swift
func setOperatorFeedback(_ opIndex: Int, feedback: Float)
```

オペレータフィードバックを設定します。

---

```swift
func setOperatorEGRates(_ opIndex: Int, r1: Float, r2: Float, r3: Float, r4: Float)
```

オペレータEGレートを設定します（DX7形式、0-99）。

---

```swift
func setOperatorEGLevels(_ opIndex: Int, l1: Float, l2: Float, l3: Float, l4: Float)
```

オペレータEGレベルを設定します（0.0-1.0）。

---

#### プリセット読み込み

```swift
func loadPreset(_ preset: DX7Preset)
```

DX7プリセットを読み込み、全パラメータをエンジンに適用します。

**動作**:
1. 全ノートオフ
2. アルゴリズムを設定
3. 各オペレータのパラメータを設定（レベル、比率、デチューン、フィードバック、EG）

**パラメータ**:
- `preset`: 読み込むDX7プリセット

---

#### macOS専用メソッド

```swift
func listMacOutputDevices() -> [(id: AudioDeviceID, name: String)]
```

利用可能なmacOS出力デバイス一覧を取得します。

**戻り値**: デバイスID と名前のタプル配列

---

```swift
func setMacOutputDevice(_ deviceID: AudioDeviceID)
```

macOS出力デバイスを設定します（エンジンを再起動）。

**パラメータ**:
- `deviceID`: AudioDeviceID

---

### MIDIInputManager

外部MIDIデバイス入力を管理し、MIDI 2.0 UMP対応でイベントをオーディオエンジンにルーティングします。

**スレッドセーフティ**: `@MainActor` 隔離。

**Observable**: SwiftUIの `@Observable` マクロを使用。

#### データ型

##### `MIDISourceItem`

```swift
public struct MIDISourceItem: Identifiable, Hashable, Sendable {
    public let id: String       // 一意識別子（名前ベース）
    public let name: String     // 表示名
    public let isOnline: Bool   // 接続状態
}
```

---

##### `MIDISourceMode`

```swift
public enum MIDISourceMode: Equatable, Sendable {
    case all                    // 全ソースから受信（Omni）
    case specific(String)       // 特定ソース名から受信
}
```

---

#### 監視可能プロパティ

```swift
private(set) var isConnected: Bool
```

MIDIが初期化されているか。

---

```swift
private(set) var connectedDevices: [String]
```

接続デバイス名リスト。

---

```swift
private(set) var availableSources: [MIDISourceItem]
```

利用可能なMIDIソースデバイス（選択UI用）。

---

```swift
var selectedSourceMode: MIDISourceMode
```

選択されたソースモード（`.all` または `.specific(name)`）。

---

```swift
private(set) var errorMessage: String?
```

最後のエラーメッセージ。

---

```swift
var receiveChannel: Int
```

MIDI受信チャンネル（0 = Omni、1-16 = 特定チャンネル）。

---

#### コールバック

```swift
var onNoteOn: ((UInt8, UInt16) -> Void)?
```

ノートオンコールバック。

**パラメータ**: `(note: UInt8, velocity16: UInt16)`

---

```swift
var onNoteOff: ((UInt8) -> Void)?
```

ノートオフコールバック。

**パラメータ**: `(note: UInt8)`

---

```swift
var onControlChange: ((UInt8, UInt32) -> Void)?
```

コントロールチェンジコールバック（32ビット値、MIDI 2.0対応）。

**パラメータ**: `(controller: UInt8, value32: UInt32)`

---

```swift
var onPitchBend: ((UInt32) -> Void)?
```

ピッチベンドコールバック（32ビット符号なし、中央値 = 0x80000000）。

**パラメータ**: `(value32: UInt32)`

---

#### デバッグプロパティ

```swift
private(set) var debugSources: [String]
private(set) var debugConnectedCount: Int
private(set) var debugReceiveCount: Int
private(set) var debugLastReceived: String
private(set) var debugLastEvent: String
var debugTransportCallback: String
```

デバッグ情報（UI表示用）。

---

#### メソッド

```swift
func start()
```

MIDI入力マネージャーを開始します。

**動作**:
1. CoreMIDITransportを作成（クライアント名: "M2DX"）
2. PEResponder（MIDI-CI Property Exchange）を作成・登録
3. 選択されたソースモードに基づいて接続（`.all` または `.specific`）
4. 受信タスクを開始し、MIDIデータをリスンしてコールバックを呼び出す

**MIDI 2.0対応**:
- UMP (Universal MIDI Packet) 形式で受信
- Type 0x4 (MIDI 2.0 Channel Voice) をデコード
- 16ビットベロシティ、32ビットCC/ピッチベンドをフルプレシジョンで処理
- MIDI 1.0フォールバック（7-bit → 16/32-bitアップスケール）

---

```swift
func selectSource(_ mode: MIDISourceMode)
```

MIDIソースを切り替えます（接続を再起動）。

**パラメータ**:
- `mode`: `.all` または `.specific(name)`

---

```swift
func stop()
```

MIDI入力マネージャーを停止します。

---

```swift
func refreshDeviceList()
```

接続MIDIデバイスリストを更新します。

---

### MIDIEventQueue

UIスレッドからオーディオレンダースレッドへMIDIイベントを渡すためのロックフリーリングバッファ。

**スレッドセーフティ**: `@unchecked Sendable`、`OSAllocatedUnfairLock` による最小オーバーヘッドの同期。

#### データ型

##### `MIDIEvent`

```swift
struct MIDIEvent: Sendable {
    enum Kind: UInt8, Sendable {
        case noteOn = 0x90
        case noteOff = 0x80
        case controlChange = 0xB0
        case pitchBend = 0xE0
    }

    let kind: Kind
    let data1: UInt8       // ノート番号またはCC番号（7-bit）
    let data2: UInt32      // velocity16、CC value32、またはpitchBend32
}
```

軽量なMIDIイベント構造体。

---

#### メソッド

```swift
init(capacity: Int = 256)
```

MIDIイベントキューを作成します。

**パラメータ**:
- `capacity`: 最大イベント数（デフォルト: 256）

---

```swift
func enqueue(_ event: MIDIEvent)
```

MIDIイベントをエンキューします（UIスレッドから呼び出し）。

**動作**: キューが満杯の場合、イベントは静かに破棄されます（リアルタイムオーディオでは、ブロックよりドロップが望ましい）。

---

```swift
func drain() -> [MIDIEvent]
```

保留中のイベント全てをドレインします（オーディオレンダースレッドから呼び出し）。

**戻り値**: イベント配列。内部バッファはクリアされます。

---

## M2DXCore モジュール

### OperatorParameters

FM オペレータパラメータを表す構造体。

```swift
public struct OperatorParameters: Sendable, Equatable, Identifiable {
    public let id: Int
    public var level: Double                        // 0.0-1.0（DX7: 0-99を正規化）
    public var frequencyRatio: Double               // 周波数比率
    public var detune: Int                          // デチューン（-50...+50推奨）
    public var fixedFrequency: Bool                 // 固定周波数モード
    public var fixedFrequencyValue: Double          // 固定周波数値（Hz）
    public var envelope: EnvelopeParameters         // エンベロープジェネレータ
    public var velocitySensitivity: Double          // ベロシティ感度（0.0-1.0）
    public var lfoAmpModSensitivity: Double         // LFO AM感度
    public var keyboardRateScaling: Double          // キーボードレートスケーリング
    public var keyboardLevelScaling: KeyboardLevelScaling  // キーボードレベルスケーリング
    public var outputLevel: Double                  // キャリアオペレータ出力レベル
}
```

#### 初期化

```swift
public init(
    id: Int = 0,
    level: Double = 0.99,
    frequencyRatio: Double = 1.0,
    detune: Int = 0,
    fixedFrequency: Bool = false,
    fixedFrequencyValue: Double = 440.0,
    envelope: EnvelopeParameters = EnvelopeParameters(),
    velocitySensitivity: Double = 0.0,
    lfoAmpModSensitivity: Double = 0.0,
    keyboardRateScaling: Double = 0.0,
    keyboardLevelScaling: KeyboardLevelScaling = KeyboardLevelScaling(),
    outputLevel: Double = 1.0
)
```

---

```swift
public static func defaultOperator(id: Int) -> OperatorParameters
```

デフォルトパラメータを持つオペレータを作成します。

---

### EnvelopeParameters

4レート/4レベルのADSR風エンベロープ（DX7形式）。

```swift
public struct EnvelopeParameters: Sendable, Equatable {
    public var rate1: Double
    public var rate2: Double
    public var rate3: Double
    public var rate4: Double

    public var level1: Double
    public var level2: Double
    public var level3: Double
    public var level4: Double
}
```

#### 初期化

```swift
public init(
    rate1: Double = 0.99,
    rate2: Double = 0.99,
    rate3: Double = 0.99,
    rate4: Double = 0.99,
    level1: Double = 0.99,
    level2: Double = 0.99,
    level3: Double = 0.99,
    level4: Double = 0.0
)
```

---

### KeyboardLevelScaling

キーボードレベルスケーリングパラメータ。

```swift
public struct KeyboardLevelScaling: Sendable, Equatable {
    public var breakPoint: Int                  // ブレークポイント（MIDIノート番号）
    public var leftDepth: Double                // 左側深さ
    public var rightDepth: Double               // 右側深さ
    public var leftCurve: ScalingCurve          // 左側カーブ
    public var rightCurve: ScalingCurve         // 右側カーブ

    public enum ScalingCurve: Int, Sendable, CaseIterable {
        case negativeLinear = 0
        case negativeExponential = 1
        case positiveExponential = 2
        case linear = 3
    }
}
```

#### 初期化

```swift
public init(
    breakPoint: Int = 60,
    leftDepth: Double = 0.0,
    rightDepth: Double = 0.0,
    leftCurve: ScalingCurve = .linear,
    rightCurve: ScalingCurve = .linear
)
```

---

### DX7Preset

完全なDX7ボイスプリセット。

```swift
public struct DX7Preset: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let name: String                     // DX7互換10文字名
    public let algorithm: Int                   // 0-31（0-indexed）
    public let feedback: Int                    // 0-7
    public let operators: [DX7OperatorPreset]   // 6オペレータ
    public let category: PresetCategory
}
```

#### 初期化

```swift
public init(
    id: UUID = UUID(),
    name: String,
    algorithm: Int,
    feedback: Int,
    operators: [DX7OperatorPreset],
    category: PresetCategory
)
```

#### 変換プロパティ

```swift
public var normalizedFeedback: Float
```

DX7フィードバック（0-7）を正規化（0.0-1.0）。

---

### DX7OperatorPreset

DX7ネイティブオペレータパラメータ（全て DX7 範囲）。

```swift
public struct DX7OperatorPreset: Codable, Sendable, Equatable {
    public let outputLevel: Int      // 0-99
    public let frequencyCoarse: Int  // 0-31
    public let frequencyFine: Int    // 0-99
    public let detune: Int           // 0-14（7=中央）
    public let feedback: Int         // 0-7（フィードバックOP時のみ有効）
    public let egRate1: Int          // 0-99
    public let egRate2: Int          // 0-99
    public let egRate3: Int          // 0-99
    public let egRate4: Int          // 0-99
    public let egLevel1: Int         // 0-99
    public let egLevel2: Int         // 0-99
    public let egLevel3: Int         // 0-99
    public let egLevel4: Int         // 0-99
}
```

#### 初期化

```swift
public init(
    outputLevel: Int = 99,
    frequencyCoarse: Int = 1,
    frequencyFine: Int = 0,
    detune: Int = 7,
    feedback: Int = 0,
    egRate1: Int = 99, egRate2: Int = 99, egRate3: Int = 99, egRate4: Int = 99,
    egLevel1: Int = 99, egLevel2: Int = 99, egLevel3: Int = 99, egLevel4: Int = 0
)
```

#### 変換プロパティ

```swift
public var normalizedLevel: Float
```

DX7出力レベル（0-99）を正規化振幅（0.0-1.0）に変換します。

**対数カーブ**: OL 99 = 0 dB（振幅1.0）、各ステップごとに約0.75 dB減衰。

---

```swift
public var frequencyRatio: Float
```

DX7周波数（coarse + fine）を比率に変換します。

**計算**:
- Coarse: 0 → 0.5、1 → 1.0、N → N.0
- Fine: (1 + fine/100) で乗算

---

```swift
public var detuneCents: Float
```

DX7デチューン（0-14、7=中央）をセントオフセットに変換します。

---

```swift
public var normalizedFeedback: Float
```

DX7フィードバック（0-7）を正規化（0.0-1.0）。

---

```swift
public var egRatesDX7: (Float, Float, Float, Float)
```

EGレートをDX7ネイティブ値（0-99）でタプル返却。

---

```swift
public var egLevelsNormalized: (Float, Float, Float, Float)
```

EGレベルを正規化（0.0-1.0）でタプル返却。

---

### PresetCategory

プリセットカテゴリー列挙型。

```swift
public enum PresetCategory: String, Codable, CaseIterable, Sendable {
    case keys, bass, brass, strings, organ, percussion, woodwind, other
}
```

---

## スレッドセーフティまとめ

| クラス/構造体 | スレッドセーフティ | 備考 |
|-------------|------------------|------|
| `FMSynthEngine` | `@unchecked Sendable` + `NSLock` | 複数スレッドから安全にアクセス可能 |
| `M2DXAudioEngine` | `@MainActor` | メインスレッドからのみアクセス |
| `MIDIInputManager` | `@MainActor` | メインスレッドからのみアクセス |
| `MIDIEventQueue` | `@unchecked Sendable` + `OSAllocatedUnfairLock` | ロックフリー、リアルタイムセーフ |
| `MIDIEvent` | `Sendable` | 値型、スレッドセーフ |
| `OperatorParameters` | `Sendable` | 値型、スレッドセーフ |
| `EnvelopeParameters` | `Sendable` | 値型、スレッドセーフ |
| `KeyboardLevelScaling` | `Sendable` | 値型、スレッドセーフ |
| `DX7Preset` | `Sendable` + `Codable` | 値型、スレッドセーフ、JSON対応 |
| `DX7OperatorPreset` | `Sendable` + `Codable` | 値型、スレッドセーフ、JSON対応 |

---

## MIDI 2.0 対応

M2DXは MIDI 2.0 UMP (Universal MIDI Packet) に完全対応しています。

### 対応機能

- **16-bit Velocity**: ノートオン/オフで16ビットベロシティをフルプレシジョン処理
- **32-bit Control Change**: CC値を32ビットで処理（MIDI 1.0: 7-bit → MIDI 2.0: 32-bit）
- **32-bit Pitch Bend**: ピッチベンドを32ビットで処理（MIDI 1.0: 14-bit → MIDI 2.0: 32-bit）
- **MIDI-CI Property Exchange**: ResourceList、DeviceInfo、ProgramList をサポート

### MIDI 1.0フォールバック

MIDI 1.0デバイスからの入力は自動的にアップスケールされます。

- 7-bit velocity → 16-bit: `velocity << 9`
- 7-bit CC → 32-bit: `value << 25`
- 14-bit pitch bend → 32-bit: `value << 18`

---

## サンプルコード

### オーディオエンジン起動

```swift
import M2DXFeature

@MainActor
class MyApp {
    let audioEngine = M2DXAudioEngine()

    func setup() async {
        await audioEngine.start()
    }

    func playNote() {
        audioEngine.noteOn(60, velocity16: 0x7F00)  // C4、フルベロシティ

        // 1秒後にノートオフ
        Task {
            try await Task.sleep(for: .seconds(1))
            audioEngine.noteOff(60)
        }
    }
}
```

### MIDI入力接続

```swift
import M2DXFeature

@MainActor
class MyMIDIManager {
    let midiManager = MIDIInputManager()
    let audioEngine = M2DXAudioEngine()

    func setup() {
        midiManager.onNoteOn = { [weak self] note, velocity16 in
            self?.audioEngine.noteOn(note, velocity16: velocity16)
        }
        midiManager.onNoteOff = { [weak self] note in
            self?.audioEngine.noteOff(note)
        }
        midiManager.onControlChange = { [weak self] cc, value32 in
            self?.audioEngine.controlChange(cc, value32: value32)
        }
        midiManager.onPitchBend = { [weak self] value32 in
            self?.audioEngine.pitchBend(value32)
        }

        midiManager.start()
    }
}
```

### プリセット読み込み

```swift
import M2DXCore
import M2DXFeature

@MainActor
func loadAndPlay(preset: DX7Preset, engine: M2DXAudioEngine) {
    engine.loadPreset(preset)

    // プリセットが適用されたら演奏
    engine.noteOn(60, velocity16: 0x7F00)
}
```

---

このドキュメントはM2DXプロジェクトの主要APIをカバーしています。実装の詳細は各ソースファイルを参照してください。
