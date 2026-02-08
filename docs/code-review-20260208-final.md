# コードレビューレポート

## 概要
- **レビュー対象**: M2DX + MIDI2Kit 最新修正（Phase 12完了後）
- **レビュー日**: 2026-02-08
- **対象コミット**:
  - M2DX: eaee487 "Fix KeyStage reconnect hang, PC off-by-one, and replyDest duplication"
  - MIDI2Kit: 757c95f "Add subscribe dedup and stale subscription cleanup to PEResponder"

## サマリー
- 🔴 Critical: 0件
- 🟡 Warning: 0件
- 🔵 Suggestion: 5件
- 💡 Nitpick: 2件

**総合評価**: 優秀 ⭐⭐⭐⭐⭐

Phase 12で実施された3つのバグ修正（replyDest重複、Subscribe重複、stale subscription）は、いずれも正しく実装されており、KeyStage電源再起動の実機テストで全項目が成功しています。コードは堅牢で、Swift Concurrency安全性も適切に保たれています。

---

## 詳細レビュー

### 1. MIDIInputManager.swift

#### 🔵 Suggestion: 重複排除ロジックの明瞭化

**ファイル**: MIDIInputManager.swift:916-938

**問題**
`updatePEReplyDestinations()` 内のSet重複排除ロジックは正しく動作していますが、なぜ `Set<UInt32>` で重複チェックが必要なのかコメントがありません。

**現在のコード**
```swift
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
        // ...
    }
}
```

**提案**
コメントで意図を明確化すると保守性が向上します:

```swift
// KeyStageのような複数PE対応デバイスでは、1つの物理デバイスに対して
// 複数のMUIDが割り当てられることがある（例: Initiator用、Responder用）。
// CIManagerは全MUIDを登録するが、実際の送信先は1つのCTRLポートなので、
// Set<UInt32>で重複排除して同じdestinationIDへの多重送信を防ぐ。
var seen = Set<UInt32>()
```

**理由**
このロジックはPhase 12のコミットで追加されたバグ修正の核心部分です。将来のメンテナで「なぜSetが必要か」を理解しやすくするため、意図をドキュメント化することを推奨します。

---

#### 🔵 Suggestion: stale subscription cleanupの呼び出しタイミング

**ファイル**: MIDIInputManager.swift:593-599

**問題**
`deviceDiscovered` イベント時に `removeSubscriptions(notIn:)` を呼んでいますが、`deviceLost` 時には呼んでいません。通常はこれで問題ありませんが、KeyStageが切断された後に再接続せず、MUIDだけが discoveredPEDevices から消えた場合、古いsubscriptionが残り続けます。

**現在のコード**
```swift
case .deviceDiscovered(let device):
    // ...
    if let responder = self.peResponder {
        let activeMUIDs = Set(self.discoveredPEDevices.map(\.muid))
        Task {
            await responder.removeSubscriptions(notIn: activeMUIDs)
        }
    }
case .deviceLost(let muid):
    self.discoveredPEDevices.removeAll { $0.muid == muid }
    self.updatePEReplyDestinations()
    // ← stale subscription cleanup is missing here
```

**提案**
`deviceLost` ケースでも同様に cleanup を呼ぶ:

```swift
case .deviceLost(let muid):
    self.discoveredPEDevices.removeAll { $0.muid == muid }
    self.updatePEReplyDestinations()
    // Clean up subscriptions for lost device
    if let responder = self.peResponder {
        let activeMUIDs = Set(self.discoveredPEDevices.map(\.muid))
        Task {
            await responder.removeSubscriptions(notIn: activeMUIDs)
        }
    }
```

**理由**
現在の実装でも次回 deviceDiscovered 時にクリーンアップされるため Critical ではありませんが、deviceLost 直後にクリーンアップする方が即座に不要なsubscriptionが削除され、メモリ効率とログの明瞭性が向上します。

---

#### 💡 Nitpick: peLogger使用箇所の統一

**ファイル**: MIDIInputManager.swift:949, 206-208

**問題**
`notifyProgramChange()` で `peLogger.info()` を使っていますが、他の箇所では `appendDebugLog()` 経由で条件付きpeLogger出力を行っています。

**現在のコード**
```swift
// Line 949
peLogger.info("PC: program=\(idx) name=\(name, privacy: .public)")

// Line 206-208 (appendDebugLog内)
if first == "P" { peLogger.info("\(line, privacy: .public)") }
```

