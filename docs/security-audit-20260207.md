# M2DX セキュリティ監査レポート

## 監査概要
- **対象**: M2DX (iOS/macOS MIDI 2.0 FMシンセサイザー)
- **日付**: 2026-02-07
- **監査範囲**:
  - M2DXPackage/Sources/M2DXFeature/ (全ファイル)
  - M2DXPackage/Sources/M2DXCore/ (全ファイル)
  - Config/ (entitlements, xcconfig)
  - MIDI2Kit依存ライブラリ

## エグゼクティブサマリー

| レベル | 件数 |
|--------|------|
| Critical | 0件 |
| High | 0件 |
| Medium | 3件 |
| Low | 5件 |
| Info | 4件 |

**総合リスク評価**: 低

M2DXプロジェクトは全体的にセキュリティ意識の高い設計となっています。ネットワーク通信なし、機密データ処理なし、最小限のentitlementsで構成されており、OWASP Mobile Top 10の多くの脆弱性カテゴリに該当しません。発見された問題は主にコード品質とベストプラクティスに関するものです。

---

## 発見事項

### [SEV-001] Medium: リアルタイムスレッドでのロック使用

**概要**
FMSynthEngine.render()がAVAudioSourceNodeのレンダーコールバック（リアルタイムオーディオスレッド）から呼び出されますが、内部でNSLockを使用しています。

**影響**
- リアルタイムスレッドでのロック待機は優先度逆転を引き起こす可能性
- 極端なケースでオーディオのドロップアウト（グリッチ）が発生する可能性

**場所**
- ファイル: `M2DXPackage/Sources/M2DXFeature/FMSynthEngine.swift`
- 行: 449, 455, 461-502, 509

**証跡**
```swift
func render(into bufferL: UnsafeMutablePointer<Float>,
            bufferR: UnsafeMutablePointer<Float>,
            frameCount: Int) {
    lock.lock(); defer { lock.unlock() }  // リアルタイムスレッドでのロック
    // ... レンダリング処理
}
```

**推奨対策**
ロックフリーのデータ構造（OSAllocatedUnfairLock with tryLock、またはアトミック操作）への移行を検討。現状でも実用上問題ない可能性が高いが、負荷が高い状況での安定性向上のため。

**参考**
- Apple: Audio Unit Hosting Guide - Real-Time Thread Safety

---

### [SEV-002] Medium: MIDIEventQueueのOSAllocatedUnfairLockがリアルタイムスレッドで使用

**概要**
MIDIEventQueue.drain()がリアルタイムオーディオスレッドから呼び出されますが、OSAllocatedUnfairLock.withLockを使用しています。OSAllocatedUnfairLockはスピンロックではないため、競合時にカーネル待機が発生する可能性があります。

**影響**
- SEV-001と同様、優先度逆転のリスク
- MIDIイベントが多い状況でオーディオグリッチの可能性

**場所**
- ファイル: `M2DXPackage/Sources/M2DXFeature/MIDIEventQueue.swift`
- 行: 49-55

**証跡**
```swift
func drain() -> [MIDIEvent] {
    lock.withLock { buffer in
        guard !buffer.isEmpty else { return [] }
        let events = buffer
        buffer.removeAll(keepingCapacity: true)
        return events
    }
}
```

**推奨対策**
- ロックフリーのリングバッファ実装への移行を検討
- 現状の256イベント固定容量は妥当

**参考**
- Swift Atomics: https://github.com/apple/swift-atomics

---

### [SEV-003] Medium: UnsafeMutablePointerの境界チェック

**概要**
FMSynthEngine.render()はフレームカウントを受け取り、ポインタに書き込みますが、バッファサイズの検証がありません。呼び出し側（AVAudioSourceNode）が正しいframeCountを渡すことに依存しています。

**影響**
- 不正なframeCountが渡された場合、バッファオーバーフローの可能性
- 実際には AVAudioSourceNode が正しい値を渡すため、リスクは理論的

