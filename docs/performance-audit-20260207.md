# M2DX Performance Audit Report

**Date:** 2026-02-07
**Analyst:** Claude Opus 4
**Total Source Lines:** ~5,465 lines across 15 Swift files
**Platform:** iOS 18.0+ / Swift 6.1+ / AVAudioSourceNode

---

## Executive Summary

M2DXは16ポリフォニー・6オペレータのDX7互換FMシンセサイザーで、AVAudioSourceNodeによるリアルタイムオーディオレンダリングを行っている。全体的にコード品質は高く、リアルタイムオーディオの基本原則（ヒープ割り当て回避、シンプルなロック戦略）を概ね守っている。ただし、以下の領域で性能改善の余地がある。

### 重大度サマリ

| 重大度 | 件数 | 概要 |
|--------|------|------|
| **Critical** | 2 | NSLockによるrender thread全体ロック、MIDIEventQueue.drain()でのヒープ割り当て |
| **High** | 3 | sinf()をフレームごとに最大96回呼出、sqrtf()のフレーム内計算、powf()のリアルタイム呼出 |
| **Medium** | 5 | debugLog無制限成長、@Observable変更通知頻度、peFlowLog無制限、算術テーブル未最適化、Voice配列CoW |
| **Low** | 4 | groupedCategories再計算、Canvas描画、EnvelopeDrag精度、FactoryPresets常駐メモリ |

---

## 1. オーディオレンダリング性能（Critical/High）

### 1.1 NSLock がrender thread全体を保持（Critical）

**場所:** `FMSynthEngine.swift:509`

```swift
func render(into bufferL: ..., frameCount: Int) {
    lock.lock(); defer { lock.unlock() }
    // ← render全体（MIDIドレイン + 全フレーム生成）をロック保持
```

**問題:**
- `render()`はCoreAudioリアルタイムスレッドから呼ばれる。NSLockはpriority inversionに対する保護がない
- UI threadで`setOperatorLevel()`等を呼ぶとlock競合が発生し、audio glitch（ドロップアウト）の原因になる
- ロック保持時間が長い：256フレーム × 16ボイス処理の全期間（推定0.1-0.5ms）

**影響度:**
- 48kHz/256フレームバッファの場合、バッファ期間は約5.33ms
- ロック保持中にUI threadのパラメータ変更がブロックされ、逆にUI threadがロック保持中にrender callbackがブロックされる
- iOSの厳格なリアルタイムデッドライン下ではaudio dropoutに直結

**推奨:**
- `os_unfair_lock`（`OSAllocatedUnfairLock`）への移行（MIDIEventQueueで既に使用）
- または、パラメータ変更をすべてMIDIEventQueue経由のメッセージパッシングに統一し、render内でのロックを完全排除
- lockless ring bufferパターンの採用（SPSC: Single Producer Single Consumer）

### 1.2 MIDIEventQueue.drain() がヒープ割り当てを行う（Critical）

**場所:** `MIDIEventQueue.swift:49-56`

```swift
func drain() -> [MIDIEvent] {
    lock.withLock { buffer in
        guard !buffer.isEmpty else { return [] }
        let events = buffer          // ← Array copy → ヒープ割り当て
        buffer.removeAll(keepingCapacity: true)
        return events
    }
}
```

**問題:**
- `let events = buffer` は Swift Array の Copy-on-Write により、ほとんどの場合ヒープ割り当てが発生する
- `return []` も空配列のヒープ割り当てが発生する可能性がある
- CoreAudioリアルタイムスレッドでのmalloc/freeは厳禁（リアルタイム保証の喪失）

**影響度:**
- バッファ256フレームごとに1回のdrain()呼出。フレームレートが高い場合（48kHz/128frames = 375回/秒）特に深刻
- mallocがロックを取得する可能性があり、priority inversionの追加リスク

**推奨:**
- Fixed-size ring buffer（配列ではなくUnsafeMutableBufferPointer）で実装し、drain時にコピーではなくポインタスワップを使う
- または、render内でインプレース処理（drain結果をrender外の固定バッファに書き出し）

### 1.3 sinf() 呼出頻度（High）

**場所:** `FMSynthEngine.swift:153`

```swift
let output = sinf((phase + mod + fbMod) * kTwoPi) * envLevel * level
```

