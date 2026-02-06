# コードレビューレポート

## 概要
- レビュー対象: M2DXプロジェクト（AUv3 FM Synthesizer）
- レビュー日: 2026-02-06
- レビュー範囲: AUv3実装、C++ DSPエンジン、Swift統合、PE階層定義

## サマリー
- 🔴 Critical: 2件
- 🟡 Warning: 5件
- 🔵 Suggestion: 8件

---

## 詳細レビュー

### 🔴 M2DXKernelBridge.mm:16 - 8オペレーター初期化の不整合

**問題**
ブリッジ初期化で8オペレーター（0..<8）を初期化していますが、C++カーネルは6オペレーター（kNumOperators = 6）で定義されています。これにより配列外アクセスが発生します。

**現在のコード**
```objective-c
// M2DXKernelBridge.mm:16
for (int i = 0; i < 8; ++i) {
    _kernel->setOperatorLevel(i, (i < 4) ? 1.0f : 0.5f);
    // ...
}
```

```cpp
// M2DXKernel.hpp:11
constexpr int kNumOperators = 6;
```

**提案**
```objective-c
// kNumOperators定数を使用
for (int i = 0; i < M2DX::kNumOperators; ++i) {
    _kernel->setOperatorLevel(i, (i < 4) ? 1.0f : 0.5f);
    // ...
}
```

**理由**
配列外アクセスはundefined behaviorを引き起こし、クラッシュやメモリ破壊の原因となります。DX7互換（6オペレーター）に統一されたため、全箇所で一貫性を保つ必要があります。

---

### 🔴 M2DXAudioUnitViewController.swift:105,138 - UI表記と実装の不整合

**問題**
UI上の説明文が「8-Operator FM Synthesizer」と表記され、Algorithmピッカーが1-64を表示していますが、実装は6オペレーター・32アルゴリズムです。

**現在のコード**
```swift
// Line 105
Text("8-Operator FM Synthesizer")
    .font(.caption)

// Line 138-140
ForEach(1...64, id: \.self) { num in
    Text("\(num)").tag(num - 1)
}
```

**提案**
```swift
// DX7互換の正確な表記
Text("6-Operator FM Synthesizer (DX7 Compatible)")
    .font(.caption)

// 32アルゴリズムに制限
ForEach(1...32, id: \.self) { num in
    Text("\(num)").tag(num - 1)
}
```

**理由**
UIとバックエンドの不整合はユーザー混乱とバグを引き起こします。実装仕様（DX7互換6オペレーター・32アルゴリズム）に正確に一致させるべきです。

---

### 🟡 M2DXKernel.hpp:86-107 - アルゴリズム実装の不完全性

**問題**
32アルゴリズム中、実装されているのは4種類（1, 2, 5, 32）のみで、残り28アルゴリズムがデフォルトにフォールバックします。これはDX7互換性の観点から不十分です。

**現在のコード**
```cpp
switch (algorithm_) {
    case 0: // Algorithm 1
        output = processAlgorithm1();
        break;
    case 1: // Algorithm 2
        output = processAlgorithm2();
        break;
    case 4: // Algorithm 5
        output = processAlgorithm5();
        break;
    case 31: // Algorithm 32
        output = processAlgorithm32();
        break;
    default:
        // Default to algorithm 1 for unimplemented
        output = processAlgorithm1();
        break;
}
```

**提案**
- docs/DSP.mdに記載されている32アルゴリズム全てを実装
- または、未実装アルゴリズムを明示的にログ出力し、将来実装予定であることを文書化

**理由**
DX7互換を謳う以上、32アルゴリズム全実装は必須です。現状では特定の音色が正しく再現できません。

---

### 🟡 FMOperator.hpp:170 - リアルタイム処理でのセルフフィードバック安定性

**問題**
セルフフィードバックが1サンプル遅延のみで、Dexed実装では2サンプル平均化を採用しています。これは高フィードバック時の数値不安定性回避のためです。

**現在のコード**
```cpp
// Line 170
float feedbackMod = feedback_ * previousOutput_;
```

**提案**
```cpp
// 2サンプル平均化（Dexed方式）
float feedbackMod = feedback_ * (previousOutput_ + previousOutput2_) * 0.5f;
// processの最後で:
previousOutput2_ = previousOutput_;
previousOutput_ = output;
```

**理由**
DX7実機では高フィードバック時にもノイズが出にくい設計です。1サンプル遅延のみでは発振やエイリアシングが発生しやすくなります。

---

### 🟡 M2DXKernel.hpp:266 - ボイス正規化ロジックの非線形性

