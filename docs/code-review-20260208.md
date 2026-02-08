# コードレビューレポート

## 概要
- レビュー対象: M2DXPackage/Sources/M2DXFeature/ (6ファイル)
- レビュー日: 2026-02-08
- レビュー範囲: PE Notify 0x38修正 + macOS entity除外 + KORG KeyStage連携対応後のコードベース

## サマリー
- 🔴 Critical: 0件
- 🟡 Warning: 3件
- 🔵 Suggestion: 8件
- 💡 Nitpick: 4件

---

## 詳細

### 🟡 [FMSynthEngine.swift:19-25] グローバルLUTのメモリリーク

**問題**
```swift
nonisolated(unsafe) private let kSineLUT: UnsafePointer<Float> = {
    let buf = UnsafeMutablePointer<Float>.allocate(capacity: kSineLUTSize + 1)
    for i in 0...kSineLUTSize {
        buf[i] = sinf(Float(i) / Float(kSineLUTSize) * 2.0 * .pi)
    }
    return UnsafePointer(buf)
}()
```

**理由**
グローバル変数として初期化されたLUTは、アプリ終了時にdeallocateされない。起動時に一度だけ確保され、プログラム終了まで保持されるため実質的な問題は少ないが、`deinit`がないため、厳密にはメモリリークとして検出される可能性がある。

**提案**
静的データなので、`deallocate()`を呼ぶ場所がない（グローバルスコープにdeinitは存在しない）。以下の対応を検討:

1. **許容する**（推奨）: OS終了時に自動解放されるので、実害なし。コメントで意図を明記。
2. **StaticLUTクラス化**: `final class StaticLUT`を作り、`deinit`でdeallocate。ただしシングルトン管理が必要。

**コメント追加案**
```swift
// NOTE: Global LUT allocated once at startup, deallocated by OS on process termination.
// This is intentional for maximum performance (no lookup overhead).
nonisolated(unsafe) private let kSineLUT: UnsafePointer<Float> = { ... }()
```

---

### 🟡 [M2DXAudioEngine.swift:246-263] Configuration Change時の再入ガード実装に潜在的競合

**問題**
```swift
private var isRestarting = false

private func handleConfigurationChange() {
    guard !isRestarting else { return }
    isRestarting = true
    audioLogger.info("Configuration changed, restarting engine...")
    let wasRunning = isRunning
    stop()
    if wasRunning {
        Task {
            await start()
            isRestarting = false  // ← Taskの中で設定
        }
    } else {
        isRestarting = false
    }
}
```

**理由**
- `isRestarting`フラグは`@MainActor`で保護されているが、`Task {}`非同期ブロック内で`isRestarting = false`が実行される
- `Task`が完了する前に再度`handleConfigurationChange()`が呼ばれた場合、`isRestarting == false`のタイミングで再入可能
- macOS/iOS両方で、デバイス切り替えやBluetooth接続時に短時間に複数の通知が来る可能性がある

**提案**
```swift
private var restartTask: Task<Void, Never>?

private func handleConfigurationChange() {
    // Cancel previous restart task
    restartTask?.cancel()

    restartTask = Task { @MainActor in
        audioLogger.info("Configuration changed, restarting engine...")
        let wasRunning = isRunning
        stop()
        if wasRunning {
            await start()
        }
        restartTask = nil
    }
}
```

**理由**
- `Task`をプロパティで保持し、新しい変更が来たら前のタスクをキャンセル
- デバウンス効果で最後の変更のみ適用される
- 再入チェックが不要になり、コードが簡潔化

---

### 🟡 [MIDIInputManager.swift:788-819] PE Notify実装に複数の懸念点

**問題1: Debounce実装が未使用**
```swift
/// Debounce task for PE Notify — cancel previous before scheduling new
private var pendingNotifyTask: Task<Void, Never>?
```
プロパティが定義されているが、`notifyProgramChange()`内で実際には使われていない。連続PCでハングした過去の経緯から、500msディレイは入っているが、前のNotifyタスクのキャンセル処理がない。

**問題2: 固定500ms待機**
```swift
try? await Task.sleep(for: .milliseconds(500))
```
すべてのPC変更で一律500ms待つため、ユーザーがPCを高速連打した場合、古いプログラム名のNotifyが遅れて届く可能性がある。

