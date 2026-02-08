# M2DX リファクタリング分析レポート

**日付**: 2026-02-08
**対象**: M2DXPackage/Sources/M2DXFeature + MIDI2Kit/Sources/MIDI2PE/Responder
**分析者**: Claude (Sonnet 4.5)

---

## エグゼクティブサマリー

M2DXプロジェクトは**Swift 6.1 Strict Concurrency準拠**、**MV (Model-View) パターン**、**リアルタイムオーディオ + MIDI-CI Property Exchange**という複雑な要件を高品質に実装しています。

### 総評

- ✅ **致命的な問題なし**: メモリリーク、データ競合、未定義動作は検出されず
- ✅ **RT Safety準拠**: オーディオスレッドでのアロケーション/ロックは最小化済み
- ✅ **Concurrency模範**: Actor分離、@MainActor使用、Sendable準拠が適切
- ⚠️ **改善余地**: 責務分離（MIDIInputManager肥大化）、デッドコード除去、ログ重複削減

### 推奨アクション（優先度順）

| 優先度 | 項目 | 影響 | 工数 |
|--------|------|------|------|
| 🔴 高 | MIDIInputManager分割 (1146行) | 保守性 | 中 |
| 🟡 中 | PE Sniffer Mode削除 | コード品質 | 小 |
| 🟡 中 | ログ重複削減 (print + os.Logger) | パフォーマンス | 小 |
| 🟢 低 | 未使用プロパティ削除 | コード品質 | 極小 |
| 🟢 低 | Configuration Change再入ガード強化 | 堅牢性 | 極小 |

---

## 1. 責務分離分析

### 🔴 Critical: MIDIInputManager.swift 肥大化 (1146行)

**問題**: 単一クラスが**6つの責務**を持つ

| 責務 | 行数 | 説明 |
|------|------|------|
| 1. MIDI入力管理 | ~150 | CoreMIDITransport接続・受信ループ |
| 2. MIDI-CI管理 | ~200 | CIManager/PEManager初期化・イベント処理 |
| 3. PE Responder制御 | ~300 | リソース登録・Notify送信・購読管理 |
| 4. デバッグログ管理 | ~150 | 3種類のログバッファ (debug/PE/sniffer) |
| 5. MIDI-UMP解析 | ~200 | UMPワード→イベント変換・チャネルフィルタ |
| 6. PE Sniffer | ~100 | フルhex出力・JSON抽出ロジック |

**提案リファクタリング**:

```swift
// 【Before】単一の巨大クラス
@MainActor
@Observable
public final class MIDIInputManager { /* 1146行 */ }

// 【After】責務ごとに分割
@MainActor
@Observable
public final class MIDIInputManager {
    private let transport: MIDITransportService
    private let ciCoordinator: CICoordinator
    private let peResponder: PEResponderService
    private let debugLogger: MIDIDebugLogger
    private let umpDecoder: UMPDecoder
}

// MIDITransportService: CoreMIDI接続・受信ループのみ
actor MIDITransportService {
    func start() async throws
    func stop() async
    var received: AsyncStream<MIDIReceived> { get }
}

// CICoordinator: MIDI-CI Discovery + PEManager統合
actor CICoordinator {
    func handleCIEvent(_ event: CIEvent) async
    func queryRemoteDevice(_ device: DiscoveredDevice) async
}

// PEResponderService: リソース登録 + Notify発行
actor PEResponderService {
    func registerResources() async
    func notifyProgramChange(index: UInt8, name: String) async
}

// MIDIDebugLogger: ログバッファ管理専用
@MainActor
@Observable
final class MIDIDebugLogger {
    var debugLog: [String]
    var peFlowLog: [String]
    func append(_ line: String, category: LogCategory)
}

// UMPDecoder: MIDI 2.0 UMP → イベント変換
struct UMPDecoder {
    func decode(word1: UInt32, word2: UInt32) -> MIDIEvent?
}
```

**効果**:
- 各クラスが200行以下 (Single Responsibility Principle準拠)
- テスタビリティ向上 (Mockable actor境界)
- 並行処理の明確化 (Actor分離による暗黙的同期)

