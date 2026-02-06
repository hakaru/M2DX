# M2DX アーキテクチャ仕様書

## 概要

M2DXは**8オペレーターFMシンセサイザー**として設計された、MIDI 2.0準拠のiOS AUv3 Audio Unit Extensionです。DX7互換のFM合成エンジンを持ち、MIDI2KitとProperty Exchangeを活用した次世代のパラメータ制御を実現しています。

### システム構成

```
┌─────────────────────────────────────────────────────────┐
│ M2DX (iOS App Shell)                                    │
│   - M2DXApp.swift (エントリポイント)                    │
│   - SwiftUI Root View                                   │
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│ M2DXAudioUnit (AUv3 Extension)                          │
│                                                         │
│  ┌───────────────────────────────────────────────┐      │
│  │ Swift Layer                                   │      │
│  │  - M2DXAudioUnit.swift                        │      │
│  │  - M2DXAudioUnitViewController.swift          │      │
│  │  - AUParameterTree (200+ parameters)          │      │
│  └───────────────────────────────────────────────┘      │
│                         │                               │
│                         ▼                               │
│  ┌───────────────────────────────────────────────┐      │
│  │ Objective-C++ Bridge                          │      │
│  │  - M2DXKernelBridge.h / .mm                   │      │
│  └───────────────────────────────────────────────┘      │
│                         │                               │
│                         ▼                               │
│  ┌───────────────────────────────────────────────┐      │
│  │ C++ DSP Engine                                │      │
│  │  - M2DXKernel.hpp (ポリフォニー管理)          │      │
│  │  - Voice (8オペレーター)                      │      │
│  │  - FMOperator.hpp (FM合成+EG)                 │      │
│  │  - Envelope (DX7スタイル4-rate/4-level)       │      │
│  └───────────────────────────────────────────────┘      │
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│ M2DXPackage (Swift Package)                             │
│  - M2DXCore: パラメータモデル、PropertyExchange定義     │
│  - M2DXFeature: SwiftUI UI (8-op view, TX816 view)     │
└─────────────────────────────────────────────────────────┘
```

---

## 1. AUv3 Audio Unit Extension

### 1.1 M2DXAudioUnit.swift

**役割**: AUv3 Generatorの実装。AudioToolboxフレームワーク上で動作し、DAWやホストアプリに読み込まれる。

**主要機能**:
- **AUAudioUnitサブクラス**: Audio Unitのライフサイクル管理
- **AUParameterTree**: 200以上のパラメータを階層構造で公開
  - Global parameters (algorithm, master volume, feedback)
  - 8 operator parameters (level, ratio, detune, feedback, EG rates/levels)
- **internalRenderBlock**: リアルタイムオーディオ処理ブロック
- **MIDI処理**: AURenderEvent経由でNote On/Off、Control Change受信

**パラメータアドレス設計**:
```swift
// グローバル
0: Algorithm
1: MasterVolume
2: Feedback

// オペレーター (100単位でセクション分割)
100 + opIndex*100 + 0:  Level
100 + opIndex*100 + 1:  Ratio
100 + opIndex*100 + 2:  Detune
100 + opIndex*100 + 3:  Feedback
100 + opIndex*100 + 10-13: EG Rates (R1-R4)
100 + opIndex*100 + 20-23: EG Levels (L1-L4)

例: OP3のLevel = address 300
例: OP8のEG Rate2 = address 811
```

**MIDI処理フロー**:
1. `internalRenderBlock`内で`AURenderEvent`を受信
2. `handleMIDIEventStatic`でMIDIメッセージを解析
   - 0x90: Note On → `kernel.handleNoteOn(note, velocity)`
   - 0x80: Note Off → `kernel.handleNoteOff(note)`
   - 0xB0: Control Change → CC#7 (Volume)等を処理
3. C++カーネルにディスパッチ

### 1.2 M2DXAudioUnitViewController.swift

**役割**: AUv3のUI。SwiftUIビューをUIViewControllerにホスティング。

