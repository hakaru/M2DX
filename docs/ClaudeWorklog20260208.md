# Claude Worklog 2026-02-08

---
2026-02-08 03:44
作業項目: 監査指摘事項修正計画の実装開始（全17件、3フェーズ）
追加機能の説明: Phase 1 Critical修正（#4→#3→#2→#1の順で実装）- リアルタイム安全性の改善
決定事項: 計画通りリスクの低い順に実装開始
次のTODO: Phase 1 #4 .taskキャンセル遅延修正から着手
---

---
2026-02-08 03:51
作業項目: 監査指摘事項 全3フェーズ実装完了（13件/17件）
追加機能の説明:
- Phase 1 Critical修正（4件完了）:
  - #4: .task キャンセル遅延修正（while loop → Task.sleep）
  - #3: MIDIInputManager コールバック5箇所に @MainActor 注釈追加
  - #2: MIDIEventQueue を固定長リングバッファ化（os_unfair_lock + UnsafeMutablePointer）、drain をコールバック方式に変更
  - #1: FMSynthEngine パラメータ/ステート分離（SynthParamSnapshot + os_unfair_lock でsnapshot swapのみ保護、render本体はlock-free）
- Phase 2 High修正（3件完了）:
  - #6+#11: sqrtf/checkActive をフレームループ外に移動（invNorm事前計算）
  - #5: sinf() を4096エントリ線形補間LUTに置換（fastSin）
  - #7: pitchBend powf() を1024エントリLUTに置換（fastPitchBendFactor）
- Phase 3 Medium修正（3件完了、3件後日）:
  - #12: handleConfigurationChange 再帰防止ガード追加
  - #14: debugLog insert(at:0) → append + debugLogReversed計算プロパティ
  - #17: peFlowLog 上限2000件追加
  - 未実施: #10,#16,#9（大規模リファクタのため後日）
決定事項:
- nonisolated(unsafe)でLUTポインタのSendable問題を解決
- MIDIEventQueue は os_unfair_lock を直接使用（OSAllocatedUnfairLock の @Sendable 制約回避）
- 実機ビルド成功確認（BUILD SUCCEEDED）
次のTODO: 実機接続テスト（KeyStage NoteOn/Off, CC, PitchBend, Program Change）、聴感テスト（sinf LUTで音質劣化ないか）
---

---
2026-02-08 03:53
作業項目: macOS版ビルド — M2DXMacスキームが既に存在
追加機能の説明:
- 調査結果: M2DXMacスキームとM2DXMacApp.swiftが既にプロジェクトに存在
- Package.swift: platforms に .macOS(.v14) 設定済み
- M2DXFeature: #if os(iOS/macOS) で条件付きコンパイル済み
- M2DXMac/M2DXMacApp.swift: M2DXRootView() を共有
- M2DXMac.entitlements: Sandbox + Audio Input 設定済み
- PlatformColors.swift: iOS/macOS カラー抽象化済み
決定事項: 新規作成不要。既存の M2DXMac スキームをビルド
次のTODO: xcodebuild -scheme M2DXMac ビルド実行
---

---
2026-02-08 03:55
作業項目: ★macOS版 M2DXMac ビルド＆起動成功
追加機能の説明:
- xcodebuild -scheme M2DXMac -configuration Debug BUILD SUCCEEDED
- アプリ起動成功（open M2DXMac.app）
- log stream --predicate 'subsystem == "com.example.M2DX"' でログ取得準備OK
  - MIDIイベントがまだ無いためログは空だが、ストリーム自体は動作
- macOS版はiOS版と同じ M2DXRootView() を共有
決定事項: macOS版のビルド・起動・ログストリーム全て動作
次のTODO: KeyStageをUSBでMacに接続 → log stream でリアルタイムログ取得テスト
---

---
2026-02-08 03:58
作業項目: macOS版で音が鳴らない問題調査
追加機能の説明:
- KeyStage USB接続はmacOSで認識済み（Keystage KBD/CTRL, Keystage DAW IN）
- M2DXMac の os.Logger ログが一切出ない → .task が実行されていない or AudioEngine起動失敗
- App Sandbox有効、com.apple.security.device.audio-input のみ
- Sandbox下のCoreMIDIアクセスに問題がある可能性
決定事項: Sandboxを一時的に無効化してテスト
次のTODO: Sandbox無効化 → リビルド → 動作確認
---

---
2026-02-08 04:01
作業項目: macOS版クラッシュ修正 — Task.sleep(Int.max) オーバーフロー
追加機能の説明:
- クラッシュ原因: M2DXFeature.swift:84 `Task.sleep(for: .seconds(Int.max))`
  - macOS x86_64 で Duration.components getter が Int オーバーフロー
  - iOS (ARM64) では発生しなかったがmacOS (x86_64) で発生
- Fatal error: "Not enough bits to represent the passed value"
- 修正: `Task.sleep(for: .seconds(86400))` + while !Task.isCancelled ループに変更
- Sandbox無効化で os.Logger ログ取得成功（PE sharedMUID, CIManager.muid 確認）
決定事項: Int.max → 86400 (1日) に変更。.taskのキャンセルで自然終了
次のTODO: リビルド → 起動確認
---

---
2026-02-08 04:04
作業項目: PE Notify 無効化 — KeyStageハング再発
追加機能の説明:
- macOS版でPC 001送信 → KeyStageハング再発
- iOSでは500msデバウンスで単発Notifyはハングしなかったが、macOSでは1発でもハング
- PE Notify を完全無効化して macOS 基本動作確認を優先
- notifyProgramChange: currentProgramIndex更新 + ログ出力のみ、Notify送信なし
決定事項: PE Notifyは当面無効。macOS検証環境の確立を優先
次のTODO: KeyStage再起動 → macOS版でMIDI受信・発音確認
---

---
2026-02-08 04:08
作業項目: ★macOS版 PEフロー完全成功 + log streamリアルタイム取得成功
追加機能の説明:
- M2DX再起動 → KeyStageハングなし（PE Notify無効化の効果）
- PEフロー全ステップ成功（log streamで全キャプチャ）:
  - Discovery → Cap → ResourceList → DeviceInfo → ChannelList(sub-1)
  - ProgramList(sub-2) → X-ParameterList(sub-3) → X-ProgramEdit(sub-4) → JSONSchema×2
- KeyStage鍵盤のNoteOn/Off受信確認（UMP mt=4 st=9/8）
- **log stream でリアルタイムにCI/PE/MIDIログを取得可能に！**
  - `log stream --predicate 'subsystem == "com.example.M2DX"' --level debug`
  - iOS版のCopy Log手動ペースト方式から大幅改善
決定事項: macOS検証環境が確立。log streamで全ログリアルタイム取得可能
次のTODO: macOS版で音が鳴るか確認、Program Changeの動作確認
---

---
2026-02-08 04:16
作業項目: PCがログに出ない問題 — KeyStageハング状態の可能性
追加機能の説明:
- NoteOn/Off, CC, PitchBendは正常受信（log streamで確認済み）
- PCを送信しても st=12 がログに出ない
- その後ログが完全に停止 → KeyStageが先のPC操作でハング状態になった可能性
- PE Notifyは無効化済みだが、KeyStageがPC操作でハングする別の原因がある?
- 仮説: PE SETでX-ProgramEditが来て、それに対する応答に問題がある
決定事項: KeyStage電源再投入 → PCがハングを引き起こすメカニズムを調査
次のTODO: KeyStage再起動 → log stream監視しながらPC送信 → ハングの瞬間をキャプチャ
---

---
2026-02-08 04:19
作業項目: ★macOS版 PC受信成功 + KeyStageハングなし
追加機能の説明:
- KeyStage再起動後、M2DX再起動
- PC送信: program=9 (CLAV 1) 正常受信（UMP mt=4 st=12）
- PC後もNoteOn/Off正常動作 → KeyStageハングなし
- PE Notify無効化が効いている
- 前回ハングした原因: PE Notifyが有効だった時にPC送信→Notify→ハング
- 今回はPE Notify無効なのでPC送信してもハングしない
- PEフローはlog streamでキャプチャできなかった（起動直後のタイミング）
決定事項: PE Notify無効状態ではPC受信+KeyStage安定が両立
次のTODO: 音色が実際に切り替わるか確認（program 0-9でapplyPreset動作確認）
---

---
2026-02-08 04:21
作業項目: PEフロー自体がKeyStageハングの原因か切り分けテスト
追加機能の説明:
- ユーザー報告: M2DX再起動時にKeyStage表示系ハング（LCD消灯+ノブ無反応）
- PE Notify無効でもPEフロー（Discovery→Cap→ResourceList等）でハングする可能性
- 切り分け: PE/CI初期化を完全無効化（peDisabledForDebug=true）
  - MIDI入力のみ、CIManager/PEResponder/PEManager 一切なし
  - これでKeyStageがハングしなければ、PEフローが原因確定
決定事項: PE完全無効でビルド、KeyStage再起動後にテスト
次のTODO: KeyStage再起動 → M2DXMac起動 → ハングしないか確認
---

---
2026-02-08 04:23
作業項目: PE完全無効状態でのKeyStageハング切り分けテスト開始
追加機能の説明:
- KeyStage再起動完了（ユーザー報告）
- peDisabledForDebug=true でビルド済みのM2DXMacを起動してテスト
- テスト手順: M2DXMac起動 → KeyStage LCD正常か → NoteOn/Off → PC送信
- ハングしなければ → PEフローが原因確定
- ハングすれば → CoreMIDI接続自体に問題あり
決定事項: テスト開始
次のTODO: M2DXMac起動 → log stream監視 → KeyStage LCD状態確認
---

---
2026-02-08 04:25
作業項目: ★PEフローがKeyStageハングの原因であることが確定
追加機能の説明:
- peDisabledForDebug=true（PE/CI完全無効）でM2DXMac起動
- KeyStage LCD正常、ノブ反応あり（ユーザー確認: option 1）
- NoteOn/Off正常受信、音が鳴る
- PE関連ログ一切なし（PE無効の証拠）
- 結論: **PEフロー（Discovery→Cap→ResourceList等）がKeyStage表示系ハングの原因**
- CoreMIDI接続自体には問題なし
決定事項: PEフローがKeyStageハングの根本原因。PE Notifyだけでなく、PEフロー全体が問題
次のTODO: PEフローのどのステップがハングを引き起こすか段階的に特定（Discovery only → +Cap → +ResourceList...）
---

---
2026-02-08 04:26
作業項目: PE段階的切り分け — Step 1（CIManagerのみ）ビルド完了
追加機能の説明:
- peIsolationStep変数で段階制御:
  - Step 0: PE完全無効（確認済み: ハングなし）
  - Step 1: CIManager作成のみ（respondToDiscovery=true、Discovery Inquiry送信なし）← 今ここ
  - Step 2: CIManager + PEResponder + PEManager（Discovery Inquiry送信なし）
  - Step 3: CIManager + PEResponder + PEManager + Discovery Inquiry送信（フル）
- BUILD SUCCEEDED
決定事項: Step 1でビルド。KeyStage再起動待ち
次のTODO: KeyStage再起動 → M2DXMac起動 → LCD状態確認
---

---
2026-02-08 04:31
作業項目: ★PE段階切り分け完了 — Discovery Inquiry送信がKeyStageハングの原因確定
追加機能の説明:
- Step 0: PE完全無効 → ハングなし ✓
- Step 1: CIManager作成のみ → ハングなし ✓
- Step 2: CIManager + PEResponder + PEManager（Discovery送信なし）→ ハングなし ✓
- Step 3: + Discovery Inquiry送信 → ★ハング発生 ✗
- 結論: ci.sendDiscoveryInquiry() がKeyStage表示系ハングのトリガー
- Discovery Inquiryを受けたKeyStageがPEフロー開始→応答やり取り中にハング
- さらなる切り分け: Discovery Inquiryは送るがPEResponderなし（KeyStageのPE要求に無応答）でテスト
決定事項: Discovery Inquiry送信がハングの直接原因。PEフロー応答が問題か、Discovery自体が問題か追加切り分け必要
次のTODO: Step 2.5（Discovery送信 + PEResponder/PEManagerなし）でテスト
---

---
2026-02-08 04:34
作業項目: ★Discovery Inquiry送信自体がKeyStageハングの根本原因確定
追加機能の説明:
- Step 2.5: CIManager + Discovery Inquiry（PEResponder/PEManagerなし）→ ★ハング
- PEの応答やり取りは関係ない。Discovery Inquiryメッセージ自体がトリガー
- 切り分け結果まとめ:
  - Step 0: PE無効 → OK
  - Step 1: CIManager作成のみ → OK
  - Step 2: + PEResponder/PEManager → OK
  - Step 2.5: CIManager + Discovery Inquiry（PE応答なし）→ ★ハング
  - Step 3: フルPE/CI → ★ハング
- 仮説:
  A) Discovery Inquiryのフォーマット/MUID値がKeyStageにとって不正
  B) KeyStageがDiscovery Reply後のCI/PEフロー開始でハング（PE応答がなくてもフロー試行自体がハング）
  C) ハードコードMUID 0x5404629がKeyStageのキャッシュと衝突
- 次の切り分け: categorySupport を .none にして Discovery Inquiry 送信（PE非対応として宣言）
決定事項: Discovery Inquiry送信がハングの根本原因。PE応答の有無は無関係
次のTODO: categorySupport=なし(PE非対応)でDiscovery → ハングするか確認。またはランダムMUIDでテスト
---

