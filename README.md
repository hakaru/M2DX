# M2DX
### MIDI 2.0 FM Synthesizer Reference Implementation

> **MIDI 2.0 + DX7互換のFMシンセシス、Swift 6で完全実装**

**M2DX** は、iOS/macOS向けのMIDI 2.0対応FMシンセサイザーです。
DX7互換の6オペレータ・32アルゴリズムによるクラシックなFMサウンドを、現代のSwift 6技術スタックで完全再実装しています。

このプロジェクトは **MIDI2Kit** と **Swift Concurrency** を活用した、次世代のソフトウェアシンセサイザーのリファレンス実装です。

---

## ✨ 主な特徴

### 🎹 MIDI 2.0 UMP対応
- **MIDI 2.0プロトコル** (UMP: Universal MIDI Packet) 完全サポート
- **Channel Voice type 0x4** デコード対応
  - 16-bit velocity (65536段階)
  - 32-bit CC値 (4,294,967,296段階)
  - 32-bit pitch bend (±2半音、滑らかな変調)
- MIDI 1.0フォールバック対応 (type 0x2)
- CoreMIDIから直接UMPワードを処理

### 🎚 MIDI-CI Property Exchange
- **155以上のパラメータ** を階層的に公開
  ```
  Operators/Op1/Level
  Operators/Op6/Ratio
  LFO/Wave
  Global/Algorithm
  ```
- DAWやコントローラーが自動的にパラメータを発見可能
- JSONベースのプリセット管理（SysEx不要）
- 自己記述型インストゥルメント

### 🔊 AVAudioSourceNode直接レンダリング
- **ゼロレイテンシ**のオーディオ生成
- CoreAudioレンダーコールバックでFMエンジンを直接駆動
- バッファキューイングのオーバーヘッドを排除
- iOS IOBufferDuration (≈5ms) が実質的なレイテンシ

### 🎵 DX7互換FMエンジン
- **6オペレータ** × **32アルゴリズム** (完全なDX7アルゴリズムセット)
- データ駆動型ルーティングテーブル (`kAlgorithmTable`)
- 4段階ADSR エンベロープ
- キーボードレートスケーリング (KRS)
- キーボードレベルスケーリング (KLS)
- フィードバック対応

### 🎛 高品質オーディオ処理
- **16ボイス ポリフォニー**
- Padé近似tanhによる **ソフトクリッピング** (デジタル歪み防止)
- ダイナミックボイス正規化 (`1/sqrt(activeCount)`)
- サスティンペダル (CC64) 対応
- ピッチベンド対応 (±2半音)

### 🎼 DX7プリセットライブラリ
- 32種類のファクトリープリセット内蔵
  - BRASS1, E.PIANO1, WOOD BASS, FLUTE 1など
- リアルタイムプリセット切り替え
- プリセットブラウザUI

---

## 🧠 アーキテクチャ

### Pure Swift 6.1+ 実装
- **C++コード不使用**（旧版のC++ DSPは削除済み）
- **Objective-C++ブリッジ不使用**
- Swift Concurrency (async/await, actors, @MainActor) による完全なスレッドセーフ
- Sendable準拠による厳格な並行性チェック

### Audio処理
- **AVAudioSourceNode** でCoreAudioレンダーコールバックを直接利用
- ロックフリーの **MIDIEventQueue** (OSAllocatedUnfairLock)
- 48kHz サンプリングレート
- ステレオ出力

### MIDI処理
- **MIDI2Kit** (ローカル依存)
- CoreMIDITransport による動的MIDI入力ソース列挙
- AsyncStream ベースのMIDIデータフロー
- MIDI 2.0 ._2_0 プロトコルモード
- 16-bit velocity / 32-bit CC / 32-bit pitch bend の完全精度保持

### UI
- **SwiftUI** + **MV (Model-View) パターン**
- ViewModelは不使用（@State, @Observable, @Environment による状態管理）
- タッチキーボード（C3-B4、1オクターブ）
- リアルタイムMIDIデバッグ表示
- プリセットブラウザ

### プロジェクト構造
```
M2DX/
├── M2DX/                        # iOS app shell
│   └── M2DXApp.swift           # @main entry point
├── M2DXMac/                     # macOS app
│   └── M2DXMacApp.swift
├── M2DXPackage/                 # All features (Swift Package)
│   ├── Package.swift
│   ├── Sources/
│   │   ├── M2DXCore/           # Data models, PE definitions
│   │   └── M2DXFeature/        # UI + Audio + MIDI
│   └── Tests/
│       └── M2DXCoreTests/      # Swift Testing tests
├── MIDI2Kit/                    # Local dependency (Git submodule)
├── Config/                      # XCConfig, entitlements
└── docs/                        # Documentation
```