**CPU負荷計算（ワーストケース: 16ボイス全発音時）:**

| 項目 | 値 |
|------|-----|
| ボイス数 | 16 |
| オペレータ数/ボイス | 6 |
| sinf()呼出/フレーム | 16 × 6 = 96 |
| フレーム/バッファ(256) | 256 |
| sinf()呼出/バッファ | 96 × 256 = 24,576 |
| sinf()呼出/秒(48kHz) | 96 × 48,000 = 4,608,000 |

**sinf()のコスト:**
- Apple Silicon (A15以降) の sinf(): 約10-15サイクル（vsinf NEON最適化済み）
- 4,608,000 × 12.5サイクル = 57,600,000サイクル/秒
- A15 (3.23GHz) での使用率: ~1.8%

**判定:** iPhone 14以降では問題なし。iPhone SE (A13) でも約2.5%程度で許容範囲。ただし、LUT（ルックアップテーブル）による高速化で更に改善可能。

**推奨:**
- 2048点のsinテーブル + 線形補間でsinf()を置換（品質維持可能）
- vDSP/Accelerate frameworkのvsinf()でSIMDバッチ処理

### 1.4 sqrtf() がフレームごとに呼ばれる（High）

**場所:** `FMSynthEngine.swift:541`

```swift
output /= sqrtf(Float(activeCount)) * kVoiceNormalizationScale
```

**問題:**
- 各フレームでsqrtf()が呼ばれる（256回/バッファ）
- activeCountは通常フレーム間で変化しない

**推奨:**
- `1.0 / (sqrtf(Float(activeCount)) * kVoiceNormalizationScale)` をフレームループ外でキャッシュし、乗算で置換
- activeCountをフレームループ前に確定し、逆数テーブル（1/sqrt(1)...1/sqrt(16)）を事前計算

### 1.5 powf() がリアルタイムパスで呼ばれる（High）

**場所:** `FMSynthEngine.swift:598`

```swift
pitchBendFactor = powf(2.0, semitones / 12.0)
```

**問題:**
- `doPitchBend32()`はrender内（MIDIイベント処理時）で呼ばれる
- powf()はsinf()より重い（約20-30サイクル）
- ピッチベンド連続入力時、フレームごとに複数回呼ばれる可能性

**推奨:**
- ピッチベンドテーブル（4096点のpow(2, x/12)テーブル）の事前計算
- または、線形近似による高速化

---

## 2. MIDIイベント処理レイテンシ（Medium）

### 2.1 全パスのレイテンシ分析

```
CoreMIDI callback
  ↓ (transport.received AsyncSequence)
MIDIInputManager.handleUMPData/handleReceivedData (MainActor)
  ↓ (callback: onNoteOn/onNoteOff)
M2DXAudioEngine.noteOn/noteOff (MainActor)
  ↓ (MIDIEventQueue.enqueue)
MIDIEventQueue (OSAllocatedUnfairLock)
  ↓ (drain at next render callback)
FMSynthEngine.render() (audio thread)
```

**レイテンシ内訳:**

| ステージ | レイテンシ |
|----------|------------|
| CoreMIDI → AsyncSequence yield | ~0.1ms |
| AsyncSequence → MainActor dispatch | **0.5-2ms** (ランキューイング) |
| MainActor → MIDIEventQueue.enqueue | <0.01ms |
| enqueue → 次回render drain | **0-5.33ms** (バッファサイズ依存) |
| **合計** | **0.6-7.4ms** |

**問題点:**
- MainActor経由のルーティングが不要なオーバーヘッドを追加（0.5-2ms）
- MIDIInputManagerが@MainActorで、MIDI受信もMainActorスケジュールされている

**推奨:**
- CoreMIDI callback → MIDIEventQueue.enqueue() の直接パスを構築し、MainActor経由を排除
- これにより最大2msのレイテンシ削減が可能

### 2.2 OSAllocatedUnfairLock の競合特性

**場所:** `MIDIEventQueue.swift:32`

MIDIEventQueueは`OSAllocatedUnfairLock`を使用しており、これは正しい選択。

**良い点:**
- priority inversion保護がある（os_unfair_lockベース）
- ロック保持時間が極めて短い（enqueue: append、drain: swap）