**問題**
アクティブボイス数に基づく正規化で平方根を使用していますが、これはリアルタイムパフォーマンスへの影響とDX7互換性の観点から検討が必要です。

**現在のコード**
```cpp
// Line 266
if (activeVoices > 0) {
    output /= std::sqrt(static_cast<float>(activeVoices));
}
```

**提案**
```cpp
// オプション1: 線形スケーリング（DX7方式）
if (activeVoices > 1) {
    output /= static_cast<float>(activeVoices);
}

// オプション2: ルックアップテーブル化
const float scaleFactors[kNumVoices + 1] = {1.0f, 1.0f, 0.707f, ...};
output *= scaleFactors[activeVoices];
```

**理由**
sqrt()はリアルタイム処理で比較的重い演算です。DX7はシンプルな線形スケーリングまたは固定ゲインを使用していました。

---

### 🟡 M2DXAudioUnit.swift:77-101 - internalRenderBlockでのメモリ安全性

**問題**
kernelをキャプチャしていますが、force unwrap（!）を使用しており、nilチェックがありません。レンダースレッドでのクラッシュリスクがあります。

**現在のコード**
```swift
// Line 77
let kernel = self.kernel!

return { actionFlags, timestamp, frameCount, outputBusNumber, outputData, realtimeEventListHead, pullInputBlock in
    // ...
}
```

**提案**
```swift
// Guard let でnil安全性を確保
guard let kernel = self.kernel else {
    return { _, _, _, _, outputData, _, _ in
        // サイレント出力
        let outputBufferList = UnsafeMutableAudioBufferListPointer(outputData)
        for buffer in outputBufferList {
            memset(buffer.mData, 0, Int(buffer.mDataByteSize))
        }
        return noErr
    }
}

let kernel = kernel  // キャプチャ用
return { actionFlags, ... in
    // 処理
}
```

**理由**
AUv3のライフサイクル中、allocateRenderResources前にinternalRenderBlockが呼ばれる可能性があります。クラッシュ防止のため安全な初期化が必要です。

---

### 🟡 M2DXParameterTree.swift:144 - PE階層とAUParameterのインピーダンスミスマッチ

**問題**
M2DXParameterTree.swiftで定義されたPE階層（Coarse: 0-31, Fine: 0-99等）と、M2DXAudioUnit.swiftのAUParameter定義（ratio: 0.5-32）が対応していません。

**現在のコード**
```swift
// M2DXParameterTree.swift:144
// Coarse: 0-31, Fine: 0-99

// M2DXAudioUnit.swift:224-226
let ratio = AUParameterTree.createParameter(
    address: baseAddress + 1,
    min: 0.5,
    max: 32,
    unit: .ratio
)
```

**提案**
PE階層定義とAUParameterを統一し、変換ロジックを明示的に実装:
```swift
// AUParameter → DX7 Coarse/Fine への変換関数を追加
private func ratioToCoarseFine(_ ratio: Float) -> (coarse: Int, fine: Int) {
    // DX7変換ロジック
}
```

**理由**
MIDI 2.0 Property Exchange統合時、パラメータマッピングが不明確だとバグの温床になります。階層定義と実装の対応を明確にすべきです。

---

### 🔵 M2DXAudioUnit.swift:26 - サンプルレートのハードコード

**問題**
初期化時に44100.0をハードコードしていますが、iOS Audio Sessionのデフォルトは48000が多く、また動的に変更される可能性があります。

**現在のコード**
```swift
// Line 26, 30-31
kernel = M2DXKernelBridge(sampleRate: 44100.0)

let format = AVAudioFormat(
    standardFormatWithSampleRate: 44100.0,
    channels: 2
)!
```

**提案**
```swift
// システムのサンプルレートを使用
let defaultSampleRate = AVAudioSession.sharedInstance().sampleRate
kernel = M2DXKernelBridge(sampleRate: defaultSampleRate)

let format = AVAudioFormat(
    standardFormatWithSampleRate: defaultSampleRate,
    channels: 2
)!
```

**理由**
iOSデバイスやオーディオインターフェースによってサンプルレートが異なります。システム設定を尊重することで互換性が向上します。

---

### 🔵 FMOperator.hpp:103 - DX7エンベロープレートカーブの簡略化

**問題**
エンベロープのレート→係数変換が簡略化された指数関数ですが、DX7実機の非線形カーブとは異なります。

**現在のコード**
```cpp
// Line 103
float timeInSeconds = 10.0f * std::exp(-0.069f * rate);
coefficients_[i] = 1.0f - std::exp(-1.0f / (timeInSeconds * sampleRate_));
```