**重要:** すべての機能は **M2DXPackage** Swift Package 内に実装されています。アプリプロジェクトは単なるエントリポイントです。

---

## 🚀 ビルド方法

### 必要要件
- **Xcode 16.0+**
- **Swift 6.1+**
- **iOS 18.0+** または **macOS 14.0+**
- **MIDI2Kit** (ローカル依存、`MIDI2Kit/` サブディレクトリ)

### ビルド手順

1. **リポジトリのクローン**
   ```bash
   git clone https://github.com/your-username/M2DX.git
   cd M2DX
   ```

2. **MIDI2Kit サブモジュールの初期化** (必要な場合)
   ```bash
   # MIDI2Kitがサブモジュールの場合
   git submodule update --init --recursive
   ```

3. **Workspace を開く**
   ```bash
   open M2DX.xcworkspace
   ```

4. **ビルド**
   - iOS版: **M2DX** スキームを選択
   - macOS版: **M2DXMac** スキームを選択
   - Simulator または 実機 を選択
   - `Cmd+B` でビルド

5. **実行**
   - `Cmd+R` で実行
   - 実機推奨（MIDIデバイス接続のため）

### テスト実行
```bash
# Swift Testing を使用
xcodebuild test -workspace M2DX.xcworkspace -scheme M2DX -destination 'platform=iOS Simulator,name=iPhone 16'
```

---

## 🎯 使い方

### MIDI入力
1. アプリ起動後、上部の **MIDI Input** ピッカーからMIDIデバイスを選択
2. 選択したデバイスがオンライン状態（緑のドット）であることを確認
3. MIDIキーボードを演奏すると音が出力されます

### 画面内キーボード
- 下部のタッチキーボード (C3-B4) をタップして演奏可能
- 16-bit velocity 固定値で送信

### プリセット選択
- 上部の **Preset** ピッカーから32種類のDX7プリセットを選択
- リアルタイムで音色が切り替わります

### サスティンペダル
- CC64 (Sustain Pedal) に対応
- ペダルON中はノートオフしても音が持続
- ペダルOFF時にリリースフェーズへ移行

### ピッチベンド
- ±2半音の範囲でピッチベンド対応
- MIDI 2.0では32-bitの滑らかな変調
- MIDI 1.0では14-bit (MSB+LSB)

---

## 🧩 技術仕様

### FMアルゴリズム
- **6オペレータ** (OP1-OP6)
- **32アルゴリズム** (DX7完全互換)
- 各オペレータは以下を持つ:
  - ADSR エンベロープ (Attack, Decay, Sustain, Release)
  - 周波数比 (Ratio: Coarse + Fine)
  - デチューン (-7 ~ +7)
  - 出力レベル (0-99)
  - キーボードレート/レベルスケーリング
  - ベロシティセンシティビティ

### アルゴリズムルーティング
- データ駆動型テーブル (`FMSynthEngine.swift` 内)
- 各アルゴリズムは以下を定義:
  - 各オペレータの変調ソース (src0, src1, src2)
  - キャリア判定 (isCarrier)
  - 正規化係数 (normalizationScale)
- `Voice.process()` がテーブルから読み取り、汎用的に処理

### MIDI 2.0対応内容
| 機能 | 対応状況 | 備考 |
|------|---------|------|
| MIDI 2.0 UMP | ✅ | type 0x4 (Channel Voice) |
| 16-bit velocity | ✅ | 65536段階 |
| 32-bit CC | ✅ | 4,294,967,296段階 |
| 32-bit pitch bend | ✅ | ±2半音、滑らかな変調 |
| Property Exchange | ✅ | 155+パラメータ公開 |
| Per-Note Controllers | ❌ | 未実装 |
| Profile Configuration | ❌ | 未実装 |

---

## 📎 プロジェクトステータス