**問題3: エラーハンドリング不足**
```swift
await responder.notify(resource: "ChannelList", data: channelListBody, excludeMUIDs: excludeMUIDs)
```
`notify()`の失敗をキャッチしていない（`PEResponder.notify()`がthrowsかは不明だが、ログにエラーが記録されるのみ）。

**提案**
```swift
/// Debounce task for PE Notify
private var pendingNotifyTask: Task<Void, Never>?

private func notifyProgramChange(programIndex: UInt8) {
    // Cancel previous notify task (debounce)
    pendingNotifyTask?.cancel()

    currentProgramIndex = Int(programIndex)
    let name = currentProgramName
    let idx = Int(programIndex)
    appendDebugLog("PC: program=\(idx) name=\(name)")
    peLogger.info("PC: program=\(idx) name=\(name, privacy: .public)")

    guard let responder = peResponder else {
        appendDebugLog("PE-Notify: no responder")
        return
    }

    pendingNotifyTask = Task { [weak self] in
        guard let self else { return }

        // Debounce: wait for PC flood to settle
        try? await Task.sleep(for: .milliseconds(500))

        // Check if task was cancelled (new PC arrived)
        guard !Task.isCancelled else {
            await MainActor.run {
                self.appendDebugLog("PE-Notify: cancelled (new PC)")
            }
            return
        }

        // ... (existing notify code)

        await MainActor.run {
            self.pendingNotifyTask = nil
        }
    }
}
```

**理由**
- 連続PC時、最後のPCのみがNotifyされる（正しいプログラム名がLCDに表示される）
- タスクキャンセルで不要な通信を削減
- キャンセル検出でログが明確化

---

### 🔵 [FMSynthEngine.swift:522] `@unchecked Sendable`の使用根拠をコメント化

**問題**
```swift
final class FMSynthEngine: @unchecked Sendable {
```

**理由**
`@unchecked Sendable`は、コンパイラのSendableチェックをバイパスするため、使用理由をコメントで明記すべき。特に、Swift 6の厳格なconcurrency checkingでは、将来的なメンテナンス時に「なぜuncheckedか」が不明になる。

**提案**
```swift
/// Pure-Swift FM synth engine.
///
/// Thread-safety strategy:
/// - `os_unfair_lock` protects only the parameter snapshot swap (sub-microsecond hold time).
/// - The audio render thread copies the snapshot once per buffer, then runs lock-free.
/// - MIDI events flow through a separate lock-free ring buffer (`MIDIEventQueue`).
///
/// Marked `@unchecked Sendable` because:
/// - `os_unfair_lock` is not Sendable, but we ensure thread-safe access manually.
/// - Render-thread-only state (voices, sampleRate, etc.) is never accessed from UI thread.
/// - UI thread only writes to `pendingParams` under lock, audio thread only reads.
final class FMSynthEngine: @unchecked Sendable {
```

---

### 🔵 [MIDIEventQueue.swift:73-79] ロック外で読み取る範囲の安全性を保証するコメント追加

**問題**
```swift
// Process events outside the lock — storage slots are safe to read
// because new enqueues write to different slots (count was reset to 0,
// so writes go to the new head position, not the range we're reading).
for i in 0..<n {
    let index = (h + i) % capacity
    handler(storage[index])
}
```

**理由**
コメントはあるが、「なぜ安全か」の説明が不十分。リングバッファの二重書き込み防止ロジック（`count`リセット後、読み取り範囲と書き込み範囲が重ならない）の詳細を明記すべき。

**提案**
```swift
// SAFETY: Process events outside the lock to minimize hold time.
// This is safe because:
// 1. We captured `n` (event count) and `h` (head position) under lock.
// 2. We reset `count = 0` under lock, so new enqueues write to `(head + 0) % capacity`.
// 3. Our read range is `[h, h+n)`, which does not overlap with new writes.
// 4. Ring buffer capacity (256) >> typical buffer size (~128 events), so overflow is unlikely.
for i in 0..<n {
    let index = (h + i) % capacity
    handler(storage[index])
}
```

---

### 🔵 [MIDIInputManager.swift:428-445] MUID DROP処理のログレベル引き上げ