**参考: Dexed実装**
```cpp
// env.cc: レートテーブルとインクリメント計算
// 非線形マッピングテーブル使用
```

**提案**
docs/DSP.mdに記載されたDexedのレートテーブルベース実装を検討してください。より正確なDX7エミュレーションが可能です。

**理由**
現状でも動作しますが、DX7の特徴的なエンベロープカーブを正確に再現するにはルックアップテーブルが望ましいです。

---

### 🔵 M2DXKernel.hpp:299 - ボイススティーリングアルゴリズムの改善

**問題**
ボイススティーリングが常に最初のボイス（voices_[0]）を盗むため、発音中の音が途切れやすくなります。

**現在のコード**
```cpp
// Line 299
// Voice stealing: return first voice (oldest)
return &voices_[0];
```

**提案**
```cpp
// 最もエンベロープレベルが低いボイスを盗む
Voice* findLowestLevelVoice() {
    Voice* lowest = &voices_[0];
    float lowestLevel = lowest->getCurrentEnvelopeLevel();

    for (auto& voice : voices_) {
        float level = voice.getCurrentEnvelopeLevel();
        if (level < lowestLevel) {
            lowest = &voice;
            lowestLevel = level;
        }
    }
    return lowest;
}
```

**理由**
最も音量が小さいボイスを盗むことで、聴覚的な不自然さを最小化できます。DX7も類似のロジックを使用していました。

---

### 🔵 M2DXAudioUnit.swift:154-195 - パラメータツリー構造の改善

**問題**
buildParameterTree()がフラットな配列を作成していますが、AUParameterGroupを使用した階層構造の方が理解しやすく、ホストアプリでの表示も改善されます。

**提案**
```swift
// グループ化されたパラメータツリー
let globalGroup = AUParameterTree.createGroup(
    withIdentifier: "global",
    name: "Global",
    children: [algorithm, masterVolume, feedback]
)

let operatorsGroup = AUParameterTree.createGroup(
    withIdentifier: "operators",
    name: "Operators",
    children: (0..<6).map { createOperatorGroup(index: $0) }
)

return AUParameterTree.createTree(withChildren: [globalGroup, operatorsGroup])
```

**理由**
AUParameterGroupを使用することで、GarageBandやLogic Proなどのホストアプリでパラメータが整理されて表示されます。

---

### 🔵 FMOperator.hpp:176 - 位相精度とエイリアシング対策

**問題**
基本的なサイン波オシレーターで、高周波数域でのエイリアシング対策がありません。

**現在のコード**
```cpp
// Line 176
float output = std::sin(effectivePhase * 2.0f * M_PI);
```

**提案**
```cpp
// オプション1: BLEP/PolyBLEP（帯域制限）
// オプション2: Oversampling（2x or 4x）
// オプション3: Wavetableオシレーター（事前計算）
```

**理由**
FMシンセシスでは変調深度が大きいと高調波が多数発生し、ナイキスト周波数を超えやすいです。エイリアシングノイズを防ぐため帯域制限が望ましいです。

---

### 🔵 M2DXAudioUnit.swift:307-313 - パラメータ変更の非同期性

**問題**
implementorValueObserverでのパラメータ変更がメインスレッドから呼ばれる可能性がありますが、kernelへの変更がスレッドセーフかどうか不明確です。

**現在のコード**
```swift
_parameterTree.implementorValueObserver = { [weak self] param, value in
    self?.handleParameterChange(address: param.address, value: value)
}
```

**提案**
```swift
// ドキュメントでスレッド安全性を明記
// または、アトミック操作を保証:

private let parameterQueue = DispatchQueue(label: "com.m2dx.parameters")

_parameterTree.implementorValueObserver = { [weak self] param, value in
    // C++側がスレッドセーフならそのまま呼び出し可能
    // 不明な場合はキューで保護
    self?.handleParameterChange(address: param.address, value: value)
}
```

**理由**
AUv3のパラメータ変更はホストアプリの任意のスレッドから呼ばれる可能性があります。レンダースレッドとの競合状態を防ぐ必要があります。

---

### 🔵 M2DXAudioUnitViewController.swift:31-33 - configure呼び出しタイミングの不確実性

**問題**
configure(with:)がいつ呼ばれるか明示的でなく、viewDidLoad時点ではparameterTreeがnilの可能性があります。

**現在のコード**
```swift
// Line 31-33
DispatchQueue.main.async { [weak self] in
    self?.setupUI()
}
```

**提案**
```swift
// AUViewControllerの標準ライフサイクルを活用
public override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)

    if let audioUnit = audioUnit as? M2DXAudioUnit {
        configure(with: audioUnit)
    }
}
```