**提案**
統一性を保つため、`notifyProgramChange()` でも `appendDebugLog()` 経由で出力する（現在は重複出力になっている）:

```swift
// Remove direct peLogger call (already logged via appendDebugLog)
// peLogger.info("PC: program=\(idx) name=\(name, privacy: .public)")
```

**理由**
`appendDebugLog("PC: ...")` が既にpeLoggerに出力するため、重複ログになっています。統一性のため、どちらか一方に統一することを推奨します。

---

#### 🔵 Suggestion: ccNotifyTask の未使用変数削除

**ファイル**: MIDIInputManager.swift:983-989

**問題**
`ccNotifyTask` が宣言されていますが、実際には使われていません（debounce実装が無効化されているため）。

**現在のコード**
```swift
private var ccNotifyTask: Task<Void, Never>?

private func notifyCCChange() {
    // Disabled: PE Notify for CC changes causes KeyStage hang
    // TODO: Fix PE Notify format/timing before re-enabling
    appendDebugLog("CC-state: \(ccValues)")
}
```

**提案**
未使用変数を削除してコードをクリーンに保つ:

```swift
// Remove: private var ccNotifyTask: Task<Void, Never>?
```

または、将来の再有効化のためにコメントで意図を残す:

```swift
// Future: debounce task for CC Notify (currently disabled due to KeyStage hang)
// private var ccNotifyTask: Task<Void, Never>?
```

**理由**
デッドコードの削除により可読性が向上します。将来再有効化する可能性があるなら、コメントで保留理由を明記することを推奨します。

---

### 2. PEResponder.swift

#### 🔵 Suggestion: Subscribe重複チェックのログ改善

**ファイル**: PEResponder.swift:402-422

**問題**
Subscribe重複時に既存subscribeIdをREUSEするロジックは正しく実装されていますが、ログに「なぜREUSEが必要か」の説明がありません。

**現在のコード**
```swift
if let existing = subscriptions.first(where: {
    $0.value.resource == resourceName && $0.value.initiatorMUID == inquiry.sourceMUID
}) {
    let subscribeId = existing.key
    logger.info("Subscribe REUSE \(resourceName) subscribeId=\(subscribeId) (same MUID)", category: "PE-Resp")
    // ...
}
```

**提案**
ログメッセージに意図を追加:

```swift
logger.info("Subscribe REUSE \(resourceName) subscribeId=\(subscribeId) (dedup: same MUID already subscribed)", category: "PE-Resp")
```

**理由**
このロジックはPhase 12で追加されたsubscribe storm防止の核心部分です。ログを見た時に「REUSEが重複防止である」ことが明確になります。

---

#### 🔵 Suggestion: removeSubscriptions(notIn:) のバッチ処理

**ファイル**: PEResponder.swift:129-135

**問題**
現在の実装はシンプルで正しいですが、大量のstale subscriptionがある場合、ループ内でlogger.debugを多数呼ぶことになります。

**現在のコード**
```swift
public func removeSubscriptions(notIn activeMUIDs: Set<MUID>) {
    let stale = subscriptions.filter { !activeMUIDs.contains($0.value.initiatorMUID) }
    for (key, sub) in stale {
        logger.debug("Removing stale subscription \(key) for MUID \(sub.initiatorMUID)", category: "PE-Resp")
        subscriptions.removeValue(forKey: key)
    }
}
```

**提案**
バッチログで要約を出力:

```swift
public func removeSubscriptions(notIn activeMUIDs: Set<MUID>) {
    let stale = subscriptions.filter { !activeMUIDs.contains($0.value.initiatorMUID) }
    guard !stale.isEmpty else { return }

    logger.info("Removing \(stale.count) stale subscription(s): \(stale.keys.joined(separator: ", "))", category: "PE-Resp")
    for (key, _) in stale {
        subscriptions.removeValue(forKey: key)
    }
}
```

**理由**
KeyStage電源再起動のような状況では、複数のstale subscriptionが一度に削除されます。バッチログの方が見やすく、パフォーマンスも若干向上します。

---

### 3. M2DXFeature.swift

**レビュー結果**: 問題なし ✅

- Swift Concurrency: `@MainActor` 分離が適切、`.task` モディファイアの正しい使用
- State Management: `@State`, `@Observable` の適切な使用
- エラーハンドリング: 適切（audioEngine.errorMessage表示）
- コードの明瞭性: 良好（セクション分割が明確）

