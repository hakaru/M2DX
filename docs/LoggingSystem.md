# ロギングシステム技術ドキュメント

## 概要

M2DX のロギングシステムは、`devicectl --console` の不安定性からの脱却を目的に全面改修されました。従来の `print()` ベースのログ出力を、Apple の統合ロギングフレームワーク `os.Logger` とアプリ内バッファ (`BufferMIDI2Logger`) の **二重出力アーキテクチャ** に置き換えています。

### 改修の動機

- `devicectl --console` が実機デバッグ中に頻繁に切断される
- `print()` はリリースビルドで意図しない出力になる
- MIDI-CI / PE の複雑なフロー解析に、構造化されたログが必要

### 改修後のメリット

- **macOS Console.app** でリアルタイムフィルタリング可能
- **アプリ内 UI** でログをコピー＆ペーストで共有可能
- カテゴリ別フィルタ（MIDI / PE / CI / Audio / PEBridge）
- リリースビルドでも `log collect` で事後収集可能

## アーキテクチャ

```
┌─────────────────────────────────────────────────────┐
│                   MIDIInputManager                   │
│                                                      │
│  ┌─────────────────────────────────────────────┐    │
│  │         CompositeMIDI2Logger                 │    │
│  │  ┌───────────────┐  ┌────────────────────┐  │    │
│  │  │OSLogMIDI2Logger│  │BufferMIDI2Logger   │  │    │
│  │  │(→ Console.app) │  │(→ アプリ内バッファ)│  │    │
│  │  └───────────────┘  └────────────────────┘  │    │
│  └─────────────────────────────────────────────┘    │
│         ↓ inject                                     │
│  ┌──────────┐  ┌──────────┐                         │
│  │CIManager │  │PEManager │                         │
│  └──────────┘  └──────────┘                         │
│                                                      │
│  appendDebugLog() ─→ os.Logger (カテゴリ別振り分け)  │
│                   ─→ debugLog[] / peFlowLog[]        │
└─────────────────────────────────────────────────────┘

┌──────────────────┐  ┌──────────────────┐
│M2DXAudioEngine   │  │M2DXPEBridge      │
│ audioLogger      │  │ bridgeLogger     │
│ (category:Audio) │  │ (category:PEBrdg)│
└──────────────────┘  └──────────────────┘
```

### Subsystem 統一

全 os.Logger インスタンスで共通の subsystem を使用:

```swift
private let logSubsystem = "com.example.M2DX"
```

### カテゴリ設計

| カテゴリ | Logger 変数 | 用途 |
|---------|------------|------|
| `MIDI` | `midiLogger` | MIDI メッセージ受信、UMP デコード |
| `PE` | `peLogger` | PE GET/Reply/Notify、Sniffer モード |
| `CI` | `ciLogger` | MIDI-CI Discovery、Cap Inquiry/Reply |
| `Audio` | `audioLogger` | オーディオエンジン起動/停止、エラー |
| `PEBridge` | `bridgeLogger` | AU ↔ PE 同期エラー |

## 変更ファイル一覧

### 1. MIDIInputManager.swift

**主な変更:**

- `BufferMIDI2Logger` クラス新規追加（アプリ内バッファ向けログ転送）
- `CompositeMIDI2Logger` 構築: `OSLogMIDI2Logger` + `BufferMIDI2Logger`
- `CIManager` / `PEManager` に `CompositeMIDI2Logger` を注入
- `appendDebugLog()` 内でプレフィックスに基づきカテゴリ別 os.Logger に振り分け:
  - `"PE"` → `peLogger.info()`
  - `"CI"` → `ciLogger.info()`
  - `"SNIFF"` → `peLogger.notice()`
  - その他 → `midiLogger.debug()`
- 全 `print()` を削除

### 2. M2DXAudioEngine.swift

**主な変更:**

- `audioLogger` (subsystem: `com.example.M2DX`, category: `Audio`) 追加
- `print()` → `audioLogger.error()` / `audioLogger.warning()` / `audioLogger.info()` に置換
- エラーメッセージ、設定変更通知、デバイス切替をログ出力

### 3. M2DXPEBridge.swift

**主な変更:**

- `bridgeLogger` (subsystem: `com.example.M2DX`, category: `PEBridge`) 追加
- AU ↔ PE 同期エラーを `bridgeLogger.error()` で出力
- `privacy: .public` でパス名を可視化（デバッグ時の利便性確保）

### 4. SettingsView.swift

**主な変更:**

- PE Sniffer モードの footer に Console.app の subsystem フィルタ情報を追加
- 「Copy Log」「Copy PE Log」ボタンでアプリ内バッファをクリップボードにコピー可能

## BufferMIDI2Logger 設計

```swift
final class BufferMIDI2Logger: MIDI2Core.MIDI2Logger, @unchecked Sendable {
    let minimumLevel: MIDI2Core.MIDI2LogLevel = .debug
    private let onLog: @Sendable (String) -> Void

    init(onLog: @escaping @Sendable (String) -> Void) {
        self.onLog = onLog
    }

    func log(
        level: MIDI2Core.MIDI2LogLevel,
        message: @autoclosure () -> String,
        category: String,
        file: String,
        function: String,
        line: Int
    ) {
        guard shouldLog(level) else { return }
        let text = "[\(category)] \(message())"
        onLog(text)
    }
}
```

