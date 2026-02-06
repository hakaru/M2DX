# M2DX Property Exchange 仕様書

## 概要

M2DXは**MIDI 2.0 Property Exchange (PE)** に準拠したパラメータ階層構造を持ち、DAWやMIDIコントローラーから**自己記述的 (self-describing)** にパラメータを発見・操作できます。

従来のMIDI 1.0 SysExでは、パラメータの意味や範囲が不明瞭で、ベンダー固有のドキュメントが必要でした。Property Exchangeは、パラメータのメタデータ（名前、型、範囲、説明）をMIDIメッセージとして送受信可能にし、**プラグアンドプレイの完全自動化**を実現します。

---

## 1. Property Exchange とは

### 1.1 従来のMIDI 1.0 SysExの問題点

**DX7の例**:
```
F0 43 00 00 01 1B 50 ... F7
```
- バイナリデータ、人間が読めない
- パラメータの意味が不明 (1Bは何？)
- ベンダー固有の仕様書が必須
- DAWが自動的に理解できない

### 1.2 MIDI 2.0 Property Exchange の利点

**M2DXの例**:
```json
{
  "path": "Operators/Op1/Level",
  "title": "Op1 Level",
  "type": "integer",
  "min": 0,
  "max": 99,
  "value": 85
}
```
- **階層パス**: `Global/Algorithm`, `Operators/Op3/EG/Rates/Rate2`
- **型情報**: integer, float, boolean, enum, string
- **範囲情報**: min/max
- **ヒューマンリーダブル**: JSONベース
- **DAWが自動で認識**: パラメータツリーを自動構築

**利点**:
- SysExの16進数ダンプが不要
- プリセットをGit管理可能（JSON差分が見える）
- タグ付け・検索・部分転送が容易
- クラウドベースのワークフロー対応

---

## 2. M2DXパラメータ階層構造

M2DXは**DX7の155パラメータ**を拡張し、**8オペレーター対応**として約**200+パラメータ**を提供します。

### 2.1 階層トップレベル

```
M2DX Parameter Tree
├── Global/                      # グローバルパラメータ (6項目)
├── Operators/                   # オペレーターパラメータ (8オペレーター)
│   ├── Op1/                     # (各17項目)
│   ├── Op2/
│   ├── ...
│   └── Op8/
├── LFO/                         # LFOパラメータ (7項目)
├── PitchEG/                     # ピッチEGパラメータ (8項目)
└── Controller/                  # コントローラーマッピング (12項目)
    ├── Wheel/
    ├── Foot/
    ├── Breath/
    └── Aftertouch/
```

---

## 3. パラメータ詳細

### 3.1 Global/ (グローバルパラメータ)

| パス | タイプ | 範囲 | デフォルト | 説明 |
|------|--------|------|-----------|------|
| `Global/Algorithm` | integer | 1-64 | 1 | FMアルゴリズム (1-32: DX7互換, 33-64: 8-op拡張) |
| `Global/Feedback` | integer | 0-7 | 0 | フィードバック量 |
| `Global/OscSync` | boolean | - | true | オシレーター・キー・シンク |
| `Global/Transpose` | integer | -24 - +24 | 0 | グローバル・トランスポーズ (半音) |
| `Global/VoiceName` | string | 10文字 | "INIT VOICE" | パッチ名 |
| `Global/MasterVolume` | integer | 0-127 | 100 | マスター音量 |

**DX7からの変更点**:
- `Algorithm`: 32 → 64 (8オペレーター拡張アルゴリズム追加)
- `MasterVolume`: 新規追加 (DX7にはなかった)

---

### 3.2 Operators/Op[1-8]/ (オペレーターパラメータ)

**DX7は6オペレーター**でしたが、M2DXは**8オペレーター**に拡張。各オペレーターは以下の17パラメータを持ちます。

#### 3.2.1 周波数モード

| パス | タイプ | 範囲 | デフォルト | 説明 |
|------|--------|------|-----------|------|
| `Operators/Op[N]/Mode` | enum | - | "Ratio" | 周波数モード: "Ratio" または "Fixed" |

**DX7互換**:
- Ratio: 基本周波数の整数倍/分数倍
- Fixed: 固定周波数 (Hz)

#### 3.2.2 周波数パラメータ

| パス | タイプ | 範囲 | デフォルト | 説明 |
|------|--------|------|-----------|------|
| `Operators/Op[N]/Frequency/Coarse` | integer | 0-31 | N | 粗い周波数比 (0=0.5, 1-31=1-31) |
| `Operators/Op[N]/Frequency/Fine` | integer | 0-99 | 0 | 細かい周波数調整 |
| `Operators/Op[N]/Frequency/Detune` | integer | -7 - +7 | 0 | ファイン・デチューン |