**問題**
```swift
if subID2Val >= 0x30 && subID2Val <= 0x3F,
   let parsed = CIMessageParser.parse(data),
   parsed.destinationMUID != ourMUID,
   parsed.destinationMUID != MUID.broadcast,
   data.count >= 14 {
    // Drop PE messages destined for other MUIDs (e.g. macOS MIDI-CI 0x1E204DF).
    await MainActor.run {
        self.appendDebugLog("PE: DROP dst=\(parsed.destinationMUID) (not ours \(ourMUID)) sub=\(subID2)")
    }
    shouldDispatch = false
}
```

**理由**
macOS entityへのPE DROP処理は、KeyStageハング問題の核心的な修正の一つ。通常のdebugLogではなく、`peLogger.info`レベルで記録すべき（Console.appで追跡可能にする）。

**提案**
```swift
await MainActor.run {
    let logMsg = "PE: DROP dst=\(parsed.destinationMUID) (not ours \(ourMUID)) sub=\(subID2)"
    self.appendDebugLog(logMsg)
    peLogger.info("\(logMsg, privacy: .public)")
}
```

---

### 🔵 [MIDIInputManager.swift:645-658] ResourceListから`canSubscribe`を削除可能か検討

**問題**
```swift
await responder.registerResource("ResourceList", resource: ComputedResource(
    get: { _ in
        Data("""
        [{"resource":"DeviceInfo"},{"resource":"ChannelList","canSubscribe":true},{"resource":"ProgramList","canSubscribe":true},{"resource":"X-ParameterList","canSubscribe":true},{"resource":"X-ProgramEdit","canSubscribe":true}]
        """.utf8)
    },
    // ...
))
```

**理由**
コメントに「Step 3: Full PE/CI with Subscribe disabled in ResourceList」とあるが、実際には`canSubscribe:true`が4つのリソースに設定されている。もしKeyStageが自動Subscribe（0x38 command:start）を送ってくる場合、PEResponderが処理することになる。過去のハング原因がSubscribe関連だった可能性があるなら、本当に必要か再検証すべき。

**提案**
1. 一時的に`canSubscribe:false`でテストし、KeyStageのLCD更新が動作するか確認
2. 動作するなら、Subscribeを無効化してコード簡素化
3. 動作しないなら、現状維持だが「Subscribeが必須」の旨をコメント追加

---

### 🔵 [M2DXFeature.swift:84-87] 無限ループの意図をコメント化

**問題**
```swift
// Keep alive until view disappears (.task cancels automatically)
while !Task.isCancelled {
    try? await Task.sleep(for: .seconds(86400))
}
```

**理由**
`.task`モディファイアのライフサイクル維持のための無限ループだが、`86400秒（24時間）`の選択理由が不明。また、このループ自体が本質的に必要か（MIDIInputManager/AudioEngineは`.task`外でも動作可能なはず）も疑問。

**提案**
```swift
// MARK: Keep MIDI/Audio alive for view lifetime
// `.task` cancels this Task when the view disappears, triggering cleanup.
// We use an infinite sleep loop to keep the task alive without CPU usage.
// The 24-hour duration is arbitrary (any long duration works).
while !Task.isCancelled {
    try? await Task.sleep(for: .seconds(86400))
}
```

または、より明示的に:
```swift
// Alternative: use withTaskCancellationHandler
await withTaskCancellationHandler {
    // Keep alive indefinitely
    try? await Task.sleep(for: .seconds(.max))
} onCancel: {
    // Cleanup happens in outer scope (lines 87-88)
}
```

---

### 🔵 [M2DXAudioEngine.swift:359] Force unwrap on audioUnit

**問題**
```swift
let outputUnit = outputNode.audioUnit!
```

**理由**
AVAudioOutputNodeの`audioUnit`プロパティは`AudioUnit?`型。通常はnilにならないが、特殊な環境（macOS Catalystアプリなど）でnilになる可能性がある。

**提案**
```swift
guard let outputUnit = outputNode.audioUnit else {
    audioLogger.error("Failed to get audio unit from output node")
    return
}
```

---

### 🔵 [SettingsView.swift:307-314] PE Sniffer Mode切り替え時のMIDI再起動タイミング