---
2026-02-08 04:38
作業項目: Step 2.5バグ修正 — peIsolationStep=25がPEResponder条件(>=2)を満たしていた
追加機能の説明:
- 前回のStep 2.5テストは無効: peIsolationStep=25 >= 2 が true → PEResponder作成されていた
- ログで確認: 完全なPEフロー（ResourceList→DeviceInfo→ChannelList→ProgramList→Subscribe×4→JSONSchema×2）が実行
- categorySupport=[]でもKeyStageはPEフローを開始（フラグ無視の可能性）
- PC受信は1回のみ（program=1）、複数回送信したが1回しか届いていない → ハング後PC送信不可
- 修正: `peIsolationStep >= 2 && peIsolationStep < 25` に変更
決定事項: Step 2.5を正しく再テスト必要（Discovery送信 + PEResponder/PEManagerなし + categorySupport=[]）
次のTODO: KeyStage再起動 → 修正版Step 2.5テスト
---

---
2026-02-08 04:41
作業項目: ★Step 2.5修正版テスト成功 — Discovery自体は無害、PEフローがハング原因
追加機能の説明:
- Step 2.5修正版（Discovery送信 + categorySupport=[] + PEResponderなし）→ ハングなし ✓
- PCチェンジ連打も正常
- ログ確認: Discovery Inquiry → Discovery Reply(0x30) → CI: Discovered KORG → 以降PEフローなし
- KeyStageはcategorySupport=[]を見てPEフローを開始しなかった
- 切り分け結果更新:
  - Step 0: PE無効 → OK ✓
  - Step 1: CIManager作成のみ → OK ✓
  - Step 2: + PEResponder/PEManager（Discovery送信なし）→ OK ✓
  - Step 2.5: Discovery送信 + categorySupport=[]（PE非対応宣言）→ OK ✓ ← NEW
  - Step 3: フルPE/CI（categorySupport=.propertyExchange）→ ハング ✗
- 結論: **Discovery Inquiryで.propertyExchange宣言→KeyStageがPEフロー開始→PEフロー中にハング**
- 次の切り分け: PE GETリクエスト応答までは許可し、Subscribe要求を拒否してテスト
決定事項: PEフロー（GET/Subscribe）がハングの原因。Discoveryは無害
次のTODO: PEフローのどの段階か切り分け（GET応答のみ vs Subscribe込み）
---

---
2026-02-08 04:45
作業項目: PE GETフロー自体がハング原因 — Subscribe無関係、さらに絞り込み
追加機能の説明:
- canSubscribe=false テスト結果: 即座にハング（Subscribeなしでも）
- ハング後PC 1回だけ成功、その後KeyStage PC機能も死ぬ
- PEフローのGET応答自体が原因
- 次の切り分け: ResourceList を DeviceInfo のみに最小化（totalCount=1）
- これでハング → ResourceList+DeviceInfoの2回のGETだけでハング
- これでOK → 他のリソース（ChannelList/ProgramList/X-*）が原因
決定事項: PE GETフロー自体がハング原因。最小構成で絞り込み
次のTODO: KeyStage再起動 → 最小ResourceListテスト
---

---
2026-02-08 04:47
作業項目: ★DeviceInfoのみの最小PE構成ではハングなし — リソース追加で特定へ
追加機能の説明:
- ResourceList=[DeviceInfo]のみ → ハングなし ✓ PC連打OK
- PEフロー: Discovery→ResourceList(1件)→DeviceInfo GET→完了
- KeyStageはResourceListにない不明リソースもGET試行（res=?）
- 次の絞り込み: ChannelList追加 → ProgramList追加 → X-*追加 の順で1つずつテスト
決定事項: DeviceInfoのみならPE安定。他リソースのどれかがハング原因
次のTODO: ChannelList追加テスト
---

---
2026-02-08 04:54
作業項目: ★★X-ProgramEdit がKeyStageハングの根本原因特定！
追加機能の説明:
- リソース段階追加テスト結果:
  - DeviceInfo のみ → OK ✓
  - + ChannelList → OK ✓
  - + ProgramList → OK ✓
  - + JSONSchema → OK ✓
  - + X-ParameterList → OK ✓
  - + X-ProgramEdit → ★ハング ✗ ← これが原因！
- KeyStage LCDには「000:INIT VOIC」「MIDICh.1」「(1/D)」と表示（写真確認）
  - X-ProgramEdit GETの応答（name=INIT VOICE）は受信・表示された
  - 表示後にハング（ノブ無反応、LCD固着）
- X-ProgramEdit応答: {"name":"INIT VOICE","category":"FM Synth","bankPC":[0,0,0]}
- canSubscribe=false でもハング → Subscribeは無関係
- 仮説: X-ProgramEdit応答のフォーマット/フィールドがKeyStageの期待と合わない
決定事項: X-ProgramEditリソースのGET応答がKeyStageハングの直接原因
次のTODO: X-ProgramEditの応答フォーマットを調査・修正（KORG Module Proの正式フォーマットに合わせる）
---

---
2026-02-08 04:56
作業項目: X-ProgramEditフォーマット調査 — canSubscribe=true に戻してテスト
追加機能の説明:
- PE_Implementation_Notes.md確認: X-ProgramEditフォーマット自体は正しい
- ドキュメント仕様: canSubscribe=true が必須（行289）
- 仮説: canSubscribe=false が KeyStage に不整合を起こしハングの原因
- ResourceListの canSubscribe と PEResponder の supportsSubscription の矛盾が問題？
- テスト: 元の canSubscribe=true + PE Notify無効 でビルド
決定事項: ドキュメント仕様通り canSubscribe=true に戻してテスト
次のTODO: KeyStage再起動 → フルPE(canSubscribe=true, Notify無効)テスト
---

---
2026-02-08 05:01
作業項目: X-ProgramEditに params フィールド追加 — KORG Module Proフォーマットに合わせる
追加機能の説明:
- canSubscribe=true でもハング確認（PE Notify無効でも X-ProgramEdit 自体がハング原因）
- MIDI2Kit PEKORGTypes.swift 調査: KORG Module Pro の X-ProgramEdit には params フィールドあり
  - {"name":"...","category":"...","params":[{"controlcc":11,"current":100},...]}
- M2DXの応答には params がなかった → KeyStageが期待するフィールド不足でハング？
- 修正: params フィールド追加（5つのCC値: ModWheel, Volume, Expression, Sustain, Brightness）
決定事項: params フィールド追加でテスト
次のTODO: KeyStage再起動 → X-ProgramEdit params付きテスト
---

---
2026-02-08 05:10
作業項目: セッション再開 — manufacturerName変更テスト準備
追加機能の説明:
- 前回セッション最終状態の確認:
  - ResourceList: 5リソース（X-ProgramEditなし）
  - X-ProgramEditハンドラ: 登録済み（500ms遅延、paramsフィールド付き）
  - テスト結果まとめ: X-ProgramEdit GET Reply自体がハング原因（内容/遅延/Subscribe設定すべて無関係）
- 次のテスト方針:
  1. DeviceInfo manufacturerName を "KORG" → 別名に変更
     → KeyStageがKORG固有リソース（X-ProgramEdit等）を要求しなくなるか確認
  2. X-ProgramEditをResourceListから除外したまま全PE動作確認
- まずは方法1: manufacturerNameを"M2DX"に変更してビルド
決定事項: manufacturerName変更による影響テスト
次のTODO: DeviceInfo manufacturerName="M2DX" に変更 → ビルド → テスト
---

---
2026-02-08 05:12
作業項目: ★manufacturerName="M2DX"でハングなし確認 — KORG名がX-ProgramEditリクエストのトリガー
追加機能の説明:
- テスト結果: manufacturerName="M2DX" + ResourceList 5件（X-ProgramEditなし）→ ハングなし ✓
- 結論: KeyStageは DeviceInfo の manufacturerName が "KORG" の場合にKORG固有リソース（X-ProgramEdit）を要求する
- manufacturerName を非KORGにすれば X-ProgramEdit 要求自体が発生しない
- 切り分け結果まとめ:
  - manufacturerName="KORG" + X-ProgramEdit in ResourceList → ハング ✗
  - manufacturerName="KORG" + X-ProgramEdit NOT in ResourceList → ハングなし ✓（前回テスト）
  - manufacturerName="M2DX" + X-ProgramEdit NOT in ResourceList → ハングなし ✓ ← NEW
- 次のテスト: manufacturerName="M2DX" + X-ProgramEdit を ResourceList に戻す → ハングするか？
  - もしOK → KORG名 + X-ProgramEdit の組み合わせだけが問題
  - もしハング → X-ProgramEdit自体が問題（manufacturerName無関係）
決定事項: manufacturerName="KORG"がX-ProgramEditリクエストのトリガー
次のTODO: PCチェンジ動作確認 → その後 manufacturerName="M2DX" + X-ProgramEdit追加テスト
---

---
2026-02-08 05:13
作業項目: テスト — manufacturerName="M2DX" + X-ProgramEdit ResourceList復帰
追加機能の説明:
- 前テスト: manufacturerName="M2DX" + X-ProgramEditなし → 正常 ✓ PC正常動作
- 今回テスト: manufacturerName="M2DX" + X-ProgramEdit ResourceList復帰（6リソース）
  - X-ProgramEditハンドラは登録済み（500ms遅延、params付き）
- 目的: 非KORG名でもX-ProgramEditがResourceListにあればKeyStageがGETするか確認
  - OK → KORG名の時のみKeyStageがX-ProgramEditで特殊処理してハング
  - ハング → X-ProgramEdit GET Reply自体が問題（manufacturerName無関係）
決定事項: 切り分け継続
次のTODO: KeyStage再起動 → テスト結果確認
---

---
2026-02-08 05:14
作業項目: ★★★ KeyStage PE公式仕様書発見 + ハング根本原因特定
追加機能の説明:
- テスト結果: manufacturerName="M2DX" + X-ProgramEdit in ResourceList → ハングなし ✓
  - 非KORG名ではKeyStageがX-ProgramEditをGETしない（またはKORG固有処理をスキップ）
- ★公式仕様書: Keystage_PE_ResourceList 2.txt (v1.0 2023/8/31)
  - KeyStageが送信するリソース: ResourceList, DeviceInfo, ChannelList のみ
  - KeyStageが受信（認識）するリソース:
    - X-ParameterList: {"name":"...","controlcc":24,"default":0} 形式
    - X-ProgramEdit: {"currentValues":[{"name":"...","value":0,"displayValue":"0.0","displayUnit":"%"},...]} 形式
  - JSONSchema: parameterListSchema, programEditSchema
- ★★★ハング根本原因:
  - 我々の X-ProgramEdit 形式: {"name":"...","category":"...","bankPC":[...]} ← KORG Module Pro形式
  - KeyStage期待形式: {"currentValues":[{"name":"...","value":0,"displayValue":"...","displayUnit":"..."},...]}
  - currentValuesフィールドが見つからずKeyStage内部でパースエラー → ハング
  - X-ParameterListも形式が微妙に違う（min/maxはKeyStage仕様にない）
決定事項: X-ProgramEdit/X-ParameterListをKeyStage公式仕様に合わせてフォーマット修正
次のTODO: X-ProgramEditを currentValues 形式に修正 → manufacturerName="KORG"に戻してテスト
---

---
2026-02-08 05:16
作業項目: ★★★★ KeyStageハング完全解決！X-ProgramEdit currentValues形式で正常動作
追加機能の説明:
- テスト結果: manufacturerName="KORG" + X-ProgramEdit(currentValues形式) → ★ハングなし ✓
- 修正内容:
  - X-ProgramEdit: {"currentValues":[{"name":"...","value":N,"displayValue":"...","displayUnit":"..."},...]}
  - X-ParameterList: {"name":"...","controlcc":N,"default":N} (min/max削除)
  - parameterListSchema: KeyStage仕様準拠
  - programEditSchema: currentValuesベース
- ★根本原因確定: X-ProgramEditのJSONフォーマット不一致
  - KORG Module Pro形式（name/category/bankPC/params）≠ KeyStage期待形式（currentValues）
  - KeyStageはcurrentValuesフィールドを必須としてパースし、見つからないとハング
- これでフルPE/CI（manufacturerName="KORG"、6リソース、canSubscribe=true）が正常動作
決定事項: ハング解決。次はPC動作・プログラム名表示・Subscribe動作の確認
次のTODO: PCチェンジ動作確認 → KeyStage LCD表示確認 → PE Notify再有効化検討
---

---
2026-02-08 05:18
作業項目: X-ProgramEditにnameフィールド追加 — プログラム名表示テスト
追加機能の説明:
- PC動作正常だがプログラム名がKeyStage LCDに表示されない
- 原因: currentValues形式にはプログラム名フィールドがない
- 前回ハング前テストでは name フィールドから "000:INIT VOIC" が表示されていた
- 修正: name（表示用）+ currentValues（仕様必須）を両方含める
  - {"name":"INIT VOICE","currentValues":[...]}
- 仮説: currentValues があればKeyStageパーサがハングしない + name があれば表示される
決定事項: name + currentValues の併用テスト
次のTODO: KeyStage再起動 → プログラム名表示確認
---

---
2026-02-08 05:21
作業項目: KORG PE技術仕様のWeb調査
追加機能の説明: KORG KeyStage / MIDI-CI Property Exchange の公式仕様・ドキュメントをWeb検索で調査
決定事項: 調査開始
次のTODO: 検索結果から仕様ドキュメントを特定・内容確認
---

---
2026-02-08 05:22
作業項目: MIDI2Kit X-ProgramEdit / PE Notify 仕様調査
追加機能の説明:
- PEKORGTypes.swift調査:
  - PEXProgramEdit構造体: name, category, bankMSB/LSB, programNumber, params, currentValues フィールド
  - JSON decode時に複数形式対応: bankPC=[MSB,LSB,program]形式もサポート
  - currentValues: AnyCodableValueベース（型柔軟対応）