**Coarse値の対応表** (DX7互換):
```
0 → 0.5
1 → 1.0
2 → 2.0
3 → 3.0
...
31 → 31.0
```

**Fine値の変換**:
```
周波数 = (Coarse + Fine / 100.0) * 基本周波数
```

**Detune値**:
- -7 〜 +7 の範囲で、約±1半音の微調整

#### 3.2.3 レベルパラメータ

| パス | タイプ | 範囲 | デフォルト | 説明 |
|------|--------|------|-----------|------|
| `Operators/Op[N]/Level` | integer | 0-99 | 99 (Op1-4), 70 (Op5-8) | オペレーター出力レベル |
| `Operators/Op[N]/VelocitySensitivity` | integer | 0-7 | 2 | ベロシティ感度 |
| `Operators/Op[N]/AmpModSensitivity` | integer | 0-3 | 0 | 振幅モジュレーション感度 |

#### 3.2.4 スケーリングパラメータ

| パス | タイプ | 範囲 | デフォルト | 説明 |
|------|--------|------|-----------|------|
| `Operators/Op[N]/RateScaling` | integer | 0-7 | 0 | エンベロープ・レート・スケーリング |

**Rate Scaling (DX7互換)**:
- 高音域でエンベロープを速く、低音域で遅くする
- 0 = オフ, 7 = 最大効果

#### 3.2.5 キーボード・レベル・スケーリング (Keyboard Level Scaling)

| パス | タイプ | 範囲 | デフォルト | 説明 |
|------|--------|------|-----------|------|
| `Operators/Op[N]/KeyboardLevelScaling/BreakPoint` | integer | 0-99 | 39 (C3) | ブレークポイント (基準ノート) |
| `Operators/Op[N]/KeyboardLevelScaling/LeftDepth` | integer | 0-99 | 0 | 左側スケーリング深さ |
| `Operators/Op[N]/KeyboardLevelScaling/RightDepth` | integer | 0-99 | 0 | 右側スケーリング深さ |
| `Operators/Op[N]/KeyboardLevelScaling/LeftCurve` | enum | - | "Linear-" | 左側カーブ: "Linear-", "Linear+", "Exp-", "Exp+" |
| `Operators/Op[N]/KeyboardLevelScaling/RightCurve` | enum | - | "Linear-" | 右側カーブ: "Linear-", "Linear+", "Exp-", "Exp+" |

**DX7互換のキーボード・スケーリング**:
```
        BreakPoint (基準音)
            │
   Left     │    Right
 ←─────────┼─────────→
 LeftCurve │ RightCurve
 LeftDepth │ RightDepth
```

#### 3.2.6 エンベロープ・ジェネレーター (EG)

**Rates (レート: 速度)**:
| パス | タイプ | 範囲 | デフォルト | 説明 |
|------|--------|------|-----------|------|
| `Operators/Op[N]/EG/Rates/Rate1` | integer | 0-99 | 99 | R1 (Attack) |
| `Operators/Op[N]/EG/Rates/Rate2` | integer | 0-99 | 75 | R2 (Decay 1) |
| `Operators/Op[N]/EG/Rates/Rate3` | integer | 0-99 | 50 | R3 (Decay 2) |
| `Operators/Op[N]/EG/Rates/Rate4` | integer | 0-99 | 50 | R4 (Release) |

**Levels (レベル: 到達目標)**:
| パス | タイプ | 範囲 | デフォルト | 説明 |
|------|--------|------|-----------|------|
| `Operators/Op[N]/EG/Levels/Level1` | integer | 0-99 | 99 | L1 (Attack target) |
| `Operators/Op[N]/EG/Levels/Level2` | integer | 0-99 | 80 | L2 (Decay 1 target) |
| `Operators/Op[N]/EG/Levels/Level3` | integer | 0-99 | 70 | L3 (Sustain) |
| `Operators/Op[N]/EG/Levels/Level4` | integer | 0-99 | 0 | L4 (Release target, 通常0) |

**DX7互換のエンベロープ構造**:
```
Level
  L1 ┐
     │╲ R1
  L2 │ ┐
     │ │╲ R2
  L3 │ │ ┐━━━━━━━━━━━━ (Sustain, Hold)
     │ │ │         ╲ R4
   0 └─┴─┴──────────┴──→ Time
       R1 R2 R3 (Hold) R4
```

---

### 3.3 LFO/ (LFOパラメータ)