- ✅ Pure Swift 6.1+ 実装 (C++/ObjC++削除)
- ✅ 6オペレータ DX7互換モデル
- ✅ 32アルゴリズム (データ駆動型)
- ✅ MIDI 2.0 UMP対応 (type 0x4)
- ✅ Property Exchange (155+パラメータ)
- ✅ AVAudioSourceNode (ゼロレイテンシ)
- ✅ ソフトクリッピング (Padé近似tanh)
- ✅ サスティンペダル (CC64)
- ✅ ピッチベンド (32-bit)
- ✅ DX7プリセットライブラリ (32種類)
- ✅ iOS + macOS 両対応
- ❌ 8オペレータ拡張 (計画中)
- ❌ TX816マルチティンバー (計画中)
- ❌ AUv3 Audio Unit Extension (削除済み)

---

## 🏷 Git履歴（主要マイルストーン）

1. **Initial commit**: MIDI 2.0 Property Exchange対応FM Synthesizer
2. **Standalone audio playback**: スタンドアロン再生 + MIDIキーボードUI
3. **Pure-Swift FM synth engine**: AUv3ホスティング廃止、Pure Swiftエンジン
4. **macOS desktop app**: macOSデスクトップアプリ追加
5. **MIDI2Kit migration**: MIDIKit → MIDI2Kit 移行
6. **DX7 preset system**: プリセットシステム + MIDI入力選択 + オーディオデバイス管理
7. **MIDI-CI Property Exchange**: PE + MIDIデバッグUI + 仮想エンドポイント提案
8. **Soft clipping**: ソフトクリッピング追加 (iOS歪み対策)
9. **AVAudioSourceNode migration**: 最小レイテンシ化 + コードベースリファクタリング (737行削減)
10. **Sustain pedal & pitch bend**: サスティンペダル (CC64) + ピッチベンド対応
11. **MIDI 2.0 protocol**: ._2_0切り替え + Channel Voice (type 0x4) デコード

---

## 🛠 開発方針

### コーディングスタイル
- **Swift 6 Strict Concurrency** モード
- **@MainActor** によるUI隔離
- **async/await** による非同期処理（GCD不使用）
- **@Observable** による状態管理（ObservableObject廃止）
- **value types (struct)** 優先、reference types (class) は最小限
- **早期リターン** による可読性向上

### テスト
- **Swift Testing** フレームワーク (@Test, #expect)
- XCTest不使用
- `M2DXPackage/Tests/M2DXCoreTests/` にテストを配置

### ドキュメント
- コード内ドキュメントコメント
- `docs/` ディレクトリに技術資料
- `docs/ClaudeWorklogYYYYMMDD.md` に開発ログ

---

## 🎼 使用例

### MIDIキーボードでの演奏
1. KeyStageなどのMIDI 2.0対応キーボードを接続
2. M2DXアプリで **MIDI Input** ピッカーから選択
3. プリセット「E.PIANO1」を選択
4. 鍵盤を弾くと、DX7スタイルのエレピサウンドが出力される
5. サスティンペダルでノートを持続
6. ピッチベンドホイールで音程を変調

### プリセットブラウジング
- **BRASS1**: 金管楽器サウンド (アルゴリズム22)
- **E.PIANO1**: エレクトリックピアノ (アルゴリズム5)
- **WOOD BASS**: ウッドベース (アルゴリズム13)
- **FLUTE 1**: フルート (アルゴリズム19)
- **STRINGS 1**: ストリングスパッド (アルゴリズム24)

---

## 📚 参考資料

### MIDI 2.0
- [MIDI 2.0 Specification](https://www.midi.org/specifications)
- [MIDI2Kit Documentation](https://github.com/orchetect/MIDI2Kit)

### DX7 / FM Synthesis
- Yamaha DX7 Service Manual
- [The DX7 Algorithm Chart](https://github.com/asb2m10/dexed/wiki/Algorithms)

### Swift Concurrency
- [Swift Concurrency Roadmap](https://github.com/apple/swift-evolution/blob/main/proposals/0304-structured-concurrency.md)
- [Swift 6 Migration Guide](https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/)

---

## 🏷 キーワード

`MIDI 2.0` · `MIDI2Kit` · `Property Exchange` · `FM Synthesis` · `DX7`
`Swift 6` · `SwiftUI` · `AVAudioSourceNode` · `6-Operator` · `iOS` · `macOS`

---

## 📄 ライセンス

MIT License (詳細は `LICENSE` ファイルを参照)

---

## 🤝 コントリビューション

Issue、Pull Requestを歓迎します。
大きな変更の場合は、まずIssueで提案してください。

---

**M2DX** — MIDI 2.0時代のFMシンセシス、Pure Swiftで。