**問題**
```swift
Toggle(isOn: Binding(
    get: { midiInput.peSnifferMode },
    set: { newValue in
        midiInput.peSnifferMode = newValue
        // Restart MIDI to apply mode change
        midiInput.stop()
        midiInput.start()
    }
))
```

**理由**
- `stop()` → `start()`が同期的に呼ばれるため、`stop()`内の非同期クリーンアップ（Task内のdisconnect/shutdown）が完了する前に`start()`が実行される可能性がある
- CoreMIDI接続状態が中途半端なまま再接続すると、デバイスが認識されない、MUIDが重複するなどの問題が起きうる

**提案**
```swift
set: { newValue in
    midiInput.peSnifferMode = newValue
    // Async restart to ensure cleanup completes
    Task {
        midiInput.stop()
        try? await Task.sleep(for: .milliseconds(100))
        midiInput.start()
    }
}
```

---

### 🔵 [MIDIInputManager.swift:256-258] PE Isolation Stepのマジックナンバー削除

**問題**
```swift
let peIsolationStep = 3  // Full PE/CI with Subscribe disabled in ResourceList
if peIsolationStep == 0 || peSnifferMode {
```

**理由**
本番コードにデバッグ用の段階的切り替え変数が残っている。Step 3で固定運用するなら削除し、Sniffer Modeのみで制御すべき。

**提案**
```swift
if peSnifferMode {
    appendDebugLog("SNIFF: Sniffer mode ON — PE Responder disabled")
} else {
    // PE/CI initialization (full capabilities)
    let sharedMUID = MUID(rawValue: 0x5404629)!
    // ... (CI/PE setup)
}
```

---

### 💡 [FMSynthEngine.swift:467-477] withOpのswitch文をinline配列アクセスに最適化可能

**問題**
```swift
@inline(__always)
mutating func withOp(_ i: Int, _ body: (inout FMOp) -> Void) {
    switch i {
    case 0: body(&ops.0)
    case 1: body(&ops.1)
    // ... (6 cases)
    default: break
    }
}
```

**理由**
タプルアクセスは既にインライン展開されるため、この`@inline(__always)`はコンパイラヒントとして有効だが、可読性を優先するなら`withUnsafeMutablePointer`を使った配列風アクセスも検討可能。ただし、現状で十分高速なので優先度は低い。

**コメント**
現状維持推奨。タプルベースのアクセスは安全で、コンパイラが十分最適化する。

---

### 💡 [M2DXAudioEngine.swift:60-64] masterVolumeのdidSetで冗長な代入

**問題**
```swift
public var masterVolume: Float = 0.8 {
    didSet {
        synth.setMasterVolume(masterVolume)
    }
}
```

**理由**
`@Observable`マクロが既に変更検知を行うため、`didSet`内での`setMasterVolume`呼び出しは必要。ただし、`didSet`が呼ばれた時点で値は既に更新済みなので、oldValueチェックは不要（SwiftUIの@Stateが重複変更をフィルタ）。

**コメント**
現状で問題なし。ただし、UIからの高速スライダー操作時に大量の`setMasterVolume()`呼び出しが発生する可能性があるため、必要に応じてデバウンス検討。

---

### 💡 [MIDIInputManager.swift:181] print文の残留

**問題**
```swift
private func appendDebugLog(_ line: String) {
    print("[M2DX] \(line)")  // TEMP: devicectl --console 用
```

**理由**
`os.Logger`を使っているため、`print()`は不要。開発中の一時的なログと思われるが、リリース前に削除すべき。

**提案**
```swift
private func appendDebugLog(_ line: String) {
    // Print to Xcode console (optional, remove in release build)
    #if DEBUG
    print("[M2DX] \(line)")
    #endif

    debugLog.append(line)
    // ... (rest of the code)
}
```

---

### 💡 [MIDIInputManager.swift:1010-1067] handleUMPData/handleReceivedDataの重複コード

**問題**
UMP処理（handleUMPData）とMIDI 1.0処理（handleReceivedData）で、NoteOn/Off/CC/PBの処理ロジックが重複している。

**提案**
共通処理を関数化して、DRY原則に従う。

