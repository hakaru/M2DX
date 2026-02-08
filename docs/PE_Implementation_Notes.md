# MIDI-CI Property Exchange 実装ノート

KORG KeyStage との PE (Property Exchange) 通信を実現するために得られた知見をまとめる。

---

## 1. アーキテクチャ概要

### M2DX の PE 役割

- **PE Responder**: M2DX がリソースを公開し、KeyStage が取得する
- **PE Initiator**: KeyStage が PE Initiator 専用（Responder 未実装）

KeyStage は PE Initiator としてのみ動作し、M2DX からの PE GET には一切応答しない。
全4 destination（CTRL, Session 1, DAW OUT, Bluetooth）に PE GET を送信して確認済み。
つまり M2DX → KeyStage 方向の PE GET は不可能。

### MUID 管理

- PEResponder / CIManager / PEManager は **同一 MUID (sharedMUID)** を使用
- MIDI-CI 仕様上は Initiator と Responder で別 MUID だが、
  KeyStage は Discovery Reply で学習した MUID 宛に PE GET を送信するため統一が必要
- **固定 MUID `0x0D170D8`** を使用（後述「MUID キャッシュ問題」参照）

### トランスポート

- `transport.received` (AsyncStream) は一度しか消費できない
- MIDIInputManager の receiveTask が消費し、CI SysEx は手動ディスパッチ:
  1. PEResponder.handleMessage(data)
  2. CIManager.handleReceivedExternal(received)
  3. PEManager.handleReceivedExternal(data)

---

## 2. PE SysEx メッセージフィールドオーダー（重要）

### 正しい順序（MIDI-CI PE 仕様 / KORG KeyStage 実装）

PE GET Reply (0x35), SET Reply (0x37), Subscribe Reply (0x39), Notify (0x3F):

```
F0 7E 7F 0D [subID2] [ciVersion]
[sourceMUID 4B] [destMUID 4B]
[requestID 1B]
[headerLength 2B (14-bit LE)]
[headerData (headerLength bytes)]     ← headerLength の直後！
[numChunks 2B (14-bit LE)]
[thisChunk 2B (14-bit LE)]
[dataLength 2B (14-bit LE)]
[propertyData (dataLength bytes)]
F7
```

PE SET Inquiry (0x36) も同じ順序。

PE GET Inquiry (0x34) と Subscribe Inquiry (0x38) にはチャンクフィールドなし:

```
[requestID 1B]
[headerLength 2B]
[headerData (headerLength bytes)]
```

### よくある間違い（修正前のバグ）

headerData を numChunks/thisChunk/dataLength の**後**に配置してしまう:

```
❌ 誤: requestID → headerLength → numChunks → thisChunk → dataLength → headerData → propertyData
✅ 正: requestID → headerLength → headerData → numChunks → thisChunk → dataLength → propertyData
```

この間違いがあると、KORG は ResourceList を受信できても DeviceInfo 以降の GET に進まない。

### 修正対象ファイル (MIDI2Kit)

| ファイル | 関数 | 役割 |
|---------|------|------|
| `CIMessageBuilder+Reply.swift` | `peGetReply`, `peSetReply`, `peSubscribeReply`, `peNotify` | 送信（ビルダー） |
| `CIMessageBuilder.swift` | `peSetInquiry` | 送信（ビルダー） |
| `CIMessageParser.swift` | `parsePEReplyCI12` | 受信（パーサー） |
| `CIMessageParser+Inquiry.swift` | `parsePESetInquiry` | 受信（パーサー） |

---

## 3. KORG KeyStage PE 通信フロー

### 完全な PE フロー（2026-02-07 実機ログで確認済み）

```
KeyStage (0x602AA21)              M2DX (0x0D170D8)
   |                                |
   |-- Discovery Inquiry (0x70) --> |
   |<-- Discovery Reply (0x71) ---- |
   |                                |
   |-- PE Cap Inquiry (0x30) -----> |
   |<-- PE Cap Reply (0x31) ------- |
   |                                |
   |-- GET ResourceList (0x34) ---> |
   |<-- Reply (0x35) -------------- |  247B body, hdr={"status":200,"totalCount":6}
   |                                |
   |-- GET DeviceInfo (0x34) -----> |
   |<-- Reply (0x35) -------------- |  147B body, hdr={"status":200}
   |                                |
   |-- GET ChannelList (0x34) ----> |
   |<-- Reply (0x35) -------------- |  63B body, hdr={"status":200,"totalCount":1}
   |                                |
   |-- Subscribe ChannelList (0x38) |
   |<-- Subscribe Reply (0x39) ---- |  subscribeId=sub-1
   |                                |
   |-- GET ProgramList (0x34) ----> |  offset=0, limit=128
   |<-- Reply (0x35) -------------- |  381B body, hdr={"status":200,"totalCount":10}
   |                                |
   |-- Subscribe ProgramList (0x38) |
   |<-- Subscribe Reply (0x39) ---- |  subscribeId=sub-2
   |                                |
   |-- GET X-ParameterList (0x34) > |
   |<-- Reply (0x35) -------------- |  307B body, hdr={"status":200,"totalCount":5}
   |                                |
   |-- Subscribe X-ParameterList -> |
   |<-- Subscribe Reply (0x39) ---- |  subscribeId=sub-3
   |                                |
   |-- GET X-ProgramEdit (0x34) --> |
   |<-- Reply (0x35) -------------- |  60B body, hdr={"status":200}
   |                                |
   |-- Subscribe X-ProgramEdit ---> |
   |<-- Subscribe Reply (0x39) ---- |  subscribeId=sub-4
   |                                |
   |-- GET JSONSchema (0x34) -----> |  resId=""
   |<-- Reply (0x35) -------------- |  2B body (empty {})
   |                                |
   |-- GET JSONSchema (0x34) -----> |  resId="" (2回目)
   |<-- Reply (0x35) -------------- |  2B body (empty {})
   |                                |
   |   ★ Program Change 送信時:     |
   |<-- Notify ChannelList (0x3F) - |  programTitle更新
   |<-- Notify X-ProgramEdit (0x3F) |  name/bankPC更新
   |                                |
```

### ★ 重要: totalCount が PE フロー完走の必須条件

**根本原因の発見経緯 (2026-02-07)**

X-ParameterList GET Reply 後に KORG が PE フローを中止する問題を調査した。

#### 症状

PEフローが以下の位置で毎回停止:
```
ResourceList → DeviceInfo → ChannelList → Subscribe(ChannelList) →
ProgramList → Subscribe(ProgramList) → X-ParameterList → ★STOP
```
X-ParameterList GET Reply を正常送信後、Subscribe(X-ParameterList) が来ず、
X-ProgramEdit GET も来ない。

#### 調査手順

1. **PEResponder に logCallback 追加** — レスポンスボディとヘッダーの内容を外部ログに出力
2. **固定 MUID 導入** — `MUID.random()` → `MUID(rawValue: 0x0D170D7)!` でキャッシュ安定化
3. **X-ParameterList 応答ボディ確認**:
   ```json
   [{"controlcc":1,"name":"Mod Wheel","min":0,"max":127},
    {"controlcc":7,"name":"Volume","min":0,"max":127,"default":100},
    {"controlcc":11,"name":"Expression","min":0,"max":127,"default":127},
    {"controlcc":64,"name":"Sustain","min":0,"max":127},
    {"controlcc":74,"name":"Brightness","min":0,"max":127,"default":64}]
   ```
   307B body, 345B reply — broadcast 成功確認済み