**問題点:**
- drain()での配列コピー（1.2で既述）がロック保持時間を延ばす
- enqueue側（MainActor）とdrain側（audio thread）が同時アクセスする確率は低いが、MIDI連打時に競合可能

---

## 3. SwiftUI描画パフォーマンス（Medium/Low）

### 3.1 @Observable変更通知の粒度（Medium）

**場所:** `M2DXAudioEngine.swift`, `MIDIInputManager.swift`

**問題:**
- `M2DXAudioEngine`は`@Observable`で、`isRunning`, `algorithm`, `masterVolume`, `operatorLevels`, `errorMessage`, `currentOutputDevice`をすべて公開
- `operatorLevels`配列の1要素変更で`@Observable`の変更通知が発火し、`operatorLevels`を参照するすべてのビューが再描画される
- `MIDIInputManager`の`debugReceiveCount`, `debugLastReceived`, `debugLastEvent`がMIDIメッセージごとに更新され、SettingsViewの大量の再描画を引き起こす

**影響度:**
- Settings画面が開いている間、MIDIメッセージ受信のたびに全デバッグ表示が再描画される
- NoteOn/NoteOff高速連打時（ピアノロール再生など）に顕著

**推奨:**
- デバッグ関連プロパティの更新をスロットリング（例: 100ms間隔）
- SettingsViewが表示されていない時はデバッグプロパティの更新を停止

### 3.2 debugLog配列への頻繁な変更（Medium）

**場所:** `MIDIInputManager.swift:178`

```swift
debugLog.insert(line, at: 0)  // ← 先頭挿入 = O(n) コピー
if debugLog.count > debugLogMax {
    debugLog.removeLast()
}
```

**問題:**
- `insert(at: 0)`は配列の全要素をシフトする O(n) 操作
- MIDIメッセージ受信のたびに呼ばれ、最大200要素のシフト
- `@Observable`プロパティのため、変更のたびにSwiftUI通知が発火

**推奨:**
- 循環バッファ（ring buffer）パターンに置換し、先頭挿入を O(1) に
- または`append()`で末尾追加し、表示時に`reversed()`

### 3.3 peFlowLog の無制限成長（Medium）

**場所:** `MIDIInputManager.swift:173`

```swift
/// PE flow log: dedicated buffer for PE communication only (oldest first, unlimited during session)
public private(set) var peFlowLog: [String] = []
```

**問題:**
- コメントにも「unlimited during session」と明記されている
- 長時間セッションでメモリ使用量が無制限に増加
- PE通信が活発な環境では数千エントリに到達する可能性

**推奨:**
- 上限（例: 1000件）を設けるか、メモリ警告時にクリア

### 3.4 PresetPickerView の groupedCategories（Low）

**場所:** `PresetPickerView.swift:64-81`

```swift
private var groupedCategories: [(PresetCategory, [DX7Preset])] {
    // O(n^2) に近いロジック（全プリセットを2回走査）
```

**問題:**
- computed propertyのため、body再評価のたびに再計算
- 現在10プリセットなので実害なし。プリセット数が増加した場合に影響

### 3.5 AlgorithmSelectorView の Canvas 描画（Low）

**場所:** `AlgorithmSelectorView.swift:65-67`

- 32アルゴリズムそれぞれでCanvas描画を実行
- LazyVGridを使用しているため、表示範囲外は描画されず問題なし
- 個々のCanvas内の`operatorPositions()`計算は軽量

---

## 4. メモリ使用量分析

### 4.1 Voice/FMOp/Envelope のメモリレイアウト

**構造体サイズ推定:**

| 型 | フィールド数 | 推定サイズ(bytes) |
|----|-------------|-------------------|
| Envelope | 14 × Float + 1 enum | ~60B |
| FMOp | 10 × Float + 1 Envelope | ~104B |
| Voice | 6 × FMOp (tuple) + 5 fields | ~640B |
| Voice × 16 | Array<Voice> | ~10,240B (~10KB) |

**良い点:**
- Voice配列は`Array`（ヒープ）で正しい。タプル版はスタックオーバーフローのリスクがあった
- Envelope, FMOp は struct（値型）で、コピー時のヒープ割り当てなし

