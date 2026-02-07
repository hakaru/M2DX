# TODO

## リリース前（必須）

- [ ] MIDI2Kit の依存をローカルパス参照（`path: "../../MIDI2Kit"`）からリモートリポジトリ参照に切り替え＆ビルドテスト

## 次回最優先 — ログ取得環境改善

- [ ] macOS スタンドアローン版を作成（CoreMIDI/PE/CI ロジックの検証環境）
  - log stream で Claude がリアルタイムにログ読取可能になる
  - iOS の Copy Log 手動ペーストが不要に
- [ ] macOS 版で PE/CI フロー検証（KeyStage USB 接続 → Mac）

## 検証（実機テスト）

- [ ] program 0-9 で applyPreset による音色切替が動作するか確認
- [ ] KeyStage LCD にプログラム名が表示されるか目視確認
- [ ] PE Notify によるプログラム切替が KeyStage LCD に反映されるか確認
- [ ] BLE MIDI 接続での動作確認（macOS/iOS 版安定後）

## 改善（優先度低）

- [ ] os.Logger の privacy アノテーション見直し（リリースビルド向け `.public` の適切性）
- [ ] 0x5404629 不明 MUID の正体調査（KeyStage 内部エンティティ？別アプリ？）

## 完了

- [x] ロギングシステム全面改修（print → os.Logger + BufferMIDI2Logger 二重出力）
- [x] MIDI-CI Property Exchange フロー実装（ResourceList, DeviceInfo, ChannelList, ProgramList, X-ProgramEdit, X-ParameterList, JSONSchema）
- [x] Program Change preset switching + PE Notify 連携
- [x] ソフトクリッピング（tanhApprox）+ AVAudioSourceNode 移行
- [x] MIDI 2.0 フルプレシジョン対応（16bit velocity, 32bit CC/PB）