| パス | タイプ | 範囲 | デフォルト | 説明 |
|------|--------|------|-----------|------|
| `LFO/Speed` | integer | 0-99 | 35 | LFO速度 |
| `LFO/Delay` | integer | 0-99 | 0 | LFOディレイ時間 |
| `LFO/PitchModDepth` | integer | 0-99 | 0 | ピッチモジュレーション深さ (PMD) |
| `LFO/AmpModDepth` | integer | 0-99 | 0 | 振幅モジュレーション深さ (AMD) |
| `LFO/Sync` | boolean | - | true | LFOキー・シンク |
| `LFO/Waveform` | enum | - | "Triangle" | LFO波形: "Triangle", "Saw Down", "Saw Up", "Square", "Sine", "S&H" |
| `LFO/PitchModSensitivity` | integer | 0-7 | 3 | ピッチモジュレーション感度 (PMS) |

**DX7互換**:
- 6種類のLFO波形
- Speed: 0 (最遅) 〜 99 (最速)
- Delay: ノートオンからLFOが始まるまでの遅延

---

### 3.4 PitchEG/ (ピッチ・エンベロープ)

DX7のピッチEGは、ノートオンからピッチを上下に変化させるための専用エンベロープです。

**Rates**:
| パス | タイプ | 範囲 | デフォルト | 説明 |
|------|--------|------|-----------|------|
| `PitchEG/Rates/Rate1` | integer | 0-99 | 99 | R1 |
| `PitchEG/Rates/Rate2` | integer | 0-99 | 99 | R2 |
| `PitchEG/Rates/Rate3` | integer | 0-99 | 99 | R3 |
| `PitchEG/Rates/Rate4` | integer | 0-99 | 99 | R4 |

**Levels** (50が基準 = ピッチ変化なし):
| パス | タイプ | 範囲 | デフォルト | 説明 |
|------|--------|------|-----------|------|
| `PitchEG/Levels/Level1` | integer | 0-99 | 50 | L1 |
| `PitchEG/Levels/Level2` | integer | 0-99 | 50 | L2 |
| `PitchEG/Levels/Level3` | integer | 0-99 | 50 | L3 |
| `PitchEG/Levels/Level4` | integer | 0-99 | 50 | L4 |

**レベル値の意味**:
- 50: ピッチ変化なし (基準)
- 0: 最低ピッチ (約-2オクターブ)
- 99: 最高ピッチ (約+2オクターブ)

---

### 3.5 Controller/ (コントローラー・マッピング)

各コントローラー (Mod Wheel, Foot, Breath, Aftertouch) に対して、**Pitch, Amp, EGBias** の3つのパラメータを設定できます。

#### 3.5.1 Mod Wheel (モジュレーション・ホイール)

| パス | タイプ | 範囲 | デフォルト | 説明 |
|------|--------|------|-----------|------|
| `Controller/Wheel/Pitch` | integer | 0-99 | 50 | ピッチへの影響深さ |
| `Controller/Wheel/Amp` | integer | 0-99 | 0 | 振幅への影響深さ |
| `Controller/Wheel/EGBias` | integer | 0-99 | 0 | EGバイアス深さ |

#### 3.5.2 Foot Controller (フット・コントローラー)

| パス | タイプ | 範囲 | デフォルト | 説明 |
|------|--------|------|-----------|------|
| `Controller/Foot/Pitch` | integer | 0-99 | 0 | ピッチへの影響深さ |
| `Controller/Foot/Amp` | integer | 0-99 | 0 | 振幅への影響深さ |
| `Controller/Foot/EGBias` | integer | 0-99 | 0 | EGバイアス深さ |

#### 3.5.3 Breath Controller (ブレス・コントローラー)

| パス | タイプ | 範囲 | デフォルト | 説明 |
|------|--------|------|-----------|------|
| `Controller/Breath/Pitch` | integer | 0-99 | 0 | ピッチへの影響深さ |
| `Controller/Breath/Amp` | integer | 0-99 | 0 | 振幅への影響深さ |
| `Controller/Breath/EGBias` | integer | 0-99 | 0 | EGバイアス深さ |

#### 3.5.4 Aftertouch (アフタータッチ)

| パス | タイプ | 範囲 | デフォルト | 説明 |
|------|--------|------|-----------|------|
| `Controller/Aftertouch/Pitch` | integer | 0-99 | 0 | ピッチへの影響深さ |
| `Controller/Aftertouch/Amp` | integer | 0-99 | 0 | 振幅への影響深さ |
| `Controller/Aftertouch/EGBias` | integer | 0-99 | 0 | EGバイアス深さ |

---

## 4. パラメータツリーの実装

### 4.1 M2DXParameterTree.swift

**PEParameter構造体**:
```swift
public struct PEParameter: Sendable {
    public let path: String              // 階層パス
    public let title: String             // 表示名
    public let description: String       // 説明文
    public let type: PEValueType         // データ型
    public let min: Double?              // 最小値
    public let max: Double?              // 最大値
    public let defaultValue: Any         // デフォルト値
    public let enumValues: [String]?     // enum型の選択肢
}
```