```swift
private func dispatchNoteOn(_ note: UInt8, velocity16: UInt16) {
    if velocity16 == 0 {
        onNoteOff?(note)
    } else {
        onNoteOn?(note, velocity16)
    }
}

private func dispatchCC(_ controller: UInt8, value32: UInt32) {
    onControlChange?(controller, value32)
    if controller == 123 {
        for n: UInt8 in 0...127 { onNoteOff?(n) }
    }
}

// handleUMPData内:
case 0x9:
    dispatchNoteOn(byte3, velocity16: vel16)
```

---

## 良かった点

### 1. **Swift Concurrency完全準拠**
- 全クラスが`@MainActor`/`actor`/`@unchecked Sendable`で適切に隔離
- `os_unfair_lock`による最小限のロック範囲
- `.task`モディファイアによる自動キャンセル処理

### 2. **MIDI-CI PE実装の品質**
- KORG KeyStageとの互換性を実現（LCD更新成功）
- macOS entity除外ロジックで不要な通信を排除
- PE Notify debounce（500ms）で連続PC時のハング防止
- Sniffer Modeによる柔軟なデバッグ

### 3. **リアルタイム音声処理の最適化**
- LUT（Sine, PitchBend）による高速計算
- AVAudioSourceNodeでCoreAudioスレッド直接駆動
- Lock-free ring buffer（MIDIEventQueue）

### 4. **詳細なロギング**
- os.Logger（subsystem分離: MIDI/PE/CI/Audio）
- in-app debug log buffer（200行）
- PE専用フローログ（2000行）
- Console.appとの連携

### 5. **エラーハンドリング**
- AudioEngineError列挙型による明確なエラー分類
- AVAudioSessionの中断/ルート変更への対応
- MIDI接続エラーの適切な伝播

---

## 総評

M2DXプロジェクトは、**MIDI 2.0 UMP対応FMシンセ**として高い完成度を持つ。特に以下の点が優れている:

### 技術的強み
- **Swift 6並行性**: `@MainActor`/`actor`の適切な使用、Sendable準拠
- **リアルタイム性能**: Lock-free設計、LUT最適化、CoreAudioダイレクト駆動
- **MIDI-CI PE v1.1準拠**: KORG KeyStageとの相互運用性実現（LCD更新成功）
- **デバッグ容易性**: 3層ログ（os.Logger/debug buffer/PE flow log）

### 改善推奨事項（優先度順）

#### High Priority
1. **PE Notify debounce実装** (🟡Warning) — 連続PC時の古いプログラム名送信を防止
2. **Configuration Change再入ガード** (🟡Warning) — Task管理によるデバウンス
3. **macOS entity DROP処理ログ強化** (🔵Suggestion) — Console.app追跡性向上

#### Medium Priority
4. **print文削除** (💡Nitpick) — DEBUG条件分岐化
5. **PE Isolation Step削除** (🔵Suggestion) — 本番コードの簡素化
6. **@unchecked Sendableコメント** (🔵Suggestion) — 将来のメンテナンス性
7. **ResourceList canSubscribe検証** (🔵Suggestion) — 必要性の再確認

#### Low Priority
8. **LUTメモリ管理コメント** (🟡Warning) — 意図の明記（リーク許容）
9. **無限ループ意図コメント** (🔵Suggestion) — `.task`ライフサイクル説明
10. **handleUMP/Received統合** (💡Nitpick) — DRY原則

### 次のステップ
- iOS実機での長時間安定性テスト（KORG KeyStage接続）
- PE Subscribe自動受付の挙動確認（KeyStageが0x38 command:startを送るか？）
- macOS Sandboxing有効化時の動作確認（現在はfalse）

---

**結論**: 本コードベースは、Swift 6 + MIDI 2.0の最新技術を活用した高品質な実装である。指摘した改善点は、安定性向上とメンテナンス性向上のための「Better Practice」であり、現時点で致命的な問題は存在しない。KORG KeyStage LCD更新成功により、MIDI-CI PE実装の正しさが実証されている。

---

# コードレビューレポート (bankPC 1-based変更)

## 概要
- レビュー対象: MIDIInputManager.swift — bankPC 1-based変更
- レビュー日: 2026-02-08 15:51
- 変更内容: ProgramList/X-ProgramEdit/Notify の bankPC値を 0-based → 1-based に変更、PC受信時の配列インデックス変換追加

## サマリー
- 🔴 Critical: 0件
- 🟡 Warning: 0件
- 🔵 Suggestion: 2件