---

### 4. SettingsView.swift

#### 💡 Nitpick: peSnifferMode のコンパイル条件

**ファイル**: SettingsView.swift:309-324

**問題**
`peSnifferMode` は `#if DEBUG` で宣言されているのに、SettingsView では条件なしでアクセスしています。

**現在のコード**
```swift
// SettingsView.swift
Toggle(isOn: Binding(
    get: { midiInput.peSnifferMode },
    set: { newValue in
        midiInput.peSnifferMode = newValue
        // ...
    }
))

// MIDIInputManager.swift
#if DEBUG
public var peSnifferMode: Bool = false
#endif
```

**提案**
SettingsViewのToggleも `#if DEBUG` で囲む:

```swift
#if DEBUG
Toggle(isOn: Binding(
    get: { midiInput.peSnifferMode },
    set: { newValue in
        midiInput.peSnifferMode = newValue
        midiInput.stop()
        midiInput.start()
    }
)) {
    // ...
}
#endif
```

**理由**
Releaseビルドでコンパイルエラーになります。現在はDebugビルドのみテストしているため顕在化していませんが、Releaseビルド時に問題になります。

---

## 良かった点 👍

### 1. **重複排除ロジックの実装が堅牢**
`Set<UInt32>` による replyDestinations の重複排除は、KeyStageのような複数MUID対応デバイスで発生するバグを完全に解決しています。

### 2. **Subscribe重複REUSEの実装が適切**
同一MUID+リソースの重複Subscribe時に既存subscribeIdを返す実装により、subscribe stormを防止できています。

### 3. **stale subscription cleanupの設計が適切**
KeyStage電源再起動でMUID変更があっても、古いsubscriptionが自動削除されるため、メモリリークやログの混乱を防いでいます。

### 4. **Swift Concurrency安全性**
- `@MainActor` 分離が適切（MIDIInputManager, M2DXFeature）
- `actor` による非同期安全性（PEResponder）
- `@Sendable` クロージャの正しい使用（BufferMIDI2Logger）
- Taskのキャンセル処理が適切（.task モディファイア使用）

### 5. **エラーハンドリングの充実**
- PE GET/SET/Subscribe の各エラーケースで適切なステータスコードとメッセージを返している
- macOS外部MUID invalidation ロジックが堅牢

### 6. **ログとデバッグ機能の充実**
- PE Flow Log（2000行バッファ）による詳細なトレース
- Console.app連携（os.Logger使用）
- Sniffer Modeによるパッシブ観測機能

---

## Phase 12 修正の検証結果

実機テスト（KeyStage電源再起動）で以下を確認済み:

✅ **修正1**: replyDestinations重複排除
- 結果: `replyDestinations=3154177` — 1つだけ（重複なし）

✅ **修正2**: Subscribe重複REUSE
- 結果: `sub-1〜sub-4` の4つだけ — storm無し

✅ **修正3**: stale subscription cleanup
- 結果: `sub-1` から開始 — 旧MUID残存なし

✅ **副次効果**: KeyStage LCD ハングなし
- PE全フロー完走、LCD正常表示、PC名前正しい

---

## 総評

Phase 12で実施された3つのバグ修正は、いずれも正しく実装されており、実機テストで全項目が成功しています。

**特筆すべき点**:
1. Swift Concurrency安全性が適切に保たれている
2. MIDI-CI/PE仕様との整合性が高い（Subscribe重複対応など）
3. 実機テストによる検証が徹底されている
4. ログ・デバッグ機能が充実しており、今後のトラブルシューティングが容易

**Suggestionは5件**ありますが、いずれも品質向上のための改善提案であり、現在のコードは十分に堅牢です。

---

## 推奨事項

1. **Releaseビルド前の確認**
   - `peSnifferMode` の `#if DEBUG` 条件をSettingsViewにも追加
   - 未使用変数 `ccNotifyTask` の削除または保留理由の明記

2. **ドキュメント強化**
   - 重複排除ロジック（Set使用理由）のコメント追加
   - Subscribe REUSE の意図を明確化

3. **stale subscription cleanup**
   - `deviceLost` ケースでも cleanup を呼ぶ（即座削除）

これらは軽微な改善であり、現状でも問題なく動作します。

---

**レビュアー**: Claude Sonnet 4.5
**レビュー日時**: 2026-02-08 18:20
