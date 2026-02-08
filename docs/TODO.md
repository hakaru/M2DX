# TODO

## リリース前（必須）

- [ ] MIDI2Kit の依存をローカルパス参照（`path: "../../MIDI2Kit"`）からリモートリポジトリ参照に切り替え＆ビルドテスト

## 次回最優先 — ログ取得環境改善

- [x] macOS スタンドアローン版を作成（CoreMIDI/PE/CI ロジックの検証環境）★完了 2026-02-08
  - log stream で Claude がリアルタイムにログ読取可能になる
  - iOS の Copy Log 手動ペーストが不要に
- [x] macOS 版で PE/CI フロー検証（KeyStage USB 接続 → Mac）★完了 2026-02-08

## 検証（実機テスト）

- [x] program 0-9 で applyPreset による音色切替が動作するか確認 ★完了 2026-02-08
- [x] KeyStage LCD にプログラム名が表示されるか目視確認 ★完全成功 2026-02-08（PE Notify 0x38修正）
- [x] PE Notify によるプログラム切替が KeyStage LCD に反映されるか確認 ★完全成功 2026-02-08（連続20+PC動作安定）
- [x] iOS USB版 KeyStage LCD 動作確認 ★完全成功 2026-02-08（targeted送信＋bankPC 1-based修正）
- [x] Value UP/DOWN による順番通りのプログラム変更確認 ★完全成功 2026-02-08（bankPC 1-based修正）
- [ ] BLE MIDI 接続での動作確認（macOS/iOS 版安定後）

## 改善（優先度低）

- [ ] os.Logger の privacy アノテーション見直し（リリースビルド向け `.public` の適切性）
- [ ] 0x5404629 不明 MUID の正体調査（KeyStage 内部エンティティ？別アプリ？）
- [ ] デバッグ print 文のクリーンアップ（PE/CI 本格運用前）

## 完了

- [x] ロギングシステム全面改修（print → os.Logger + BufferMIDI2Logger 二重出力）
- [x] MIDI-CI Property Exchange フロー実装（ResourceList, DeviceInfo, ChannelList, ProgramList, X-ProgramEdit, X-ParameterList, JSONSchema）
- [x] Program Change preset switching + PE Notify 連携
- [x] ソフトクリッピング（tanhApprox）+ AVAudioSourceNode 移行
- [x] MIDI 2.0 フルプレシジョン対応（16bit velocity, 32bit CC/PB）
- [x] PE Notify sub-ID2 修正（0x3F → 0x38 + command:notify ヘッダー、MIDI-CI PE v1.1 準拠）★2026-02-08
- [x] KeyStage LCD プログラム名表示実現（X-ProgramEdit currentValues 形式 + PE Notify 0x38）★2026-02-08
- [x] macOS entity 除外ロジック実装（PEResponder.excludeMUIDs / subscriberMUIDs()）★2026-02-08
- [x] KeyStage Subscribe Reply (0x39) フィルタ実装★2026-02-08
- [x] iOS USB targeted送信実装（resolvePEDestinations() — CTRL優先、Session 1/DAW OUT除外）★2026-02-08
- [x] ChannelList supportsSubscription バグ修正★2026-02-08
- [x] bankPC 1-based修正（ProgramList/X-ProgramEdit/Notify全て）★2026-02-08
- [x] peIsolationStep デバッグ分岐削除（常にフルPE/CI動作）★2026-02-08
- [x] PEリファクタリング（MIDI2Logger注入、restartTask パターン、#if DEBUG peSnifferMode）★2026-02-08