---

## 詳細

### 🔵 [行882-887] notifyProgramChange エッジケース：programIndex=0 の処理

**現在の実装**
```swift
private func notifyProgramChange(programIndex: UInt8) {
    // KeyStage sends 1-based bankPC values as PC numbers, convert to 0-based array index
    currentProgramIndex = max(0, Int(programIndex) - 1)
    let name = currentProgramName
    let idx = currentProgramIndex
    appendDebugLog("PC: program=\(idx) name=\(name)")
```

**指摘**
KeyStageが `programIndex=0` を送信した場合、`max(0, 0 - 1) = 0` となり、プリセット配列の0番目（期待では1番目のプリセット）が選択される。

しかし、KeyStageの1-based仕様では：
- `programIndex=1` → 配列インデックス0
- `programIndex=0` → **仕様外の値（存在しない）**

この実装は `programIndex=0` を「プリセット1番」として扱うため、結果的に安全だが、論理的には `programIndex < 1` のガード節を追加した方が意図が明確。

**提案**
```swift
private func notifyProgramChange(programIndex: UInt8) {
    // KeyStage sends 1-based bankPC values as PC numbers
    // programIndex=0 is invalid but treated as 1 for safety
    let adjusted = max(1, Int(programIndex))
    currentProgramIndex = adjusted - 1
    let name = currentProgramName
    let idx = currentProgramIndex
    appendDebugLog("PC: program=\(programIndex) → idx=\(idx) name=\(name)")
```

**理由**
- `programIndex=0` の処理意図が明確になる
- デバッグログに受信値 `programIndex` と変換後の `idx` 両方が記録され、不正値受信時の追跡が容易

---

### 🔵 [行789-797] currentProgramName エッジケース：範囲外インデックスのフォールバック

**現在の実装**
```swift
private var currentProgramName: String {
    let presets = DX7FactoryPresets.all
    if currentProgramIndex < presets.count {
        return "\(currentProgramIndex + 1):\(presets[currentProgramIndex].name)"
    }
    return "0:INIT VOICE"
}
```

**指摘**
`currentProgramIndex >= presets.count` の場合、フォールバックとして `"0:INIT VOICE"` を返すが、1-based表記では `"0:"` は不自然。

`currentProgramIndex` が範囲外になるシナリオ：
1. KeyStageが `program > presetCount` のPC値を送信
2. `notifyProgramChange` で `currentProgramIndex = program - 1` → 範囲外

現在の実装ではこれをフォールバックで救済できているが、表記が0-basedになる矛盾がある。

**提案**
```swift
private var currentProgramName: String {
    let presets = DX7FactoryPresets.all
    if currentProgramIndex >= 0 && currentProgramIndex < presets.count {
        return "\(currentProgramIndex + 1):\(presets[currentProgramIndex].name)"
    }
    // Fallback for invalid index (out of range)
    return "1:INIT VOICE"
}
```

**理由**
- 1-based表記の一貫性（`"0:"` → `"1:"`）
- 範囲外値受信時もKeyStage LCDに正常な表示が期待できる

---

## bankPC 1-based変換の整合性チェック ✅

### ✅ 変更箇所1: ProgramList GET (行717)
```swift
return "{\"title\":\"\(globalIndex + 1):\(preset.name)\",\"bankPC\":[0,0,\(globalIndex + 1)]}"
```
**評価**: ✅ 正しい
- `globalIndex` は0-basedループインデックス
- `bankPC[2]` に `globalIndex + 1` を設定 → 1-based

---

### ✅ 変更箇所2: X-ProgramEdit GET (行736)
```swift
let json = "{\"name\":\"\(name)\",\"bankPC\":[0,0,\(idx + 1)],\"currentValues\":[...]}"
```
**評価**: ✅ 正しい
- `idx = currentProgramIndex` (0-based)
- `bankPC[2]` に `idx + 1` を設定 → 1-based

---

### ✅ 変更箇所3: notifyProgramChange X-ProgramEdit Notify (行897)
```swift
let xProgramEditBody = Data("{\"name\":\"\(name)\",\"bankPC\":[0,0,\(idx + 1)],\"currentValues\":[...]".utf8)
```
**評価**: ✅ 正しい
- `idx = currentProgramIndex` (0-based)
- `bankPC[2]` に `idx + 1` を設定 → 1-based