**理由**
AUViewControllerのaudioUnitプロパティは自動的に設定されます。viewDidAppearで確実にアクセスできます。

---

### 🔵 M2DXParameterTree.swift:636-668 - JSON Export機能の未使用

**問題**
exportAsJSON()メソッドが実装されていますが、実際のPE統合コードで使用されていません。また、MIDI2Kitとの統合が未実装です。

**提案**
```swift
// MIDI2Kit PEResource統合例
import MIDI2Kit

extension M2DXParameterTree {
    public static func createPEResource() -> PEResource {
        // PEResource生成ロジック
        // MIDI 2.0 UMP Property Exchange メッセージへの変換
    }
}
```

**理由**
Property Exchange階層は詳細に定義されていますが、実際のMIDI 2.0統合が欠落しています。将来の実装に備えて明確な統合ポイントを用意すべきです。

---

### 🔵 全体 - Swift 6 Concurrencyの完全対応

**問題**
Swift 6 strict concurrency modeを有効化している場合、いくつかの箇所でSendable適合やisolationの明示が必要になる可能性があります。

**確認箇所**
- M2DXAudioUnit.swift:77 - renderブロッククロージャのSendable性
- M2DXParameterTree.swift - 全てのenumとstructがSendable適合済み（✅良好）
- M2DXAudioUnitViewController.swift:67 - AUEditorViewのStateプロパティ

**提案**
```swift
// renderブロックを@Sendableクロージャとして明示
return { @Sendable actionFlags, timestamp, ... in
    // ...
} as AUInternalRenderBlock
```

**理由**
Swift 6 strict concurrency modeでは、並行コンテキスト間でのデータ共有に明示的なSendable適合が要求されます。将来のコンパイラバージョンでの警告・エラーを防ぐため、早期対応が望ましいです。

---

## 良かった点

### ✅ コード構造の明確性
- AUv3の標準構造（AudioUnit本体、ViewController、C++ DSP、Objective-C++ブリッジ）が適切に分離されている
- M2DX namespaceの使用でC++コードの衝突回避ができている

### ✅ DX7互換性への配慮
- エンベロープの4-stage DADR構造が正しく実装されている
- オペレーターのフィードバック、Ratio、Detuneパラメータが揃っている
- 16ボイスポリフォニーは十分な同時発音数

### ✅ SwiftUI統合
- UIHostingControllerを使用したモダンな統合
- オペレーターカラーリング（operatorColor）による視覚的識別
- レスポンシブなパラメータバインディング

### ✅ Property Exchange階層の詳細設計
- M2DXParameterTree.swiftが非常に詳細に定義されている
- 190パラメータの完全な階層構造
- Sendable適合でSwift 6対応

### ✅ メモリ管理
- C++ kernelをstd::unique_ptrで管理（M2DXKernelBridge.mm:6）
- [weak self]の適切な使用でretain cycleを回避

### ✅ リアルタイム処理への配慮
- レンダーブロック内でのallocation回避
- MIDIイベントハンドリングがリアルタイムセーフ

---

## 総評

M2DXプロジェクトは全体として**堅実な設計と実装**がなされています。AUv3の標準パターンに沿っており、Swift/C++の境界も適切に管理されています。

### 主要な改善推奨事項（優先度順）

1. **🔴 Critical修正（即座に対応）**
   - 8オペレーター初期化の不整合修正（M2DXKernelBridge.mm:16）
   - UI表記の6オペレーター・32アルゴリズムへの統一

2. **🟡 Warning対応（短期）**
   - 32アルゴリズム全実装の計画策定
   - フィードバック安定化（2サンプル平均）の検討
   - PE階層とAUParameterの対応整理

3. **🔵 Suggestion検討（中長期）**
   - ボイススティーリングアルゴリズム改善
   - パラメータツリーのグループ化
   - MIDI2Kit Property Exchange統合実装

### 次のステップ

1. Critical問題の修正後、実機ビルド・動作確認
2. GarageBand/Logic ProでのAUv3ホスト動作テスト
3. DX7 SysExインポート機能の実装検討
4. 残り28アルゴリズムの段階的実装
5. MIDI 2.0 Property Exchange統合の具体化

**総合評価**: コードベースは**プロダクション投入に向けた基盤として十分**ですが、DX7完全互換を目指すためにはアルゴリズム実装の完成が必須です。リアルタイム処理の安全性とパフォーマンスは概ね良好です。

---

レビュー担当: Claude Code
日付: 2026-02-06
ファイル数: 7
総行数: 約2,500行
