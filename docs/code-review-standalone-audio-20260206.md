# コードレビューレポート - スタンドアロン音声再生機能

## 概要
- レビュー対象: M2DX スタンドアロン音声再生機能
- レビュー日: 2026-02-06

## サマリー
- 🔴 Critical: 3件
- 🟡 Warning: 6件
- 🔵 Suggestion: 7件

---

## 詳細

### 🔴 [M2DXAudioEngine.swift:148] force unwrap によるクラッシュリスク

**問題**
MIDI送信時に`baseAddress!`を使用したforce unwrapがある。バッファが空の場合にクラッシュする可能性がある。

**現在のコード**
```swift
midiData.withUnsafeMutableBufferPointer { buffer in
    midiBlock(AUEventSampleTimeImmediate, 0, 3, buffer.baseAddress!)
}
```

**提案**
```swift
midiData.withUnsafeMutableBufferPointer { buffer in
    guard let baseAddress = buffer.baseAddress else { return }
    midiBlock(AUEventSampleTimeImmediate, 0, 3, baseAddress)
}
```

**理由**
リアルタイムオーディオ処理においてクラッシュは致命的。nil チェックを追加してもパフォーマンスへの影響は無視できる。

---

### 🔴 [M2DXAudioEngine.swift:63-64] @Observableと非同期処理のスレッドセーフティ問題

**問題**
`start()`メソッドが`async`だが、`@MainActor`アノテーションのみに依存している。`setupAudioEngine()`内でAVAudioSession設定がメインスレッドで実行される保証がない。

**現在のコード**
```swift
public func start() async {
    do {
        try await setupAudioEngine()
        isRunning = true  // @Observable プロパティ
        errorMessage = nil
    } catch {
        errorMessage = "Failed to start audio engine: \(error.localizedDescription)"
    }
}
```

**提案**
```swift
public func start() async {
    do {
        try await setupAudioEngine()
        // Ensure UI updates happen on main thread
        await MainActor.run {
            isRunning = true
            errorMessage = nil
        }
    } catch {
        await MainActor.run {
            errorMessage = "Failed to start audio engine: \(error.localizedDescription)"
        }
    }
}
```

**理由**
`@Observable`プロパティの変更はUIを更新するため、確実にメインスレッドで実行すべき。Swift 6 strict concurrencyでは明示的な`@MainActor`分離が推奨される。

---

### 🔴 [M2DXAudioEngine.swift:82] AVAudioSessionのエラーハンドリング不足

**問題**
AVAudioSessionの設定失敗が上位に伝播するのみで、アプリ全体のオーディオ状態に影響を与える可能性がある。

**現在のコード**
```swift
let session = AVAudioSession.sharedInstance()
try session.setCategory(.playback, mode: .default, options: [])
try session.setActive(true)
```

**提案**
```swift
let session = AVAudioSession.sharedInstance()
do {
    try session.setCategory(.playback, mode: .default, options: [])
    try session.setActive(true)
} catch {
    throw AudioEngineError.audioSessionSetupFailed(underlying: error)
}

// 専用のエラー型を定義
enum AudioEngineError: LocalizedError {
    case audioSessionSetupFailed(underlying: Error)
    case audioUnitInstantiationFailed(underlying: Error)
    case engineStartFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .audioSessionSetupFailed(let error):
            return "オーディオセッションの設定に失敗しました: \(error.localizedDescription)"
        case .audioUnitInstantiationFailed(let error):
            return "Audio Unitの読み込みに失敗しました: \(error.localizedDescription)"
        case .engineStartFailed(let error):
            return "オーディオエンジンの起動に失敗しました: \(error.localizedDescription)"
        }
    }
}
```

**理由**
AVAudioSessionはシステム全体で共有されるリソース。他のアプリによる割り込み（電話着信等）でも失敗する可能性があるため、詳細なエラーメッセージが必要。

---

### 🟡 [M2DXAudioEngine.swift:72-75] 停止時のクリーンアップ不足

**問題**
`stop()`メソッドでAVAudioEngineを停止しているが、AVAudioSessionの非アクティブ化やリソースのクリーンアップが不足している。