- PE Notify関連ファイル:
  - PENotifyAssemblyManager: 複数チャンクのNotify再組立、ソース別アセンブラ管理
  - PESubscriptionHandler: Subscribe/Unsubscribe/Notify処理を担当（PEManagerから分離）
  - PEResponder: GET/SET/Subscribe処理、supportsSubscriptionフラグ確認で購読可否判定
- プログラム名通信メカニズム:
  - MIDI2Client+KORG.swift: getXProgramEdit()でX-ProgramEdit取得
  - PEResponder.notify(): 登録済みSubscriberに対して自動配信
  - X-ProgramEditはcanSubscribe=trueでサポート
決定事項:
- KeyStage期待形式: {"currentValues":[{"name":"...","value":0,"displayValue":"...","displayUnit":"..."},...]} ← currentValuesフィールド必須
- M2DXの修正結果: name + currentValues 併用で正常動作確認
- PE Notify無効化でもX-ProgramEdit自体がハング原因（フォーマット不一致）
次のTODO: KeyStage再起動 → 調査結果をM2DX実装に反映（currentValues形式確保）
---

---
2026-02-08 05:22
作業項目: PE Notify再有効化 + KORG公式仕様確認
追加機能の説明:
- KORG公式PE実装仕様(cdn.korg.com) v1.00 (2023.8.31) ダウンロード・全文解析
  - ProgramList: Recognized only（KeyStageは受信側のみ）
  - Subscription(0x38): 送受信両対応
  - KeyStage参照仕様: Keystage_PEResourceList_v0_1.txt（ユーザー提供済み）
- bankPC追加テスト結果: ハングなし ✓ だがプログラム名は非表示
- PE Notify再有効化:
  - X-ProgramEdit Notify: name + bankPC + currentValues形式
  - ChannelList Notify: programTitle付き
  - 50msデバウンス + pendingNotifyTask キャンセルで連打対策
決定事項: PE Notify再有効化（currentValues形式で安全なはず）
次のTODO: KeyStage再起動 → PE Notifyでプログラム名表示テスト
---

---
2026-02-08 05:27
作業項目: KORG PE技術仕様 4ファイル調査完了 — サマリー提供
追加機能の説明:
- ~/Downloads/ に存在する4つのKORG公式仕様ファイルを全文読了:
  1. Keystage_PE_ResourceList 2.txt (v1.0 2023/8/31) — PE Resource List仕様
  2. Keystage_PE_ResourceList.txt — 同内容の旧版
  3. Keystage_PE_MIDIimp.txt (v1.00 2023.8.31) — PE MIDI Implementation（SysExバイト構造）
  4. Keystage_MIDIimp.txt (v1.00 2023.8.31) — フルMIDI Implementation
- セッション継続: 前回コンテキスト切れの続きでサマリーを提供
決定事項: 4ファイル全て解析済み、ユーザーにサマリーを報告
次のTODO: 必要に応じてM2DX実装とKORG仕様の差分分析
---

---
2026-02-08 05:32
作業項目: PE全フロー正常確認 + JSONSchemaデバッグ
追加機能の説明:
- ★PE全フロー正常動作確認（ハングなし！）:
  - Discovery → Reply → Cap Inquiry → Cap Reply
  - GET: ResourceList→DeviceInfo→ChannelList→ProgramList→X-ParameterList→X-ProgramEdit→JSONSchema(×2)
  - Subscribe: ChannelList(sub-1), ProgramList(sub-2), X-ParameterList(sub-3), X-ProgramEdit(sub-4) 全4リソース
  - PE Notify: 送信成功（"PE-Notify: X-ProgramEdit+ChannelList program=1 name=E.PIANO 1"）
- ★問題発見: JSONSchemaが2回とも {} を返している
  - KeyStageが parameterListSchema と programEditSchema をGETしているが、resId がマッチせず default case
  - JSONSchemaにデバッグログ追加: resId と rawData を出力
- MIDI2Kit PERequestHeader調査: resId フィールドは "resId" キーでJSONパース（正しい）
決定事項: JSONSchema resIdパース問題を調査
次のTODO: M2DXMac再起動 → JSONSchemaの resId ログ確認
---

---
2026-02-08 05:37
作業項目: ログ詳細解析 — Subscription失効 + JSONSchema未確認
追加機能の説明:
- 完全なPEフロー確認（05:30:42, PID 4432）:
  - GET全リソース成功、Subscribe 4件成功(sub-1~sub-4)
  - PE Notify送信確認: "PE-Notify: X-ProgramEdit+ChannelList program=1/2/3"
  - しかしプログラム名表示されず
- 問題1: KeyStage再起動(05:33:19)でMUID変更 0xC26B18D → 0x5B14367
  - 古いSubscription(sub-1~4)はMUID 0xC26B18Dに紐付き → 無効
  - PE Notifyが旧MUID宛に送信 → KeyStageに届かない
- 問題2: PE-Schemaデバッグログが未出力
  - JSONSchemaデバッグ追加ビルドが反映されていない可能性
  - またはJSONSchemaがGETされなかった（KeyStage再起動後はGETしていない）
- 次のアクション: M2DXMac完全再起動 + KeyStage再起動でクリーンテスト
決定事項: クリーンテスト必要（両方再起動で新しいSubscription確立）
次のTODO: M2DXMac Cmd+Q終了 → 再起動 → KeyStage再起動 → PE-Schemaログ確認
---

---
2026-02-08 05:36
作業項目: PE_Implementation_Notes.md ドキュメント更新 — KORG公式仕様反映
追加機能の説明:
- PE_Implementation_Notes.md を KORG公式仕様(Keystage_PE_ResourceList v1.0)に基づいて更新:
  - セクション6 X-ParameterList: min/max削除、KORG公式形式(name/controlcc/default)に修正、parameterListSchema追加
  - セクション6 X-ProgramEdit: ★currentValues形式に全面書換え、ハング根本原因の説明追加、programEditSchema追加
  - セクション12: Phase 7追加（X-ProgramEdit currentValues形式によるKeyStageハング解決の全経緯）
  - セクション13: 最新状態に更新（2026-02-08時点）、JSONSchema resId調査中を追加
  - セクション14: KORG公式仕様4ファイルの一覧・要点を追加
決定事項: ドキュメント更新完了。KORG PE仕様の知見が永続化された
次のTODO: JSONSchema resIdパース問題の調査継続
---

---
2026-02-08 05:43
作業項目: PE_Implementation_Notes.md KORG公式仕様更新レビュー完了
追加機能の説明:
- PE_Implementation_Notes.md（793行）の全文レビュー完了
- KORG公式仕様(Keystage_PE_ResourceList v1.0)に基づく更新内容を確認:
  - セクション6: X-ParameterList形式（min/max削除、controlcc/default/name）✓
  - セクション6: X-ProgramEdit currentValues形式（★ハング解決の核心）✓
  - セクション6: parameterListSchema / programEditSchema 追加 ✓
  - セクション12 Phase 7: ハング切り分け・解決経緯の時系列 ✓
  - セクション13: 最新ステータス（JSONSchema resId調査中含む）✓
  - セクション14: KORG公式仕様4ファイルの参照一覧 ✓
- ドキュメント品質: 正確で網羅的。KORG公式仕様との対比が明確
- 未解決項目（セクション13）:
  1. JSONSchema resId パース問題
  2. KeyStage LCD プログラム名表示
  3. デバッグ print 文クリーンアップ
  4. コミット
決定事項: PE_Implementation_Notes.md の KORG仕様反映は正確で完全。次のアクション項目を進行
次のTODO: Discovery 100msタイミング修正のテスト → JSONSchema resId問題調査
---

---
2026-02-08 05:44
作業項目: M2DXMac起動 + log stream監視開始 — Discovery 100msテスト準備
追加機能の説明:
- M2DXMac ビルド成功 (BUILD SUCCEEDED)
- M2DXMac.app 起動完了
- log stream --predicate 'subsystem == "com.example.M2DX"' --level debug でリアルタイム監視開始
- テスト項目:
  1. Discovery 100ms遅延でM2DXが先にDiscovery Inquiry送信するか
  2. KeyStageがフルPEフロー（GET全リソース + Subscribe 4件）を走らせるか
  3. JSONSchema PE-Schemaデバッグログ（resIdの値）
  4. プログラム名表示
決定事項: KeyStage電源再起動待ち
次のTODO: KeyStage再起動 → ログ確認
---

---
2026-02-08 05:43
作業項目: JSONSchema resId パース問題のコード調査完了
追加機能の説明:
- MIDI2Kit ソースコード調査:
  - PERequestHeader (PEResponderResource.swift:14-46): resId は JSON キー "resId" から直接パース
  - PEResponder (PEResponder.swift:193-240): inquiry.resource でリソースルーティング → resources["JSONSchema"] ルックアップ
  - CIMessageParser+Inquiry.swift:65-94: parseFullPEGetInquiry でヘッダーJSON解析、resId = json["resId"]
  - CIMessageType (MIDICIConstants.swift:151): peGetInquiry = 0x34 正しくマッピング
- KORG公式仕様確認:
  - Keystage_PE_ResourceList v1.0: resId="parameterListSchema" / resId="programEditSchema"
  - KeyStageがGET JSONSchemaに {"resource":"JSONSchema","resId":"parameterListSchema"} を送信するはず
- 問題分析:
  - ワークログ 05:32: 「JSONSchemaが2回とも {} を返している」→ ハンドラは呼ばれたが default ケースに入った
  - PE_Implementation_Notes セクション3: ログで resId="" と記録 → resId が nil or 空文字列
  - M2DXの JSONSchema ハンドラ (MIDIInputManager.swift:759-771): switch resId で "parameterListSchema"/"programEditSchema" にマッチせず default → {}
- 仮説3つ:
  A) KeyStageは resId なしで {"resource":"JSONSchema"} のみ送信 → resId=nil → default ケース
  B) KeyStageは resId を送信しているが、JSONパース失敗でnilになっている
  C) 05:32のログはデバッグ版ビルドが反映前のもの（05:37で示唆）
- PE-Schema デバッグログ（MIDIInputManager.swift:757）が出力されれば原因確定
決定事項: log stream で PE-Schema: resId='...' raw=... を確認するのが最も確実
次のTODO: KeyStage再起動後の log stream で PE-Schema ログを確認 → resId の実値特定
---

---
2026-02-08 05:49
作業項目: MIDI2Kit ライブラリの invalidateMUID 関数とInvalidate MUID メッセージ実装の検索・調査
追加機能の説明:
- invalidateMUID 関数定義の特定と全シグネチャ取得:
  1. CIMessageBuilder.invalidateMUID() (static) — SysExメッセージ構築
  2. CIManager.invalidateMUID() (instance) — マネージャーシャットダウン時送信
  3. CIMessageParser.parseInvalidateMUID() (static) — Invalidate MUIDペイロード解析
- Invalidate MUID SysEx構造（0x7E sub-ID）:
  - F0 7E 7F 0D 7E 01 [srcMUID:4] [dstMUID:4] [targetMUID:4] F7
  - ciVersion=0x01 (CI 1.1)、broadcastMUID使用、targetMUIDで無効化対象指定