**機能**:
- SwiftUIベースのエディタUI統合
- ホストアプリ（GarageBand、Logic Pro等）内で表示される
- M2DXFeature (SwiftUI UI)をホストする薄いラッパー

---

## 2. Objective-C++ ブリッジ

### 2.1 M2DXKernelBridge.h / .mm

**役割**: Swift (AUv3) と C++ DSPエンジン間の言語ブリッジ。

**実装詳細**:
- `std::unique_ptr<M2DX::M2DXKernel>` をObjective-Cクラス内に保持
- Swiftから呼び出し可能なObjective-Cメソッドを提供
- C++カーネルへのメソッド転送

**公開API**:
```objc
- (instancetype)initWithSampleRate:(double)sampleRate;
- (void)setSampleRate:(double)sampleRate;
- (void)setAlgorithm:(int)algorithm;
- (void)setMasterVolume:(float)volume;

// オペレーター設定
- (void)setOperatorLevel:(int)opIndex level:(float)level;
- (void)setOperatorRatio:(int)opIndex ratio:(float)ratio;
- (void)setOperatorDetune:(int)opIndex detuneCents:(float)cents;
- (void)setOperatorFeedback:(int)opIndex feedback:(float)feedback;
- (void)setOperatorEnvelopeRates:(int)opIndex r1:(float)r1 r2:(float)r2 r3:(float)r3 r4:(float)r4;
- (void)setOperatorEnvelopeLevels:(int)opIndex l1:(float)l1 l2:(float)l2 l3:(float)l3 l4:(float)l4;

// MIDI処理
- (void)handleNoteOn:(uint8_t)note velocity:(uint8_t)velocity;
- (void)handleNoteOff:(uint8_t)note;
- (void)allNotesOff;

// オーディオ処理
- (void)processBufferLeft:(float *)outL right:(float *)outR frameCount:(int)frameCount;
- (int)activeVoiceCount;
```

**初期化時のデフォルトサウンド**:
- OP1-4: Level=1.0, Ratio=1-4
- OP5-8: Level=0.5, Ratio=5-8
- OP6のみ Feedback=0.3 (DX7のフィードバック・オペレーター相当)
- すべてのオペレーターに基本的なEG設定 (R1=99, R2=75, R3/R4=50)

---

## 3. C++ DSPエンジン

### 3.1 M2DXKernel.hpp

**役割**: メインDSPカーネル。16ボイスポリフォニー管理、アルゴリズム切り替え、MIDIハンドリング。

**定数**:
```cpp
constexpr int kNumOperators = 8;   // 8オペレーター (DX7=6を拡張)
constexpr int kNumVoices = 16;     // 16音ポリフォニー
constexpr int kNumAlgorithms = 64; // 64アルゴリズム (1-32: DX7互換, 33-64: 8-op拡張)
```

**クラス構造**:

#### MIDINote
```cpp
struct MIDINote {
    uint8_t note;
    uint8_t velocity;
    bool active;
};
```

#### Voice
- **8個のFMOperator**を保持
- **アルゴリズム処理**: 64種類のアルゴリズムに対応
  - Algorithm 1 (index 0): OP6→5→4→3→2→1 (シリアルチェーン)
  - Algorithm 2 (index 1): (OP6→5→4→3→2) + OP1 (2キャリア)
  - Algorithm 5 (index 4): 3ペア並列
  - Algorithm 32 (index 31): 全6オペレーター並列
  - Algorithm 33 (index 32): 全8オペレーター・シリアル (8-op拡張)
  - Algorithm 64 (index 63): 全8オペレーター並列 (8-op拡張)

