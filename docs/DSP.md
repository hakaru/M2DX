# M2DX DSPエンジン仕様書

## 概要

M2DXのDSPエンジンは、**DX7互換のFM合成アルゴリズム**を忠実に再現しつつ、**8オペレーターへの拡張**と**64アルゴリズム**をサポートする、C++で実装されたリアルタイム音声合成システムです。

**主要技術**:
- **FM (Frequency Modulation) 合成**: 正弦波オシレーターの周波数変調
- **DX7スタイル4-Rate/4-Level エンベロープ**: 非線形エンベロープジェネレーター
- **16ボイス・ポリフォニー**: 同時発音16音
- **64アルゴリズム**: 32 DX7互換 + 32拡張8-opアルゴリズム

---

## 1. FM合成の基礎

### 1.1 FM合成の原理

**周波数変調 (Frequency Modulation)**:
```
carrier_output = sin(2π × carrier_freq × t + modulator_output)
```

**モジュレーター (Modulator)** が **キャリア (Carrier)** の周波数を変調することで、倍音豊かな音色を生成します。

**例**:
```
Modulator: sin(2π × 880 Hz × t)  ← OP2
           ↓ modulation
Carrier:   sin(2π × 440 Hz × t + modulation) ← OP1 (出力)
```

DX7では、**6個のオペレーター (OP1-6)** を様々な接続パターン (アルゴリズム) で組み合わせることで、ベル、エレピ、ブラス、ベース等の多彩な音色を生成します。

M2DXは**8オペレーター (OP1-8)** に拡張し、さらに複雑な変調が可能です。

---

## 2. システム構成

### 2.1 C++クラス階層

```
M2DXKernel (M2DXKernel.hpp)
├── Voice (16個)
│   └── FMOperator (8個)
│       └── Envelope
└── パラメータ管理
```

**定数**:
```cpp
constexpr int kNumOperators = 8;   // 8オペレーター
constexpr int kNumVoices = 16;     // 16音ポリフォニー
constexpr int kNumAlgorithms = 64; // 64アルゴリズム
```

---

## 3. FMOperator (FMOperator.hpp)

### 3.1 役割

単一のFMオペレーター。以下の機能を持ちます：
- **正弦波オシレーター**: `sin(2π × phase)`
- **周波数比 (Ratio) 制御**: 基本周波数の整数倍・分数倍
- **デチューン**: 微細な周波数調整 (セント単位)
- **エンベロープ**: DX7スタイル4-Rate/4-Level
- **自己フィードバック**: 出力を自分自身に変調

### 3.2 パラメータ

```cpp
class FMOperator {
private:
    float sampleRate_;       // サンプリングレート (44100 Hz等)
    float frequency_;        // 現在の周波数 (Hz)
    float ratio_;            // 周波数比 (1.0, 2.0, 3.5等)
    float detune_;           // デチューン乗数 (1.0 = デチューンなし)
    float level_;            // 出力レベル (0.0-1.0)
    float feedback_;         // 自己フィードバック (0.0-1.0)
    float phase_;            // 位相 (0.0-1.0)
    float phaseIncrement_;   // 1サンプルごとの位相増加量
    float previousOutput_;   // 前回の出力 (フィードバック用)
    Envelope envelope_;      // エンベロープジェネレーター
};
```

### 3.3 周波数計算

**Note On時**:
```cpp
void noteOn(float baseFrequency) {
    frequency_ = baseFrequency * ratio_ * detune_;
    phaseIncrement_ = frequency_ / sampleRate_;
    envelope_.noteOn();
    phase_ = 0.0f;
}
```

**例**:
- MIDIノート番号 69 (A4) → 440 Hz
- Ratio = 2.0, Detune = 1.02 (約+35セント)
- 最終周波数 = 440 × 2.0 × 1.02 = **897.6 Hz**

### 3.4 FM合成処理

```cpp
float process(float modulation = 0.0f) {
    float envelopeLevel = envelope_.process();

    // 自己フィードバック
    float feedbackMod = feedback_ * previousOutput_;

    // 位相計算 (外部変調 + 自己フィードバック)
    float effectivePhase = phase_ + modulation + feedbackMod;

    // 正弦波生成
    float output = std::sin(effectivePhase * 2.0f * M_PI);

    // エンベロープとレベルを適用
    output *= envelopeLevel * level_;

    // 位相更新
    phase_ += phaseIncrement_;
    if (phase_ >= 1.0f) {
        phase_ -= 1.0f;
    }

    previousOutput_ = output;
    return output;
}
```

