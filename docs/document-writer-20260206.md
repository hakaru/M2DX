# M2DX ドキュメント作成サマリー

**作成日**: 2026-02-06
**作成者**: Claude (document-writer)

---

## 作成したドキュメント一覧

### 1. docs/Architecture.md
**内容**: M2DXのアーキテクチャ全体像
**主要セクション**:
- システム構成図 (iOS App Shell → AUv3 Extension → C++ DSP)
- AUv3 Audio Unit Extension詳細 (M2DXAudioUnit.swift, ViewController)
- Objective-C++ ブリッジ (M2DXKernelBridge)
- C++ DSPエンジン (M2DXKernel, FMOperator, Envelope)
- SwiftUI UI (M2DXPackage)
- ビルド構成とデプロイ
- 技術的判断と設計理由

**特筆事項**:
- パラメータアドレス設計 (100単位でオペレーター分割)
- MIDI処理フロー (AURenderEvent → handleMIDIEventStatic)
- 言語選択の理由 (C++: DSP, Objective-C++: Bridge, Swift: AUv3, SwiftUI: UI)
- パフォーマンス最適化戦略

---

### 2. docs/PropertyExchange.md
**内容**: MIDI 2.0 Property Exchange準拠のパラメータ階層仕様
**主要セクション**:
- Property Exchangeの概念と利点 (vs SysEx)
- M2DXパラメータ階層構造
  - Global/ (6パラメータ)
  - Operators/Op[1-8]/ (各17パラメータ × 8 = 136)
  - LFO/ (7パラメータ)
  - PitchEG/ (8パラメータ)
  - Controller/ (12パラメータ)
- 各パラメータの詳細仕様 (型、範囲、デフォルト値)
- M2DXParameterTree.swift実装解説
- JSON Export機能
- DX7互換性 (155パラメータ → 190パラメータ)
- 使用例 (DAW自動認識、プリセット保存、検索・タグ付け)

**特筆事項**:
- DX7の155パラメータをすべてカバー
- 8オペレーター拡張で+35パラメータ追加
- JSON形式によるGit管理可能なプリセット
- 自己記述的 (self-describing) なパラメータツリー

---

### 3. docs/DSP.md
**内容**: C++ DSPエンジンの技術仕様
**主要セクション**:
- FM合成の基礎理論
- システム構成 (M2DXKernel → Voice → FMOperator → Envelope)
- FMOperator詳細 (周波数計算、FM合成処理、パラメータ)
- Envelope詳細 (DX7スタイル4-Rate/4-Level、レート→係数変換)
- Voice (8オペレーター単位、Note On/Off処理)
- アルゴリズム詳細
  - DX7互換 (1-32): Algorithm 1, 2, 5, 32等
  - M2DX拡張 (33-64): Algorithm 33 (8-op serial), 64 (8-op parallel)
- M2DXKernel (16ボイス・ポリフォニー、Voice Stealing)
- フィードバック実装 (DX7互換)
- パフォーマンス最適化 (正規化、クリッピング防止)
- DX7との互換性マトリックス

**特筆事項**:
- DX7アルゴリズムの完全互換実装
- 8オペレーター拡張アルゴリズムの新規追加
- エンベロープのレート→時間変換式 (指数関数)
- ボイス正規化 (`√activeVoices`)

---

## ソースコード解析の基礎データ

### 解析したファイル

**C++ DSP**:
- `/M2DXAudioUnit/DSP/FMOperator.hpp` (213行)
- `/M2DXAudioUnit/DSP/M2DXKernel.hpp` (338行)

**Objective-C++ Bridge**:
- `/M2DXAudioUnit/Bridge/M2DXKernelBridge.h` (62行)
- `/M2DXAudioUnit/Bridge/M2DXKernelBridge.mm` (85行)

**Swift AUv3**:
- `/M2DXAudioUnit/M2DXAudioUnit.swift` (398行)
- `/M2DXAudioUnit/M2DXAudioUnitViewController.swift`

**Swift Package**:
- `/M2DXPackage/Sources/M2DXCore/PropertyExchange/M2DXParameterTree.swift` (658行)

**プロジェクト構成**:
- `/README.md` (113行)

---

## 技術的発見事項

### 1. アーキテクチャ設計
- **言語レイヤリング**: C++ (DSP) → Objective-C++ (Bridge) → Swift (AUv3) → SwiftUI (UI) の明確な分離
- **AUParameterTree**: 200以上のパラメータを階層構造で管理
- **リアルタイム性能**: `internalRenderBlock`でのMIDI/Audio処理

### 2. Property Exchange実装
- **階層パス設計**: `Global/Algorithm`, `Operators/Op3/EG/Rates/Rate2`
- **型安全性**: PEValueType (integer, float, boolean, enum, string)
- **JSON Export**: MIDI 2.0準拠のメタデータ出力

### 3. DSPエンジン実装
- **DX7互換性**: 32アルゴリズム、4-Rate/4-Level EG、レート変換式
- **8オペレーター拡張**: 6→8オペレーター、32→64アルゴリズム
- **正規化戦略**: `√activeVoices`によるクリッピング防止

---

## ドキュメントの用途

### 対象読者
1. **開発者**: アーキテクチャ理解、機能拡張の参考
2. **MIDI 2.0実装者**: Property Exchange実装例
3. **FM合成研究者**: DX7互換DSPエンジンの実装詳細
4. **UIデザイナー**: パラメータ構造の理解

### 活用場面
- M2DXプロジェクトの技術仕様書
- MIDI2Kit / MIDI 2.0のリファレンス実装
- FM合成エンジンの教育資料
- 新規メンバーのオンボーディング

---

## 今後の更新計画

### 優先度: 高
- [ ] LFO実装後のドキュメント更新
- [ ] Pitch EG実装後のドキュメント更新
- [ ] Keyboard Level Scaling実装後のドキュメント更新

### 優先度: 中
- [ ] アルゴリズム33-64の詳細仕様追加
- [ ] TX816モードのドキュメント作成
- [ ] MIDI 2.0 UMP処理の詳細解説

### 優先度: 低
- [ ] SwiftUI UI実装詳細
- [ ] テスト仕様書
- [ ] パフォーマンスベンチマーク結果

---

## 変更履歴

| 日付 | ファイル | 変更内容 |
|------|---------|---------|
| 2026-02-06 | Architecture.md | 新規作成 |
| 2026-02-06 | PropertyExchange.md | 新規作成 |
| 2026-02-06 | DSP.md | 新規作成 |

---

## 参考資料

- **DX7 Technical Manual**: Yamaha公式技術資料
- **Dexed Source Code**: DX7エミュレータ実装 (EngineMkI.cpp, fm_core.cc, env.cc)
- **MIDI 2.0 Specification**: MIDI Association公式仕様
- **Property Exchange Specification**: MIDI 2.0 PE仕様

---

**完了**: 2026-02-06
**総文字数**: 約30,000文字 (3ドキュメント合計)
**総セクション数**: 85セクション