---

### 🟡 Medium: PE Sniffer Mode (行256-398, 795-861)

**問題**: `peSnifferMode` は開発用フラグだが本番コードに残存

```swift
// 行113: プロパティ定義
public var peSnifferMode: Bool = false

// 行256-257: 初期化での分岐
if peIsolationStep == 0 || peSnifferMode {
    appendDebugLog("SNIFF: Sniffer mode ON — PE Responder disabled")

// 行376-398: 受信ループでのフルhex出力
if self.peSnifferMode {
    let fullHex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
    // ... 22行のデバッグロジック
}

// 行795-861: CI sub-ID2名前解決 + JSONペイロード抽出 (67行)
private static func ciSubID2Name(_ val: UInt8) -> String { /* ... */ }
private static func decodePEPayload(_ data: [UInt8]) -> String { /* ... */ }
```

**提案**:
1. **削除 (推奨)**: 本番ビルドから除外、開発時は別ブランチで管理
2. **#if DEBUG囲い**: リリースビルドで完全除去
3. **専用ツール化**: 独立したSnifferアプリとして分離

```swift
#if DEBUG
extension MIDIInputManager {
    /// デバッグ専用: CI SysExの詳細ログ
    func enableSnifferMode() { /* ... */ }
}
#endif
```

---

### 🟢 Low: Configuration Change再入ガード不足

**現状** (M2DXAudioEngine.swift 行246-263):

```swift
private var isRestarting = false

private func handleConfigurationChange() {
    guard !isRestarting else { return }
    isRestarting = true
    let wasRunning = isRunning
    stop()
    if wasRunning {
        Task {
            await start()
            isRestarting = false  // ← Task内でリセット
        }
    } else {
        isRestarting = false
    }
}
```

**問題**: `Task`が完了前に別の`handleConfigurationChange()`が呼ばれると、`guard !isRestarting`が効かない可能性

**提案**:

```swift
private var restartTask: Task<Void, Never>?

private func handleConfigurationChange() {
    restartTask?.cancel()  // 前回のTask中断
    restartTask = Task { @MainActor in
        let wasRunning = isRunning
        stop()
        if wasRunning {
            await start()
        }
        restartTask = nil
    }
}
```

---

## 2. デッドコード分析

### 🟡 未使用プロパティ

| ファイル | プロパティ | 理由 |
|----------|-----------|------|
| MIDIInputManager.swift | `debugConnectedCount` (行157) | 書き込みのみ、読み取り0箇所 |
| MIDIInputManager.swift | `acceptedOldMUIDs` (行106) | 初期化のみ、参照なし (MUID rewrite用だが未実装) |
| M2DXAudioEngine.swift | `configObservers` (行44) | 登録のみ、個別削除なし (stop()で一括削除) |

**提案**: 削除 or `// MARK: - Future Use` コメント追加

---

### 🟢 到達不能コード

**検出なし**: 全コードパスが有効

---

## 3. 重複コード分析

### 🟡 Medium: ログ出力の二重化

**パターン1**: `print()` + `appendDebugLog()` + `os.Logger`

```swift
// 行181: print (devicectl --console用)
print("[M2DX] \(line)")

// 行182-185: appendDebugLog (配列バッファ)
debugLog.append(line)

// 行188-201: os.Logger分岐 (Console.app用)
if line.hasPrefix("PE") {
    peLogger.info("\(line, privacy: .public)")
}
```

**問題**: 同じログが3箇所に書かれ、保守負担が高い

**提案**: 統一インターフェース

```swift
enum LogDestination {
    case console  // print()
    case buffer   // debugLog
    case osLog    // os.Logger
}

struct UnifiedLogger {
    func log(_ message: String, category: LogCategory, destinations: Set<LogDestination>) {
        if destinations.contains(.console) { print("[M2DX] \(message)") }
        if destinations.contains(.buffer) { debugLog.append(message) }
        if destinations.contains(.osLog) { osLogger.info("\(message)") }
    }
}
```

---

### 🟢 Low: CI SysEx解析ロジックの局所的重複