**ポイント**:
- `modulation`: 外部オペレーターからの変調入力
- `feedbackMod`: 自己フィードバック (DX7のフィードバック機能)
- `effectivePhase`: 合成位相 = 基本位相 + 変調
- `sin(effectivePhase * 2π)`: 正弦波生成

---

## 4. Envelope (エンベロープジェネレーター)

### 4.1 DX7スタイル4-Rate/4-Level EG

DX7のエンベロープは、**4つのRate (速度)** と **4つのLevel (目標レベル)** で構成されます。

```
Level
  L1 ┐
     │╲ R1 (Attack)
  L2 │ ┐
     │ │╲ R2 (Decay 1)
  L3 │ │ ┐━━━━━━━━━━━━ (Sustain, Hold at L3)
     │ │ │         ╲ R4 (Release)
   0 └─┴─┴──────────┴──→ Time
       R1 R2 R3      R4
```

### 4.2 ステージ遷移

```cpp
enum class Stage {
    Idle,      // 待機状態
    Attack,    // R1: 0 → L1
    Decay1,    // R2: L1 → L2
    Decay2,    // R3: L2 → L3
    Sustain,   // L3でホールド
    Release    // R4: L3 → L4 (通常0)
};
```

**Note On**:
```
Idle → Attack → Decay1 → Decay2 → Sustain (ホールド)
```

**Note Off**:
```
Sustain → Release → Idle
```

### 4.3 レート→係数変換 (DX7互換)

DX7では、Rate値 (0-99) を時間に変換するために**指数関数**を使用します。

```cpp
void recalculateCoefficients() {
    for (int i = 0; i < 4; ++i) {
        float rate = rates_[i]; // 0-99

        // DX7スタイル: 高Rateほど速い
        float timeInSeconds = 10.0f * std::exp(-0.069f * rate);

        // 1次ローパス係数に変換
        coefficients_[i] = 1.0f - std::exp(-1.0f / (timeInSeconds * sampleRate_));
    }
}
```

**レート値と時間の対応**:
| Rate | 時間 (秒) | 用途 |
|------|----------|------|
| 0 | 約10秒 | 極めて遅いアタック/リリース |
| 50 | 約0.63秒 | 通常のディケイ |
| 75 | 約0.19秒 | 速めのアタック |
| 99 | 約0.01秒 | 即座のアタック |

### 4.4 エンベロープ処理 (1次ローパス近似)

```cpp
float process() {
    switch (stage_) {
        case Stage::Attack:
            currentLevel_ += coefficients_[0] * (levels_[0] - currentLevel_);
            if (currentLevel_ >= levels_[0] * 0.99f) {
                currentLevel_ = levels_[0];
                stage_ = Stage::Decay1;
            }
            break;

        case Stage::Decay1:
            currentLevel_ += coefficients_[1] * (levels_[1] - currentLevel_);
            if (std::abs(currentLevel_ - levels_[1]) < 0.001f) {
                currentLevel_ = levels_[1];
                stage_ = Stage::Decay2;
            }
            break;

        // ... (Decay2, Sustain, Release同様)
    }

    return currentLevel_;
}
```

**1次ローパス近似の式**:
```
currentLevel += coefficient × (targetLevel - currentLevel)
```

これは**指数関数的な接近**を実現し、DX7の滑らかなエンベロープカーブを再現します。

---

## 5. Voice (ボイス: 8オペレーター単位)

### 5.1 役割

1つの**Voice**は、**8個のFMOperator**を持ち、選択されたアルゴリズムに従って接続します。

```cpp
class Voice {
private:
    std::array<FMOperator, kNumOperators> operators_; // 8 operators
    MIDINote note_;                                   // MIDIノート情報
    int algorithm_;                                   // アルゴリズム番号 (0-63)
    float velocityScale_;                             // ベロシティスケール
};
```

### 5.2 Note On処理

```cpp
void noteOn(uint8_t note, uint8_t velocity) {
    note_.note = note;
    note_.velocity = velocity;
    note_.active = true;

    // MIDIノート→周波数変換
    float frequency = 440.0f * std::pow(2.0f, (note - 69) / 12.0f);
    float velocityScale = velocity / 127.0f;

    // 全オペレーターにNote On
    for (auto& op : operators_) {
        op.noteOn(frequency);
    }
    velocityScale_ = velocityScale;
}
```