**場所**
- ファイル: `M2DXPackage/Sources/M2DXFeature/FMSynthEngine.swift`
- 行: 506-551

**証跡**
```swift
func render(into bufferL: UnsafeMutablePointer<Float>,
            bufferR: UnsafeMutablePointer<Float>,
            frameCount: Int) {
    // ... frameCount の検証なし
    for frame in 0..<frameCount {
        bufferL[frame] = clipped  // 境界チェックなし
        bufferR[frame] = clipped
    }
}
```

**推奨対策**
```swift
guard frameCount > 0, frameCount <= 4096 else { return }  // 妥当な上限を設定
```

**参考**
- Apple: Audio Unit Rendering

---

### [SEV-004] Low: デバッグ用print文の残存

**概要**
プロダクションコードにデバッグ用のprint文が残存しています。機密情報は含まれていませんが、パフォーマンスとコード品質の観点から削除が推奨されます。

**影響**
- パフォーマンスへの軽微な影響
- ログの肥大化

**場所**
- ファイル: `M2DXPackage/Sources/M2DXFeature/M2DXAudioEngine.swift`
- 行: 97, 123, 245, 364
- ファイル: `M2DXPackage/Sources/M2DXFeature/MIDIKeyboardView.swift`
- 行: 300-301, 307-308 (Preview用)
- ファイル: `M2DXPackage/Sources/M2DXCore/PropertyExchange/M2DXPEBridge.swift`
- 行: 104, 214

**推奨対策**
- os.Loggerの使用への移行
- #if DEBUGでの条件付きログ出力
- Preview内のprint文は許容

---

### [SEV-005] Low: CoreMIDITransportのtry!使用なし（良好）

**概要**
MIDI2Kitを含む全コードベースで強制アンラップ(!)やtry!の使用が確認されませんでした。エラーハンドリングが適切に実装されています。

**影響**
- なし（良好な設計）

---

### [SEV-006] Low: Property ExchangeでのJSON処理

**概要**
Property Exchange（MIDI-CI）でJSONエンコード/デコードを使用していますが、入力値の検証が行われています。外部からの悪意あるJSONに対する直接的なリスクは低いです。

**影響**
- 現状で重大なリスクなし
- JSONDecoderのデフォルト設定は安全

**場所**
- ファイル: `M2DXPackage/Sources/M2DXFeature/MIDIInputManager.swift`
- 行: 277-282

**証跡**
```swift
await responder.registerResource("ProgramList", resource: ComputedResource { _ in
    let programs = DX7FactoryPresets.all.enumerated().map { ... }
    return try JSONEncoder().encode(programs)  // 内部データのみ
})
```

---

### [SEV-007] Low: MIDI入力の範囲チェック

**概要**
MIDIInputManager.handleUMPData()およびhandleReceivedData()でMIDIデータのパースを行っていますが、一部のビットマスク操作で暗黙的な範囲制限に依存しています。

**影響**
- UInt8/UInt16/UInt32への型変換で自動的にクリップされるため実害なし
- 悪意あるMIDIデータによるクラッシュリスクは低い

**場所**
- ファイル: `M2DXPackage/Sources/M2DXFeature/MIDIInputManager.swift`
- 行: 289-344 (handleUMPData)
- 行: 349-450 (handleReceivedData)

**推奨対策**
現状で問題なし。ビットマスク（& 0xFF, & 0xFFFF等）が適切に使用されています。

---

### [SEV-008] Low: DX7Preset入力値の範囲制限

**概要**
DX7Preset/DX7OperatorPresetの各パラメータは期待される範囲（0-99, 0-31等）がありますが、初期化時の範囲チェックがありません。ファクトリープリセットのみ使用する現状では問題ありません。

**影響**
- 将来的にユーザープリセットを許可する場合、異常値による予期しない動作の可能性

**場所**
- ファイル: `M2DXPackage/Sources/M2DXCore/DX7Preset.swift`
- 行: 31-53