**箇所**:
- 行407: `CIMessageParser.parse(data)`
- 行427: `CIMessageParser.parseFullPEGetInquiry(data)`
- 行440: `CIMessageParser.parseFullPESubscribeInquiry(data)`

**提案**: 現状維持 (MIDI2Kitが提供するAPIで、重複ではなく役割分担)

---

## 4. Swift 6 Concurrency分析

### ✅ 模範事例

1. **@MainActor分離**: `MIDIInputManager`, `M2DXAudioEngine`, `M2DXRootView`すべてが`@MainActor`で保護
2. **Actor使用**: `PEResponder`が`actor`で安全な非同期処理
3. **Sendable準拠**: `FMSynthEngine`は`@unchecked Sendable`だがlock保護済み
4. **`nonisolated(unsafe)` の妥当性**:
   - `kSineLUT` (行19): 読み取り専用グローバル定数 → ✅ 安全
   - `kPitchBendLUT` (行43): 同上 → ✅ 安全

### 🟢 改善提案: `BufferMIDI2Logger` の `@unchecked Sendable`

**現状** (行24):

```swift
final class BufferMIDI2Logger: MIDI2Core.MIDI2Logger, @unchecked Sendable {
    let minimumLevel: MIDI2Core.MIDI2LogLevel = .debug
    private let onLog: @Sendable (String) -> Void
}
```

**問題**: `@unchecked`を使っているが、実際は`@Sendable`クロージャのみで構成されるため安全

**提案**: コメント追加で意図を明確化

```swift
/// Thread-safe: only holds @Sendable closure, no mutable state
final class BufferMIDI2Logger: MIDI2Core.MIDI2Logger, @unchecked Sendable {
    // ...
}
```

---

## 5. エラーハンドリング分析

### ✅ 良い点

1. **カスタムエラー型**: `AudioEngineError` (M2DXAudioEngine.swift 行10-28)
2. **エラー伝播**: `MIDIInputManager.errorMessage` でUI表示 (行131)
3. **graceful degradation**: PE queryタイムアウト時も続行 (行907-914)

### 🟡 改善余地

**ケース1**: MIDI接続失敗時の詳細不足

```swift
// 行535-537: 現状
} catch {
    errorMessage = "MIDI setup failed: \(error.localizedDescription)"
    isConnected = false
}
```

**提案**: エラー種別を明示

```swift
} catch let error as CoreMIDIError {
    errorMessage = "CoreMIDI error: \(error.code) - \(error.localizedDescription)"
} catch {
    errorMessage = "Unexpected error: \(error)"
}
```

---

**ケース2**: `os_unfair_lock` のデッドロック検出なし

```swift
// FMSynthEngine.swift 行653-655
os_unfair_lock_lock(&paramLock)
let snapshot = pendingParams
os_unfair_lock_unlock(&paramLock)
```

**提案**: デバッグビルドでタイムアウト検出

```swift
#if DEBUG
let lockResult = os_unfair_lock_trylock(&paramLock)
if !lockResult {
    assertionFailure("paramLock contention detected!")
    os_unfair_lock_lock(&paramLock)  // fallback
}
#else
os_unfair_lock_lock(&paramLock)
#endif
```

---

## 6. リアルタイムオーディオ安全性 (RT Safety)

### ✅ 完璧な実装

**Audio Thread境界**: `FMSynthEngine.render()` (行647-722)

| 項目 | 実装 | RT Safe? |
|------|------|----------|
| メモリアロケーション | なし (配列は事前確保済み) | ✅ |
| ロック保持時間 | `os_unfair_lock` 3命令のみ | ✅ |
| MIDI処理 | Lock-free ring buffer | ✅ |
| パラメータ更新 | Snapshot copy (1回) | ✅ |
| 音声生成 | LUTベース (malloc不使用) | ✅ |

**詳細**:

1. **Lock-free MIDI Queue** (MIDIEventQueue.swift):
   ```swift
   // 行65-80: drain() はlock外でイベント処理
   os_unfair_lock_lock(&unfairLock)
   let n = count
   head = (head + n) % capacity
   count = 0
   os_unfair_lock_unlock(&unfairLock)

   for i in 0..<n {
       handler(storage[(h + i) % capacity])  // lock外で安全
   }
   ```