**現在のコード**
```swift
public func stop() {
    audioEngine?.stop()
    isRunning = false
}
```

**提案**
```swift
public func stop() {
    // Send all notes off before stopping
    allNotesOff()

    // Stop engine
    audioEngine?.stop()

    // Detach nodes
    if let auNode = auNode {
        audioEngine?.detach(auNode)
    }

    // Deactivate audio session
    do {
        try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    } catch {
        print("Failed to deactivate audio session: \(error)")
    }

    // Release resources
    audioUnit = nil
    auNode = nil
    audioEngine = nil
    isRunning = false
}
```

**理由**
ノートオフ送信せずに停止すると音が鳴り続ける可能性がある。また、AVAudioSessionを非アクティブ化しないとバックグラウンドオーディオが阻害される。

---

### 🟡 [M2DXAudioEngine.swift:27-48] didSetでのパラメータ設定が初期化時に無駄な処理を実行

**問題**
`algorithm`、`masterVolume`、`operatorLevels`の`didSet`でパラメータ設定を行っているが、Audio Unit初期化前に実行されても無意味。

**現在のコード**
```swift
public var algorithm: Int = 0 {
    didSet {
        setParameter(address: 0, value: Float(algorithm))
    }
}
```

**提案**
```swift
public var algorithm: Int = 0 {
    didSet {
        guard isRunning else { return }
        setParameter(address: 0, value: Float(algorithm))
    }
}
```

または、明示的なメソッドに分離:
```swift
public var algorithm: Int = 0

public func updateAlgorithm(_ value: Int) {
    algorithm = value
    setParameter(address: 0, value: Float(value))
}
```

**理由**
Audio Unit初期化前のパラメータ設定は無駄。また、`didSet`での副作用は予測しにくいため、明示的なメソッド呼び出しの方が明確。

---

### 🟡 [M2DXAudioEngine.swift:101] .loadOutOfProcessの選択理由が不明確

**問題**
`AVAudioUnit.instantiate`で`.loadOutOfProcess`を使用しているが、スタンドアロンアプリでは`.loadInProcess`の方が効率的な可能性がある。

**現在のコード**
```swift
let avAudioUnit = try await AVAudioUnit.instantiate(
    with: componentDescription,
    options: .loadOutOfProcess
)
```

**提案**
```swift
// スタンドアロンアプリでは in-process の方が低レイテンシ
let avAudioUnit = try await AVAudioUnit.instantiate(
    with: componentDescription,
    options: .loadInProcess
)
```

**理由**
- `.loadOutOfProcess`: DAWでの安定性向上（クラッシュ分離）
- `.loadInProcess`: レイテンシ低減、メモリ効率向上
- スタンドアロンアプリでは同じプロセス内で実行する方が効率的。ただし、デバッグ時は`.loadOutOfProcess`の方がクラッシュ原因の特定が容易。

---

### 🟡 [M2DXAudioEngine.swift:173-196] パラメータアドレス計算の重複とマジックナンバー

**問題**
`setOperatorLevel`、`setOperatorRatio`等でアドレス計算が重複している。また、オフセット値（+1, +2, +3）がマジックナンバー。

**現在のコード**
```swift
public func setOperatorLevel(_ opIndex: Int, level: Float) {
    let address = 100 + opIndex * 100
    setParameter(address: UInt64(address), value: level)
}

public func setOperatorRatio(_ opIndex: Int, ratio: Float) {
    let address = 100 + opIndex * 100 + 1  // +1 for ratio offset
    setParameter(address: UInt64(address), value: ratio)
}
```

**提案**
```swift
// 定数定義（M2DXCore/PropertyExchange/M2DXParameterAddressMap.swiftから参照）
enum M2DXParameterOffset {
    static let operatorBase: UInt64 = 100
    static let operatorStride: UInt64 = 100

    enum Operator {
        static let level: UInt64 = 0
        static let ratio: UInt64 = 1
        static let detune: UInt64 = 2
        static let feedback: UInt64 = 3
    }
}

public func setOperatorLevel(_ opIndex: Int, level: Float) {
    let address = M2DXParameterOffset.operatorBase +
                  UInt64(opIndex) * M2DXParameterOffset.operatorStride +
                  M2DXParameterOffset.Operator.level
    setParameter(address: address, value: level)
}
```