### 設計ポイント

- **MIDI2Logger プロトコル準拠**: MIDI2Kit の CIManager / PEManager がロガーとして受け取れる
- **@unchecked Sendable**: `onLog` クロージャが `@Sendable` であるため実質的にスレッドセーフだが、プロトコル要件によりコンパイラが自動推論できないため明示
- **@MainActor コールバック経由**: `onLog` から `Task { @MainActor in ... }` で UI スレッドに転送し、`appendDebugLog()` 経由で `debugLog[]` に追加

### CompositeMIDI2Logger 構築

```swift
let bufferLogger = BufferMIDI2Logger { [weak self] line in
    Task { @MainActor in
        self?.appendDebugLog(line)
    }
}
let osLogger = OSLogMIDI2Logger(subsystem: logSubsystem, minimumLevel: .debug)
let logger = CompositeMIDI2Logger(loggers: [osLogger, bufferLogger])
```

- `OSLogMIDI2Logger`: MIDI2Kit 提供の os.Logger ラッパー → Console.app 出力
- `BufferMIDI2Logger`: 上記カスタム実装 → アプリ内 UI 出力
- `CompositeMIDI2Logger`: 両者を束ねて CIManager / PEManager に注入

## ログ取得方法

### 1. macOS Console.app（推奨）

リアルタイムでカテゴリ別フィルタリングが可能です。

1. Console.app を起動
2. 左ペインで接続中の iPhone を選択
3. 検索バーに以下を入力:
   - **全ログ**: `subsystem:com.example.M2DX`
   - **MIDI のみ**: `category:MIDI`
   - **PE のみ**: `category:PE`
   - **CI のみ**: `category:CI`
   - **Audio のみ**: `category:Audio`
4. 「Action」→「Include Info Messages」と「Include Debug Messages」を有効化

### 2. log stream コマンド（ターミナル）

```bash
# 全カテゴリ
log stream --predicate 'subsystem == "com.example.M2DX"' --level debug

# PE のみ
log stream --predicate 'subsystem == "com.example.M2DX" AND category == "PE"' --level debug

# CI + PE
log stream --predicate 'subsystem == "com.example.M2DX" AND (category == "PE" OR category == "CI")' --level debug
```

### 3. アプリ内 Copy Log / Copy PE Log

Settings → MIDI Debug セクション:

- **Copy Log**: `debugLog[]`（最新200件、全カテゴリ）をクリップボードにコピー
- **Copy PE Log**: `peFlowLog[]`（PE/CI 通信のみ、セッション中無制限）をクリップボードにコピー

### 4. log collect（事後収集）

```bash
# デバイスからログアーカイブを収集
sudo log collect --device --last 10m --output m2dx.logarchive

# アーカイブからフィルタ表示
log show m2dx.logarchive --predicate 'subsystem == "com.example.M2DX"' --level debug
```

## トラブルシューティング

### Console.app でログが見えない場合

1. **Info/Debug メッセージの表示を確認**: メニューバー「Action」→「Include Info Messages」と「Include Debug Messages」の両方にチェック
2. **正しいデバイスを選択**: 左ペインで iPhone デバイスを選択していること
3. **subsystem フィルタを確認**: `subsystem:com.example.M2DX` を正確に入力
4. **アプリが実行中であること**: バックグラウンドではログが停止する場合がある

### カテゴリフィルタの使い方

Console.app の検索バーで複数条件を組み合わせ可能:

- `subsystem:com.example.M2DX category:PE` — PE ログのみ
- `subsystem:com.example.M2DX PE-Resp` — PE Responder のログのみ（テキスト検索）
- `subsystem:com.example.M2DX Cap` — PE Capability 関連のログ

### privacy アノテーションについて

現在、開発段階のため全てのログで `privacy: .public` を使用しています。リリースビルドでは以下の見直しを推奨します:

- **MUID**: 内部識別子のため `.public` で問題なし
- **リソース名**: PE リソース名（DeviceInfo, ChannelList 等）は `.public` で問題なし
- **プログラム名**: ユーザーデータの場合は `.private` を検討
- **エラーメッセージ**: デバッグに必要なため `.public` を維持

```swift
// リリースビルドでの推奨
peLogger.info("PE-Notify: program=\(idx) name=\(name, privacy: .private)")
```

### ログレベルの使い分け

| レベル | 用途 | 例 |
|-------|------|-----|
| `debug` | 詳細なデバッグ情報 | MIDI メッセージ受信 |
| `info` | 通常のフロー情報 | PE GET/Reply、CI Discovery |
| `notice` | 注目すべきイベント | Sniffer モードのログ |
| `warning` | 警告 | Audio session deactivation 失敗 |
| `error` | エラー | Audio engine 起動失敗、PE 同期エラー |