**推奨対策**
将来のユーザープリセット機能実装時に、値の範囲検証を追加。

---

### [INFO-001] Info: 空のEntitlements（最小権限）

**概要**
Config/M2DX.entitlementsが空です。これは最小権限の原則に従った良好な設計です。

**場所**
- ファイル: `Config/M2DX.entitlements`

**評価**
- ネットワークアクセス権限なし
- iCloud/Keychain権限なし
- App Groups権限なし
- Background Modes権限なし

---

### [INFO-002] Info: ネットワーク通信なし（良好）

**概要**
プロジェクト全体でネットワーク通信（URLSession, Network.framework等）の使用がありません。機密データの外部送信リスクがありません。

**評価**
- HTTP/HTTPS通信なし
- ATS設定不要
- プライバシーリスク低

---

### [INFO-003] Info: 機密データ保存なし（良好）

**概要**
UserDefaults、Keychain、CoreDataへの機密データ保存がありません。認証情報やAPIキーのハードコードもありません。

**評価**
- UserDefaults使用なし
- Keychain使用なし
- ログへの機密情報出力なし

---

### [INFO-004] Info: Privacy Manifest未設定

**概要**
iOS 17+のPrivacy Manifest（PrivacyInfo.xcprivacy）が確認されませんでした。現状のアプリは追跡やデータ収集を行っていないため、必須ではありませんが、App Store審査で求められる可能性があります。

**推奨対策**
リリース前にPrivacy Manifestを追加し、以下を明示:
- NSPrivacyTracking: false
- NSPrivacyCollectedDataTypes: 空配列
- NSPrivacyAccessedAPITypes: 該当なし

---

## MIDI2Kit依存ライブラリの監査

### スレッドセーフティ

CoreMIDITransport.swiftでは適切なスレッドセーフティが実装されています:

- `VirtualEndpointState`: NSLockで保護
- `ConnectionState`: NSLockで保護
- `shutdownLock`: シャットダウン状態の同期
- `receivedContinuation`: AsyncStreamで安全に処理

### UMPデコードの安全性

handleEventList()でUMPワードのデコードが行われていますが:
- ビットマスク操作が適切
- 配列境界チェックあり（`guard wi + 1 < words.count`）
- 不正なメッセージタイプは無視

### 評価
MIDI2Kitは適切に設計されており、重大なセキュリティ上の問題は発見されませんでした。

---

## 推奨事項（優先順位順）

### 即座に対応（なし）
重大な脆弱性は発見されませんでした。

### 短期（1ヶ月以内）
1. **SEV-001/SEV-002**: リアルタイムスレッドでのロック使用について、負荷テストを実施し問題がないことを確認
2. **SEV-003**: render()にframeCountの上限チェックを追加

### 中期（次回リリース）
1. **SEV-004**: print文をos.Loggerに置換
2. **INFO-004**: Privacy Manifestの追加

### 長期（将来の機能追加時）
1. **SEV-008**: ユーザープリセット機能実装時に入力値検証を追加

---

## 監査対象外・制限事項

- 動的解析（ランタイムテスト）は実施していません
- ペネトレーションテストは実施していません
- AUv3コンポーネント（M2DXAudioUnit/）は監査対象外
- サードパーティ依存（MIDIKit等のSPMパッケージ）は監査対象外

---

## 結論

M2DXプロジェクトは、セキュリティの観点から良好に設計されています。主な強みは:

1. **最小権限**: 空のentitlements、ネットワーク通信なし
2. **機密データなし**: 認証情報、APIキー、ユーザーデータの保存なし
3. **適切なエラーハンドリング**: try!/fatalError/強制アンラップなし
4. **スレッドセーフティ**: NSLock、OSAllocatedUnfairLockの適切な使用

発見されたMedium/Low レベルの問題は、主にコード品質とパフォーマンス最適化に関するものであり、セキュリティインシデントに直結するものではありません。

---

**監査実施者**: Claude Code Security Auditor
**監査日時**: 2026-02-07 08:19 JST
