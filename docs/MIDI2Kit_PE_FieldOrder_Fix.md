# MIDI2Kit PE フィールドオーダー修正記録

2026-02-07 に発見・修正した MIDI-CI PE メッセージのフィールドオーダーバグの詳細。

## 問題

MIDI-CI PE メッセージ（Reply / SET Inquiry）で `headerData` の配置が間違っていた。

### 修正前（誤）

```
requestID(1) → headerLength(2) → numChunks(2) → thisChunk(2) → dataLength(2) → headerData(N) → propertyData(M)
```

### 修正後（正）

```
requestID(1) → headerLength(2) → headerData(N) → numChunks(2) → thisChunk(2) → dataLength(2) → propertyData(M)
```

`headerData` は `headerLength` の**直後**に配置される。チャンクフィールドはその後。

## 影響

KORG KeyStage が ResourceList の PE GET Reply を受信しても、headerData の位置が違うため
JSON パースに失敗し、DeviceInfo / ProgramList の GET に進まなかった。

## 修正ファイル一覧

### 送信側（ビルダー）

**`MIDI2Kit/Sources/MIDI2CI/CIMessageBuilder+Reply.swift`**

| メソッド | 修正内容 |
|---------|---------|
| `peGetReply()` | headerData を numChunks 前に移動 |
| `peSetReply()` | 同上 |
| `peSubscribeReply()` | 同上 |
| `peNotify()` | 同上 |

**`MIDI2Kit/Sources/MIDI2CI/CIMessageBuilder.swift`**

| メソッド | 修正内容 |
|---------|---------|
| `peSetInquiry()` | headerData を numChunks 前に移動 |

### 受信側（パーサー）

**`MIDI2Kit/Sources/MIDI2CI/CIMessageParser.swift`**

| メソッド | 修正内容 |
|---------|---------|
| `parsePEReplyCI12()` | headerData 読み出し位置を headerLength 直後に修正 |

**`MIDI2Kit/Sources/MIDI2CI/CIMessageParser+Inquiry.swift`**

| メソッド | 修正内容 |
|---------|---------|
| `parsePESetInquiry()` | headerData 読み出し位置を headerLength 直後に修正 |

### 影響なし（元から正しい）

| メソッド | 理由 |
|---------|------|
| `peGetInquiry()` (Builder) | チャンクフィールドなし |
| `peSubscribeInquiry()` (Builder) | チャンクフィールドなし |
| `peCapabilityInquiry/Reply()` | PE データなし |
| `parsePEGetInquiry()` (Parser) | チャンクフィールドなし |
| `parsePESubscribeInquiry()` (Parser) | チャンクフィールドなし |

## 根拠

- KORG KeyStage PE MIDI Implementation (`Keystage_PE_MIDIimp.txt`) Section 4-5, 4-6
- フィールド順序:
  ```
  rr             RequestID
  ee, ee         Length of Following Header Data (LSB first)
  hh...          Header Data (JSON)
  cc, cc         Number of Chunks (LSB first)
  gg, gg         Number of This Chunk (LSB first)
  ff, ff         Length of Following Property Data (LSB first)
  pp...          Property Data
  ```

## 検証

修正後、KORG KeyStage が以下の全リソースを正常に GET:

1. ResourceList (121B body)
2. DeviceInfo (147B body)
3. ChannelList (63B body)
4. Subscribe ChannelList → reply OK
5. ProgramList (381B body, 10 presets)