4. **仮説: ボディフォーマットの問題** → 空配列 `[]` + totalCount ヘッダーでテスト
5. **結果: 空配列 `[]` + `{"status":200,"totalCount":0}` で全フロー完走**
6. **確認: 実データ 5パラメータ + `{"status":200,"totalCount":5}` でも全フロー完走**

#### 根本原因

**レスポンスヘッダーに `totalCount` フィールドが無かった。**

| リソース | 修正前ヘッダー | 修正後ヘッダー | 結果 |
|---------|---------------|---------------|------|
| ResourceList | `{"status":200}` | `{"status":200,"totalCount":6}` | 動作変化なし（最初に取得されるため） |
| ChannelList | `{"status":200}` | `{"status":200,"totalCount":1}` | Subscribe が安定 |
| ProgramList | `{"status":200,"totalCount":10}` | 変更なし | 元々OK |
| **X-ParameterList** | **`{"status":200}`** | **`{"status":200,"totalCount":5}`** | **★これが原因** |
| X-ProgramEdit | `{"status":200}` | 変更なし | 単一オブジェクト（配列ではない） |

KORG KeyStage は**配列を返すリソースの GET Reply ヘッダーに `totalCount` を必須**として扱っている。
`totalCount` が無い場合、そのリソース以降の PE フローを中止する。

MIDI-CI PE 仕様（M2-103-UM v1.1）では `totalCount` はオプション扱いだが、
KORG の実装は必須として動作している。

#### 教訓

- MIDI-CI PE のレスポンスヘッダーは、仕様上オプションのフィールドでも実装では必須の場合がある
- **配列（リスト）を返す全リソースに `totalCount` を付けるべき**
- KORG は `totalCount` を用いてリストの全体サイズを把握し、ページネーション判断を行っている可能性

---

## 4. MUID キャッシュ問題と解決策

### 問題

KORG KeyStage は Discovery Reply で学習した MUID をキャッシュする。
`MUID.random()` で毎回異なる MUID を使うと:

1. 前回の MUID がキャッシュに残る
2. KeyStage が古い MUID 宛に Cap Inquiry を送信
3. M2DX の新しい MUID では受信できない
4. PE フローが開始されない

### 解決策: 固定 MUID

```swift
let sharedMUID = MUID(rawValue: 0x0D170D8)!  // Fixed MUID for KORG cache stability
```

- 毎回同じ MUID を使用するため、キャッシュ済みでも直接 Cap Inquiry → PE GET が来る
- MIDI-CI 仕様上、MUID は一意であるべきだが、単一デバイスなら問題ない

### 解決策: Invalidate MUID 送信

```swift
// stop() 内
if let ci = ciManager, let transport {
    Task { await ci.invalidateMUID() }
}
```

- アプリ終了時に Invalidate MUID (0x7E) をブロードキャスト
- KORG がキャッシュから削除し、次回 Discovery からやり直す
- **注意**: signal 15 (kill) で終了した場合は stop() が呼ばれないため、
  固定 MUID との併用が確実

### 以前のアプローチ: Manual Cap Reply（廃止）

以前は「キャッシュ MUID 宛の Cap Inquiry に手動で Cap Reply を返す」アプローチを使用していた。

```swift
// ❌ 廃止されたコード
if !isKnownDevice {
    acceptedOldMUIDs.insert(parsed.destinationMUID)
    let reply = CIMessageBuilder.peCapabilityReply(...)
    try? await midi.broadcast(reply)
}
```

**問題点**:
1. `0x01C1FD1`（KeyStage 内部エンティティ）を「キャッシュ MUID」と誤判定
2. 誤判定した MUID の PE GET に応答してしまい、本来の KORG メイン MUID のフローが進まない
3. MUID rewrite ロジックが複雑化し、バグの温床になる

**現在のアプローチ**: キャッシュ MUID 宛の Cap Inquiry は無視（ignored）し、
KORG が直接新 MUID に Cap Inquiry を送るのを待つ。固定 MUID なら毎回同じなので問題なし。

### KORG Discovery タイミング

- KORG KeyStage は**電源起動時**に Discovery Inquiry を送信
- M2DX からの Discovery Inquiry に対して Discovery Reply を返す
- ただし**アプリ再起動のみ**では KORG は再 Discovery しないことがある
- **テストで確実に動作させるには KeyStage の電源再起動が必要**

---

## 5. MUID(0x01C1FD1) について

- KeyStage 内部の別ファンクションブロック（Mac の Audio MIDI Setup 由来の可能性）
- 毎回同じ MUID `0x01C1FD1` で出現
- KORG メイン MUID（毎回変わる: 0xE189663, 0x89646D8, 0xFF44576, 0x602AA21 等）とは別
- M2DX の PE 動作対象外 — `MUID mismatch` で正しく無視する

---

## 6. JSON フォーマット仕様

### ResourceList

```json
[
  {"resource":"DeviceInfo"},
  {"resource":"ChannelList","canSubscribe":true},
  {"resource":"ProgramList","canSubscribe":true},
  {"resource":"JSONSchema"},
  {"resource":"X-ParameterList","canSubscribe":true},
  {"resource":"X-ProgramEdit","canSubscribe":true}
]
```

- `canSubscribe:true` は ChannelList, ProgramList, X-ParameterList, X-ProgramEdit に必須
- DeviceInfo, JSONSchema には不要
- **注意**: `schema` 参照を追加するとKORGの動作が不安定になった → 削除した

**レスポンスヘッダー**: `{"status":200,"totalCount":6}`

### DeviceInfo

```json
{
  "manufacturerName": "KORG",
  "productName": "M2DX DX7 Synthesizer",
  "softwareVersion": "1.0",
  "familyName": "FM Synthesizer",
  "modelName": "DX7 Compatible"
}
```

- **manufacturerName を "KORG" にする**: KeyStage は manufacturerName で KORG 製品を判定し、
  KORG 独自リソース（X-ParameterList, X-ProgramEdit）の取得を決定する

**レスポンスヘッダー**: `{"status":200}` （単一オブジェクトなので totalCount 不要）

### ChannelList

```json
[
  {
    "channel": 1,
    "title": "Channel 1",
    "programTitle": "INIT VOICE"
  }
]
```

- `channel` は **1-based**（KORG 仕様: `{"title":"Keystage","channel":1}`）
- `programTitle` で現在のプログラム名を表示
- **0-based (channel:0) にするとKORGがSubscribeを送らなくなる** — 1-basedが必須

**レスポンスヘッダー**: `{"status":200,"totalCount":1}`

### ProgramList

```json
[
  {"title": "INIT VOICE", "bankPC": [0, 0, 0]},
  {"title": "E.PIANO 1", "bankPC": [0, 0, 1]},
  {"title": "BASS 1", "bankPC": [0, 0, 2]}
]
```

- **`title`** を使う（`name` ではない）
- **`bankPC`** は **配列 `[MSB, LSB, Program]`** 形式
  - `bankPC: 0, bankCC: 0, program: 0` のような個別フィールドは KORG が認識しない

**レスポンスヘッダー**: `{"status":200,"totalCount":10}` ← ★totalCount 必須

### X-ParameterList（KORG 独自リソース）

**KORG公式仕様 (Keystage_PE_ResourceList v1.0 2023/8/31):**

```json
[
  {"name": "Perf Master Mod", "controlcc": 24, "default": 0},
  {"name": "Perf Timing Mod", "controlcc": 25, "default": 0},
  {"name": "Perf Sample Mod", "controlcc": 26, "default": 0}
]
```