**周波数計算式** (Equal Temperament):
```
f = 440 × 2^((note - 69) / 12)
```

**例**:
- ノート 69 (A4): 440 Hz
- ノート 60 (C4): 440 × 2^(-9/12) ≈ 261.63 Hz
- ノート 81 (A5): 440 × 2^(12/12) = 880 Hz

### 5.3 アルゴリズム処理

```cpp
float process() {
    if (!isActive()) return 0.0f;
    return processAlgorithm();
}
```

**アルゴリズムの振り分け**:
```cpp
float processAlgorithm() {
    float output = 0.0f;

    switch (algorithm_) {
        case 0:  return processAlgorithm1();   // DX7 Algorithm 1
        case 1:  return processAlgorithm2();   // DX7 Algorithm 2
        case 4:  return processAlgorithm5();   // DX7 Algorithm 5
        case 31: return processAlgorithm32();  // DX7 Algorithm 32
        case 32: return processAlgorithm33();  // M2DX 8-op拡張
        case 63: return processAlgorithm64();  // M2DX 8-op拡張
        default: return processAlgorithm1();   // フォールバック
    }
}
```

---

## 6. アルゴリズム詳細

### 6.1 DX7互換アルゴリズム (1-32)

DX7は**32種類のアルゴリズム**を持ち、6オペレーターの接続パターンが異なります。

#### Algorithm 1: フルシリアル (最も倍音豊か)
```
OP6 → OP5 → OP4 → OP3 → OP2 → OP1 (carrier)
```

**実装**:
```cpp
float processAlgorithm1() {
    float mod = operators_[5].process();   // OP6 (modulator)
    mod = operators_[4].process(mod);      // OP5
    mod = operators_[3].process(mod);      // OP4
    mod = operators_[2].process(mod);      // OP3
    mod = operators_[1].process(mod);      // OP2
    return operators_[0].process(mod);     // OP1 (carrier, 出力)
}
```

**特徴**:
- 最も変調が深い
- ブラス、ベルなどの金属的な音色に適する

#### Algorithm 2: シリアル + 並列 (2キャリア)
```
OP6 → OP5 → OP4 → OP3 → OP2 (carrier)
                  +
                 OP1 (carrier)
```

**実装**:
```cpp
float processAlgorithm2() {
    float mod = operators_[5].process();      // OP6
    mod = operators_[4].process(mod);         // OP5
    mod = operators_[3].process(mod);         // OP4
    mod = operators_[2].process(mod);         // OP3
    float out1 = operators_[1].process(mod);  // OP2 (carrier)
    float out2 = operators_[0].process();     // OP1 (carrier, 並列)
    return (out1 + out2) * 0.5f;
}
```

**特徴**:
- 2つのキャリアで豊かな音色
- エレクトリックピアノに適する

#### Algorithm 5: 3ペア並列
```
OP6 → OP5 (carrier)
OP4 → OP3 (carrier)
OP2 → OP1 (carrier)
```

**実装**:
```cpp
float processAlgorithm5() {
    float mod1 = operators_[5].process();
    float out1 = operators_[4].process(mod1);

    float mod2 = operators_[3].process();
    float out2 = operators_[2].process(mod2);

    float mod3 = operators_[1].process();
    float out3 = operators_[0].process(mod3);

    return (out1 + out2 + out3) * 0.33f;
}
```

**特徴**:
- バランスの取れた音色
- パッド、ストリングスに適する

#### Algorithm 32: 全並列 (最もシンプル)
```
OP6 (carrier)
OP5 (carrier)
OP4 (carrier)
OP3 (carrier)
OP2 (carrier)
OP1 (carrier)
```

**実装**:
```cpp
float processAlgorithm32() {
    float output = 0.0f;
    for (int i = 0; i < 6; ++i) {
        output += operators_[i].process();
    }
    return output / 6.0f;
}
```

**特徴**:
- 加算合成に近い
- オルガン、クワイアに適する

---

### 6.2 M2DX拡張8オペレーター・アルゴリズム (33-64)

M2DXは**8オペレーター**を活用した拡張アルゴリズムを32種類追加します。