**理由**
マジックナンバーを除去し、`M2DXParameterAddressMap.swift`との一貫性を確保。将来的なアドレス変更時の修正箇所を削減。

---

### 🟡 [MIDIKeyboardView.swift:63-65] 全ノートオフの非効率な実装

**問題**
全ノートオフボタンで0-127までループしているが、実際に発音中のノートのみをオフにすべき。

**現在のコード**
```swift
Button {
    pressedNotes.removeAll()
    for note in 0...127 {
        onNoteOff(UInt8(note))
    }
} label: {
    Image(systemName: "stop.circle")
}
```

**提案**
```swift
Button {
    // 発音中のノートのみオフ
    for note in pressedNotes {
        onNoteOff(note)
    }
    pressedNotes.removeAll()

    // または MIDI All Notes Off CC#123 を送信
    // audioEngine.allNotesOff() // 既に実装済み
} label: {
    Image(systemName: "stop.circle")
        .foregroundStyle(.red)
}
```

**理由**
128回のMIDIメッセージ送信は不要。`pressedNotes`のセットのみをオフにするか、MIDI CC#123（All Notes Off）を1回送信すればよい。

---

### 🟡 [M2DXFeature.swift:113-119] .taskと.onDisappearの競合リスク

**問題**
`.task`でエンジン起動、`.onDisappear`で停止しているが、ビューの再作成時に競合する可能性がある。

**現在のコード**
```swift
.task {
    await audioEngine.start()
}
.onDisappear {
    audioEngine.stop()
}
```

**提案**
```swift
.task {
    await audioEngine.start()
    // task はキャンセル時に自動的にクリーンアップされる
    return {
        audioEngine.stop()
    }
}

// または、taskのキャンセレーションを監視
.task {
    await audioEngine.start()

    // Wait until task is cancelled
    await withTaskCancellationHandler {
        // Keep running
        await Task.sleep(for: .infinity)
    } onCancel: {
        audioEngine.stop()
    }
}
```

**理由**
`.onDisappear`は即座に呼ばれない場合がある（ナビゲーション遷移時等）。`.task`のキャンセレーション処理で確実にクリーンアップする方が安全。

---

### 🔵 [M2DXAudioEngine.swift:10] Sendable対応の検討

**問題**
`@Observable`クラスだが、Sendable適合していない。Swift 6 strict modeでは警告が出る可能性がある。

**提案**
```swift
@MainActor
@Observable
public final class M2DXAudioEngine: @unchecked Sendable {
    // AVAudioEngine等は @MainActor分離されているため安全
```

または、全プロパティをactorで保護:
```swift
@globalActor
actor AudioEngineActor {
    static let shared = AudioEngineActor()
}

@AudioEngineActor
@Observable
public final class M2DXAudioEngine {
    // ...
}
```

**理由**
Swift 6のstrict concurrency checkingでは、並行コンテキスト間で共有される型はSendableである必要がある。`@MainActor`分離で十分だが、明示的に`@unchecked Sendable`を付けることでコンパイラ警告を回避できる。

---

### 🔵 [M2DXAudioEngine.swift:86-87] AVAudioEngineの再利用

**問題**
`setupAudioEngine()`で毎回新しいAVAudioEngineインスタンスを作成しているが、再起動時は既存インスタンスを再利用できる可能性がある。

**提案**
```swift
private func setupAudioEngine() async throws {
    // 既存のエンジンがあればクリーンアップ
    if let engine = audioEngine, engine.isRunning {
        engine.stop()
    }

    // 既存エンジンを再利用
    let engine = audioEngine ?? AVAudioEngine()
    self.audioEngine = engine

    // ... 残りの処理
}
```

**理由**
AVAudioEngineインスタンスの作成はコストが高い。再起動時は再利用することでパフォーマンス向上。ただし、クリーンアップ処理を確実に行う必要がある。

---

### 🔵 [M2DXAudioEngine.swift:92-96] ComponentDescriptionの定数化

**問題**
AudioComponentDescriptionが`setupAudioEngine()`内でハードコードされている。