**M2DX実装:**

```json
[
  {"name": "Mod Wheel", "controlcc": 1, "default": 64},
  {"name": "Volume", "controlcc": 7, "default": 100},
  {"name": "Expression", "controlcc": 11, "default": 127},
  {"name": "Sustain", "controlcc": 64, "default": 0},
  {"name": "Brightness", "controlcc": 74, "default": 64}
]
```

- CC パラメータの名前とデフォルト値をKeyStageに通知
- `name`: パラメータ表示名
- `controlcc`: MIDI CC 番号
- `default`: デフォルト値（オプション）
- **注意**: `min`/`max` フィールドはKORG公式仕様に存在しない（削除済み）

**レスポンスヘッダー**: `{"status":200,"totalCount":5}` ← ★totalCount 必須

**JSONSchema (parameterListSchema):**
```json
{
  "type": "array",
  "items": {
    "type": "object",
    "properties": {
      "name": {"title": "Parameter Name", "type": "string"},
      "controlcc": {"title": "Control CC", "type": "integer", "minimum": 0, "maximum": 127},
      "default": {"title": "Default Value", "type": "integer", "minimum": 0, "maximum": 127}
    }
  }
}
```

### X-ProgramEdit（KORG 独自リソース）

**★ KORG公式仕様 (Keystage_PE_ResourceList v1.0 2023/8/31) — currentValues形式必須:**

```json
{
  "currentValues": [
    {"name": "Perf Master Mod", "value": 0, "displayValue": "0.0", "displayUnit": "%"},
    {"name": "Perf Timing Mod", "value": 0, "displayValue": "0.0", "displayUnit": "%"},
    {"name": "Perf Sample Mod", "value": 64, "displayValue": "50.0", "displayUnit": "%"}
  ]
}
```

**M2DX実装（name フィールド追加でプログラム名表示対応）:**

```json
{
  "name": "INIT VOICE",
  "currentValues": [
    {"name": "Mod Wheel", "value": 64, "displayValue": "64", "displayUnit": ""},
    {"name": "Volume", "value": 100, "displayValue": "100", "displayUnit": ""},
    {"name": "Expression", "value": 127, "displayValue": "127", "displayUnit": ""},
    {"name": "Sustain", "value": 0, "displayValue": "0", "displayUnit": ""},
    {"name": "Brightness", "value": 64, "displayValue": "64", "displayUnit": ""}
  ]
}
```

- **`currentValues` フィールドが必須** — KeyStageはこのフィールドをパースし、存在しないとハングする
- `name`: プログラム名（KeyStage LCD に表示される）
- `currentValues[].name`: パラメータ名
- `currentValues[].value`: 現在のCC値 (0-127)
- `currentValues[].displayValue`: UI表示用の値文字列
- `currentValues[].displayUnit`: 単位テキスト（"%", "ms" 等）
- Program Change 受信時に Subscription Notify で更新を通知

**★★★ ハング根本原因 (2026-02-08):**
以前のM2DX実装は KORG Module Pro 形式 `{"name":"...","category":"...","bankPC":[...]}` を使用していたが、
KeyStageは `currentValues` フィールドを必須としてパースするため、フィールド不在でハングしていた。

**レスポンスヘッダー**: `{"status":200}` （単一オブジェクトなので totalCount 不要）

**JSONSchema (programEditSchema):**
```json
{
  "type": "object",
  "properties": {
    "currentValues": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "name": {"title": "Parameter Name", "type": "string"},
          "value": {"title": "Current Value", "type": "integer", "minimum": 0, "maximum": 127},
          "displayValue": {"title": "Display Value", "type": "string"},
          "displayUnit": {"title": "Display Unit", "type": "string"}
        }
      }
    }
  }
}
```

### JSONSchema

```json
{}
```

- KORG は `resId=""` で 2 回 GET する（parameterListSchema, programEditSchema を要求）
- 現在は空オブジェクト `{}` を返している（resId パース調査中）

**レスポンスヘッダー**: `{"status":200}`

### ★ レスポンスヘッダー まとめ

| リソース | ヘッダー | totalCount |
|---------|---------|-----------|
| ResourceList | `{"status":200,"totalCount":6}` | **必須** |
| DeviceInfo | `{"status":200}` | 不要 |
| ChannelList | `{"status":200,"totalCount":1}` | **必須** |
| ProgramList | `{"status":200,"totalCount":10}` | **必須** |
| X-ParameterList | `{"status":200,"totalCount":5}` | **必須** |
| X-ProgramEdit | `{"status":200}` | 不要 |
| JSONSchema | `{"status":200}` | 不要 |

**ルール: 配列（リスト）を返すリソースには `totalCount` が必須。**

### Subscribe レスポンスヘッダー

```json
{"status": 200, "subscribeId": "sub-1"}
```

- subscribeId はサーバーが生成（M2DXでは "sub-N" 形式）

---

## 7. PE Reply Hex 解析例

### X-ParameterList Reply (360B) — 完全ダンプ解析

```
F0                    SysEx Start
7E 7F                 Universal Non-Realtime, device 7F
0D                    CI Sub-ID#1
35                    PE GET Reply (Sub-ID#2)
01                    CI version 1.1
58 61 45 06           source MUID = 0x0D170D8 (4×7bit)
21 54 0A 30           dest MUID = 0x602AA21 (4×7bit)
00                    requestID = 0
1D 00                 headerLength = 29 (14-bit LE)
7B 22 73 74 ...7D    headerData = {"status":200,"totalCount":5} (29B)
01 00                 numChunks = 1
01 00                 thisChunk = 1
33 02                 dataLength = 307 (14-bit LE: (2<<7)|51)
5B 7B 22 63 ...5D    propertyData = JSON配列 (307B)
F7                    SysEx End
```

### 14-bit LE エンコーディング

```
dataLength: 307
  low byte  = 307 & 0x7F = 51 = 0x33
  high byte = 307 >> 7   = 2  = 0x02
  → バイト列: 33 02
```

---

## 8. MIDI-CI バージョンと互換性

| 項目 | 値 |
|------|-----|
| CI Version | 0x01 (v1.1) — KORG Module Pro / KeyStage 互換 |
| PE Version | Major=0, Minor=2 |
| numSimultaneousRequests | 4 |
| Mcoded7 | **不使用** — plain UTF-8 |
| Max SysEx Size | 0 (unlimited) |

### KORG KeyStage デバイス情報

| 項目 | 値 |
|------|-----|
| Manufacturer ID | 42 00 00 (KORG) |
| Family ID | 69 01 (= 361) |
| Model ID | 01 00 (49key) / 09 00 (61key, = 9) |
| Category Support | bit3 (Property Exchange Supported) |

### KORG KeyStage ファームウェア履歴

| バージョン | PE関連の変更 |
|-----------|-------------|
| v1.0.3 | Screen Display, Property Exchange, Key Calibration 初期対応 |
| v1.0.4 | wavestate / opsix モジュールへのPE拡張 |
| v1.0.5 | wavestate/modwave表示同期修正, USB切断時のMIDI DIN PE修正 |
| v1.0.6 | **KORG Module PE互換追加**, Subscription パラメータ数修正, ch16表示修正 |
| v1.0.7 | 20分オートパワーオフ追加 |

---

## 9. UMP SysEx 7-bit (Type 0x3) の処理

### CoreMIDI Transport

MIDI 2.0 プロトコルモードでは CI SysEx は UMP type 0x3 として届く:

```
Word 0: [mt=0x3][group][status][numBytes] [data0][data1][data2][data3]
Word 1: [data4][data5][pad][pad]
```

- `status`: 0=Complete, 1=Start, 2=Continue, 3=End
- `numBytes`: ペイロードバイト数 (0-6)
- フラグメントを `umpSysExBuffer` で蓄積し、Complete/End で emit

### 重要: バッファはインスタンス変数

`umpSysExBuffer` は CoreMIDITransport の**インスタンス変数**として保持。
ローカル変数にすると、CoreMIDI コールバック間でフラグメントが消失する。
（PE GET Reply等の長いSysExは複数コールバックにまたがる）

### 送信方法

PEResponder は `broadcast()` (MIDISend + MIDIPacketList, MIDI 1.0 API) を使用。
UMP SysEx7 送信 (`sendSysEx7AsUMP`) も実装済みだが、broadcast が確実に動作する。

---

## 10. PE Responder 実装 (MIDIInputManager)

### リソース登録

```swift
// registerPEResources() 内
await responder.registerResource("ResourceList", resource: ComputedResource(
    get: { _ in Data("[...]".utf8) },
    responseHeader: { _, _ in Data("{\"status\":200,\"totalCount\":6}".utf8) }
))
await responder.registerResource("DeviceInfo", resource: StaticResource(json: "..."))
await responder.registerResource("ChannelList", resource: ComputedResource(
    supportsSubscription: true,
    get: { ... },
    responseHeader: { _, _ in Data("{\"status\":200,\"totalCount\":1}".utf8) }
))
await responder.registerResource("ProgramList", resource: ComputedResource(
    supportsSubscription: true,
    get: { ... },
    responseHeader: { _, _ in Data("{\"status\":200,\"totalCount\":N}".utf8) }
))
await responder.registerResource("X-ParameterList", resource: ComputedResource(
    supportsSubscription: true,
    get: { ... },
    responseHeader: { _, bodyData in
        let count = (try? JSONSerialization.jsonObject(with: bodyData) as? [Any])?.count ?? 0
        return Data("{\"status\":200,\"totalCount\":\(count)}".utf8)
    }
))
await responder.registerResource("X-ProgramEdit", resource: ComputedResource(
    supportsSubscription: true,
    get: { ... }  // デフォルト {"status":200} ヘッダー
))
await responder.registerResource("JSONSchema", resource: ComputedResource(
    get: { ... }  // resId に応じたスキーマ返却
))
```

- **配列リソースには必ず `responseHeader` で `totalCount` を返す**
- `supportsSubscription: true` が必須（ResourceListの`canSubscribe`と一致させる）

### PE Notify（Program Change 連動）

```swift
func notifyChannelListUpdate(programIndex: UInt8) {
    guard let responder = peResponder else { return }
    let name = DX7FactoryPresets.all[Int(programIndex)].name
    let json = "[{\"channel\":1,\"title\":\"Channel 1\",\"programTitle\":\"\(name)\"}]"
    Task { await responder.notify(resource: "ChannelList", data: Data(json.utf8)) }
}
```

- Program Change受信時にPEResponder.notify()でSubscriberに通知
- ChannelList と X-ProgramEdit の両方を更新

### PEResponderResource プロトコル

```swift
protocol PEResponderResource {
    func get(header:) async throws -> Data
    func set(header:body:) async throws -> Data
    var supportsSubscription: Bool { get }
    func responseHeader(for header: PERequestHeader, bodyData: Data) -> Data
}
```

- デフォルト `responseHeader` は `{"status":200}`
- **配列リソースでは必ず `responseHeader` をオーバーライドして `totalCount` を返す**

---

## 11. デバッグ手法

### コンソールログキャプチャ

```bash
xcrun devicectl device process launch \
  --device <DEVICE_ID> \
  --terminate-existing \
  --console com.example.M2DX > /tmp/output.log 2>&1 &
BGPID=$!
sleep 90
kill $BGPID
```

- `print()` (stdout) を使用 — **`os.Logger` は `--console` に表示されない**
- `--terminate-existing` で既存プロセスを終了してから起動
- 90秒以上のキャプチャが推奨（PEフロー全体 + Program Change テスト）

### ログ出力の仕組み

- `appendDebugLog()` — UI（debugLog配列）と peFlowLog に記録
- PE/CI プレフィックスの行は自動的に `print("[M2DX] \(line)")` でコンソール出力
- PEResponder 内部のログは直接 `print()` で出力
- PEResponder の `logCallback` でレスポンス詳細を外部に通知

### テスト手順（確実にPEフローを通す方法）

1. M2DXアプリをビルド・インストール
2. **KeyStage の電源を再起動**（KORG は起動時のみ Discovery を送信）
3. `devicectl --terminate-existing --console` でM2DXを起動
4. 90秒以上ログキャプチャ
5. ログに以下が含まれることを確認:
   - `PE-RX sub=0x30` (Cap Inquiry)
   - `PE-Resp: replied GET ResourceList`
   - `PE-Resp: replied GET X-ProgramEdit`
   - `PE-Resp: handled Sub X-ProgramEdit cmd=start`

---

## 12. 解決済み問題の時系列

### Phase 1: PE SysEx フィールドオーダー (2026-02-06)
- **問題**: KORG が ResourceList 以降の GET に進まない
- **原因**: headerData と chunks の順序が逆
- **解決**: MIDI-CI PE 仕様通りの順序に修正

### Phase 2: ProgramList JSON フォーマット (2026-02-06)
- **問題**: ProgramList を受信するが名前が表示されない
- **原因**: `name` → `title`, `bankPC` → 配列形式に修正
- **解決**: KORG Module Pro と同じフォーマットに合わせた

### Phase 3: ChannelList Subscribe (2026-02-06)
- **問題**: ChannelList 後に Subscribe が来ない
- **原因**: `channel:0` (0-based) → `channel:1` (1-based) に修正
- **解決**: KORG 仕様通り 1-based に統一

### Phase 4: MUID キャッシュ問題 (2026-02-07)
- **問題**: アプリ再起動後に PE フローが開始されない
- **原因**: KORG がキャッシュした古い MUID に Cap Inquiry を送るが、新 MUID では受信できない
- **解決**: 固定 MUID + stop() での Invalidate MUID 送信

### Phase 5: ★ totalCount ヘッダー (2026-02-07) — 最大のブレイクスルー
- **問題**: X-ParameterList GET Reply 後に KORG が PE フローを中止
- **原因**: 配列リソースのレスポンスヘッダーに `totalCount` が無い
- **解決**: 全配列リソースに `totalCount` 付きヘッダーを追加
- **結果**: 全 PE フロー完走 + Subscription Notify 動作確認

### Phase 6: Manual Cap Reply 廃止 (2026-02-07)
- **問題**: `0x01C1FD1` を「キャッシュ MUID」と誤判定して応答
- **原因**: Manual Cap Reply ロジックが他デバイスの MUID も受け入れていた
- **解決**: Manual Cap Reply を完全廃止、KORG が直接新 MUID に接続するのを待つ

### Phase 7: ★★★ X-ProgramEdit currentValues 形式（KeyStageハング解決）(2026-02-08)
- **問題**: X-ProgramEdit GET Reply 後に KeyStage の LCD 固着・ノブ無反応（完全ハング）
- **原因**: M2DXが KORG Module Pro 形式 `{"name":"...","category":"...","bankPC":[...]}` で応答していたが、
  KeyStage は `currentValues` フィールドを必須として期待 `{"currentValues":[{"name":"...","value":N,"displayValue":"...","displayUnit":"..."}]}`