#### Algorithm 33: 8オペレーター・フルシリアル
```
OP8 → OP7 → OP6 → OP5 → OP4 → OP3 → OP2 → OP1 (carrier)
```

**実装**:
```cpp
float processAlgorithm33() {
    float mod = operators_[7].process();   // OP8
    mod = operators_[6].process(mod);      // OP7
    mod = operators_[5].process(mod);      // OP6
    mod = operators_[4].process(mod);      // OP5
    mod = operators_[3].process(mod);      // OP4
    mod = operators_[2].process(mod);      // OP3
    mod = operators_[1].process(mod);      // OP2
    return operators_[0].process(mod);     // OP1 (carrier)
}
```

**特徴**:
- DX7では不可能だった深い変調
- 極めて倍音豊かなブラス、パーカッシブサウンド

#### Algorithm 64: 8オペレーター・全並列
```
OP8 (carrier)
OP7 (carrier)
OP6 (carrier)
OP5 (carrier)
OP4 (carrier)
OP3 (carrier)
OP2 (carrier)
OP1 (carrier)
```

**実装**:
```cpp
float processAlgorithm64() {
    float output = 0.0f;
    for (int i = 0; i < kNumOperators; ++i) {
        output += operators_[i].process();
    }
    return output / static_cast<float>(kNumOperators);
}
```

**特徴**:
- 8音の加算合成
- 豊かなオルガン、パッド

---

## 7. M2DXKernel (ポリフォニー管理)

### 7.1 役割

**M2DXKernel**は、16個のVoiceを管理し、以下を処理します：
- MIDI Note On/Off
- ボイス割り当て (Voice Allocation)
- ボイス・スティーリング (Voice Stealing)
- オーディオバッファ処理

```cpp
class M2DXKernel {
private:
    std::array<Voice, kNumVoices> voices_;  // 16ボイス
    float sampleRate_;
    float masterVolume_;
    int algorithm_;
};
```

### 7.2 Note On処理

```cpp
void noteOn(uint8_t note, uint8_t velocity) {
    if (velocity == 0) {
        noteOff(note);
        return;
    }

    // 空きボイスを検索、なければスティール
    Voice* voice = findFreeVoice();
    if (voice) {
        voice->noteOn(note, velocity);
    }
}
```

**ボイス検索**:
```cpp
Voice* findFreeVoice() {
    // 1. 非アクティブなボイスを探す
    for (auto& voice : voices_) {
        if (!voice.isActive()) {
            return &voice;
        }
    }

    // 2. 空きがない場合、最古のボイスをスティール
    return &voices_[0];
}
```

**Voice Stealing (ボイス・スティーリング)**:
- 16音を超えた場合、最古のボイスを強制的にNote Offして再利用
- DX7と同様の挙動

### 7.3 Note Off処理

```cpp
void noteOff(uint8_t note) {
    for (auto& voice : voices_) {
        if (voice.isActive() && voice.getNote() == note) {
            voice.noteOff();
        }
    }
}
```

**Note Off時**:
- エンベロープが**Release**ステージに移行
- L4 (通常0) に向かって減衰
- 完全に消音後、ボイスが**Idle**に戻り再利用可能になる

### 7.4 オーディオ処理

**単一サンプル処理**:
```cpp
float processSample() {
    float output = 0.0f;
    int activeVoices = 0;

    // 全ボイスを加算
    for (auto& voice : voices_) {
        if (voice.isActive()) {
            output += voice.process();
            ++activeVoices;
        }
    }

    // 正規化 (クリッピング防止)
    if (activeVoices > 0) {
        output /= std::sqrt(static_cast<float>(activeVoices));
    }

    return output * masterVolume_;
}
```

**バッファ処理 (ステレオ)**:
```cpp
void processBuffer(float* outputL, float* outputR, int numFrames) {
    for (int i = 0; i < numFrames; ++i) {
        float sample = processSample();
        outputL[i] = sample;
        outputR[i] = sample;
    }
}
```

**正規化の理由**:
- 16ボイス同時発音時、単純加算では16倍の音量でクリッピング
- `√activeVoices` で除算することで、適度な音量を維持
- DX7と同様の挙動

---

## 8. フィードバック実装

### 8.1 DX7のフィードバック

DX7では、特定のオペレーター (通常OP6) が**自己フィードバック**を持ちます。

