# コードレビューレポート

## 概要
- レビュー対象: ロギングシステム全面改修（print() → os.Logger + MIDI2Logger移行）
- レビュー日: 2026-02-07
- 対象ファイル:
  - `M2DXPackage/Sources/M2DXFeature/MIDIInputManager.swift`
  - `M2DXPackage/Sources/M2DXFeature/M2DXAudioEngine.swift`
  - `M2DXPackage/Sources/M2DXCore/PropertyExchange/M2DXPEBridge.swift`

## サマリー
- 🔴 Critical: 0件
- 🟡 Warning: 2件
- 🔵 Suggestion: 5件
- 💡 Nitpick: 1件

## 詳細

### 🟡 [MIDIInputManager.swift:24] BufferMIDI2Logger の `@unchecked Sendable` が適切かどうか要検証

**問題**
`BufferMIDI2Logger` が `@unchecked Sendable` として宣言されていますが、`onLog` クロージャが `@Sendable` であることに依存しています。クロージャが MainActor に捕捉される値を持つ可能性があり、実行時にデータ競合が発生する潜在的リスクがあります。

**現在のコード**
```swift
final class BufferMIDI2Logger: MIDI2Core.MIDI2Logger, @unchecked Sendable {
    let minimumLevel: MIDI2Core.MIDI2LogLevel = .debug
    private let onLog: @Sendable (String) -> Void

    init(onLog: @escaping @Sendable (String) -> Void) {
        self.onLog = onLog
    }
```

**理由**
`@unchecked Sendable` は「プログラマが責任を持ってスレッドセーフを保証する」という宣言です。現状では `onLog` が `@Sendable` クロージャであり、内部で `Task { @MainActor in ... }` を使用しているため、理論上は安全です。しかし、以下の点を確認すべきです：

1. `onLog` クロージャが常に `@Sendable` であることが型システムで保証されている → ✅ OK
2. `appendDebugLog` への `weak self` キャプチャが適切である → ✅ OK
3. 将来的に別のクロージャが渡された場合の安全性 → ⚠️ 要注意

**推奨**
現状の実装は問題ありませんが、将来の保守性を考慮して以下のいずれかを検討：
- ドキュメントコメントで `@unchecked Sendable` の理由と `onLog` の要件を明記
- 可能であれば `actor` ベースの実装に変更してコンパイラに安全性を保証させる

---

### 🟡 [MIDIInputManager.swift:227-230] BufferMIDI2Logger の weak self キャプチャが適切

**問題**
`BufferMIDI2Logger` の初期化時に `[weak self]` でキャプチャしていますが、`MIDIInputManager` が解放された後もロガーが生存している場合、ログが失われる可能性があります。

**現在のコード**
```swift
let bufferLogger = BufferMIDI2Logger { [weak self] line in
    Task { @MainActor in
        self?.appendDebugLog(line)
    }
}
```

**理由**
これは意図的な設計と思われます。`MIDIInputManager` が解放された場合、ログを追記する意味がないため、`weak self` は適切です。ただし、以下のシナリオを考慮すべきです：

- `MIDIInputManager.stop()` が呼ばれた後も `CIManager`/`PEManager` がバックグラウンドで動作している場合、ログが失われる
- 現状では `stop()` で `ciManager = nil` としているため、問題ない → ✅ OK

**推奨**
現状の実装は適切ですが、将来的に `stop()` の実装が変更された場合に備えて、ドキュメントコメントで意図を明記することを推奨します。

---

### 🔵 [MIDIInputManager.swift:181-190] os.Logger への privacy アノテーションが適切

**問題**
すべてのログメッセージに `.public` プライバシーアノテーションを付けていますが、これは意図的ですか？

**現在のコード**
```swift
if line.hasPrefix("PE") {
    peFlowLog.append(line)
    peLogger.info("\(line, privacy: .public)")
} else if line.hasPrefix("CI") {
    peFlowLog.append(line)
    ciLogger.info("\(line, privacy: .public)")
} else if line.hasPrefix("SNIFF") {
    peFlowLog.append(line)
    peLogger.notice("\(line, privacy: .public)")
} else {
    midiLogger.debug("\(line, privacy: .public)")
}
```

**理由**
`.public` を使用すると、すべてのログがコンソールに平文で記録されます。MIDI データや PE メッセージには以下の情報が含まれる可能性があります：

- MUID（デバイス識別子）
- プログラム名
- デバイス名
- 内部状態

デバッグ目的であれば問題ありませんが、本番環境でのプライバシーリスクを考慮すべきです。

**推奨**
- デバッグビルドでは `.public`
- リリースビルドでは `.auto` または `.private`
- または、センシティブな情報（MUID, デバイス名など）のみ `.private` に変更

---

### 🔵 [MIDIInputManager.swift] メモリリークの可能性は低いが、クロージャのキャプチャを再確認

**問題**
多数のクロージャで `[weak self]` を使用していますが、一部で `self` を直接キャプチャしている箇所があります。