**パラメータ取得API**:
```swift
// すべてのパラメータ (約200個)
M2DXParameterTree.allParameters

// パス指定で取得
M2DXParameterTree.parameter(at: "Operators/Op3/EG/Rates/Rate2")

// プレフィックス検索
M2DXParameterTree.parameters(under: "Operators/Op1/")

// 総数
M2DXParameterTree.totalParameterCount // 200+
```

### 4.2 JSON Export

**Property Exchange用JSON出力**:
```swift
let json = M2DXParameterTree.exportAsJSON()
```

**出力例**:
```json
[
  {
    "path": "Global/Algorithm",
    "title": "Algorithm",
    "description": "FM Algorithm selection (1-64 for 8-op, 1-32 for DX7 compatible)",
    "type": "integer",
    "min": 1,
    "max": 64
  },
  {
    "path": "Operators/Op1/Level",
    "title": "Op1 Level",
    "description": "Operator output level",
    "type": "integer",
    "min": 0,
    "max": 99
  },
  ...
]
```

---

## 5. DX7互換性

### 5.1 互換パラメータ

M2DXは**DX7の155パラメータ**をすべてサポートします：

**DX7パラメータ内訳**:
- Global: 5パラメータ (Algorithm, Feedback, OscSync, Transpose, VoiceName)
- 6オペレーター × 各17パラメータ = 102
- LFO: 6パラメータ
- PitchEG: 8パラメータ
- Controller: 12パラメータ (Mod Wheel, Foot, Breath, AT各3)

**合計**: 約155パラメータ

### 5.2 M2DX拡張

M2DXは以下を追加:
- **8オペレーター**: OP7, OP8を追加 (各17パラメータ × 2 = +34)
- **MasterVolume**: グローバルに追加 (+1)
- **拡張アルゴリズム**: 33-64 (8オペレーター用)

**M2DX総パラメータ数**: 約**190パラメータ**

---

## 6. 使用例

### 6.1 DAWでの自動認識

**Logic Pro / GarageBand**:
1. M2DX AUv3を読み込み
2. Property Exchangeでパラメータツリーを取得
3. 自動的に以下が表示される:
   ```
   Global/
     ├── Algorithm (1-64)
     ├── Feedback (0-7)
     └── MasterVolume (0-127)

   Operators/
     ├── Op1/
     │   ├── Level (0-99)
     │   ├── Frequency/Coarse (0-31)
     │   └── EG/Rates/Rate1 (0-99)
     ...
   ```

### 6.2 プリセット保存 (JSON)

**従来のSysEx**:
```
F0 43 00 00 01 1B 50 49 41 4E 4F ... F7
```
↑ 意味不明のバイナリ

**M2DX Property Exchange**:
```json
{
  "preset": "M2DX Init Voice",
  "parameters": {
    "Global/Algorithm": 1,
    "Global/Feedback": 0,
    "Operators/Op1/Level": 99,
    "Operators/Op1/Frequency/Coarse": 1,
    "Operators/Op1/EG/Rates/Rate1": 99,
    "Operators/Op1/EG/Levels/Level1": 99,
    ...
  }
}
```
↑ 人間が読める、Gitで差分管理可能

### 6.3 検索・タグ付け

**JSON形式のメリット**:
```json
{
  "preset": "Electric Piano",
  "tags": ["electric", "piano", "vintage", "dx7"],
  "author": "M2DX Team",
  "parameters": { ... }
}
```

クラウドサービスで以下が可能:
- タグ検索: `tags:vintage AND category:piano`
- 作者検索: `author:"M2DX Team"`
- パラメータ検索: `Algorithm=5 AND Feedback>0`

---

## 7. まとめ

M2DXのProperty Exchange階層構造:

| カテゴリ | パラメータ数 | 説明 |
|---------|-------------|------|
| Global | 6 | アルゴリズム、フィードバック、音量等 |
| Operators (×8) | 17 × 8 = 136 | 周波数、レベル、EG等 |
| LFO | 7 | 速度、波形、深さ等 |
| PitchEG | 8 | ピッチエンベロープ |
| Controller | 12 | Wheel, Foot, Breath, AT |
| **合計** | **約190** | DX7 (155) + M2DX拡張 (35) |

**Property Exchangeの利点**:
- ✅ 自己記述的 (self-describing)
- ✅ DAWが自動認識
- ✅ JSONベースでGit管理可能
- ✅ タグ付け・検索・部分転送が容易
- ✅ SysExの16進数ダンプが不要

M2DXは、MIDI 2.0の特性を最大限活用した、次世代のFMシンセサイザー・パラメータモデルです。