- MIDI2Kit MIDICIConstants で定義:
  - sysExNonRealtime = 0x7E (Universal SysEx Non-Realtime)
  - ciSubID1 = 0x0D (MIDI-CI Sub-ID #1)
  - CIMessageType.invalidateMUID = 0x7E (message type)
決定事項: invalidateMUID関数 2個＋パーサー 1個の計3個の実装が確定
次のTODO: 調査結果をユーザーに報告（ファイルパス・行番号含む）
---

---
2026-02-08 05:51
作業項目: log stream 解析 — PE GETフロー未発生、MUID不一致問題発見
追加機能の説明:
- log stream 解析結果（05:47:43〜05:48:23）:
  - KeyStage Discovery Inquiry → M2DXが登録（CI: Discovered KORG (361:9)）
  - ★問題発見: 全PE通信が MUID(0x1E204DF) 宛 — M2DX(0x5404629) ではない
    - Cap Inquiry (0x30) src=0x1FE8856 dst=0x1E204DF → rewrite → PEResponder処理
    - Cap Reply (0x31) src=0x1FE8856 dst=0x1E204DF → これはKeyStage→別デバイスの通信
    - GET Reply (0x35) ×2 src=0x1FE8856 dst=0x1E204DF → KeyStageのResourceListを別デバイスに返答
  - ★JSONSchema GET (0x34) がM2DXに一度も来ていない → ハンドラ未呼出
  - PC受信は正常: program=1(E.PIANO 1), program=2(BASS 1), program=3(BRASS 1) + PE Notify送信OK
- MUID(0x1E204DF) の正体:
  - M2DXのMUIDではない（0x5404629）
  - macOS上の別のMIDI-CIエンティティ、または前セッションのキャッシュ
  - M2DXはMUID rewriteで捕捉しているが、返信のsrcが0x5404629→KeyStageが無視
- MUID rewrite根本問題:
  - INBOUND: dst 0x1E204DF → 0x5404629 (rewrite OK)
  - OUTBOUND: PEResponder replies with src=0x5404629 ≠ 0x1E204DF (KeyStageが期待するsrc)
  - KeyStageはsrc不一致で返信を無視 → PEフロー停止
決定事項: JSONSchema調査はPEフロー確立が前提。MUID問題を先に解決する必要あり
次のTODO: Invalidate MUID送信 → KeyStage再起動 → クリーンPEフロー確立 → JSONSchema resId確認
---

---
2026-02-08 05:55
作業項目: ★フルPEフロー完走！Discovery再送信成功 + ハング原因追加特定
追加機能の説明:
- ★Discovery再送信ロジック成功:
  - KeyStageのDiscovery Inquiry(0x70)受信 → 200ms後にM2DXからDiscovery Inquiry送信
  - KeyStageがM2DXの実MUID(0x5404629)宛にDiscovery Reply → Cap Inquiry → 全GET + Subscribe
- ★フルPEフロー完走（sub-5~sub-8で4リソースSubscribe成功）:
  - GET: ResourceList(x2)→DeviceInfo→ChannelList→Sub(sub-5)→ProgramList→Sub(sub-6)
  →X-ParameterList→Sub(sub-7)→X-ProgramEdit→Sub(sub-8)→JSONSchema(x2)
- ★★JSONSchema resId判明: resId='' (空文字列)
  - KeyStageは {"resource":"JSONSchema","resId":""} で2回GETする
  - "parameterListSchema" でも "programEditSchema" でもない → 空文字列
  - ResourceListに schema 参照がないので KeyStage はどのスキーマか指定しない
- ★★ハング再発: X-ProgramEdit に name/bankPC フィールドを含めるとハング
  - 前回(05:16)は currentValues のみで成功 → name/bankPC が追加されていた
  - 修正: X-ProgramEdit GET Reply と PE Notify から name/bankPC を完全削除
  - currentValues のみの純粋なKORG公式仕様に戻した
- macOS MIDI-CI (0x1E204DF) は引き続き存在:
  - KeyStageは 0x1E204DF と M2DX(0x5404629) の両方にPEを実行
  - Discovery再送信で M2DX への PE フロー確立成功
決定事項:
- X-ProgramEdit: currentValues のみ（name/bankPC は禁止）
- JSONSchema: resId は空文字列 → 全スキーマをまとめて返すか、空で返すか検討
- Discovery再送信ロジック有効
次のTODO: currentValues のみで再テスト → ハング解消確認
---

---
2026-02-08 05:59
作業項目: ★currentValuesのみでもハング再発 — ハング原因はX-ProgramEditフォーマットではない可能性
追加機能の説明:
- テスト条件: currentValues のみ（name/bankPC削除済み）、M2DXMac再起動→KeyStage既起動
- PEフロー: 完全走破（GET全リソース + Sub-1~4 + JSONSchema x2）✓
- X-ProgramEdit body: {"currentValues":[...]} のみ ✓
- macOS MIDI-CI (0x1E204DF): 今回は非関与（M2DXのDiscoveryが先着）
- ★ハング再発:
  - 05:57:09 PEフロー完走
  - 05:57:17 PC program=1 + PE Notify送信
  - KeyStage LCD ハング（"000:i My" 表示 → 以前と同じ症状）
- ★新仮説: ハングの原因は X-ProgramEdit フォーマットだけではない可能性
  - M2DXMac終了時の stop()/Invalidate MUID が KeyStage を混乱させている？
  - macOSのMIDI-CI + M2DXの2重PE Responderが原因？
  - PEフロー完了後のPE Notifyが原因？
決定事項: 切り分けテスト必要 — M2DXMacなしでKeyStage再起動してハングするか確認
次のTODO: M2DXMac終了 → KeyStage再起動 → macOS MIDI-CI単体でのハング有無確認
---

---
2026-02-08 06:14
作業項目: セッション復帰 — PE Notify無効化ビルドの動作確認
追加機能の説明:
- 前セッションでPE Notify (0x3F) がKeyStageハングの原因と特定
- PE Notify完全無効化ビルドでM2DXMac再起動済み (PID 11620)
- PEフロー完全走破: GET(DeviceInfo, ChannelList, ProgramList, X-ParameterList, X-ProgramEdit) + Sub-1~4 ✓
- NoteOn/NoteOff UMP正常受信 (06:12:44~06:13:02)
- PC program=1 (E.PIANO 1) 受信 @ 06:13:13 → PE Notify DISABLED → KeyStageハングなし ✓
- ログは06:13:13以降出力なし → KeyStageは正常動作継続中と推定
決定事項:
- PE Notify無効化でKeyStageハング回避を確認（PC変更1回成功）
- PE Notifyのフォーマット/タイミング調査が次の課題
次のTODO:
- ユーザーにPCを複数回変更してもらいハングしないことを確認
- PE Notify (0x3F) のKORG対応フォーマット調査
- JSONSchema empty resId対応
---

---
2026-02-08 06:18
作業項目: ★PE Notify無効でもハング再発 — X-ProgramEdit自体がLCDハングの原因
追加機能の説明:
- ユーザー報告: PE Notify無効化ビルドでも KeyStage LCD が "000:INIT VOIC" 表示でハング
- NoteOn/NoteOff UMP は流れているが、LCD/PE系が固まっている
- 前回の5リソーステスト: 初回はLCD動作→2回目PCでハング (PE Notifyトリガー)
- 今回: PE Notify無効なのにLCDが初期PEフロー完了直後にハング
- ★新仮説: X-ProgramEdit Subscribe自体がハングの原因かもしれない
- 切り分けテスト: X-ProgramEdit canSubscribe=false + supportsSubscription=false に変更
- ResourceList: DeviceInfo, ChannelList(sub), ProgramList(sub), X-ParameterList(sub), X-ProgramEdit(sub なし)
- M2DXMac 再ビルド＆再起動 (PID 12354)
決定事項: X-ProgramEdit Subscribe vs GET Reply の切り分けテスト実施
次のTODO: KeyStage再起動してハング有無を確認
---

---
2026-02-08 06:27
作業項目: X-ProgramEdit canSubscribe=false でもハング再発 → GET Reply自体が原因と確定
追加機能の説明:
- テスト結果: X-ProgramEdit canSubscribe=false + supportsSubscription=false → 再起動直後ハング
- ★結論: X-ProgramEdit の GET Reply 内容自体がKeyStage LCDハングの原因
- 切り分け進捗:
  - 4リソース (X-ProgramEdit なし) → ハングしない ✓ (前回確認済み)
  - 5リソース (X-ProgramEdit canSubscribe=true) → ハング
  - 5リソース (X-ProgramEdit canSubscribe=false) → ハング
  - → GET Reply の currentValues フォーマットが問題
- 次のテスト: X-ProgramEditをResourceListから完全削除 (4リソース) で正常動作を再確認
- M2DXMac再ビルド＆再起動 (PID 13203)
決定事項: X-ProgramEdit GET Reply の currentValues 内容を修正する必要がある
次のTODO: KeyStage再起動 → 4リソースでハングしないことを再確認
---

---
2026-02-08 06:31
作業項目: 4リソーステスト — MIDI接続OK、PEフローなし、ハングなし
追加機能の説明:
- 4リソース構成 (X-ProgramEdit削除): DeviceInfo, ChannelList, ProgramList, X-ParameterList
- M2DXMac再起動 (PID 13450) → KeyStage起動後に接続
- NoteOn/NoteOff UMP正常受信、音出ている ✓
- PEフローのログなし — Discoveryタイミングの問題でPEフロー未確立
  - ただしKeyStageハングなし ✓ (PEフローなし=ハングしない)
- ★切り分け結論まとめ:
  - 4リソース (X-ProgramEditなし) → ハングしない ✓ (今回再確認)
  - 5リソース (X-ProgramEdit canSubscribe=false) → ハング
  - 5リソース (X-ProgramEdit canSubscribe=true) → ハング
  - → X-ProgramEdit GET Reply の currentValues が原因と確定
決定事項: X-ProgramEdit GET Reply の currentValues フォーマットを KORG spec に厳密合わせる必要あり
次のTODO: KORG spec の X-ProgramEdit currentValues を再確認 → フォーマット修正テスト
---

---
2026-02-08 06:34
作業項目: ★★★ 真のハング原因発見 — MUID rewrite による2重応答
追加機能の説明:
- 空currentValues `{"currentValues":[]}` でもハング → GET Reply内容は無関係
- ログ詳細分析で発見:
  - KeyStageは macOS MIDI-CI (0x1E204DF) と M2DX (0x5404629) の **両方** にPEを送信
  - MUID rewrite ロジックが 0x1E204DF 宛てメッセージを横取りして M2DX の PEResponder に転送
  - → KeyStageは **1つのCapability Inquiryに対して2つの応答** を受信（macOS entity + M2DX）
  - → KeyStageは **1つのGETに対して2つのReply** を受信
  - → PE状態機械が破綻してハング
- X-ProgramEdit Subscribe が **2回** 来ている (sub-8, sub-9) のも2重処理の証拠
- ★修正: MUID rewrite 完全廃止 → M2DX MUID (0x5404629) 宛て以外のPEメッセージは DROP
- ビルド成功、M2DXMac再起動 (PID 14266)
決定事項:
- MUID rewrite は2重応答を引き起こしKeyStageをハングさせる根本原因
- M2DX宛て(0x5404629)のメッセージのみ処理する
次のTODO: KeyStage再起動テスト — 5リソース構成でハングしないことを確認
---

---
2026-02-08 06:46
作業項目: MUID rewrite廃止ビルド — MIDI接続未確立でテスト不成立
追加機能の説明:
- M2DXMac再起動 (PID 15108) したが M2DX MIDI/PE ログが一切出ない
- KeyStage側がハング状態のまま → MIDI接続未確立
- ユーザー報告: ハングした（ただしPEフローは未発生 = 前セッションの影響の可能性）
- テスト不成立 — KeyStage電源OFF/ON後にクリーンな状態で再テスト必要
決定事項: KeyStageをクリーン再起動後にM2DXMacを再起動してテスト
次のTODO: KeyStage電源OFF→ON → M2DXMac再起動 → PEフロー確認
---

---
2026-02-08 06:46
作業項目: MUID rewrite廃止でもハング — DROPは正常動作だが根本原因は別
追加機能の説明:
- MUID rewrite廃止ビルドでPEフロー確認:
  - macOS MIDI-CI (0x1E204DF) 宛て: 全てDROP ✓
  - M2DX (0x5404629) 宛て: 正常処理 ✓
  - Subscribe: sub-5~sub-8 (各1回のみ、2重なし) ✓
  - X-ProgramEdit GET Reply: {"currentValues":[]} reply=58B ✓
- ★しかしKeyStageはハング
- → MUID rewrite 2重応答はハングの原因ではなかった
- → macOS MIDI-CI entity (0x1E204DF) 自体がKeyStageにX-ProgramEdit関連で何か返している可能性
- → M2DXのPE応答 (特にX-ProgramEdit) がハングの原因の可能性（依然として）
- M2DXMac終了 → KeyStage単体テストで切り分け
決定事項: M2DXMac終了後にKeyStage単体でハング有無を確認
次のTODO: KeyStage電源OFF→ON (M2DXMacなし) → ハング有無確認
---

---
2026-02-08 06:55
作業項目: ★4リソース + MUID DROP + PEフロー完走 → 正常動作確認
追加機能の説明:
- テスト構成: 4リソース (X-ProgramEditなし) + MUID DROP有効
- PEフロー完走: Discovery → Cap → GET全リソース → Sub(sub-4~sub-6) ✓
- macOS MIDI-CI (0x1E204DF) 宛て: 全DROP ✓ (sub=0x30, 0x31, 0x35 x2)
- KeyStage正常動作、ハングなし ✓
- M2DXMacなし → ハングなし ✓
- ★★★確定した切り分け結果:
  - 4リソース (PEフロー有) → 正常 ✓
  - 5リソース (X-ProgramEdit) → ハング (内容不問: 空配列でもハング)
  - M2DXなし → 正常 ✓
  - → X-ProgramEdit GET Reply (任意の内容) がKeyStageハングの直接原因
- 空currentValuesでもハング = 内容ではなくリソース応答自体が問題
- 仮説: macOS MIDI-CI entity との2重PE Responder環境で、
  片方だけがX-ProgramEditを持つことがKeyStageを混乱させる？
決定事項: X-ProgramEdit GET Reply を status 404 等のエラーで返すテスト
次のTODO: X-ProgramEdit GET → status 404 応答でハング回避できるか確認
---

---
2026-02-08 06:55
作業項目: macOS MIDI-CI entity の ResourceList 解析 + 方針決定
追加機能の説明:
- macOS entity (0x1E204DF) の PE Reply (sub=0x35) RAWデータ解析
  - ヘッダー: {"status":200}
  - ボディ: [{"resource":... (ResourceListの応答)
  - macOS entity も独自 ResourceList を KeyStage に返している
- ★2つの PE Responder が異なる ResourceList を返す問題:
  - macOS entity: 標準リソース (DeviceInfo等のみ、X-ProgramEditなし)
  - M2DX: 標準 + KORG独自 (X-ProgramEdit含む)
  - 4リソース (M2DXにX-ProgramEditなし) → 両者のResourceListが矛盾しない → 正常
  - 5リソース (M2DXにX-ProgramEditあり) → M2DXにだけ存在 → KeyStage混乱 → ハング
- ★★方針案: X-ProgramEdit を ResourceList から削除し、PE SET 受信のみ対応
  - KeyStage は PE SET で X-ProgramEdit bankPC を送信可能（ResourceList広告不要）
  - GET/Subscribe は不要（M2DXからpush通知する必要がない）
決定事項: 4リソース構成を正式版とし、X-ProgramEditはPE SET受信のみ対応する方針
次のTODO: 4リソース + PE SET X-ProgramEdit受信 構成で全機能テスト
---

---
2026-02-08 06:59
作業項目: ★★★ 4リソース構成でPC変更成功 — ハングなし！
追加機能の説明:
- PC変更テスト結果:
  - KeyStageは通常のMIDI Program Change (UMP st=12) でPC変更を送信 ✓
  - PE SET X-ProgramEdit ではない（ResourceListにないため）
  - program=9 (CLAV 1), program=8 (FLUTE 1), program=7 (HARPSICH 1) 受信成功
  - 複数回のPC変更でもKeyStageハングなし ✓
  - PE Notify は DISABLED のまま（将来的に除去可能 — 標準PCで来るため不要）
- ★重要発見: X-ProgramEdit が ResourceList にない場合、KeyStage は標準 MIDI PC メッセージを使う
  - PE SET X-ProgramEdit は KORG 製品間の独自プロトコル
  - 標準 MIDI PC で十分 → X-ProgramEdit は ResourceList に含める必要なし
決定事項: 4リソース構成を正式版として確定。PC変更は標準MIDIメッセージで動作。
次のTODO: PE Notify コード除去、コード整理、iOS実機ビルド準備
---

---
2026-02-08 07:07
作業項目: PE Notify無効化 + X-ProgramEdit ComputedResource削除 + コード整理
追加機能の説明:
- ChannelList PE Notify が macOS dual-PE-Responder 環境で KeyStage を部分ハングさせる問題確認済み
  - 初回表示は "000:INIT VOIC" で正常、PC変更後にLCD更新されず、その後PC送信不可
  - 原因: macOS MIDI-CI entity (0x1E204DF) と M2DX の2つの PE Responder が同時にNotifyを送る
- 対応: notifyProgramChange() から PE Notify コード完全除去
  - PC ログ記録と currentProgramIndex 更新のみ残す
  - KeyStage は標準 MIDI PC (UMP st=12) でプログラム変更するため Notify 不要
- X-ProgramEdit ComputedResource 登録を完全削除
  - ResourceList に含まれておらず、KeyStage は PE SET を送らない（標準 MIDI PC を使用）
  - 不要コードの除去によりコード量削減
- ResourceList: 4リソース (DeviceInfo, ChannelList, ProgramList, X-ParameterList) に確定
- コメント整理: X-ProgramEdit 関連の古いコメントを更新
決定事項: PE Notify完全無効化、X-ProgramEdit削除、4リソース構成を正式版として確定
次のTODO: M2DXMac再起動してKeyStageとの動作確認、iOS実機ビルド
---

---
2026-02-08 07:13
作業項目: ★ 4リソース + PE Notify無効 構成でKeyStage動作確認 — 問題なし
追加機能の説明:
- M2DXMac PID 18298 再起動後、KeyStageと接続確認
- NoteOn/NoteOff (UMP mt=4 st=9/8) 正常受信
- KeyStage ハングなし ✓
- ユーザー確認: 「問題なし」
- ★確定構成:
  - ResourceList: 4リソース (DeviceInfo, ChannelList, ProgramList, X-ParameterList)
  - PE Notify: 完全無効
  - X-ProgramEdit: ComputedResource登録も削除済み
  - MUID DROP: 有効（macOS entity宛メッセージは破棄）
  - PC変更: 標準 MIDI Program Change (UMP st=12) で動作
決定事項: 4リソース + PE Notify無効 構成が安定動作することを最終確認
次のTODO: iOS実機ビルド、コード最終整理
---

---
2026-02-08 07:15
作業項目: TODO.md 確認・現状整理
追加機能の説明:
- ユーザーから現在のTODO確認依頼
- TODO.md が今日の調査結果（PE Notify無効化、X-ProgramEdit削除、4リソース確定）を反映していない
- TODO.md 更新が必要
決定事項: TODO.md を今日の成果を反映して更新する
次のTODO: TODO.md 更新
---

---
2026-02-08 07:17
作業項目: ★最優先タスク再確認 — KeyStage LCD にプログラム名を表示させる
追加機能の説明:
- ユーザーから最優先項目の明確化: 「PC時にKeyStageにM2DXのプログラム名を反映させる」
- ★重要な気づき: PE Notifyハングは macOS dual-PE-Responder 環境固有の問題
  - macOS: M2DX + macOS MIDI-CI entity (0x1E204DF) = 2つの PE Responder → ハング
  - iOS: M2DX のみ = 1つの PE Responder → Notify が正常動作する可能性が高い
- 方針案: iOS実機ビルドで PE Notify + X-ProgramEdit (5リソース) を有効化してテスト
  - ChannelList PE Notify 再有効化 (programTitle更新)
  - X-ProgramEdit を ResourceList に復活 (5リソース構成)
  - iOS実機にデプロイしてKeyStage接続テスト
決定事項: iOS実機でPE Notify有効化テストを行う方針（macOS問題はiOSには影響しない仮説）
次のTODO: ユーザー確認後、iOS実機向けにPE Notify再有効化 + ビルド
---

---
2026-02-08 07:19
作業項目: MIDI2Kit PEResponder.notify メソッド実装調査開始
追加機能の説明: PEResponder.notify(resource:data:) の実装詳細 + Subscription管理メカニズムを調査
決定事項: M2DX iOS向けのPE Notify再有効化を検討するため、MIDI2KitのPEResponder実装を深掘り
次のTODO: PEResponder.swift, Subscription管理ファイル, notify送信フロー調査
---

---
2026-02-08 07:19
作業項目: MIDI2Kit PEResponder.notify 実装調査完了 + macOS環境でのデバッグ方針
追加機能の説明:
- ★ユーザー指摘: iOSはログ取得に限界があるのでmacOSで検証している
  - iOS移行は解決策ではない。macOSで問題を解決する必要がある
- PEResponder.notify() の実装詳細:
  - subscriptions辞書からresource名で一致するsubscriptionを検索
  - 各subscriberに対してJSON header {"subscribeId":"sub-N","resource":"ResourceName"} を生成
  - CIMessageBuilder.peNotify() で SysEx メッセージ (0x3F) を構築
  - sendReply() で initiatorMUID 宛に送信
  - requestID は常に 0
- ★重要: Notifyは M2DX→KeyStage の送信。macOS entityのDROPとは無関係。
  - ChannelList Notifyハングは macOS entity問題ではなく、Notify自体のフォーマット/タイミング問題の可能性
- ★検証方針（macOS環境で）:
  1. PE Subscribe (0x38) フローが正しく完了しているか確認
  2. Notify送信時の実際のバイト列をログで確認
  3. Notify タイミング (50ms→もっと長く？) を変更して検証
  4. ChannelList Notify のJSON body フォーマットが KORG spec に合っているか確認
決定事項: macOS環境でNotifyデバッグを継続。Notify送信内容のワイヤレベル検証が必要
次のTODO: ChannelList Notify再有効化 + 詳細ログ付きでmacOSテスト
---

---
2026-02-08 07:26
作業項目: ChannelList Notify デバッグ — 送信OK/LCD反映なし/ハングなし
追加機能の説明:
- ★★★ 大きな進歩: ChannelList Notify (500ms debounce) でハングしない！
  - PC変更: E.PIANO 1, BASS 1, BRASS 1, STRINGS 1 — 全て送信成功
  - ハングゼロ — 前回テスト時 (50ms) はハングした → 500ms で安定
- 問題: LCD に programTitle が反映されない
- PEフロー正常完了:
  - Subscribe ChannelList → sub-4 ✓
  - Subscribe ProgramList → sub-5 ✓
  - Subscribe X-ParameterList → sub-6 ✓
- Notify 送信ログ: PE-Notify: ChannelList sent OK（複数回確認）
- ★仮説: Notify ヘッダーに "command":"notify" フィールドが不足
  - 現行: {"subscribeId":"sub-4","resource":"ChannelList"}
  - MIDI-CI PE仕様: "command":"notify" が必要な可能性
- 対応: MIDI2Kit CIMessageBuilder+Reply.swift の notifyHeader に "command":"notify" を追加
  - 変更: {"subscribeId":"sub-4","resource":"ChannelList","command":"notify"}
決定事項: Notify ヘッダーに command:notify を追加してテスト
次のTODO: M2DXMac再起動 → KeyStage再起動 → PC変更でLCD表示確認
---

---
2026-02-08 07:30
作業項目: Notify command:notify テスト → LCD反映なし + X-ProgramEdit 必要性の分析
追加機能の説明:
- command:notify ヘッダー追加: LCD反映なし、ハングなし
- ★★ 重要な仮説: KeyStage LCD は X-ProgramEdit の name フィールドで更新する
  - PE_Implementation_Notes.md 記載:
    - Program Change時に ChannelList Notify (programTitle更新) と X-ProgramEdit Notify (name/bankPC更新) の両方送信
    - KeyStage LCD のプログラム名は X-ProgramEdit.name から取得している可能性が高い
    - ChannelList.programTitle は補助情報（初期表示のみ？）
- PEResponder sendReply の配送確認:
  - replyDestinations 未設定 → broadcast で全destination に送信
  - Subscribe Reply は broadcast でも正常に KeyStage に届いている（PEフロー完走）
  - → Notify も broadcast で届いているはず → 問題はフォーマットではなく表示リソースの違い
- 方針: X-ProgramEdit を ResourceList に戻す（5リソース）
  - 前回のハングは 50ms delay + command:notify なし + MUID rewrite問題が複合していた
  - 現在: MUID DROP有効 + 500ms delay + command:notify → ハングリスクが大幅に低下
  - X-ProgramEdit Notify で name + bankPC を送信すれば LCD 更新される可能性
決定事項: X-ProgramEdit を ResourceList に復活（5リソース）+ X-ProgramEdit Notify を追加してテスト
次のTODO: ResourceList 5リソース化 + X-ProgramEdit Notify 実装 + ビルド
---

---
2026-02-08 07:38
作業項目: ★KeyStage写真確認 + 昨日のスニッファー結果再確認
追加機能の説明:
- ★KeyStage LCD写真(IMG_4624.HEIC)確認:
  - メインLCD: "000:INIT VOIC" 表示 ← ChannelList GET成功の証拠
  - ノブ下OLED: "Mod Wheel", "Volume", "Expression", "Sustain", "Brightness" 表示
  - ★★ X-ParameterList のCC名がKeyStageに正しく反映されている！
  - → PEフロー（GET + Subscribe）は完全に成功している
  - → 問題は PC変更後のNotifyによるLCD更新のみ
- ★昨日のスニッファー結果（2026-02-07 ClaudeWorklog）:
  - KORG Module Pro ↔ KeyStage 通信を傍受
  - KeyStageはX-ProgramEditをSubscribe (command:start) している
  - KeyStageはChannelList, ProgramList, X-ParameterList, X-ProgramEdit 全てSubscribe
  - X-ProgramEdit の KORG公式仕様:
    - currentValues形式必須（フィールド不在でハング）
    - "name"フィールドでプログラム名表示
  - ★★結論: KeyStage LCD更新には X-ProgramEdit Notify の name フィールドが必要
- 現在のビルド (PID 21331): 5リソース + X-ProgramEdit Notify 実装済み
  - KeyStage再起動前の時点でCC名表示に成功（前のビルドの4リソースで接続中）
決定事項: 5リソース構成 + X-ProgramEdit Notify でテスト（KeyStage再起動が必要）
次のTODO: KeyStage OFF→ON → 5リソースでPEフロー確認 → PC変更でLCD更新テスト
---

---
2026-02-08 07:45
作業項目: 5リソース + X-ProgramEdit Notify テスト → 部分ハング確認 → X-ProgramEdit Notify無効化
追加機能の説明:
- ★5リソース PEフロー完全成功:
  - ResourceList(5) → DeviceInfo → ChannelList → Sub(ChannelList=sub-5)
  - → ProgramList → Sub(ProgramList=sub-6)
  - → X-ParameterList → Sub(X-ParameterList=sub-7)
  - → X-ProgramEdit GET → name="E.PIANO 1" currentValues OK → Sub(X-ProgramEdit=sub-8)
  - ★全8ステップ完走！ 5リソースでもPEフロー自体は問題なし
- ★部分ハング再発:
  - PC送信後、X-ProgramEdit Notify送信 → KeyStageがPC送信不可に
  - NoteOn/NoteOffは引き続き動作（MIDI接続自体は生きている）
  - LCD表示直後にハング
- ★切り分け結果:
  | 構成 | Notify | 結果 |
  |------|--------|------|
  | 4リソース | ChannelList Notify (500ms) | ハングなし ✓ |
  | 5リソース | ChannelList + X-ProgramEdit Notify | 部分ハング ✗ |
  | → X-ProgramEdit Notify が原因 |
- 対策: 5リソース維持 + X-ProgramEdit Notify だけ無効化
  - X-ProgramEdit GET応答は維持（初回LCD表示のため）
  - ChannelList Notify のみ送信（PC変更時）
決定事項: X-ProgramEdit Notifyが部分ハングの原因。GET応答のみ残し、Notify無効化
次のTODO: KeyStage再起動 → 5リソース + ChannelList Notifyのみ でPC動作確認
---

---
2026-02-08 07:51
作業項目: セッション継続 — MIDI接続確認とログストリーム再開
追加機能の説明:
- 前セッションからの継続: M2DXMac PID 23127再起動済み、MIDI接続未確認状態
- ユーザーはCLAV 1をM2DXで選択後、KeyStage起動したが「MIDI接続されてない」と報告
- 5リソース + ChannelList Notifyのみ構成のテスト中
- M2DXMac再起動が必要な可能性あり
決定事項: 前セッションの状態を引き継ぎ、MIDI接続確認から再開
次のTODO: M2DXMacプロセス確認 → ログストリーム開始 → MIDI接続状態チェック
---

---
2026-02-08 07:56
作業項目: PC送信テスト結果 — ChannelList Notifyも部分ハングを引き起こす
追加機能の説明:
- M2DXMac PID 23460 起動、5リソースPEフロー完走 (sub-1~sub-4)
- 初回LCD表示: 「INIT VOIC」 ← X-ProgramEdit GET name="INIT VOICE" から
- PC#1送信: UMP 0x40C00001 → program=1 "E.PIANO 1" → M2DX受信OK
- ChannelList Notify送信 (500ms後): programTitle="E.PIANO 1" → sent OK
- 結果: **LCDは「INIT VOIC」のまま変化なし** ← ChannelList NotifyではLCD更新されない
- PC後にNoteOnは動作（st=9/st=8 確認）
- PC#2送信試行: **M2DXにUMP PC到着なし** ← KeyStageがPC送信不可に
- ★★ ChannelList Notify も部分ハング（PC不可、NoteOn可）を引き起こしている
- 前回「ChannelList Notifyでハングなし」と報告されたが、PC再送テストはしていなかった可能性
- PE_Implementation_Notes分析:
  - KORG Module Pro ↔ KeyStage スニッファー: PC時にChannelList + X-ProgramEdit 両方のNotify送信
  - X-ProgramEdit name フィールドがLCD表示を制御
  - currentValues フィールドが必須（不在でハング）
  - しかしX-ProgramEdit Notifyもハング。ChannelList Notifyもハング。
決定事項: PE Notify自体がKeyStageの部分ハングを引き起こす根本問題がある
次のTODO: Notifyフォーマットの詳細比較（M2DX vs KORG Module）/ macOS entity干渉の可能性調査
---

---
2026-02-08 08:06
作業項目: ★★★ PE Notify sub-ID2修正 (0x3F→0x38) — LCD表示更新成功！
追加機能の説明:
- ★根本原因特定: KORG KeyStage MIDI Implementation に 0x3F (PE Notify) が存在しない
  - KeyStage は MIDI-CI PE v1.1 準拠: 0x38(Subscription) + 0x39(Reply) のみ
  - 0x3F は CI v1.2+ の Notify メッセージで、KeyStage未対応
  - M2DXが 0x3F で送信 → KeyStageが未知メッセージとして処理 → 部分ハング
- ★修正: CIMessageBuilder+Reply.swift peNotify() の sub-ID2 を 0x3F → 0x38 に変更
  - MIDI-CI PE v1.1 仕様: Subscription通知は 0x38 + command:notify ヘッダーで送信
- ★結果: LCD表示が変わった！ X-ProgramEdit Notify で "E.PIANO 1" がLCDに反映
- 新たな問題: KeyStageが 0x39 (Reply to Subscription) を大量に返送
  - M2DXの0x38 Notifyに対して、KeyStageが「Subscriptionリクエスト」と解釈してReply返送
  - 08:04:46〜08:05:45 に sub=0x39 が多数到着（各Notify毎に2個ずつ）
  - Notify後も2回目のPCは受信できている（ハングではない）
  - ただし表示更新が遅い
- macOS entity (MUID 0x11A6109) もPEフロー走行: sub-1~sub-4
- KeyStage (MUID 0xB76CFA4) がメインPEフロー: sub-5~sub-8
決定事項: 0x3F→0x38修正でLCD更新成功。Subscribe Reply大量返送の処理が次の課題
次のTODO: Subscribe Reply (0x39) 受信時の処理確認 / macOS entityのSubscription重複問題対応
---

---
2026-02-08 08:11
作業項目: macOS entity除外 + 0x39フィルタ + command:notify無視 実装
追加機能の説明:
- PEResponder.swift 修正:
  1. handlePESubscribeInquiry: command:"notify" ケース追加 → break（無視）
     - 自分が送った0x38 Notifyがエコーバックされた場合、error replyを返さない
  2. notify(): excludeMUIDs パラメータ追加
     - 除外MUIDセットに含まれるSubscriberにはNotify送信しない
  3. subscriberMUIDs(): 新メソッド — 全Subscriber MUIDのSetを返す
- MIDIInputManager.swift 修正:
  1. notifyProgramChange: discoveredPEDevices（KORG KeyStage）のMUIDのみにNotify送信
     - discoveredPEDevicesに含まれないMUID（macOS entity）を自動除外
  2. 受信0x39 (Subscribe Reply) をPEResponderに渡さずドロップ
     - KeyStageがNotifyに対して返すAck応答を無視
- ビルド成功、M2DXMac PID 25740 起動済み
決定事項: macOS entity除外でNotify送信数半減、0x39フィルタで不要な応答処理を排除
次のTODO: KeyStage再起動 → PCテスト → LCD更新 + ハングなし + 連続PC動作確認
---

---
2026-02-08 08:28
作業項目: ★★★★★ KeyStage LCD プログラム名表示 完全成功 — 連続20+ PC ハングなし
追加機能の説明:
- ★最終テスト結果（KeyStage再起動後、M2DXMac PID 25740）:
  - 20回以上の連続PC変更: E.PIANO 1, CLAV 1, BASS 1, E.ORGAN 1, MARIMBA, FLUTE 1 等
  - **全てハングなし** ✓ — 連続PC動作が完全に安定
  - **LCD更新成功** — X-ProgramEdit Notify (0x38 + command:notify) でプログラム名反映
  - KeyStage 0x39 (Subscribe Reply) 正しくフィルタ: "PE: ignoring Subscribe Reply (0x39)"
  - macOS entity 除外: discoveredPEDevicesのみにNotify送信
- ★修正内容まとめ（本日の全修正）:
  1. CIMessageBuilder+Reply.swift: PE Notify sub-ID2 を 0x3F → 0x38 に変更（CI v1.1準拠）
  2. PEResponder.swift: command:"notify" 無視 / excludeMUIDs / subscriberMUIDs()
  3. MIDIInputManager.swift: macOS entity除外ロジック / 0x39フィルタ
- ★根本原因: KORG KeyStage は MIDI-CI PE v1.1 準拠で 0x3F (PE Notify) 未対応
  - 0x38 (Subscription) + command:notify ヘッダーが正しいNotify方式
  - 0x3F送信 → KeyStageが未知メッセージとして部分ハング（PC不可、NoteOn可）
決定事項: KeyStage LCDプログラム名表示の最優先タスク完了。macOS環境での安定動作確認済み
次のTODO: iOS実機ビルド / コード整理・コミット / TODO.md更新
---

---
2026-02-08 08:30
作業項目: iOS実機ビルド成功 (BUILD SUCCEEDED)
追加機能の説明:
- M2DX iOS実機向けビルド成功 — PE Notify 0x38修正 + macOS entity除外 + 0x39フィルタ含む
- 全修正（監査修正13件 + PE Notify修正3ファイル）がiOS実機ビルドに含まれる
決定事項: iOS実機ビルド成功確認
次のTODO: コード整理・コミット / TODO.md更新
---
---
2026-02-08 08:32
作業項目: コードレビュー & ドキュメントライター起動
追加機能の説明:
- ユーザー依頼: 現在のM2DXコードベースに対してコードレビュー + ドキュメント作成
- code-reviewer エージェントとdocument-writer エージェントを並列起動
- 対象: M2DXPackage/Sources/M2DXFeature/ の変更ファイル群
決定事項: コードレビューとドキュメント作成を並行で実施
次のTODO: レビュー結果とドキュメントを確認・反映
---

---
2026-02-08 08:33
作業項目: M2DXプロジェクト全コードレビュー実施
追加機能の説明:
- M2DXPackage/Sources/M2DXFeature/ の主要6ファイルを詳細レビュー
- 観点: コード品質、Swift Concurrency、エラーハンドリング、メモリ管理、MIDI/音声パフォーマンス、セキュリティ
- PE Notify 0x38修正（CI v1.1準拠）後のコードベースを対象
- レビュー結果を docs/code-review-20260208.md に出力
決定事項: 包括的コードレビューを実施し、改善提案を提供
次のTODO: レビュー結果確認 → 改善実施判断
---
---
2026-02-08 08:33
作業項目: M2DXプロジェクトドキュメント更新（TODO/CHANGELOG/PE実装ノート）
追加機能の説明:
- docs/TODO.md: 本日の成果（PE Notify 0x38修正・LCD表示成功）を反映、完了項目チェック
- docs/CHANGELOG.md: 本日の変更（PE v1.1準拠・macOS entity除外・0x39フィルタ）をエントリ追加
- docs/PE_Implementation_Notes.md: 0x3F→0x38修正の技術的詳細を追記
決定事項: 既存内容は消さず追記・更新のみ実施
次のTODO: ドキュメント更新後、コミット判断
---
---
2026-02-08 08:37
作業項目: M2DXドキュメント更新完了（TODO/CHANGELOG/PE実装ノート）
追加機能の説明:
- ★docs/TODO.md 更新完了:
  - 次回最優先タスク2件を完了チェック（macOS版作成・PE/CI検証）
  - 検証タスク3件を完了チェック（音色切替・LCD表示・PE Notify反映）
  - 完了セクションに本日の4件追加（PE Notify 0x38・LCD表示・macOS entity除外・0x39フィルタ）
- ★docs/CHANGELOG.md 更新完了:
  - [Unreleased] セクションにmacOS entity除外・0x39フィルタを追加
  - Fixed セクションに「KORG KeyStage LCD プログラム名表示問題を完全解決」を追加
  - PE Notify 0x3F→0x38修正・currentValues形式修正・ハング解決・デバッグ環境確立を記載
- ★docs/PE_Implementation_Notes.md 更新完了:
  - セクション15追加: PE Notify sub-ID2修正（0x3F→0x38）の詳細ドキュメント
  - 問題の経緯・症状・根本原因（CI v1.1/v1.2互換性）を詳述
  - MIDI2Kit 3ファイルの修正内容をコードブロック付きで記載
  - テスト結果（連続20+PC、ハングなし、LCD更新成功）を記録
  - 教訓4項目: CI互換性・仕様オプション・macOS特有問題・0x39扱い
  - セクション16更新: Phase 8追加
  - セクション17更新: 現状を2026-02-08時点に更新
決定事項: 全ドキュメントが本日の成果を正確に反映。既存内容は全て保持。
次のTODO: コミット判断・iOS実機テスト
---
---
2026-02-08 08:39
作業項目: コードレビュー & ドキュメント更新 完了
追加機能の説明:
- ★コードレビュー完了 → docs/code-review-20260208.md 作成
  - 致命的問題なし。Warning 3件、Suggestion 8件、Nitpick 4件
  - Swift 6 Concurrency完全準拠、MIDI-CI PE v1.1実装、リアルタイム最適化が高評価
  - 最優先改善: PE Notify debounce実装、Configuration Change再入ガード、macOS entity DROPログ強化
- ★ドキュメント更新完了:
  - docs/TODO.md — PE Notify修正・LCD表示成功を完了チェック
  - docs/CHANGELOG.md — 2026-02-08の変更エントリ追加（0x3F→0x38修正、macOS entity除外等）
  - docs/PE_Implementation_Notes.md — セクション15追加（sub-ID2修正の技術詳細）、セクション16/17更新
決定事項: コードレビュー・ドキュメント更新完了。レビュー指摘の改善は次ステップ
次のTODO: レビュー指摘（debounce実装、再入ガード）の対応 / コミット
---

---
2026-02-08 08:45
作業項目: MIDI2Logger プロトコル & NullMIDI2Logger 実装確認
追加機能の説明:
- MIDI2Kit codebase で MIDI2Logger protocol と NullMIDI2Logger の定義を特定
- CIManager, PEManager の logger パラメータ宣言を確認
- コード上の使用パターンをドキュメント化
決定事項: MIDI2Logger protocol定義と NullMIDI2Logger実装を把握完了
次のTODO: MIDI2Logger統合の検討
---

---
2026-02-08 08:45
作業項目: PE実装問題 → MIDI2Kit吸収計画の実装開始（4フェーズ）
追加機能の説明:
- Phase 1: PEResponder.swift に MIDI2Logger プロトコル注入（print()→logger.debug/info()統一、peRespLog削除）
- Phase 2: handleMessage() に .peSubscribeReply (0x39) 明示ケース追加（default暗黙無視→明示DROP）
- Phase 3: MUID mismatch ログを logger.debug() に統一
- Phase 4: MIDIInputManager.swift の重複フィルタ（行429-451のMUID DROP + 0x39フィルタ）を削除、PEResponder初期化時にlogger渡し
決定事項:
- MIDI2Logger は MIDI2Core モジュールに定義済み → MIDI2PE から直接アクセス可能
- PEManager パターン準拠: init(logger: any MIDI2Logger = NullMIDI2Logger())
- excludeMUIDs/subscriberMUIDs/logCallback はアプリ側に残す（計画通り）
次のTODO: Phase 1 から順に実装開始
---

---
2026-02-08 08:57
作業項目: PEリファクタリング コードレビュー完了
追加機能の説明:
- ★PEResponder.swift + MIDIInputManager.swift のリファクタリング詳細レビュー実施
- レビュー対象:
  1. PEResponder.swift 全体 — logger注入、print()→logger置換、0x39明示ケース追加
  2. MIDIInputManager.swift 422-460行 — 重複MUID/0x39フィルタ削除、logger渡し
- レビュー結果: **Critical 0件、Warning 0件、Suggestion 2件**
  - 🔵 Suggestion 1: logger初期化パターン統一 (Optional+nil-coalescing → 非Optional+デフォルト引数)
  - 🔵 Suggestion 2: 0x39ログレベル検討 (正常フローなのでログ削除 or #if DEBUG)
- 正しく実装された点 6項目:
  ✅ 挙動完全保持 (MUID/0x39フィルタが重複なく動作)
  ✅ API一貫性 (PEManager パターンにほぼ準拠)
  ✅ スレッド安全性 (Swift 6 Concurrency完全準拠)
  ✅ print()完全削除、peRespLog完全削除
  ✅ Breaking Change影響なし (デフォルト引数で後方互換)
  ✅ RT Safety問題なし (Audio Thread とは無関係)
- 良かった点 4項目:
  🎯 単一責任原則の徹底 (MIDIInputManager→PEResponderへ責務移管)
  🎯 ログ一元化 (category="PE-Resp")
  🎯 明示的プロトコル処理 (0x39が暗黙→明示)
  🎯 テスト容易性向上 (logger注入可能)
- 総評: **教科書的品質のリファクタリング。このままコミット可能。**
- レビューレポート保存: docs/code-review-20260208-pe-refactoring.md (324行)
決定事項: Suggestion 2件は機能影響なし。このままコミット可能と判断
次のTODO: (ユーザーの判断待ち) コミット or Suggestion対応 or iOS実機テスト
---

---
2026-02-08 08:53
作業項目: PEリファクタリング コードレビュー実施
追加機能の説明:
- PEResponder.swift + MIDIInputManager.swift の変更を詳細レビュー
- Critical: 0件、Warning: 0件、Suggestion: 2件（機能影響なし）
- Suggestion 1: logger初期化パターン統一（(any MIDI2Logger)? = nil → any MIDI2Logger = NullMIDI2Logger()）
- Suggestion 2: 0x39ログレベル検討（本番ノイズ削減）
- 正しく実装された点: 挙動完全保持、API設計一貫性、Actor安全性、print()完全置換、Breaking Changes無し、RT Safety問題なし
決定事項: このままコミット可能。Suggestion 2件は任意対応。
次のTODO: Suggestion対応判断 → コミット
---

---
2026-02-08 09:01
作業項目: Suggestion 1 対応 + コミット完了
追加機能の説明:
- Suggestion 1 適用: PEResponder init の logger パラメータを PEManager パターンに統一
  - Before: `logger: (any MIDI2Logger)? = nil` + `?? NullMIDI2Logger()`
  - After: `logger: any MIDI2Logger = NullMIDI2Logger()`
- MIDI2Kit コミット: `50b2d4f` — Inject MIDI2Logger into PEResponder, add explicit 0x39 handling
- M2DX コミット: `900bb13` — Remove duplicate PE filters, delegate MUID/0x39 handling to PEResponder
- 両リポジトリビルド成功確認済み
決定事項: 2リポジトリにそれぞれコミット完了。pushはユーザー判断。
次のTODO: 実機テスト / 残りのドキュメント更新コミット判断
---

---
2026-02-08 09:09
作業項目: M2DXプロジェクト リファクタリング分析（編集なし）
追加機能の説明:
- 対象: M2DXFeature/ (SwiftUI/Actor/MV) + PEResponder.swift
- 観点: 責務分離、デッドコード、重複、Concurrency、エラーハンドリング、RT Safety
決定事項: 分析開始
次のTODO: コードベース読み込み → 分析レポート作成
---

---
2026-02-08 09:10
作業項目: M2DXコードベース リファクタリング分析 完了
追加機能の説明:
- MIDIInputManager.swift (1146行)、M2DXAudioEngine.swift (525行)、FMSynthEngine.swift (785行)、M2DXFeature.swift (460行)、MIDIEventQueue.swift (82行)、PEResponder.swift (568行) を精査
- 責務分離・デッドコード・重複・Concurrency・エラーハンドリング・RT Safetyの6観点で分析
- レポート作成: docs/refactoring-20260208.md
決定事項: 分析完了。改善提案を含むレポートを出力
次のTODO: ユーザーがレポートを確認 → 優先度判断
---

---
2026-02-08 09:09
作業項目: M2DXプロジェクト リファクタリング分析
追加機能の説明:
- 6ファイル(MIDIInputManager 1146行, M2DXAudioEngine 525行, FMSynthEngine 785行等)を分析
- 致命的問題: 0件
- 重要な改善推奨: 1件（MIDIInputManager 責務分割 → 5ファイル化）
- 中程度の改善: 3件（Sniffer削除、ログ重複、再入ガード）
- 軽微な改善: 2件
- RT Safety / Swift 6 Concurrency: 教科書的品質で問題なし
- 詳細レポート: docs/refactoring-20260208.md
決定事項: Phase 1（Sniffer削除・未使用プロパティ削除）から段階的に実施可能
次のTODO: ユーザー判断 → Phase 1 実施 or MIDIInputManager分割計画
---

---
2026-02-08 09:16
作業項目: リファクタリング全3フェーズ実装開始
追加機能の説明:
- Phase 1: peSnifferMode を #if DEBUG 囲い、未使用プロパティ(debugConnectedCount, acceptedOldMUIDs)削除、@unchecked Sendableコメント追加
- Phase 2: MIDIInputManager分割 — appendDebugLogのログ統一化、Configuration Change再入ガード強化
- Phase 3: 軽微な改善
決定事項: 全3フェーズ一括実施。MIDIInputManager分割は大規模すぎるため、まず責務ごとのextension分離から段階的に進める
次のTODO: Phase 1 実装開始
---

---
2026-02-08 09:19
作業項目: リファクタリング Phase 1-3 実装再開（前セッション中断分）
追加機能の説明:
- Task #6 (in_progress): peSnifferMode #if DEBUG化の残り — snifferブロック(行383-405) + ciSubID2Name/parseCIHeader ラップ
- Task #7: 未使用プロパティ削除 (debugConnectedCount, acceptedOldMUIDs)
- Task #8: @unchecked Sendable コメント追加
- Task #9: Configuration Change 再入ガード強化
- Task #10: appendDebugLog ログ統一
- Task #11: ビルド検証 + コミット
決定事項: 前セッションの状態を確認、Task #6から再開
次のTODO: sniffer受信ループブロックと sniffer-only ヘルパーを #if DEBUG で囲う
---

---
2026-02-08 09:22
作業項目: リファクタリング Phase 1-3 全タスク完了 + ビルド成功
追加機能の説明:
- Task #6: peSnifferMode #if DEBUG化 — プロパティ、start()、受信ループ、ciSubID2Name/parseCIHeader全てラップ
- Task #7: acceptedOldMUIDs 削除（初期化+リセットのみで読み取りなし）。debugConnectedCountはUI使用のため残置
- Task #8: BufferMIDI2Logger @unchecked Sendable 安全性コメント追加
- Task #9: handleConfigurationChange の isRestarting → restartTask パターンに変更（cancel+replace、100msデバウンス）
- Task #10: appendDebugLog のPE/CI/SNIFF分岐を統一（peFlowLog.append重複解消）
- Task #11: iOS実機ビルド BUILD SUCCEEDED（warningのみ、errorなし）
決定事項:
- Swift #if/#else/#endifはif/else分岐内に置けないため、snifferActiveローカル変数パターンで対応
- debugConnectedCountはSettingsView.swiftで使用中のため削除対象外
次のTODO: コミット
---

---
2026-02-08 11:27
作業項目: USB版KeyStage LCD プログラム名非表示の原因調査
追加機能の説明:
- PEResponder.notify() → sendReply() → transport.broadcast() のフロー追跡
- broadcast()はMIDISend()（レガシーMIDI 1.0 API）を使用（CoreMIDITransport.swift:367）
- USB MIDI 2.0デバイス（KeyStage）にはMIDI 1.0 SysExが正しく届かない可能性
- sendSysEx7AsUMP()メソッド（UMP type 0x3）が存在するがbroadcast経路では使われていない
- M2DXはPEResponder.setReplyDestinations()を一度も呼んでいない → broadcast経路のみ
- PEResponder.sendReply()には targeted（replyDestinations設定時→UMP送信）とbroadcast（未設定時→レガシー送信）の2経路がある
決定事項:
- 原因: PE NotifyがレガシーMIDI 1.0 APIで送信されているため、USB MIDI 2.0接続のKeyStageに届いていない
- 対策: MIDIInputManagerでdiscoveredPEDevicesからKeyStageのdestinationIDを取得し、PEResponder.setReplyDestinations()に設定する
次のTODO: replyDestinations設定の実装
---

---
2026-02-08 11:32
作業項目: USB版KeyStage LCD プログラム名非表示の修正
追加機能の説明:
- 原因特定: PE NotifyがCoreMIDITransport.broadcast()経由でMIDISend()（MIDI 1.0レガシーAPI）で送信されていた
  - USB MIDI 2.0接続のKeyStageにはMIDI 1.0 SysExが正しく届かない
  - PEResponder.sendReply()にはtargeted送信経路（sendSysEx7AsUMP→UMP type 0x3）があるが、replyDestinationsが未設定のため使われなかった
- 修正: updatePEReplyDestinations()メソッド追加
  - CIManager.destination(for:)でdiscoveredPEDevicesのdestination IDを解決
  - PEResponder.setReplyDestinations()に設定
  - deviceDiscovered / deviceLost イベント時に自動更新
  - targeted経路はCoreMIDITransport.sendSysEx7AsUMP()を使用し、UMP SysEx7フォーマットでMIDI 2.0プロトコル配信
- iOS実機ビルド BUILD SUCCEEDED
決定事項:
- CIManagerはactor isolatedなのでdestination(for:)にawait必要 → Task内でasyncループ
- discoverPEDevicesリストをキャプチャしてTask内でCI actorにアクセス
次のTODO: 実機テスト — KeyStage USB接続 → PC送信 → LCD プログラム名表示確認
---

---
2026-02-08 11:33
作業項目: 実機ビルド＋インストール (Midi デバイス)
追加機能の説明:
- デバイス: Midi (00008120-001211102EEB401E) iOS 26.2.1
- xcodebuild -destination 'id=00008120-001211102EEB401E' BUILD SUCCEEDED
決定事項: 実機ビルド成功
次のTODO: KeyStage USB接続 → PC送信 → LCDプログラム名表示確認
---

---
2026-02-08 11:37
作業項目: replyDestinations設定をrevert — KeyStageハング再発のため
追加機能の説明:
- replyDestinationsを設定すると全PE応答（GET Reply, Subscribe Reply, Notify全て）がUMP SysEx7経由になる
- PE初期フロー（ResourceList GET Reply等）がUMP SysEx7で送信されKeyStageがハング
- macOS版で確認済みのハングと同じ現象
- updatePEReplyDestinations()メソッドとdeviceDiscovered/deviceLostでの呼び出しを削除
- 実機再ビルド BUILD SUCCEEDED
決定事項:
- replyDestinations全体切替はNG。PE Notifyだけ別経路で送る必要がある
- PEResponder.notify()内でsendReply()ではなく直接targeted UMP送信する方法を検討
- または: broadcast経路でもKeyStageに届いていたのか？LCDに表示されない原因は別か？
次のTODO: revert版で実機テスト → PEフロー正常動作確認 → Notifyが届いているかログ確認
---

---
2026-02-08 11:37
作業項目: KeyStageハング原因分析 — PEフロー完走後にハング
追加機能の説明:
- revert版でもM2DX再起動でKeyStage LCDハング発生
- ログ: PEフロー完走（ResourceList→DeviceInfo→ChannelList→ProgramList→X-ParameterList→X-ProgramEdit→JSONSchema×2）→Subscribe sub-1〜sub-4成功→ハング
- broadcast mode で3 destinationsに全PE応答を送信
- 87ca00eとの差分確認: PE リソース設定（canSubscribe等）は変更なし
- 87ca00eにはMUID DROPフィルタがあったが受信側のみ、送信broadcastに影響なし
- 問題仮説: PE応答がKeyStageの3 destination全てにbroadcastされ、適切でないポートへの応答がKeyStageを混乱させている
決定事項: broadcastを止めてtargeted送信に変更する方針は正しいが、UMP SysEx7ではなくlegacy MIDISend()で送る必要あり
次のTODO: PEResponder.sendReply()のtargeted経路でlegacy send()を使うよう修正
---

---
2026-02-08 11:42
作業項目: PE targeted送信をlegacy MIDISend()に変更 + 実機ビルド
追加機能の説明:
- PEResponder.sendReply() targeted経路: CoreMIDITransport.sendSysEx7AsUMP() → transport.send() (legacy) に変更
  - UMP SysEx7がKeyStageハングの原因だった可能性を排除
  - legacy MIDISend()はPE GET/SET/Subscribe Replyで実績あり
- MIDIInputManager: updatePEReplyDestinations()を再追加
  - CIManager.destination(for:)でModuleポートを解決
  - PE応答をKeyStageの正しいdestinationのみに送信（3 dest broadcast → 1 dest targeted）
- 実機ビルド BUILD SUCCEEDED
決定事項: targeted + legacy送信の組み合わせでテスト
次のTODO: 実機テスト — M2DX再起動 → ハングしないか確認 → PC送信 → LCD表示確認
---

---
2026-02-08 11:55
作業項目: PE replyDestinations を PEResponder init で同期設定（タイミング問題修正）
追加機能の説明:
- 原因: updatePEReplyDestinations()はdeviceDiscoveredイベント（MainActor経由）で呼ばれるがPEフローはそれより前に開始
- Discovery Reply送信 → KeyStageが即PE GET開始 → broadcast mode → 3 dests送信 → ハング
- 修正:
  1. PEResponder.init()にreplyDestinationsパラメータ追加
  2. resolvePEDestinations() static メソッド追加（CoreMIDI API直接使用、同期）
  3. PEResponder作成時にreplyDestinationsを渡す（CIManager.start()より前）
  4. 優先順: Module(BT) > CTRL(USB) > DAW > broadcast fallback
- PEResponder.sendReply()はlegacy MIDISend()使用（UMP SysEx7は使わない）
- 実機ビルド BUILD SUCCEEDED
決定事項: PEResponder作成前にCoreMIDI APIで同期的にdestination解決
次のTODO: KeyStage USB抜き差しで復旧 → M2DX起動 → ハングしないか確認
---

---
2026-02-08 12:01
作業項目: destination名ログ追加 + フォールバック拡張
追加機能の説明:
- resolvePEDestinations()が空を返していた → destination名にModule/CTRL/DAWが含まれていない
- ログ追加: 全destination名を表示（PE: MIDI dests=[name1, name2, ...]）
- フォールバック拡張: Module > CTRL > DAW > "keystage" > 最初のnon-KBD > 最初のdest
- これで必ず1つのdestinationが選択される（空は返さない）
- 実機ビルド BUILD SUCCEEDED
決定事項: destination名をログで確認し、必要に応じてパターン追加
次のTODO: KeyStage USB復旧 → M2DX起動 → ログで destination名確認 + ハングテスト
---

---
2026-02-08 12:04
作業項目: devicectl で実機にインストール
追加機能の説明:
- xcodebuild build はビルドのみでインストールしない問題を発見
- xcrun devicectl device install app でM2DX.appをデバイスにインストール成功
- bundleID: com.example.M2DX
決定事項: 今後はビルド後に devicectl install も実行する
次のTODO: KeyStage USB復旧 → M2DX起動 → PE: MIDI dests=ログ確認
---

---
2026-02-08 12:11
作業項目: KeyStage LCDハング原因調査 — PE応答内容の特定
追加機能の説明:
- 前セッション結果: targeted legacy MIDISend(CTRLポート1つ)でもLCDハング
- broadcast vs targeted は原因でない → PE応答の内容自体が原因
- 調査方針: どのPE応答がハングを引き起こすか特定
  1. CIManager Discovery Reply のbroadcast問題を確認
  2. peIsolationStep活用で段階的にPE応答を有効化
  3. 最小ResourceList(DeviceInfoのみ)でテスト
決定事項: transport方式は問題なし、PE応答コンテンツの調査に移行
次のTODO: MIDIInputManager の peIsolationStep / PE disable 機能を確認し、段階的テスト方針を決定
---

---
2026-02-08 12:14
作業項目: PE段階テスト Step 4 実装 + CIManager targeted送信
追加機能の説明:
- peIsolationStep に新しい値を追加:
  - Step 4: DeviceInfoのみ(canSubscribe無し) ← 今回テスト
  - Step 5: DeviceInfo + ChannelList(canSubscribe無し)
  - Step 6: DeviceInfo + ChannelList + canSubscribe
- registerPEResources() に step パラメータ追加、stepでリソース登録を制御
- CIManager.handleDiscoveryInquiry() のDiscovery Reply送信もtargeted化
  - CIManager に replyDestinations プロパティ + setReplyDestinations() メソッド追加
  - M2DX側: resolvePEDestinations()をCIManager作成前に移動、CIにも設定
- stale log行修正: "PE-Resp: N dests (broadcast mode)" → "MIDI: N destinations available"
- 実機ビルド BUILD SUCCEEDED + devicectl install OK
決定事項: Step 4(DeviceInfoのみ)でハングするか確認、ハングしなければStepを上げていく
次のTODO: KeyStage USB復旧 → M2DX起動 → Step 4でハングテスト
---

---
2026-02-08 12:17
作業項目: Step 4 ハングなし確認 → Step 5 へ
追加機能の説明:
- Step 4(DeviceInfoのみ) テスト結果: ハングなし
- PE Flow: ResourceList(1件) → DeviceInfo → ChannelList(404) で停止、正常
- 次: Step 5 (DeviceInfo + ChannelList, canSubscribe無し)
決定事項: Discovery Reply + ResourceList + DeviceInfo は安全
次のTODO: Step 5 ビルド → インストール → テスト
---

---
2026-02-08 12:20
作業項目: Step 5 ハングなし確認 → Step 6 へ
追加機能の説明:
- Step 5(DeviceInfo + ChannelList, canSubscribe無し) テスト結果: ハングなし
- 次: Step 6 (DeviceInfo + ChannelList + canSubscribe=true)
決定事項: ChannelList GET応答自体は安全。Subscribe有無が分岐点か
次のTODO: Step 6 ビルド → インストール → テスト
---

---
2026-02-08 12:22
作業項目: Step 6 ハングなし確認 → Step 3 (フル) へ
追加機能の説明:
- Step 6(DeviceInfo + ChannelList + canSubscribe) テスト結果: ハングなし
- Subscribe(0x38 start) + Notify送信も正常動作
- 次: Step 3 (フル5リソース) でtargeted送信のままテスト
- もしStep 3でもハングしなければ → 原因はbroadcast(3ポート全送信)だった
決定事項: Subscribe/Notifyフロー自体は安全
次のTODO: Step 3 ビルド → インストール → テスト
---

---
2026-02-08 12:25
作業項目: ★ KeyStage LCDハング根本原因特定 + 修正完了
追加機能の説明:
- Step 3(フル5リソース + targeted送信) テスト結果: ハングなし
- フルPEフロー完走、Program Change Notify正常動作確認
- 根本原因: USB 3ポート(Session 1, CTRL, DAW OUT)全てにbroadcast送信していたこと
  - Session 1やDAW OUTにCI/PEメッセージを送ると KeyStage が混乱しLCDハング
  - CTRLポートのみにtargeted送信で完全解決
- 修正箇所:
  1. PEResponder: replyDestinations パラメータでtargeted送信
  2. CIManager: replyDestinations + setReplyDestinations() で Discovery Reply もtargeted
  3. MIDIInputManager: resolvePEDestinations() でCoreMIDI API直接使用、CTRL優先解決
- 段階テスト結果:
  - Step 4(DeviceInfoのみ): ハングなし
  - Step 5(+ChannelList): ハングなし
  - Step 6(+canSubscribe): ハングなし
  - Step 3(フル): ハングなし ← targeted送信が鍵
決定事項: targeted送信が正式な修正。peIsolationStepは3に固定してコミット準備
次のTODO: KeyStage LCDにプログラム名が表示されるか確認、コード整理 + コミット
---

---
2026-02-08 12:27
作業項目: LCD非表示の原因調査 — macOS版との比較
追加機能の説明:
- macOS版での成功要件:
  1. PE Notify sub-ID2 = 0x38 (CI v1.1) ← コード確認: 既に正しい
  2. command:notify ヘッダー ← コード確認: notifyHeader()に含まれる
  3. X-ProgramEdit name フィールドがLCD表示を制御
  4. 初回 X-ProgramEdit GET Reply で「INIT VOIC」がLCDに表示された
- iOS版の現状: Notify送信ログは出ているがLCDに反映なし
- 疑問点: 
  - KeyStageがX-ProgramEditをGET/Subscribeしているか？
  - PE Flow Logの全文確認が必要
決定事項: PE Flow Log全文でKeyStageのGET/Subscribe状況を確認
次のTODO: ユーザーにPE Flow Log全文の提供を依頼
---

---
2026-02-08 12:33
作業項目: Step 3 フル — 2回目ハング + LCD非表示の調査
追加機能の説明:
- Step 3 1回目: ハングなし、LCD非表示
- Step 3 2回目: 約7回のPC変更後にハング、LCD非表示
- ログ分析:
  - フルPEフロー完走（5リソースGET + 4 Subscribe OK）
  - 各PC後: Notify送信 → 0x39 Reply → X-ParameterList再GET のサイクルが繰り返される
  - iOS entity MUIDs (0x4EC8E9E, 0x8A8A6E2) が背景で Discovery している
  - ChannelList Subscribeのlog callbackが欠落（タイミング問題?）
- macOS版との主な違い:
  - macOS: broadcast(2 dests) / iOS: targeted(1 dest=CTRL)
  - macOS: macOS entity除外あり / iOS: iOS entity除外も動作するはず
  - macOS: X-ParameterList再GETがあったか不明
決定事項: LCD非表示 + 間欠ハングの2問題を並行調査
次のTODO: PE_Implementation_Notes確認、macOS版との通信パターン比較
---

---
2026-02-08 12:35
作業項目: CTRL+DAW 2ポートtargeted送信テスト
追加機能の説明:
- macOS版成功時は2ポート(KBD/CTRL + DAW IN)にbroadcast送信
- iOS版はCTRL 1ポートのみだったがLCD非表示
- 仮説: macOSと同様に2ポートに送信すればLCD表示される可能性
- resolvePEDestinations() を変更:
  - USB KORG: CTRL + DAW OUT の2ポートに送信（Session 1は除外）
  - BT KORG: Module のみ（変更なし）
  - フォールバックからもSession 1を除外
- 実機ビルド BUILD SUCCEEDED + devicectl install OK
決定事項: CTRL+DAW 2ポートでLCD表示テスト
次のTODO: KeyStage USB復旧 → M2DX起動 → LCD表示 + ハング確認
---

---
2026-02-08 12:38
作業項目: ★バグ発見 — ChannelList supportsSubscription が Step 3 で false
追加機能の説明:
- 根本原因: registerPEResources() の ChannelList 登録で supportsSubscription: step >= 6
  - Step 3: 3 >= 6 = false → ChannelList Subscribe が 405 拒否
  - macOS版: supportsSubscription: true → ChannelList Subscribe 成功
- 証拠: ProgramList が sub-1 (ChannelListの次が sub-1 = ChannelList は Subscribe 未成功)
- 影響:
  1. LCD非表示: KeyStage は canSubscribe:true と宣言されたリソースの Subscribe 拒否で異常動作
  2. ハング: 405拒否 + Notify送信の組み合わせで混乱
- 修正: supportsSubscription: step != 5 に変更（Step 5のみfalse）
- CTRL+DAWからCTRL-onlyに戻す（DAW OUTもハング要因）
決定事項: ChannelList Subscribe バグが LCD非表示+ハングの主要因
次のTODO: バグ修正 + CTRL-only + ビルド + テスト
---

---
2026-02-08 12:42
作業項目: KeyStage未復旧状態でのテスト結果
追加機能の説明:
- PE Flow Log 8件のみ — KeyStageがDiscovery Replyを返していない
- PEフロー未開始のままNotify送信（subscriberなしでno-op）
- MIDI自体は正常（2,959メッセージ、NoteOff受信OK）
- 原因: 前回ハング後にKeyStage USB抜き差ししていない
決定事項: テスト前にKeyStage USB抜き差しが必要
次のTODO: KeyStage USB抜き差し → M2DX起動 → ChannelList Subscribe修正の動作確認
---

---
2026-02-08 12:46
作業項目: iOS entity干渉問題の発見
追加機能の説明:
- PE Flow Logの0x35(GET Reply)が全てdst=0xBB77068(iOS entity)
- M2DX(0x5404629)にはPE GETが一つも来ていない
- KeyStageがiOS内蔵MIDI-CI entityとPEフローを実行し、M2DXを無視
- macOSでも同様だったが、macOSではM2DXにもGETが来ていた
- iOSではタイミングによりKeyStageがiOS entityのみを選択する場合がある
- KeyStage MUID変化: 0xF3EDB46→0x6525F32 (USB抜き差しで変わる)
- ChannelList Subscribe修正は未テスト（iOS entity干渉で正しいテストができず）
決定事項: iOS entity干渉が不安定さの主要因
次のTODO: KeyStage完全USB抜き差しリセット後に再テスト（ChannelList Subscribe修正版）
---

---
2026-02-08 12:50
作業項目: ChannelList Subscribe修正版テスト — PEフロー完走
追加機能の説明:
- 全GETが dst=MUID(0x5404629) (M2DX) に正しく到達
- ChannelList Subscribe修正成功:
  - ChannelList → sub-1 ✓ (以前は405拒否)
  - ProgramList → sub-2 ✓
  - X-ParameterList → sub-3 ✓
  - X-ProgramEdit → sub-4 ✓
- ResourceList body表示にcanSubscribeが正しく含まれている
- PE Flow Log 38件、初期PEセットアップ完了
決定事項: ChannelList Subscribe修正が正しく動作
次のTODO: LCD表示確認、PC変更でLCD更新されるか、ハングしないか確認
---

---
2026-02-08 12:53
作業項目: ★★★★★ iOS USB版 KeyStage LCD プログラム名表示 完全成功
追加機能の説明:
- ユーザー確認: LCD表示成功、PC変更でLCD更新成功
- 「反応が遅くハングと誤認していたパターンがあったかも」— 遅延はあるが正常動作
- 修正箇所まとめ（全3点）:
  1. PEResponder + CIManager targeted送信（CTRLポートのみ、Session 1/DAW OUT除外）
     - Session 1/DAW OUTへのCI/PEメッセージがKeyStage LCDハングの原因だった
  2. ChannelList supportsSubscription バグ修正（step >= 6 → step != 5）
     - Step 3でChannelList Subscribeが405拒否されていた
  3. CIManager Discovery Replyもtargeted送信化
     - handleDiscoveryInquiry()が全ポートにbroadcastしていた
- 根本原因（2つ）:
  a. USB 3ポート全broadcastがKeyStage LCDハングを引き起こす
  b. ChannelList Subscribe拒否でKeyStageのPEフローが不完全だった
- 補足: iOS entity干渉でPEフローがM2DXに来ない場合がある（タイミング依存）
決定事項: iOS USB版LCD表示成功。コード整理+コミット準備
次のTODO: peIsolationStep debug levels整理、コード整理、コミット
---

---
2026-02-08 12:56
作業項目: コード整理 — peIsolationStepデバッグ分岐の削除
追加機能の説明:
- registerPEResources(): step 4/5/6デバッグ分岐を削除、step引数自体を削除
- peIsolationStep変数と関連条件分岐を削除（常にフルPE/CI動作）
- ChannelList supportsSubscription: 常にtrue（step!=5条件不要になる）
- step参照のログメッセージを整理
決定事項: デバッグステップは役割を果たしたため削除。本番コードはフルPE/CIのみ
次のTODO: コード編集 → 実機ビルド確認 → コミット
---