**問題点:**
- `voices`配列はrender内で`voices[i].process()`として変更されるが、Swiftの配列は`inout`アクセスでCopy-on-Writeトリガーしない（既にuniquelyReferenced）ため、実質問題なし
- ただし、`setOperatorLevel()`等のUIスレッドからの呼出でロック保持中にvoices配列を変更するため、CoWバッファの共有解除が発生する理論的リスクあり

### 4.2 DX7FactoryPresets の静的メモリ

```swift
public static let all: [DX7Preset] = [...]  // 10プリセット
```

**推定メモリ:**
- 各DX7Preset: ~500B（6 operators × ~70B + name + UUID + metadata）
- 合計: ~5KB

**判定:** 問題なし。100プリセットに拡大しても~50KB。

### 4.3 kAlgorithmTable の静的メモリ

```swift
private let kAlgorithmTable: [AlgorithmRoute] = { ... }()
```

**推定:**
- 32 AlgorithmRoute × (~50B per route) = ~1.6KB
- lazy初期化で初回アクセス時に生成

**判定:** 問題なし。

---

## 5. 起動時間分析

### 5.1 .task での初期化フロー

**場所:** `M2DXFeature.swift:55-88`

```swift
.task {
    applyPreset(initPreset)        // sync, ~0.1ms
    await audioEngine.start()       // async: AudioSession + AVAudioEngine setup
    // MIDI callbacks setup          // sync, ~0.01ms
    midiInput.start()               // sync: CoreMIDI + CI/PE setup

    while !Task.isCancelled {       // ← keepalive ループ
        try? await Task.sleep(for: .seconds(1))
    }
    midiInput.stop()
    audioEngine.stop()
}
```

**起動シーケンスの推定時間:**

| ステップ | 推定時間 |
|----------|----------|
| applyPreset (sync) | <1ms |
| AVAudioSession.setCategory | ~5-10ms |
| AVAudioSession.setActive | ~10-50ms |
| AVAudioEngine.start() | ~20-50ms |
| CoreMIDITransport init | ~5-10ms |
| CIManager/PEResponder init | ~5ms |
| connectToAllSources | ~10-20ms |
| Discovery Inquiry (1s delay) | 非同期、起動後 |
| **合計（UI表示まで）** | **~50-140ms** |

**判定:** 十分高速。UIはaudioEngine.start()完了前に表示される。

**改善余地:**
- `audioEngine.start()`と`midiInput.start()`を並行実行可能（現在は直列）
- `Task.sleep(for: .seconds(1))`のkeepaliveループは不要に見えるが、.taskのキャンセル時にstop()を呼ぶためのパターンとして機能している

### 5.2 AudioSession バッファ設定

**場所:** `M2DXAudioEngine.swift:143`

```swift
try session.setPreferredIOBufferDuration(0.005)  // 5ms = 240 frames at 48kHz
```

**設定値の適切性:**
- 5msは音楽アプリとして妥当（DX7ハードウェアの応答時間に近い）
- 実際のバッファサイズはiOSが決定（通常256 or 512 frames）
- iPhone 14以降では256 frames (5.33ms) が典型的

---

## 6. CPU使用率の数値見積もり

### 6.1 render() あたりの処理コスト（16ボイス全発音、256フレーム）

```
1フレームあたりの処理:
  - MIDIドレイン: 0（イベントなし時）
  - 16ボイス × checkActive(): 16 × ~5命令 = 80命令
  - 16ボイス × process():
    - kAlgorithmTable参照: ~5命令
    - 6 × modSum(): 6 × ~15命令 = 90命令
    - 6 × FMOp.process(): 6 × ~40命令 = 240命令
      (sinf: ~12命令, env.process: ~15命令, 乗算等: ~13命令)
    - carrier合計: ~30命令
    - velScale/norm乗算: ~5命令
    合計/ボイス: ~370命令
  - 合計/フレーム: 16 × 370 + 80 = ~6,000命令
  - sqrtf: ~10命令
  - tanhApprox: ~8命令（条件分岐あり）
  - バッファ書込み: ~4命令
  合計/フレーム: ~6,022命令

256フレーム合計: 256 × 6,022 = ~1,541,632命令

NSLock overhead: ~200命令（lock/unlock）
MIDIドレイン: ~100命令（空の場合）

バッファ1回合計: ~1,542,000命令 ≈ 1.54M命令
```