**アルゴリズム処理例**:
```cpp
// Algorithm 1: OP6→5→4→3→2→1 (DX7 Algorithm 1)
float processAlgorithm1() {
    float mod = operators_[5].process(); // OP6 (modulator)
    mod = operators_[4].process(mod);    // OP5
    mod = operators_[3].process(mod);    // OP4
    mod = operators_[2].process(mod);    // OP3
    mod = operators_[1].process(mod);    // OP2
    return operators_[0].process(mod);   // OP1 (carrier)
}

// Algorithm 33: 8オペレーター・フルシリアル (M2DX拡張)
float processAlgorithm33() {
    float mod = operators_[7].process(); // OP8
    mod = operators_[6].process(mod);    // OP7
    mod = operators_[5].process(mod);    // OP6
    mod = operators_[4].process(mod);    // OP5
    mod = operators_[3].process(mod);    // OP4
    mod = operators_[2].process(mod);    // OP3
    mod = operators_[1].process(mod);    // OP2
    return operators_[0].process(mod);   // OP1 (carrier)
}
```

#### M2DXKernel
- **16個のVoice**を管理
- **ボイス・スティーリング**: 空きボイスがない場合、最古のボイスを再利用
- **正規化**: アクティブボイス数の平方根で除算し、クリッピング防止
- **パラメータ一括設定**: すべてのボイスに対してパラメータを同期的に適用

**処理フロー**:
```cpp
float processSample() {
    float output = 0.0f;
    int activeVoices = 0;

    for (auto& voice : voices_) {
        if (voice.isActive()) {
            output += voice.process();
            ++activeVoices;
        }
    }

    // ボイス数に応じた正規化 (クリッピング防止)
    if (activeVoices > 0) {
        output /= std::sqrt(static_cast<float>(activeVoices));
    }

    return output * masterVolume_;
}
```

### 3.2 FMOperator.hpp

**役割**: 単一のFMオペレーター。正弦波オシレーター + DX7スタイル・エンベロープジェネレーター。

#### Envelope クラス

**DX7互換 4-Rate / 4-Level エンベロープ**:
```
Level
  L1 ┐
     │╲
     │ ╲
  L2 │  ┐
     │  │╲
  L3 │  │ ┐━━━━━━━━━━━━ (Sustain)
     │  │ │             ╲
  L4 │  │ │             │
   0 └──┴─┴─────────────┴──→ Time
     R1 R2 R3 (Hold)     R4
```

**ステージ遷移**:
1. **Idle**: 初期状態
2. **Attack** (R1): 0 → L1
3. **Decay1** (R2): L1 → L2
4. **Decay2** (R3): L2 → L3
5. **Sustain**: L3でホールド
6. **Release** (R4): L3 → L4 (通常0)

**レート→係数変換** (DX7互換):
```cpp
void recalculateCoefficients() {
    for (int i = 0; i < 4; ++i) {
        float rate = rates_[i]; // 0-99
        float timeInSeconds = 10.0f * std::exp(-0.069f * rate);
        coefficients_[i] = 1.0f - std::exp(-1.0f / (timeInSeconds * sampleRate_));
    }
}
```
- Rate 99 (最速): 約0.01秒
- Rate 0 (最遅): 約10秒

**エンベロープ処理** (1次ローパスフィルタ近似):
```cpp
currentLevel_ += coefficient * (targetLevel - currentLevel_);
```

#### FMOperator クラス

**パラメータ**:
- `frequency_`: 基本周波数 (Hz)
- `ratio_`: 周波数比 (例: 1.0, 2.0, 3.5)
- `detune_`: デチューン (セント → 乗数変換)
- `level_`: 出力レベル (0.0-1.0)
- `feedback_`: 自己フィードバック (0.0-1.0)

**FM合成処理**:
```cpp
float process(float modulation = 0.0f) {
    float envelopeLevel = envelope_.process();

    // 自己フィードバック
    float feedbackMod = feedback_ * previousOutput_;

    // 位相計算 (外部変調 + フィードバック)
    float effectivePhase = phase_ + modulation + feedbackMod;

    // サイン波生成
    float output = std::sin(effectivePhase * 2.0f * M_PI);

    // エンベロープ + レベル適用
    output *= envelopeLevel * level_;

    // 位相更新
    phase_ += phaseIncrement_;
    if (phase_ >= 1.0f) phase_ -= 1.0f;

    previousOutput_ = output;
    return output;
}
```