---

### ✅ 変更箇所4: PC受信 → 配列インデックス変換 (行884)
```swift
currentProgramIndex = max(0, Int(programIndex) - 1)
```
**評価**: ✅ 正しい
- `programIndex` はKeyStageからの1-based PC値
- `-1` で 0-based配列インデックスに変換
- `max(0, ...)` で負値保護（上記Suggestion参照）

---

### ✅ ProgramList responseHeader: offsetフィールド削除 (行721-723)
```swift
responseHeader: { _, _ in
    Data("{\"status\":200,\"totalCount\":\(presetCount)}".utf8)
}
```
**評価**: ✅ 正しい
- `offset` フィールド削除済み
- KeyStageのナビゲーション混乱を防ぐための変更として妥当

---

## バグリスク評価

### 1. PC値境界値テスト
| PC値 | 期待動作 | 実装結果 | 評価 |
|------|---------|---------|------|
| `0` | 範囲外（仕様外） | `currentProgramIndex=0` (プリセット1番) | ⚠️ 安全だが不正値 |
| `1` | プリセット1番 | `currentProgramIndex=0` (プリセット1番) | ✅ |
| `10` | プリセット10番 | `currentProgramIndex=9` (プリセット10番) | ✅ |
| `11` | 範囲外（presetCount=10） | `currentProgramIndex=10` → フォールバック | ✅ |

**結論**: 境界値処理は安全。Suggestionで改善可能。

---

### 2. 3箇所の bankPC 1-based変換の一貫性
| 箇所 | 変換式 | 結果 |
|------|--------|------|
| ProgramList GET | `globalIndex + 1` | ✅ 1-based |
| X-ProgramEdit GET | `idx + 1` | ✅ 1-based |
| X-ProgramEdit Notify | `idx + 1` | ✅ 1-based |

**結論**: 3箇所全て統一されており、整合性あり。

---

### 3. 逆変換 (PC受信 → 配列インデックス)
```swift
currentProgramIndex = max(0, Int(programIndex) - 1)
```

**テストケース**:
| `programIndex` (1-based) | 変換後 `currentProgramIndex` (0-based) | 評価 |
|-------------------------|---------------------------------------|------|
| `1` | `0` | ✅ |
| `2` | `1` | ✅ |
| `10` | `9` | ✅ |
| `0` | `0` | ⚠️ 仕様外だが安全 |

**結論**: 正しく変換されている。

---

## 良かった点
- ✅ **3箇所の bankPC 1-based変換が完全に一貫**している
- ✅ **PC受信時の逆変換（-1）が正しく実装**されている
- ✅ **エッジケース（範囲外インデックス）にフォールバック処理**がある
- ✅ **コメントで変換意図を明記**（例: "KeyStage sends 1-based bankPC values as PC numbers"）
- ✅ **ProgramList responseHeaderからoffsetフィールド削除**で不要なメタデータを排除

---

## 総評

### コード品質: ⭐⭐⭐⭐☆ (4/5)

**強み**:
1. **整合性**: 3箇所の bankPC 1-based変換が完璧に統一されている
2. **安全性**: 範囲外インデックスのフォールバック処理で実行時エラーを回避
3. **可読性**: 変換ロジックにコメントがあり、意図が明確

**改善提案**:
1. `programIndex=0` の処理をより明示的にする（Suggestion 1）
2. フォールバック表記を1-basedに統一（Suggestion 2）

### 変更の妥当性: ✅ 完全に妥当

KeyStageが1-basedでbankPC値を解釈する仕様に合わせた変更として、論理的に正しい。実機テストで Value UP/DOWN が順番通り動作した事実が実装の正しさを裏付けている。

### リスク評価: 🟢 低リスク

- Criticalな問題なし
- Warningなし
- Suggestionは「より良い」レベルの改善提案

**推奨アクション**:
- 現在の実装のまま iOS実機ビルド → コミット可能
- Suggestionは次回リファクタリング時に検討でも可

---

## 次のステップ
1. iOS実機ビルド → KeyStage Value UP/DOWN動作確認
2. コミット（現在の実装で問題なし）
3. （オプション）Suggestion 1,2をリファクタリングに追加