### 6.2 CPU使用率推定

| デバイス | クロック | 1バッファの処理時間 | バッファ期間 | CPU使用率 |
|----------|---------|---------------------|-------------|-----------|
| A15 (3.23GHz) | 3.23GHz | ~0.48ms | 5.33ms | **~9.0%** |
| A13 (2.65GHz) | 2.65GHz | ~0.58ms | 5.33ms | **~10.9%** |
| A17 Pro (3.78GHz) | 3.78GHz | ~0.41ms | 5.33ms | **~7.7%** |

**注意:** これは単一コアでの推定値。IPC（命令/サイクル比）はApple Siliconで約4-6と仮定。

**判定:** 16ボイス全発音でも10%以下であり、十分な余裕がある。ただし：
- バックグラウンドアプリのオーバーヘッド
- サーマルスロットリング
- NSLockの競合待ち
を加味すると、実際のCPU使用率は推定の1.5-2倍になる可能性がある。

---

## 7. 具体的な改善提案（優先度順）

### P0: Critical（即時対応推奨）

1. **NSLock → OSAllocatedUnfairLock + パラメータメッセージパッシング**
   - render()内のロック保持時間を最小化
   - パラメータ変更をMIDIEventQueue類似のキューに統一
   - 最終的にはlock-freeアーキテクチャに移行

2. **MIDIEventQueue.drain() のヒープ割り当て排除**
   - Fixed-size ring bufferへの移行
   - drain()はポインタスワップのみに
   - 容量: 現在の256で十分

### P1: High（次バージョンで対応）

3. **sinf() → ルックアップテーブル**
   - 2048点テーブル + 線形補間
   - CPU負荷40-60%削減の見込み

4. **sqrtf() のキャッシュ化**
   - フレームループ外で1回だけ計算

5. **powf() のテーブル化（ピッチベンド）**
   - ±200cent = ±2semitone範囲で4096点テーブル

### P2: Medium（改善検討）

6. **MIDI入力パスからMainActor経由を排除**
   - CoreMIDI → MIDIEventQueueの直接パスでレイテンシ2ms削減

7. **debugLogの循環バッファ化**
   - insert(at:0) → O(1)操作に

8. **peFlowLogの上限設定**

9. **デバッグプロパティのスロットリング**
   - debugReceiveCount等の更新を100ms間隔に

### P3: Low（将来検討）

10. **Accelerate/vDSP活用**
    - フレームバッチでのsinf計算
    - バッファゼロ初期化のvDSP_vclr()化

11. **SIMD最適化**
    - 6オペレータの並列envelope処理

---

## 8. 良い設計パターン（維持すべき点）

1. **タプルベースのFMOp格納**: `Voice.ops`がタプルで、配列アクセスのオーバーヘッドとヒープ割り当てを回避
2. **@inline(__always)の適切な使用**: `modSum()`, `outAt()`, `withOp()`のホットパスでインライン化
3. **tanhApprox**: Pade近似による高速ソフトクリッピングは優れた選択
4. **テーブル駆動アルゴリズムルーティング**: `kAlgorithmTable`による分岐レスなアルゴリズム選択
5. **OSAllocatedUnfairLockの使用**: MIDIEventQueueでの正しいロック選択
6. **AVAudioSourceNodeの直接使用**: スケジューリングレイテンシなしのレンダリング
7. **構造体ベースの値型設計**: Envelope, FMOp, Voice すべてstructで、参照カウントなし
8. **フェーズインクリメント方式**: `phase += phaseInc`は最も効率的なオシレータ実装

---

## 9. テスト・プロファイリング推奨

1. **Instruments Time Profiler**: render()のCPU使用率を16ボイス全発音で実測
2. **Instruments System Trace**: NSLockの競合頻度とブロック時間を計測
3. **Instruments Allocations**: render callback内でのヒープ割り当てを検出
4. **Audio Unit Hosting**: AVAudioSourceNodeのバッファサイズをログ出力して実測
5. **MIDI Latency Test**: CoreMIDI timestamp → 音声出力までの実測（iOS Audio Unit Testingツール）

---

*Report generated by Claude Opus 4 - M2DX Performance Audit 2026-02-07*