- **切り分け手順**: PE完全無効(Step 0) → CIManager(Step 1) → PEResponder(Step 2) → Discovery(Step 2.5) → フルPE(Step 3) → リソース段階追加 → X-ProgramEdit特定
- **解決**: KORG公式仕様 (Keystage_PE_ResourceList v1.0) に準拠し currentValues 形式に修正
- **副次発見**:
  - manufacturerName="KORG" でないとKeyStageはX-ProgramEditをGETしない
  - X-ParameterList の min/max フィールドはKORG仕様に存在しない（削除）
  - macOS版で log stream リアルタイムデバッグ環境を確立

---

## 13. 現状（2026-02-08 05:36 時点）

### 動作確認済み

- [x] PE SysExフィールドオーダー修正
- [x] ProgramList JSONフォーマット修正（title + bankPC配列）
- [x] ChannelList Subscribe成功（1-based channel）
- [x] ProgramList GET Reply成功（totalCount付きヘッダー）
- [x] ★ **全リソース totalCount ヘッダー追加**
- [x] ★ **X-ParameterList 5パラメータ応答成功（min/max削除、KORG公式仕様準拠）**
- [x] ★ **X-ProgramEdit currentValues形式で応答成功（ハング解決）**
- [x] ★ **全 Subscribe 成功（sub-1 ~ sub-4）**
- [x] ★ **PE Notify 動作確認（Program Change → ChannelList + X-ProgramEdit 通知）**
- [x] 固定 MUID でキャッシュ問題解消
- [x] Manual Cap Reply 廃止
- [x] stop() で Invalidate MUID 送信
- [x] ★★★ **KeyStageハング根本原因特定・解決（X-ProgramEdit currentValues形式）**
- [x] macOS版 log stream によるリアルタイムデバッグ環境確立
- [x] PE Notify 再有効化（50msデバウンス + currentValues形式）

### 確認待ち / 調査中

- [ ] JSONSchema resId パース問題（parameterListSchema/programEditSchema が {} を返す）
- [ ] KeyStage LCD にプログラム名が表示されるか（目視確認）
- [ ] デバッグ print 文のクリーンアップ
- [ ] コミット

---

## 14. 参考資料

### KORG公式仕様（~/Downloads/ に保存済み）

| ファイル | バージョン | 内容 |
|---------|-----------|------|
| `Keystage_PE_ResourceList.txt` | v1.0 2023/8/31 | PE Resource List仕様（送信/受信リソース定義、JSONスキーマ） |
| `Keystage_PE_ResourceList 2.txt` | v1.0 2023/8/31 | 同上（重複コピー） |
| `Keystage_PE_MIDIimp.txt` | v1.00 2023.8.31 | PE MIDI Implementation（SysExバイト構造、全PEメッセージ定義） |
| `Keystage_MIDIimp.txt` | v1.00 2023.8.31 | フルMIDI Implementation（Channel/SysEx/NativeMode/ParameterChange） |

### KeyStage PE仕様の要点

- **送信(TRANSMITTED)**: ResourceList, DeviceInfo, ChannelList のみ
- **受信(RECOGNIZED RECEIVE)**: X-ParameterList, X-ProgramEdit（カスタムリソース）
- **modelId**: [1,0]=Keystage-49, [9,0]=Keystage-61
- **ChannelList Subscribe**: Global MIDI Ch変更時に通知

### その他の参考資料

