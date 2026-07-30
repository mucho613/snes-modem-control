# ステータス画面とネットワーク・ダッシュボード

## 画面構成

通常ROMは人間向けの`COMMON`ページを既定にします。従来の
`modem-control-test`ヘッダーと区切り線は廃止し、32×32文字を状態表示へ使います。

- ステータス画面で十字キー左右: `COMMON`、`NTP`、`DNS`、`ICMP`を循環
- `R`: NDM24通信の生ログへ移動
- 生ログで`L`: 最後に選んでいたステータスページへ戻る
- 生ログ表示中の十字キー: 無視

通信開始を理由にページを自動変更しません。生ログは非表示中も更新を続けます。
画面内に操作ガイドは表示しません。

## COMMON

通信基盤だけを表示し、アプリケーション固有情報は繰り返しません。

```text
MODEM  CONNECTED
LCP    OPEN
PAP    OPEN
IPCP   OPEN
LOCAL  10.24.0.2
PEER   10.24.0.1
```

## NTP

```text
APP    NTP

STATE  RECEIVED
TIME   2026-07-30 14:29:27 JST
ERROR  NONE

VERSION 4
STRATUM 3
REF ID GPS.

REQUESTS  2
RESPONSES 2
TIMEOUTS  0
```

`TIME`は最後の同期成功後もソフトウェア時計から進めます。後続要求が失敗しても
既知の時刻は消しません。未同期時は`---- -- -- --:--:-- JST`です。

## DNS

STATE、HOST、RESOLVR、A、ANSWERS、TX ID、RTT、ERRORと要求・応答・破棄・
timeout countを表示します。HOSTは表示領域25文字を超える場合、先頭24文字と
末尾`>`へ短縮します。新しい要求を開始した時点で前回結果とRTTを消し、完了した
結果は次の要求または再起動まで残します。

## ICMP

1ページ内を`OUTBOUND`と`INBOUND`へ分けます。

`OUTBOUND`はSTATE、PEER、Identifier、Sequence、RTT、ERRORと要求・応答・破棄・
timeout countを表示します。

`INBOUND`はSTATE、SOURCE、Identifier、Sequence、payload byte数、受信要求・
送信reply・破棄count、ERRORを表示します。SOURCE等は「最後に検証へ合格した
Echo Request」の専用snapshotです。壊れたrequestはERRORとDROPSを更新しますが、
このsnapshotを上書きしません。外向きEcho Replyや他プロトコルの受信でも
上書きしません。

## 状態とエラー表記

NTP、DNS、外向きICMPの要求状態は共通して次の5語へ写像します。

- `IDLE`
- `QUEUED`
- `WAITING`
- `RECEIVED`
- `FAILED`

エラーなしは`NONE`です。既知のエラーは`TIMEOUT (0C)`のように短い記号名と
16進codeを併記し、未知値は`UNKNOWN (XX)`とします。32bit counterが65535を
超えた場合、画面では`>65535`と表示します。診断ABI内の値は32bitのままです。

## 実装境界

共通UIは`src/ui/status.asm`です。ページ選択、COMMON、生ログ切替、WRAM
tile bufferからVRAMへの1行ずつの転送を所有します。

ビルド時の選択点`src/application/status.asm`は現在
`src/application/network.inc`をincludeします。ネットワーク・アダプターは
NTP/DNS/ICMPページの静的labelと値の整形だけを所有し、PPU register、
`screenMode`、生ログ、COMMONを操作しません。エントリは次の2つです。

- `applicationStatusInitialize`: 選択ページが変わったときに静的labelを配置
- `applicationStatusPoll`: 1フレームにつき最大1回、選択ページの値を更新

アダプターはROMの`DATA`領域へ分離し、共通UIから`JSL`で呼びます。HTTP等へ
置き換える場合はこのinclude先とアダプターだけを変更でき、共通UIと生ログを
保てます。

表示状態はlinker segment `DISPLAY_BSS`（`$7E3000`以降）に置きます。メイン
ループは32×32文字bufferを組み立て、VBlankは1フレームに1行だけVRAMへ転送
します。ステータス画面のBG1縦スクロールはSFC実機で最上段の1pixelが欠けない
ように`-1`へ固定します。

## ソフトウェア時計

時刻の正本は`src/clock/clock.asm`です。検証済みNTP Server Transmit Timestampを
UTC Unix秒へ変換し、表示時だけ9時間加算してJSTへ分解します。同期後はNTSC
SFCの公称約60.0988 Hzに基づくVBlank frame数で進めます。RTC、S-RTC、
FXPAK PRO本体時計は使用しません。

## 自動検証

`cargo xtask mesen-test`はPPP常設セルフテストに加えて次を検査します。

- 起動時にCOMMONとMODEM行が選ばれる
- NTP、DNS、ICMPの各ページへ切り替えると固有headingが生成される
- NTP未同期表示がセルフテスト前の状態へ戻る
- NTPの`TIMEOUT (0C)`と10進counter `12345`を正しく整形する
- 120 emulator frameに対するSFC側`frameCounter`差が±1以内である

2026-07-30の旧3行NTP画面はrevision A、FXPAK PRO、QUsb2Snes、DFM-56U、
疑似電話交換機で確認済みです。同日の4ページ版はFXPAK PROへ転送して起動し、
COMMONをOBS Virtual Cameraのcaptureで確認しました。実機mailboxのPPP常設
セルフテストもsequence 1で合格しています。十字キーによる4ページ巡回、
L/Rによる生ログ往復、BG1縦スクロール`-1`で最上段文字が欠けないことも
実機とOBS Virtual Cameraで確認済みです。