**周波数計算**:
```cpp
void noteOn(float baseFrequency) {
    frequency_ = baseFrequency * ratio_ * detune_;
    phaseIncrement_ = frequency_ / sampleRate_;
    envelope_.noteOn();
    phase_ = 0.0f;
}
```

---

## 4. SwiftUI UI (M2DXPackage)

### 4.1 M2DXCore

**PropertyExchange パラメータ定義**:
- `M2DXParameterTree.swift`: 200以上のパラメータを階層構造で定義
- MIDI 2.0 Property Exchange準拠
- JSON形式でエクスポート可能

### 4.2 M2DXFeature

**SwiftUI Views**:
- `M2DXRootView`: モード切り替え (M2DX 8-op / TX816)
- `M2DX8OpView`: 8オペレーター 2×4グリッド表示
- `TX816View`: 8モジュール・マルチティンバー表示
- `OperatorGridView`: オペレーター詳細パネル

---

## 5. ビルドとデプロイ

### 5.1 プロジェクト構造

```
M2DX.xcworkspace/
├── M2DX.xcodeproj/           (App shell)
├── M2DXPackage/              (Swift Package)
│   ├── Sources/
│   │   ├── M2DXCore/
│   │   └── M2DXFeature/
│   └── Tests/
├── M2DXAudioUnit/            (AUv3 Extension target)
│   ├── DSP/                  (C++)
│   ├── Bridge/               (Objective-C++)
│   ├── Parameters/           (Swift)
│   ├── M2DXAudioUnit.swift
│   └── M2DXAudioUnitViewController.swift
├── M2DX/                     (App target)
└── Config/                   (XCConfig)
```

### 5.2 署名とEntitlements

- Development Team: 必須（Xcodeで設定）
- Entitlements: `Config/M2DX.entitlements`
  - Audio Unit Extension
  - Inter-App Audio (本番時のみ)

### 5.3 デバッグとテスト

**AUv3のテスト方法**:
1. Xcodeから実機/シミュレータにインストール
2. GarageBand / Logic Pro等のホストアプリを起動
3. Audio Unit Extensions → M2DX を読み込み
4. MIDI入力でサウンド確認

---

## 6. 技術的特徴と設計判断

### 6.1 言語選択

| レイヤー | 言語 | 理由 |
|---------|------|------|
| DSP | C++ | リアルタイム性能、ゼロオーバーヘッド抽象化 |
| ブリッジ | Objective-C++ | SwiftとC++の相互運用 |
| Audio Unit | Swift | AudioToolbox API、型安全性 |
| UI | SwiftUI | 宣言的UI、iOS標準 |

### 6.2 パフォーマンス最適化

- **ボイスごとの独立処理**: キャッシュ効率
- **整数演算の回避**: floatベースの処理
- **不要な分岐削減**: switch文を使ったアルゴリズム選択
- **正規化による安全性**: `sqrt(activeVoices)`でクリッピング防止

### 6.3 拡張性

- **8オペレーター対応**: DX7 (6-op) からの自然な拡張
- **64アルゴリズム**: 将来的なアルゴリズム追加に対応
- **Property Exchange**: 新規パラメータ追加が容易

---

## 7. まとめ

M2DXは以下の技術スタックで構成されています：

- **C++ DSP**: FMOperator, Envelope, M2DXKernel
- **Objective-C++ Bridge**: M2DXKernelBridge
- **Swift AUv3**: M2DXAudioUnit, AUParameterTree
- **SwiftUI**: M2DXFeature (8-op UI, TX816 UI)
- **MIDI 2.0**: Property Exchange準拠のパラメータツリー

DX7互換のFM合成を保ちつつ、8オペレーターへの拡張とMIDI 2.0の高解像度制御を実現した、次世代のFMシンセサイザー・リファレンス実装です。