- KORG Module Pro PE 調査: `SimpleMidiController/Docs/KORG_PropertyExchange_Investigation.md`
- KORG KeyStage System Updater: https://www.korg.com/us/support/download/software/0/927/5079/
- MIDI-CI PE Common Rules: [M2-103-UM (AMEI)](https://amei.or.jp/midistandardcommittee/MIDI2.0/MIDI2.0-DOCS/M2-103-UM_v1-1_Common_Rules_for_MIDI-CI_Property_Exchange.pdf)
- MIDI-CI PE Foundational Resources: [M2-105-UM (AMEI)](https://amei.or.jp/midistandardcommittee/MIDI2.0/MIDI2.0-DOCS/M2-105-UM_v1-1-1_Property_Exchange_Foundational_Resources.pdf)

---

## 15. PE Notify sub-ID2 修正（0x3F → 0x38）— KeyStage LCD表示問題の最終解決 (2026-02-08)

### 問題の経緯

X-ProgramEdit currentValues 形式への修正（Phase 7）により KeyStage ハングは解決したが、
**PE Notify によるプログラム名更新がKeyStage LCDに反映されない**問題が残っていた。

### 症状

- Program Change 受信時に M2DX が PE Notify (0x3F) を送信
- KeyStage は Notify を受信するが、**LCD にプログラム名が表示されない**
- KeyStage が **部分的にハング**（Program Change 無反応、Note On は可能）
- KeyStage 再起動で復旧

### 根本原因の発見

**MIDI-CI Property Exchange v1.1 仕様の Notify 方式の違い**

MIDI-CI PE v1.1 では、Subscription Notify に 2 つの方式が存在:

1. **0x3F (PE Notify)** — CI v1.2 で導入された専用 Notify メッセージ
2. **0x38 (Subscribe) + command:notify ヘッダー** — CI v1.1 互換の Notify 方式

**KORG KeyStage は CI v1.1 準拠デバイスであり、0x3F (PE Notify) に未対応。**
0x3F を受信すると「未知のメッセージ」として処理し、部分的にハングする。

### 修正内容（MIDI2Kit）

#### 1. CIMessageBuilder+Reply.swift

**変更前（0x3F 使用）:**
```swift
public static func peNotify(
    ciVersion: UInt8 = 0x01,
    sourceMUID: MUID,
    destinationMUID: MUID,
    requestID: UInt8,
    subscribeId: String,
    header: Data,
    data: Data
) -> Data {
    var msg = Data()
    msg.append(0xF0)
    msg.append(0x7E)
    msg.append(0x7F)
    msg.append(0x0D)
    msg.append(0x3F)  // PE Notify (CI v1.2)
    ...
```

**変更後（0x38 + command:notify）:**
```swift
public static func peNotify(
    ciVersion: UInt8 = 0x01,
    sourceMUID: MUID,
    destinationMUID: MUID,
    requestID: UInt8,
    subscribeId: String,
    header: Data,
    data: Data
) -> Data {
    var msg = Data()
    msg.append(0xF0)
    msg.append(0x7E)
    msg.append(0x7F)
    msg.append(0x0D)
    msg.append(0x38)  // Subscribe (CI v1.1 compatible)
    ...
    // ヘッダーに command:notify を追加
    let notifyHeader = "{\"command\":\"notify\",\"subscribeId\":\"\(subscribeId)\"}"
    let headerData = Data(notifyHeader.utf8)
    ...
```

**詳細:**
- sub-ID2 を 0x3F → 0x38 に変更
- ヘッダーに `{"command":"notify","subscribeId":"sub-N"}` を含める
- これにより KeyStage は「Subscribe メッセージの Notify コマンド」として認識

#### 2. PEResponder.swift

**excludeMUIDs 追加（macOS entity 除外）:**
```swift
actor PEResponder {
    // ...
    private var excludeMUIDs: Set<UInt32> = []  // macOS entities to exclude
    
    func notify(resource: String, data: Data) async {
        guard let sub = subscriptions[resource] else { return }
        let subscribers = sub.subscribers.filter { !excludeMUIDs.contains($0.key) }
        for (muid, subscribeId) in subscribers {
            // Send PE Notify (0x38)
            ...
        }
    }
    
    private func subscriberMUIDs() -> [UInt32] {
        var muids: [UInt32] = []
        for (_, sub) in subscriptions {
            muids.append(contentsOf: sub.subscribers.keys.filter { !excludeMUIDs.contains($0) })
        }
        return muids
    }
}
```

**目的:**
- macOS 環境では、M2DX 自身が discoveredPEDevices に含まれることがある
- excludeMUIDs で M2DX 自身の MUID を除外し、KeyStage にのみ Notify を送信
- 自己ループによる無限 Notify 防止

#### 3. MIDIInputManager.swift

**macOS entity 除外ロジック:**
```swift
// PE Responder discovery callback
await peResponder.onDiscovery { [weak self] muid, isKnown in
    guard let self = self else { return }
    if !isKnown {
        // New PE device discovered
        await MainActor.run {
            self.discoveredPEDevices.insert(muid)
        }
        #if os(macOS)
        // Exclude macOS entities (self) from PE Notify
        if let sharedMUID = await self.peResponder?.sharedMUID?.rawValue,
           muid == sharedMUID {
            await self.peResponder?.excludeMUIDs.insert(muid)
        }
        #endif
    }
}
```

**0x39 (Subscribe Reply) フィルタ:**
```swift
// PEResponder handleMessage() 内
if parsed.subID2 == 0x39 {
    // KeyStage sends Subscribe Reply (0x39) after successful subscription
    // Ignore it (not a Notify)
    print("PE: ignoring Subscribe Reply (0x39) from \(String(format:"0x%X", parsed.sourceMUID.rawValue))")
    return
}
```

**目的:**
- KeyStage は Subscribe 成功時に 0x39 (Subscribe Reply) を送信
- M2DX はこれを「Notify」と誤認識しないようフィルタ

### テスト結果（2026-02-08 08:27 実機確認）

**環境:**
- macOS 15.3 (Sequoia)
- M2DXMac PID 25740
- KORG KeyStage (MUID 0x602AA21)

**テスト内容:**
- 20回以上の連続 Program Change（0-9 繰り返し）
- E.PIANO 1, CLAV 1, BASS 1, E.ORGAN 1, MARIMBA, FLUTE 1 等

**結果:**
- ✅ **全てハングなし** — 連続 PC 動作が完全に安定
- ✅ **LCD 更新成功** — X-ProgramEdit Notify (0x38 + command:notify) でプログラム名が即座に反映
- ✅ **KeyStage 0x39 (Subscribe Reply) 正しくフィルタ**: "PE: ignoring Subscribe Reply (0x39)"
- ✅ **macOS entity 除外成功**: discoveredPEDevices のみに Notify 送信

### 教訓

#### 1. MIDI-CI バージョン互換性の重要性

- CI v1.1 と CI v1.2 では Notify メッセージフォーマットが異なる
- **デバイスの CI バージョンを確認し、対応する方式を使用すべき**
- KORG KeyStage は CI v1.1 準拠 → 0x38 + command:notify 必須

#### 2. 仕様書の「オプション」は実装により異なる

- MIDI-CI 仕様では 0x3F は「オプション」として記載
- しかし KORG は 0x38 + command:notify を「必須」として実装
- **仕様のオプション機能でも、実デバイスでは必須の場合がある**

#### 3. macOS 環境特有の問題

- macOS では CoreMIDI が自身のエンティティを discoveredPEDevices に含めることがある
- **excludeMUIDs で自己ループを防ぐ必要**
- iOS 環境では不要（自己検出しない）

#### 4. Subscribe Reply (0x39) の扱い

- KeyStage は Subscribe 成功時に 0x39 を送信
- **0x39 は Notify ではなく Ack（確認応答）** として扱う
- PEResponder は 0x39 を無視し、0x38 + command:notify のみ処理

### 今後の対応

#### リリース前

- [x] 0x3F → 0x38 修正の動作確認（完了 2026-02-08）
- [x] macOS entity 除外の動作確認（完了 2026-02-08）
- [x] 0x39 フィルタの動作確認（完了 2026-02-08）
- [ ] iOS 実機での動作確認（excludeMUIDs がiOSで不要であることを確認）
- [ ] デバッグ print 文のクリーンアップ

#### 将来の拡張

- [ ] CI v1.2 デバイスとの互換性確認（0x3F 対応デバイスのテスト）
- [ ] BLE MIDI 接続での PE Notify 動作確認

---

## 16. 解決済み問題の時系列（更新 2026-02-08）

### Phase 8: ★★★ PE Notify sub-ID2 修正（0x3F → 0x38）— 最終解決 (2026-02-08)

- **問題**: PE Notify 送信後に KeyStage LCD にプログラム名が表示されず、部分的にハング
- **根本原因**: KORG KeyStage は CI v1.1 準拠で 0x3F (PE Notify) 未対応
  - 0x38 (Subscription) + command:notify ヘッダーが正しい Notify 方式
  - 0x3F 送信 → KeyStage が未知メッセージとして部分ハング（PC 不可、NoteOn 可）
- **修正内容**:
  1. CIMessageBuilder+Reply.swift: PE Notify sub-ID2 を 0x3F → 0x38 に変更（CI v1.1 準拠）
  2. PEResponder.swift: command:"notify" 無視 / excludeMUIDs / subscriberMUIDs()
  3. MIDIInputManager.swift: macOS entity 除外ロジック / 0x39 フィルタ
- **結果**: 連続 20+ 回の Program Change でハングなし、LCD 更新成功

---

## 18. iOS USB版 targeted送信修正 — KeyStage LCD ハング最終解決 (2026-02-08)

### 問題の経緯

macOS版では PE Notify 0x38修正により完全動作したが、iOS実機 USB接続では依然として KeyStage LCD ハングが発生。

### 症状

- iOS実機からUSB接続で KeyStage に PE/CI メッセージ送信
- KeyStage LCD が固着、ノブ無反応（完全ハング）
- macOS版では同じコードで正常動作 → iOS固有の問題

### 根本原因の発見（2026-02-08 12:25）

**iOS USB接続では KeyStage に 3つのポートが見える:**
1. **Session 1** (Out: KORG KeyStage Port 1)
2. **CTRL** (Out: KORG KeyStage CTRL)
3. **DAW OUT** (Out: KORG KeyStage DAW Out)

**M2DXのbroadcast送信は全3ポートに送信:**
- Session 1: 音源用ポート（Note On/Off, CC等）
- CTRL: PE/CI通信用ポート（推奨）
- DAW OUT: MIDI Thru用ポート

**問題:**
- Session 1とDAW OUTへのCI/PEメッセージ送信がKeyStage内部でコンフリクト
- KeyStage LCD パーサーがSession 1からのPE Notifyを処理中にDAW OUTからも届き、ハング

**macOSでは問題が起きない理由:**
- macOSはCTRLポートのみを使用（System MIDIデバイス設定由来）
- iOSはCoreMIDI APIで全destinationを列挙 → broadcast = 全ポート送信

### 修正内容

#### 1. resolvePEDestinations() 実装（MIDIInputManager.swift）

**CoreMIDI API直接使用でCTRLポートを優先的に選択:**
```swift
private static func resolvePEDestinations(source: MIDIEndpointRef) -> [MIDIEndpointRef] {
    var result: [MIDIEndpointRef] = []
    var entityRef: MIDIEntityRef = 0
    MIDIEndpointGetEntity(source, &entityRef)

    let destCount = MIDIEntityGetNumberOfDestinations(entityRef)
    for i in 0..<destCount {
        let dest = MIDIEntityGetDestination(entityRef, i)
        var name: Unmanaged<CFString>?
        MIDIObjectGetStringProperty(dest, kMIDIPropertyName, &name)
        if let n = name?.takeRetainedValue() as? String {
            if n.contains("CTRL") {
                result = [dest]  // CTRL優先 — これのみ使用
                break
            }
        }
    }
    if result.isEmpty {
        // CTRLがない場合は全destination（フォールバック）
        for i in 0..<destCount { result.append(MIDIEntityGetDestination(entityRef, i)) }
    }
    return result
}
```

**ポイント:**
- CTRLポート優先 — 見つかればこれのみ使用
- CTRLが無い場合は全destination（後方互換性）
- macOS/iOS共通ロジック

#### 2. PEResponder replyDestinations パラメータ追加

**PEResponder.swift:**
```swift
actor PEResponder {
    private let replyDestinations: [MIDIEndpointRef]

    init(..., replyDestinations: [MIDIEndpointRef] = []) {
        self.replyDestinations = replyDestinations
    }

    private func sendReply(...) async throws {
        if !replyDestinations.isEmpty {
            // Targeted send (iOS USB)
            for dest in replyDestinations {
                try await transport.send(message, to: dest)
            }
        } else {
            // Broadcast (macOS / BLE)
            try await transport.broadcast(message)
        }
    }
}
```

#### 3. CIManager setReplyDestinations() 追加

**CIManager.swift:**
```swift
@MainActor
@Observable
final class CIManager {
    private var replyDestinations: [MIDIEndpointRef] = []

    func setReplyDestinations(_ dests: [MIDIEndpointRef]) {
        self.replyDestinations = dests
    }

    private func sendDiscoveryReply(...) {
        if !replyDestinations.isEmpty {
            for dest in replyDestinations {
                try? await transport.send(reply, to: dest)
            }
        } else {
            try? await transport.broadcast(reply)
        }
    }
}
```

#### 4. MIDIInputManager 統合

**起動時にreplyDestinationsを設定:**
```swift
func start(...) async {
    // ...
    let source = notification.source
    let peDestinations = Self.resolvePEDestinations(source: source)
    await peResponder.setReplyDestinations(peDestinations)
    await ciManager.setReplyDestinations(peDestinations)
}
```

### 段階テスト（Step 4→5→6→フル）

**Step 4: CTRL targeted Discovery Reply**
- Result: CTRLのみ送信、Session 1/DAW OUT除外 → Success

**Step 5: CTRL targeted Cap Reply + PE GET Reply**
- Result: PE GET Reply targeted → Success

**Step 6: CTRL targeted PE Notify**
- Result: Notify targeted → Success

**フルテスト: 連続PC + Value UP/DOWN**
- Result: ハングなし、LCD更新成功

### テスト結果（2026-02-08 12:53 実機確認）

**環境:**
- iOS 18.3 実機（iPhone）
- USB接続 KeyStage
- replyDestinations=[CTRL]

**結果:**
- ✅ **KeyStage LCD 表示成功** — X-ProgramEdit Notify で即座に反映
- ✅ **ハングなし** — 連続PC動作安定
- ✅ **PC変更で LCD更新成功** — Value UP/DOWN 正常動作

### 教訓

#### 1. iOSとmacOSのCoreMIDI環境差異

- macOS: System MIDI設定で推奨ポートが決まる → CTRLポート優先
- iOS: CoreMIDI APIで全destination列挙 → broadcast = 全ポート送信
- **iOS固有の問題はtargeted送信で解決**

#### 2. KeyStageのポート役割

- **CTRL**: PE/CI通信専用（推奨）
- **Session 1**: 音源用（Note On/Off, CC, PC等）
- **DAW OUT**: MIDI Thru用
- **Session 1/DAW OUTへのPE/CI送信は避けるべき**

#### 3. broadcast vs targeted送信

- **broadcast**: 全ポート送信 — BLE/macOSで推奨
- **targeted**: 特定ポートのみ送信 — iOS USBで必須
- **CoreMIDI send() API使用時は destination指定が可能**

---

## 19. bankPC 1-based修正 — Value UP/DOWN 順序問題の完全解決 (2026-02-08)

### 問題の経緯

iOS USB版 targeted送信修正により KeyStage LCD表示は成功したが、
**KeyStage Value UP/DOWN でのプログラムナビゲーション順序が異常:**
- UP: program=2→3→2→4→3→2→5→...（同じPC値が繰り返し現れる）
- DOWN: program=0→1→0→1→0→...（0と1の間を往復）

### 根本原因の発見（2026-02-08 15:36）

**KeyStageはbankPC値を1-basedで解釈する:**
- M2DXは0-based: bankPC:[0,0,0]〜[0,0,9]（配列インデックス）
- KeyStageは1-based: bankPC:[0,0,1]〜[0,0,10]（ユーザー表示番号）
- **0-basedでbankPC送信 → KeyStage内部ナビゲーションがずれる**

**実測データ（Value UP）:**
```
M2DX送信 bankPC:[0,0,0] → KeyStage LCD: program=2
M2DX送信 bankPC:[0,0,1] → KeyStage LCD: program=3
M2DX送信 bankPC:[0,0,0] → KeyStage LCD: program=2（戻る）
M2DX送信 bankPC:[0,0,2] → KeyStage LCD: program=4
...
```
→ KeyStageの内部ポインタが0-based bankPCと1-based期待値の間でズレて、同じPC値を繰り返し送信

### 修正内容

#### 1. ProgramList GET: bankPC[2]=globalIndex+1

**MIDIInputManager.swift — ProgramList リソース:**
```swift
await responder.registerResource("ProgramList", resource: ComputedResource(
    supportsSubscription: true,
    get: { header in
        let offset = header.offset ?? 0
        let limit = header.limit ?? 128
        let presets = DX7FactoryPresets.all
        let items = presets[offset..<min(offset+limit, presets.count)].enumerated().map { globalIndex, preset in
            let idx = globalIndex + offset + 1  // 1-based
            "{\"title\":\"\(preset.name)\",\"bankPC\":[0,0,\(idx)]}"
        }
        return Data("[\(items.joined(separator:","))]".utf8)
    },
    responseHeader: { _, bodyData in
        let count = (try? JSONSerialization.jsonObject(with: bodyData) as? [Any])?.count ?? 0
        return Data("{\"status\":200,\"totalCount\":\(count)}".utf8)
    }
))
```

**変更:**
- `bankPC:[0,0,\(globalIndex)]` → `bankPC:[0,0,\(globalIndex+1)]`

#### 2. X-ProgramEdit GET: bankPC[2]=idx+1

**MIDIInputManager.swift — X-ProgramEdit リソース:**
```swift
await responder.registerResource("X-ProgramEdit", resource: ComputedResource(
    supportsSubscription: true,
    get: { _ in
        await MainActor.run {
            let idx = Int(currentProgramIndex) + 1  // 1-based
            let name = DX7FactoryPresets.all[Int(currentProgramIndex)].name
            let json = """
            {"name":"\(name)","bankPC":[0,0,\(idx)],"currentValues":[...]}
            """
            return Data(json.utf8)
        }
    }
))
```

**変更:**
- `bankPC:[0,0,\(Int(currentProgramIndex))]` → `bankPC:[0,0,\(Int(currentProgramIndex)+1)]`

#### 3. notifyProgramChange X-ProgramEdit Notify: bankPC[2]=idx+1

**MIDIInputManager.swift — PE Notify送信:**
```swift
private func notifyProgramChange(programIndex: UInt8) {
    guard let responder = peResponder else { return }
    let idx = Int(programIndex) + 1  // 1-based
    let name = DX7FactoryPresets.all[Int(programIndex)].name
    let json = """
    {"name":"\(name)","bankPC":[0,0,\(idx)],"currentValues":[...]}
    """
    Task { await responder.notify(resource: "X-ProgramEdit", data: Data(json.utf8)) }
}
```

**変更:**
- `bankPC:[0,0,\(Int(programIndex))]` → `bankPC:[0,0,\(Int(programIndex)+1)]`

#### 4. PC受信マッピング修正: programIndex-1

**MIDIInputManager.swift — Program Change受信:**
```swift
if let preset = midiEvent as? MIDIEvent.ProgramChange {
    let programIndex = UInt8(max(0, min(Int(preset.program) - 1, 9)))  // 1-based → 0-based配列
    await MainActor.run {
        currentProgramIndex = programIndex
        onProgramChange?(programIndex)
    }
    notifyProgramChange(programIndex: programIndex)
}
```

**変更:**
- KeyStageはbankPC値をそのままPC番号として送信（1-based）
- `preset.program - 1` で0-based配列インデックスに変換

### テスト結果（2026-02-08 15:49 実機確認）

**環境:**
- iOS 18.3 実機
- USB接続 KeyStage
- bankPC 1-based + PC受信-1変換

**Value UP テスト:**
```
program=2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10（順番通り！）
```

**Value DOWN テスト:**
```
program=9 → 8 → 7 → 6 → 5 → 4（順番通り！）
```

**結果:**
- ✅ **Value UP/DOWN 完全動作** — 同じPC値の重複なし
- ✅ **ハングなし** — 連続PC動作安定
- ✅ **LCD更新成功** — プログラム名即座に反映

### 教訓

#### 1. bankPC値の解釈はデバイス依存

- MIDI仕様では0-based/1-basedの明確な規定なし
- **KeyStageは1-basedで解釈** — ユーザー表示番号そのまま
- **M2DXは0-based** — Swift配列インデックス
- **送信時は1-based、受信時は-1変換が必要**

#### 2. ProgramList responseHeader の offset フィールド

**以前の実装:**
```json
{"status":200,"totalCount":10,"offset":0}
```

**修正後:**
```json
{"status":200,"totalCount":10}
```

- KeyStage は offset フィールドを無視（ページネーション未対応）
- 削除しても動作に影響なし

#### 3. Value UP/DOWN の動作仕様

- KeyStage は現在の bankPC 値を基準に ±1 して次のPC番号を決定
- 0-based bankPC では KeyStage 内部ポインタとズレが生じ、同じPC値を繰り返す
- 1-based bankPC で KeyStage の期待値と一致 → 順番通り動作

---

## 20. 解決済み問題の時系列（更新 2026-02-08 15:52）

### Phase 9: ★★★ iOS USB targeted送信修正 — KeyStage LCD ハング最終解決 (2026-02-08)

- **問題**: iOS実機 USB接続で KeyStage LCD ハング（macOS版は正常）
- **根本原因**: USB 3ポート(Session 1, CTRL, DAW OUT)全てにbroadcast送信 → Session 1/DAW OUTへのCI/PEがLCDハング
- **修正内容**:
  1. resolvePEDestinations() 実装（CoreMIDI API直接使用、CTRL優先）
  2. PEResponder: replyDestinationsパラメータ追加、targeted送信
  3. CIManager: setReplyDestinations() + targeted Discovery/Cap Reply
- **結果**: iOS USB版で完全動作、LCD表示成功、ハングなし

### Phase 10: ★★★ bankPC 1-based修正 — Value UP/DOWN 順序問題の完全解決 (2026-02-08)

- **問題**: KeyStage Value UP/DOWN で同じPC値が繰り返し現れる（2→3→2→4→3→...）
- **根本原因**: KeyStageはbankPC値を1-basedで解釈する
  - 0-based(bankPC:[0,0,0]〜[0,0,9])だとKeyStage内部ナビゲーションがズレてPC重複送信
- **修正内容**:
  1. ProgramList GET: bankPC[2]=globalIndex+1（0-based→1-based）
  2. X-ProgramEdit GET: bankPC[2]=idx+1（0-based→1-based）
  3. notifyProgramChange X-ProgramEdit Notify: bankPC[2]=idx+1（0-based→1-based）
  4. PC受信マッピング: programIndex-1 して0-based配列インデックスに変換
- **結果**: Value UP/DOWN が完全に順番通り動作（UP: 2→3→...→10, DOWN: 9→8→...→1）

### Phase 11: PEリファクタリング + peIsolationStep削除 (2026-02-08)

- **Phase 1-3**: PEResponder MIDI2Logger注入、peSnifferMode #if DEBUG、acceptedOldMUIDs削除、restartTaskパターン
- **ChannelList supportsSubscription バグ修正**: peIsolationStep >= 6条件削除、常にtrue
- **peIsolationStep 完全削除**: step 4/5/6デバッグ分岐削除、常にフルPE/CI動作

---

## 21. 現状（2026-02-08 15:52 時点）

### 動作確認済み

- [x] PE SysExフィールドオーダー修正
- [x] ProgramList JSONフォーマット修正（title + bankPC配列）
- [x] ChannelList Subscribe成功（1-based channel）
- [x] ProgramList GET Reply成功（totalCount付きヘッダー）
- [x] 全リソース totalCount ヘッダー追加
- [x] X-ParameterList 5パラメータ応答成功（min/max削除、KORG公式仕様準拠）
- [x] X-ProgramEdit currentValues形式で応答成功（ハング解決）
- [x] 全 Subscribe 成功（sub-1 ~ sub-4）
- [x] ★★★ **PE Notify 0x38修正で動作確認（KeyStage LCD プログラム名表示成功）**
- [x] ★★★ **macOS entity 除外ロジック実装（自己ループ防止）**
- [x] ★★★ **KeyStage 0x39 (Subscribe Reply) フィルタ実装**
- [x] 固定 MUID でキャッシュ問題解消
- [x] Manual Cap Reply 廃止
- [x] stop() で Invalidate MUID 送信
- [x] macOS版 log stream によるリアルタイムデバッグ環境確立
- [x] 連続 20+ 回 Program Change でハングなし（完全安定動作確認）

- [x] ★★★ **iOS USB targeted送信実装（resolvePEDestinations() — CTRL優先、Session 1/DAW OUT除外）**
- [x] ★★★ **iOS USB版 KeyStage LCD 完全成功（ハングなし、LCD表示成功）**
- [x] ★★★ **bankPC 1-based修正（ProgramList/X-ProgramEdit/Notify全て）**
- [x] ★★★ **Value UP/DOWN 順番通り動作確認（UP: 2→3→...→10, DOWN: 9→8→...→1）**
- [x] PEリファクタリング（MIDI2Logger注入、restartTask、#if DEBUG peSnifferMode）
- [x] ChannelList supportsSubscription バグ修正
- [x] peIsolationStep デバッグ分岐削除（常にフルPE/CI動作）

### 確認待ち / 調査中

- [ ] JSONSchema resId パース問題（parameterListSchema/programEditSchema が {} を返す）
- [ ] デバッグ print 文のクリーンアップ
- [ ] BLE MIDI 接続での PE Notify 動作確認

---