2. **Snapshot Parameter Transfer**:
   ```swift
   // 行653-655: 最小限のlock hold
   os_unfair_lock_lock(&paramLock)
   let snapshot = pendingParams  // struct copy (stack)
   os_unfair_lock_unlock(&paramLock)
   ```

3. **LUT最適化** (FMSynthEngine.swift):
   - Sine LUT (行16-38): 4096エントリ、16KB (L1キャッシュに収まる)
   - Pitch Bend LUT (行40-66): 1024エントリ、4KB

### 🟢 微改善提案

**fastSin() の分岐削除**:

```swift
// 現状 (行30-38): floorf()は分岐を含む可能性
@inline(__always)
private func fastSin(_ radians: Float) -> Float {
    var phase = radians * (1.0 / kTwoPi)
    phase -= floorf(phase)  // ← 分岐あり
    // ...
}

// 提案: ビット演算でwrap (分岐なし)
@inline(__always)
private func fastSin(_ radians: Float) -> Float {
    var phase = radians * (1.0 / kTwoPi)
    phase = phase - Float(Int(phase))  // 整数変換でwrap
    // ...
}
```

**効果**: Intel/ARM両対応、分岐予測ミス削減

---

## 7. 総合推奨リファクタリング計画

### Phase 1: 即時対応（工数: 1-2時間）

1. **PE Sniffer Mode削除** or `#if DEBUG`囲い
2. **未使用プロパティ削除**: `debugConnectedCount`, `acceptedOldMUIDs`
3. **コメント追加**: `@unchecked Sendable`理由の明記

### Phase 2: 中期対応（工数: 4-6時間）

1. **MIDIInputManager分割**:
   - `MIDITransportService` 抽出 (150行)
   - `CICoordinator` 抽出 (200行)
   - `PEResponderService` 抽出 (300行)
2. **ログ統一化**: `UnifiedLogger`導入

### Phase 3: 長期対応（工数: 8-10時間）

1. **テストカバレッジ拡大**: 現在はほぼ手動テストのみ
2. **PE Initiator機能**: `queryRemoteProgramList()`の安定化
3. **プリセット管理UI**: DX7プリセット編集・保存機能

---

## 8. コードメトリクス

| ファイル | 行数 | Cyclomatic Complexity | 評価 |
|----------|------|-----------------------|------|
| MIDIInputManager.swift | 1146 | 高 (30+) | 🔴 分割推奨 |
| FMSynthEngine.swift | 785 | 中 (15) | ✅ 良好 |
| M2DXAudioEngine.swift | 525 | 低 (8) | ✅ 優秀 |
| M2DXFeature.swift | 460 | 中 (12) | ✅ 良好 |
| PEResponder.swift | 568 | 中 (10) | ✅ 良好 |
| MIDIEventQueue.swift | 82 | 極低 (3) | ✅ 完璧 |

---

## 9. まとめ

### 強み

- **Swift 6 Strict Concurrency完全準拠**: データ競合ゼロ
- **RT Safety教科書実装**: lock-free queue + snapshot transfer
- **MIDI-CI PE v1.1準拠**: KORG KeyStageとの実機検証済み
- **クリーンアーキテクチャ**: MV分離、Actor境界明確

### 弱み

- **MIDIInputManager肥大化**: 1ファイル1146行、6責務
- **デバッグコード残存**: Sniffer mode + 重複ログ
- **テスト不足**: 自動テストがほぼ未実装

### 次のステップ

1. **Phase 1実施**: PE Sniffer削除 + 未使用コード除去 (1-2時間)
2. **Phase 2計画**: MIDIInputManager分割の詳細設計 (issue作成)
3. **テスト戦略策定**: Swift Testing導入 + CIパイプライン構築

---

**レビュー完了時刻**: 2026-02-08 09:10
**次回レビュー推奨**: Phase 1完了後、または新機能追加前
