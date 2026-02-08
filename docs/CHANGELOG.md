# Changelog

M2DXプロジェクトの全変更履歴を記録します。

このフォーマットは [Keep a Changelog](https://keepachangelog.com/ja/1.0.0/) に基づいています。

## [Unreleased]

### Added
- MIDI 2.0 Channel Voice メッセージ (type 0x4) デコード対応
- 16ビットベロシティ、32ビットコントロールチェンジ、32ビットピッチベンドのフルプレシジョン処理
- サスティンペダル (CC64) 対応
- ピッチベンド対応 (±2半音)
- UMPワード (umpWord1/umpWord2) の生データ保存と高精度デコード
- ロギングシステム全面改修: os.Logger + BufferMIDI2Logger 二重出力アーキテクチャ
- CompositeMIDI2Logger による統合ログ管理
- MIDI-CI Property Exchange Responder 実装 (ResourceList, DeviceInfo, ChannelList, ProgramList, X-ProgramEdit, X-ParameterList, JSONSchema)
- Program Change → PE Notify 連携 (ChannelList / X-ProgramEdit 自動通知)
- MIDIデバッグログバッファ (BufferMIDI2Logger → UI表示)
- macOS entity 除外ロジック (PEResponder.excludeMUIDs / subscriberMUIDs()) — KORG KeyStage以外への誤Notify防止
- KeyStage Subscribe Reply (0x39) フィルタリング機能

### Changed
- CoreMIDITransport: MIDI 1.0プロトコルからMIDI 2.0プロトコルに切り替え
- MIDIEventQueue.data2: UInt8からUInt32に拡張 (高精度データ格納用)
- MIDIInputManagerコールバックシグネチャ: velocity UInt16, CC/PB UInt32に変更
- MIDI 1.0互換7ビットパスを廃止し、16/32ビットパイプラインに統一
- 全 print() を os.Logger に置換 (subsystem: "com.example.M2DX")
- CIManager / PEManager にロガーインスタンスを注入する設計に変更
- **PEResponder MIDI2Logger プロトコル注入** (2026-02-08)
  - print() → logger.debug/info() 統一
  - PEResponder: command:"notify" 無視ケース追加、0x39明示ケース追加
  - MIDIInputManager: 重複MUID/0x39フィルタをPEResponderに移管
- **MIDIInputManager リファクタリング** (2026-02-08)
  - peSnifferMode を #if DEBUG 囲い
  - acceptedOldMUIDs 削除（未使用プロパティ）
  - BufferMIDI2Logger @unchecked Sendable 安全性コメント追加
  - handleConfigurationChange: restartTask パターン（cancel+replace、100msデバウンス）
  - appendDebugLog PE/CI/SNIFF分岐統一
- **peIsolationStep デバッグ分岐削除** (2026-02-08)
  - step 4/5/6デバッグ分岐削除、step引数削除、常にフルPE/CI動作

### Fixed
- **KORG KeyStage LCD プログラム名表示問題を完全解決** (2026-02-08)
  - PE Notify sub-ID2 を 0x3F → 0x38 に修正 (MIDI-CI PE v1.1準拠)
  - X-ProgramEdit を KORG公式仕様の currentValues 形式に修正
  - KeyStage ハング問題を解決（連続20+回のProgram Change動作安定）
  - macOS環境でのリアルタイムデバッグ環境を確立し、根本原因を特定
- **iOS USB版 KeyStage LCD ハング問題を完全解決** (2026-02-08)
  - 根本原因: USB 3ポート(Session 1, CTRL, DAW OUT)全てにbroadcast → Session 1/DAW OUTへのCI/PEがLCDハング
  - targeted送信実装: resolvePEDestinations() — CoreMIDI API直接使用、CTRL優先
  - PEResponder/CIManager にreplyDestinationsパラメータ追加
  - 結果: iOS実機 USB接続で完全動作、LCD表示成功、ハングなし
- **KeyStage Value UP/DOWN ナビゲーション問題を完全解決** (2026-02-08)
  - 根本原因: KeyStageはbankPC値を1-basedで解釈する
  - 0-based(bankPC:[0,0,0]〜[0,0,9])だとナビゲーションがずれてPC重複送信
  - 修正: ProgramList/X-ProgramEdit/Notify全てでbankPC[2]=index+1（1-based）
  - PC受信時: programIndex-1 で0-based配列インデックスに変換
  - 結果: Value UP/DOWN が完全に順番通り動作（UP: 2→3→...→10, DOWN: 9→8→...→1）
- ChannelList supportsSubscription バグ修正 (2026-02-08)
  - peIsolationStep >= 6 条件がStep 3でfalse → 405拒否
  - 修正: 常にtrue（peIsolationStep削除後）

## [2026-02-07] - ソフトクリッピング + AVAudioSourceNode移行 + リファクタリング + MIDI 2.0対応

### Added
- ソフトクリッピング (tanhApprox Pade近似) によるデジタル歪み防止
- AVAudioSourceNodeによるゼロレイテンシオーディオレンダリング
- CoreAudio直接レンダーコールバックによる最小遅延実現
- DX7プリセットシステム (32アルゴリズム対応)
- MIDI入力選択機能
- オーディオデバイス管理機能
- MIDI-CI Property Exchange サポート
- MIDIデバッグUI
- バーチャルエンドポイント提案機能
- サスティンペダル (CC64) サポート
- ピッチベンド (±2半音) サポート
- MIDI 2.0プロトコル対応 (UMPメッセージング)

### Changed
- AVAudioPlayerNodeからAVAudioSourceNodeに移行
- オーディオレンダリング: バッファスケジューリング方式からCoreAudio直接コールバック方式に変更
- ボイス正規化スケール: 0.7から3.0に変更 (和音時のヘッドルーム確保)
- CoreMIDI受信: Task{}非同期ホップを除去し、レイテンシ削減
- FMSynthEngine: 32個のアルゴリズムメソッドを静的ルーティングテーブル (kAlgorithmTable) に置換
- オペレータアクセス: 6分岐switch文をwithOp()ヘルパーに統合
- MIDIInputManager: 冗長なMainActor.runを直接呼び出しに変更
- CoreMIDITransport: MIDI 1.0プロトコルからMIDI 2.0プロトコルに切り替え

### Fixed
- iOS実機でのデジタル歪み問題 (ソフトクリッピングで解決)
- MIDIレイテンシ問題 (AVAudioSourceNode移行で約5msに短縮)
- バッファスケジューリングのギャップによるクリック/ポップノイズ

### Removed
- M2DXCore.swift: 未使用型13個を削除 (311行削減)
  - SynthEngineMode, DX7Algorithm, M2DXAlgorithm, LFOParameters
  - ModulationSource, ModulationDestination, ModulationRouting
  - M2DXVoice, DX7Voice, TX816Module, TX816Configuration
  - M2DXEngineState, VoiceParameters typealias
- M2DXCoreTests.swift: 削除された型のテストを除去 (138行削減)
- FMSynthEngine.swift: 32個のアルゴリズムメソッド (データ駆動テーブルに置換、286行削減)
- AVAudioPlayerNode関連のバッファスケジューリングコード
- ダブルバッファリング、セマフォ、RenderState (AVAudioSourceNode移行により不要)

**コードベース削減:** 合計737行削減 (1809行→1072行)

## [2026-01-XX] - MIDI2Kit移行 + macOSサポート + DX7機能拡張

### Added
- macOSデスクトップスタンドアロンアプリ
- DX7プリセットシステム (INIT VOICE含む)
- MIDIデバイス選択機能
- オーディオデバイス管理機能
- Pure-Swift FM音源エンジン (6オペレータ、32アルゴリズム)

### Changed
- MIDIKitからMIDI2Kitに移行
- AUv3ホスティングを廃止し、Pure-Swift FMシンセエンジンに置換

### Removed
- AUv3ホスティング関連コード
- MIDIKit依存

## [2026-01-XX] - スタンドアロンオーディオ再生 + MIDI鍵盤UI

### Added
- スタンドアロンオーディオ再生機能
- MIDIキーボードUI

### Fixed
- スタンドアロンオーディオ再生における重大な問題を修正

## [2026-01-XX] - 初回リリース

### Added
- M2DX FM Synthesizer (iOS対応)
- MIDI 2.0 Property Exchange サポート
- CoreMIDI統合
- SwiftUI製ユーザーインターフェース
- Swift 6.1+ Strict Concurrency モード
- AVFoundation オーディオエンジン
- 6オペレータFM音源 (DX7互換)
- 32アルゴリズム (DX7互換)

---

## 凡例

- **Added**: 新機能
- **Changed**: 既存機能の変更
- **Deprecated**: 非推奨 (間もなく削除予定)
- **Removed**: 削除された機能
- **Fixed**: バグ修正
- **Security**: セキュリティ修正