**提案**
```swift
// クラスプロパティとして定義
private static let m2dxComponentDescription = AudioComponentDescription(
    componentType: kAudioUnitType_MusicDevice,
    componentSubType: FourCharCode("m2dx"),
    componentManufacturer: FourCharCode("M2DX"),
    componentFlags: 0,
    componentFlagsMask: 0
)

private func setupAudioEngine() async throws {
    // ...
    let avAudioUnit = try await AVAudioUnit.instantiate(
        with: Self.m2dxComponentDescription,
        options: .loadOutOfProcess
    )
    // ...
}
```

**理由**
再利用性向上、テスト容易性向上。将来的に複数のAudio Unitを切り替える場合にも対応しやすい。

---

### 🔵 [MIDIKeyboardView.swift:90-102] DragGestureの重複コード

**問題**
白鍵と黒鍵で同じDragGestureコードが重複している。

**提案**
```swift
// 共通のジェスチャーを返すメソッド
private func noteGesture(for note: UInt8) -> some Gesture {
    DragGesture(minimumDistance: 0)
        .onChanged { _ in
            if !pressedNotes.contains(note) {
                pressedNotes.insert(note)
                onNoteOn(note, 100)
            }
        }
        .onEnded { _ in
            pressedNotes.remove(note)
            onNoteOff(note)
        }
}

// 使用例
WhiteKeyView(...)
    .gesture(noteGesture(for: note))

BlackKeyView(...)
    .gesture(noteGesture(for: note))
```

**理由**
DRY原則。将来的にベロシティ対応やマルチタッチ対応する際も修正箇所が1箇所で済む。

---

### 🔵 [MIDIKeyboardView.swift:95, 120] ベロシティが固定値100

**問題**
すべてのノートでベロシティ100固定。タッチ強度に応じたベロシティ変化がない。

**提案**
```swift
@State private var noteVelocities: [UInt8: UInt8] = [:]

DragGesture(minimumDistance: 0)
    .onChanged { value in
        if !pressedNotes.contains(note) {
            // タッチ位置のY座標から疑似ベロシティを計算
            let velocity = calculateVelocity(from: value.location.y, height: geometry.size.height)
            noteVelocities[note] = velocity
            pressedNotes.insert(note)
            onNoteOn(note, velocity)
        }
    }
    .onEnded { _ in
        pressedNotes.remove(note)
        noteVelocities.removeValue(forKey: note)
        onNoteOff(note)
    }

private func calculateVelocity(from y: CGFloat, height: CGFloat) -> UInt8 {
    // 鍵盤上部をタッチ: 低ベロシティ、下部: 高ベロシティ
    let normalized = max(0, min(1, y / height))
    return UInt8(64 + normalized * 63) // 64-127の範囲
}
```

**理由**
音楽的表現力向上。ただし、タッチスクリーンでの疑似ベロシティは限界があるため、オプション機能として実装が推奨。

---

### 🔵 [MIDIKeyboardView.swift:143-160] ノート計算の最適化

**問題**
`whiteKeyNote`と`blackKeyNote`で同様の計算を繰り返している。

**提案**
```swift
// ノート計算を構造体にまとめる
struct KeyboardLayout {
    let baseOctave: Int

    private let whiteKeyOffsets = [0, 2, 4, 5, 7, 9, 11]
    private let blackKeyOffsets = [1, 3, -1, 6, 8, 10, -1]

    func whiteKeyNote(at index: Int) -> UInt8 {
        let octaveOffset = index / 7
        let keyInOctave = index % 7
        let midiNote = (baseOctave + octaveOffset) * 12 + whiteKeyOffsets[keyInOctave]
        return UInt8(clamping: midiNote)
    }

    func blackKeyNote(at index: Int) -> UInt8? {
        let keyInOctave = index % 7
        let offset = blackKeyOffsets[keyInOctave]
        guard offset >= 0 else { return nil }

        let octaveOffset = index / 7
        let midiNote = (baseOctave + octaveOffset) * 12 + offset
        return UInt8(clamping: midiNote)
    }
}
```

**理由**
計算ロジックの分離、テスト容易性向上。`UInt8(clamping:)`でオーバーフロー対策も簡潔に。