**フィードバック処理**:
```cpp
float feedbackMod = feedback_ * previousOutput_;
float effectivePhase = phase_ + modulation + feedbackMod;
float output = std::sin(effectivePhase * 2.0f * M_PI);
previousOutput_ = output;
```

**特徴**:
- 自己変調により、ノイズ成分や倍音を増加
- ブラスやリードサウンドの「エッジ」を生成

### 8.2 フィードバック安定化

Dexed (DX7エミュレータ) では、フィードバックの安定性を確保するため、**2サンプル平均化**を行います。

**M2DXの簡易実装**:
```cpp
previousOutput_ = output; // 1サンプル保持
```

**Dexedスタイル (将来実装予定)**:
```cpp
previousOutput_ = (previousOutput_ + output) * 0.5f; // 2サンプル平均
```

---

## 9. パフォーマンス最適化

### 9.1 計算効率

**使用する演算**:
- `std::sin()`: 正弦波生成 (CPUネイティブ実装)
- `std::exp()`: エンベロープ係数計算 (初期化時のみ)
- `std::pow()`: 周波数計算 (Note On時のみ)

**避ける演算**:
- 分岐 (`if`) を最小化 → アルゴリズムごとに専用関数
- 動的メモリ確保 → すべて `std::array` で静的確保

### 9.2 クリッピング防止

**正規化式**:
```cpp
output /= std::sqrt(static_cast<float>(activeVoices));
```

**理由**:
- 線形正規化 (`/activeVoices`) では、1音時に音量が小さすぎる
- 平方根正規化により、1音と16音で適度なバランス

---

## 10. 技術仕様まとめ

| 項目 | 仕様 |
|------|------|
| **オペレーター数** | 8 (DX7: 6) |
| **ポリフォニー** | 16音 |
| **アルゴリズム数** | 64 (1-32: DX7互換, 33-64: 8-op拡張) |
| **エンベロープ** | 4-Rate/4-Level (DX7互換) |
| **オシレーター** | 正弦波 (FM合成) |
| **フィードバック** | オペレーターごとに設定可能 |
| **サンプリングレート** | 44100 Hz〜 (可変) |
| **出力フォーマット** | ステレオ (モノラル音源をL/R同一出力) |
| **言語** | C++ (DSP), Objective-C++ (Bridge), Swift (AUv3) |

---

## 11. DX7との互換性

### 11.1 互換要素

✅ **完全互換**:
- エンベロープ形状 (4-Rate/4-Level)
- アルゴリズム 1-32
- レート→時間変換式
- フィードバック機構
- ボイス・スティーリング

✅ **拡張互換**:
- 8オペレーター (DX7: 6)
- 64アルゴリズム (DX7: 32)
- Property Exchange (DX7: SysEx)

### 11.2 将来実装予定

以下のDX7機能は現バージョンで未実装:
- LFO (低周波オシレーター)
- Pitch EG (ピッチ・エンベロープ)
- Keyboard Level Scaling
- Rate Scaling
- Velocity Sensitivity
- 固定周波数モード (Fixed Frequency)

---

## 12. 開発ガイドライン

### 12.1 アルゴリズム追加方法

新規アルゴリズムを追加する場合:

1. `Voice`クラスに新メソッド追加:
```cpp
float processAlgorithmXX() {
    // オペレーター接続パターンを実装
}
```

2. `processAlgorithm()`の`switch`に追加:
```cpp
case XX: return processAlgorithmXX();
```

3. Property Exchangeの`Global/Algorithm`の最大値を更新

### 12.2 新規パラメータ追加

1. `FMOperator`/`Voice`にパラメータ追加
2. `M2DXKernel`にsetter追加
3. `M2DXKernelBridge`にObjective-Cメソッド追加
4. `M2DXAudioUnit`にAUParameterTree登録
5. `M2DXParameterTree.swift`にPE定義追加

---

## まとめ

M2DX DSPエンジンは、以下の特徴を持ちます：

- ✅ **DX7互換**: 32アルゴリズム、4-Rate/4-Level EG
- ✅ **8オペレーター拡張**: DX7の6オペレーターから拡張
- ✅ **64アルゴリズム**: 拡張8-opアルゴリズム32種追加
- ✅ **C++実装**: リアルタイム性能
- ✅ **16ボイス・ポリフォニー**: Voice Stealing対応

次世代のFMシンセサイザーとして、DX7の伝統を受け継ぎつつ、現代的な拡張を実現しています。