**現在のコード（L278-284）**
```swift
Task { [weak self] in
    await responder.setLogCallback { resource, body, replySize in
        Task { @MainActor in
            self?.appendDebugLog("PE-Resp: \(resource) body=\(body.prefix(150)) reply=\(replySize)B")
        }
    }
}
```

**分析**
- 外側の `Task` で `[weak self]` を使用 → ✅ OK
- 内側の `setLogCallback` クロージャでも `self` を使用しているが、これは `responder` に保持される
- `responder` は `MIDIInputManager` の strong プロパティなので、循環参照にはならない → ✅ OK

**理由**
現状の実装は正しいですが、将来的に `responder` のライフサイクルが変更された場合（例: シングルトンになる、グローバルに保持されるなど）、循環参照が発生する可能性があります。

**推奨**
現状は問題ありませんが、保守性向上のため、`setLogCallback` 内でも `[weak self]` を明示的に使用することを推奨します：

```swift
await responder.setLogCallback { [weak self] resource, body, replySize in
    Task { @MainActor in
        self?.appendDebugLog("PE-Resp: \(resource) body=\(body.prefix(150)) reply=\(replySize)B")
    }
}
```

---

### 🔵 [M2DXAudioEngine.swift:99] os.Logger のエラーログに privacy アノテーションが適切

**問題**
エラーメッセージに `.public` を使用していますが、エラーメッセージには以下の情報が含まれる可能性があります：

- ファイルパス
- デバイス名
- システム設定

**現在のコード**
```swift
audioLogger.error("\(message, privacy: .public)")
```

**推奨**
エラーメッセージは `.auto` または `.private` を使用し、必要に応じて redacted 形式でログに記録することを推奨します。ただし、デバッグ目的であれば `.public` も許容範囲です。

---

### 🔵 [M2DXAudioEngine.swift:125] AVAudioSession エラーが warning レベルで適切

**問題**
`setActive(false)` の失敗を `warning` レベルでログしていますが、これは適切ですか？

**現在のコード**
```swift
audioLogger.warning("Failed to deactivate audio session: \(error.localizedDescription, privacy: .public)")
```

**理由**
iOS では AVAudioSession の `setActive(false)` が失敗することは稀ですが、失敗した場合でもアプリの動作に致命的な影響はありません。`warning` レベルは適切です。

**推奨**
現状のままで問題ありません。ただし、将来的にこのエラーが頻発する場合は、エラーハンドリングを強化する必要があります。

---

### 🔵 [M2DXPEBridge.swift:107] syncAUToPE のエラーログが適切

**問題**
AU → PE 同期のエラーを `error` レベルでログしていますが、これは適切ですか？

**現在のコード**
```swift
bridgeLogger.error("Failed to sync AU->PE for \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
```

**理由**
AU パラメータの変更が PE に同期できない場合、UI と内部状態が不整合になる可能性があります。`error` レベルは適切です。

**推奨**
現状のままで問題ありません。ただし、以下の改善を検討：
- エラーが頻発する場合、ユーザーに通知するメカニズムを追加
- リトライロジックを実装

---

### 💡 [MIDIKeyboardView.swift:300-308] SwiftUI Preview 内の print() は許容範囲

**問題**
SwiftUI Preview 内で `print()` を使用していますが、これは開発専用コードです。

**現在のコード**
```swift
#Preview("MIDI Keyboard") {
    VStack {
        MIDIKeyboardView(
            octave: .constant(4),
            octaveCount: 2,
            onNoteOn: { note, vel in print("Note On: \(note) vel: \(vel)") },
            onNoteOff: { note in print("Note Off: \(note)") }
        )
        .padding()
```

**理由**
Preview は開発時のみ使用され、リリースビルドには含まれません。`print()` の使用は許容範囲です。

**推奨**
現状のままで問題ありませんが、将来的に Preview を本番環境でも使用する場合（例: デバッグモード切替）、os.Logger への移行を検討してください。

---

## 良かった点

### ✅ ロギングアーキテクチャが優れている
- `CompositeMIDI2Logger` で OSLog と Buffer の二重出力を実現
- macOS Console.app でリアルタイムログ表示可能
- アプリ内デバッグログバッファで履歴確認可能
- PE/CI 専用ログ（peFlowLog）で PE 通信のみを抽出可能

### ✅ os.Logger の使い分けが適切
- `midiLogger`, `peLogger`, `ciLogger`, `audioLogger`, `bridgeLogger` でカテゴリを分離
- subsystem `"com.example.M2DX"` で統一
- Console.app でフィルタリング可能

### ✅ スレッドセーフティへの配慮
- `BufferMIDI2Logger` の `@Sendable` クロージャ
- `M2DXPEBridge` の `NSLock` による排他制御
- `weak self` キャプチャによる循環参照回避

### ✅ MainActor 分離が明確
- `Task { @MainActor in ... }` で UI 更新を明示的に MainActor に隔離
- `appendDebugLog` が MainActor 内で安全に実行される

### ✅ MIDI2Kit の MIDI2Logger プロトコルへの準拠
- `BufferMIDI2Logger` が `MIDI2Logger` に準拠
- `CIManager` / `PEManager` へのロガー注入が適切
- `CompositeMIDI2Logger` で複数のロガーを組み合わせ可能