---

### 🔵 [M2DXFeature.swift:364-366, 376-378] onChange内でaudioEngineを直接呼び出し

**問題**
UIスライダーの`.onChange`で直接`audioEngine`を呼び出しているが、頻繁な更新でCPU負荷が高くなる可能性がある。

**提案**
```swift
// スロットリング（デバウンス）の追加
@State private var parameterUpdateTask: Task<Void, Never>?

Slider(value: $op.level, in: 0...1)
    .onChange(of: op.level) { _, newValue in
        // 前回のタスクをキャンセル
        parameterUpdateTask?.cancel()

        // 少し遅延させて送信（100ms）
        parameterUpdateTask = Task {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            audioEngine?.setOperatorLevel(op.id - 1, level: Float(newValue))
        }
    }
```

または、連続更新中はUIのみ更新し、タッチ終了時にパラメータ送信:
```swift
@State private var isDragging = false

Slider(value: $op.level, in: 0...1)
    .simultaneousGesture(
        DragGesture(minimumDistance: 0)
            .onChanged { _ in isDragging = true }
            .onEnded { _ in
                isDragging = false
                audioEngine?.setOperatorLevel(op.id - 1, level: Float(op.level))
            }
    )
```

**理由**
スライダーを高速でドラッグすると毎フレームパラメータ更新が発生し、MIDIメッセージが大量に送信される。デバウンスまたはタッチ終了時の送信でCPU負荷を削減。

---

## 良かった点

### アーキテクチャ
- AVAudioEngineを使ったスタンドアロンホスティングの適切な実装
- AUv3をアプリ内部でホストする設計により、単体で音を出せる構成
- `@Observable`を使った現代的なSwiftUI状態管理

### コードの明確性
- MIDIキーボードUIが直感的で実装もシンプル
- 白鍵/黒鍵の計算ロジックが分離されており理解しやすい
- CompactKeyboardViewという代替UIも提供

### UI/UX
- オクターブ切り替え機能
- All Notes Offボタン（スタックノート対策）
- 視覚的なフィードバック（押下状態のハイライト）
- オーディオエンジン稼働状態インジケーター

### Swift 6対応
- `@MainActor`アノテーションで適切なスレッド分離
- `@Observable`による最新のSwiftUI状態管理
- async/awaitを使った非同期処理

---

## 総評

全体として、スタンドアロン音声再生機能は良く設計されており、AVAudioEngineとAUv3の統合が適切に実装されています。特に、MIDIキーボードUIの実装品質が高く、直感的な操作が可能です。

ただし、以下の改善が必要です:

### 優先度高（Critical）
1. **force unwrapの除去**: MIDIデータ送信時のクラッシュリスク対策
2. **AVAudioSession管理の改善**: オーディオ割り込み対応とエラーハンドリング
3. **スレッドセーフティの強化**: `@Observable`プロパティ更新の明示的なメインスレッド分離

### 優先度中（Warning）
1. **stop()メソッドの完全なクリーンアップ**: ノートオフ送信、リソース解放、AVAudioSession非アクティブ化
2. **パラメータ更新の最適化**: UI初期化時の無駄な処理削減
3. **インプロセス/アウトオブプロセスの選択**: スタンドアロンアプリでのレイテンシ最適化

### 優先度低（Suggestion）
1. **コードの重複削除**: DragGesture、ノート計算ロジックの共通化
2. **定数の一元管理**: AudioComponentDescription、パラメータアドレスの定数化
3. **パフォーマンス改善**: パラメータ更新のデバウンス、AVAudioEngineの再利用

### 推奨される次のステップ
1. Critical問題の即時修正（force unwrap、AVAudioSession管理）
2. ユニットテストの追加（MIDIノート計算、パラメータアドレス計算）
3. 実機でのレイテンシ測定とチューニング
4. 長時間再生時のメモリリーク検証
5. バックグラウンド/フォアグラウンド遷移時の挙動確認

このコードは優れた基盤を持っていますが、上記の改善により、より堅牢でプロフェッショナルな品質に到達できます。特に、リアルタイムオーディオ処理におけるエラーハンドリングとリソース管理の改善は必須です。