### ✅ デバッグ機能の充実
- PE Sniffer Mode で KORG Module との通信を監視可能
- PE Flow Log で PE 通信のみを抽出
- MIDI Message Log で全 MIDI メッセージを記録
- Copy ボタンでログをクリップボードにコピー可能

---

## 改善提案（優先度順）

### 1. プライバシーアノテーションの見直し（中優先度）
すべてのログに `.public` を使用していますが、以下のように使い分けることを推奨：

```swift
// MUID や デバイス名は .private
peLogger.info("PE: Cap 0x30 src=\(parsed.sourceMUID, privacy: .private)")

// デバッグメッセージは .auto（デフォルト）
midiLogger.debug("MIDI message received")

// エラーメッセージは .public（診断に必要）
audioLogger.error("Failed to start: \(error.localizedDescription, privacy: .public)")
```

### 2. BufferMIDI2Logger のドキュメント化（低優先度）
`@unchecked Sendable` の理由と `onLog` クロージャの要件を明記：

```swift
/// MIDI2Logger that forwards log messages to an @MainActor buffer callback.
///
/// Thread Safety:
/// This class uses `@unchecked Sendable` because:
/// - `onLog` is a `@Sendable` closure that internally uses `Task { @MainActor in ... }`
/// - All state is immutable (`let` properties only)
/// - The closure captures `weak self` to prevent retain cycles
///
/// The `onLog` closure MUST be `@Sendable` and MUST dispatch to @MainActor internally.
final class BufferMIDI2Logger: MIDI2Core.MIDI2Logger, @unchecked Sendable {
```

### 3. エラーハンドリングの強化（低優先度）
AU → PE 同期エラーが頻発する場合、ユーザーに通知するメカニズムを追加：

```swift
// 例: エラーカウンタを追加
private var syncErrorCount: Int = 0

private func syncAUToPE(address: AUParameterAddress, value: AUValue) {
    // ...
    do {
        try peResource.setPropertyFromFloat(path, floatValue: value)
        syncErrorCount = 0  // 成功時にリセット
    } catch {
        syncErrorCount += 1
        bridgeLogger.error("Failed to sync AU->PE for \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")

        // 10回連続エラーでユーザーに通知
        if syncErrorCount >= 10 {
            // TODO: Show error alert to user
        }
    }
}
```

### 4. 残存 print() の削除は不要（低優先度）
`MIDIKeyboardView.swift` の Preview 内 `print()` は開発専用コードなので、削除不要です。

---

## 総評

### コード品質: ⭐️⭐️⭐️⭐️⭐️ (5/5)
今回のロギングシステム改修は非常に高品質です。以下の点が特に優れています：

1. **アーキテクチャの明確さ**: `CompositeMIDI2Logger` で OSLog と Buffer を統合
2. **スレッドセーフティ**: `@Sendable`, `@MainActor`, `NSLock` を適切に使用
3. **デバッグ性**: PE Flow Log, Sniffer Mode など、実際のデバッグに役立つ機能
4. **保守性**: os.Logger のカテゴリ分離で、将来的なフィルタリングが容易

### 懸念点
1. **プライバシーアノテーション**: すべて `.public` にしているため、本番環境でのプライバシーリスクがある
2. **ドキュメント不足**: `@unchecked Sendable` の理由が明記されていない

### 推奨アクション
1. プライバシーアノテーションの見直し（中優先度）
2. BufferMIDI2Logger のドキュメント化（低優先度）
3. 現状のまま実機テスト → Console.app で動作確認 → 問題なければマージ

---

## 次のステップ

1. ✅ 実機ビルド → Console.app でログ確認
2. ✅ KORG KeyStage 接続 → PE Flow Log で通信確認
3. ⏸️ プライバシーアノテーションの見直し（必要に応じて）
4. ⏸️ BufferMIDI2Logger のドキュメント追加（必要に応じて）

---

## 付録: 残存 print() 文のリスト

検索結果: M2DXFeature 内で 4 件の `print()` を検出

| ファイル | 行番号 | 内容 | 対応要否 |
|---------|--------|------|---------|
| MIDIKeyboardView.swift | 300 | `print("Note On: \(note) vel: \(vel)")` | 不要（Preview 専用） |
| MIDIKeyboardView.swift | 301 | `print("Note Off: \(note)")` | 不要（Preview 専用） |
| MIDIKeyboardView.swift | 307 | `print("Note On: \(note)")` | 不要（Preview 専用） |
| MIDIKeyboardView.swift | 308 | `print("Note Off: \(note)")` | 不要（Preview 専用） |

**結論**: すべて SwiftUI Preview 内の開発専用コードなので、対応不要です。

---

## レビュー完了

レビュアー: Claude Opus 4.5
レビュー日時: 2026-02-07
対象コミット: ロギングシステム全面改修
総合評価: ✅ Approved (条件付き承認)

**条件**: プライバシーアノテーションの見直しを検討すること（必須ではない）

---

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
