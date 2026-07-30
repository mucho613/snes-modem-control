# ステータス画面とアプリケーション・アダプター

## 画面の役割

通常ROMは人間向けステータス画面を既定にします。`R`ボタンでNDM24通信の生ログ、`L`ボタンでステータスへ戻ります。生ログは非表示中も更新を続けます。

```text
modem-control-test
--------------------------------

MODEM  READY
LCP    OPEN
PAP    OPEN
IPCP   OPEN
LOCAL  10.24.0.2
PEER   10.24.0.1

APP    NTP
STATE  RECEIVED
TIME   2026-07-30 13:23:17 JST
```

上段のMODEMからPEERまでは通信基盤が所有します。下段のAPP、STATE、TIMEは選択中のアプリケーション・アダプターが所有します。表示器は通信プロトコル固有の状態を参照しません。

## アプリケーション境界

ビルド時の選択点は`src/application/status.asm`です。現在は`ntp.inc`をincludeします。将来HTTP等へ替える場合は別の`.inc`アダプターを追加し、このincludeだけを変更します。`.inc`にする理由は、ビルドが`src`以下の全`.asm`を自動収集する構成でも複数アダプターの同名exportを発生させないためです。

アダプターのABIは次の2エントリです。

- `applicationStatusInitialize`: 起動時に一度呼ばれる
- `applicationStatusPoll`: メインループから1フレームにつき最大一度呼ばれる

どちらもA=8-bit、X/Y=16-bit、DBR=`$7E`で呼ばれます。出力先は25文字固定幅の次の3バッファです。

- `statusApplicationName`
- `statusApplicationState`
- `statusApplicationValue`

未使用部分は空白で埋め、NUL終端は使いません。アダプターはVRAM、画面選択、生ログ、MODEM/PPP行を操作しません。この契約により、NTPをHTTPへ替えても`src/ui/status.asm`、`src/terminal/print.asm`、L/R切替処理は共通のままです。

## NTPアダプター

`src/application/ntp.inc`はNTP状態を次の表示へ写像します。

| NTP状態 | STATE |
|---|---|
| 未要求、要求中、応答待ち | `WAITING` |
| 有効な相関済み応答を受信 | `RECEIVED` |
| timeoutまたは検証失敗 | `ERROR` |

エラー後も最後に同期できた時計は失いません。時刻未取得中は`---- -- -- --:--:-- JST`を表示します。

## ソフトウェア時計

時刻の正本は`src/clock/clock.asm`です。NTPは検証済みServer Transmit TimestampをUnix秒へ変換し、プロトコル非依存の`clockSetUnixTime`へ渡します。時計はUTCのUnix秒と32-bit二進小数を保持し、表示時だけ9時間加算してJST年月日時分秒へ分解します。

同期後はSFCのVBlankフレーム数で進めます。1フレームの加算値`$04427885`はNTSC SFCの公称master clockとnon-interlace frame長から得た平均約60.0988 Hzを基準にしています。これはRTCではないため、長時間の誤差、PAL、処理停止中の経過時間はNTP再同期で補正する前提です。S-RTCおよびFXPAK PRO本体時計は使用しません。

時計のフレーム加算ループではXレジスタを残りフレーム数として使います。秒境界で
呼ぶ表示整形処理もXを文字位置に使うため、処理のABIとしてXを保存・復元します。
常設セルフテストは小数部`$80000000`から60フレーム進め、Unix秒がちょうど1増え、
小数部が`$7F943F2C`になることをstep `$A1`で検査します。

## 描画所有権

メインループは状態をWRAMの32×32文字バッファへ組み立てます。VBlankは1フレームに1行だけVRAMへ転送します。アプリケーション処理はPPUレジスタへ直接書かず、画面切替はVBlank内でBG1 tilemap baseとvertical scrollを選ぶだけです。

表示・時計状態はlinker segment `DISPLAY_BSS`（`$7E3000`以降）へ置きます。NDM24のbank `$80` WRAM mirror制約を受けるドライバ状態と、固定`PPP_BSS`（`$7E2000`）から分離し、両領域の将来拡張を妨げません。

## 実機確認

2026-07-30にrevision AのNDM24、FXPAK PRO、QUsb2Snes、DFM-56U、
疑似電話交換機を使用して確認しました。起動時はステータス画面、`R`で生ログ、
`L`でステータスへ戻り、生ログには初期化時の`ATM0`と`OK`が欠落なく残って
いました。

疑似PSTN接続後はMODEM `CONNECTED`、LCP/PAP/IPCP `OPEN`、LOCAL
`10.24.0.2`、PEER `10.24.0.1`へ更新されました。NTP Version 4、Stratum 3の
応答後はSTATE `RECEIVED`、TIME `2026-07-30 14:29:27 JST`を表示し、別の
キャプチャで秒が進むことを確認しました。対向停止後はMODEM `READY`、
LCP/IPCP `CLOSED`、PAP `INACTIVE`へ戻り、最後に同期した時刻は失わず進み
続けました。

初回実装では表示整形がフレーム加算ループのXを破壊し、秒境界ごとに余分な
フレームを加算していました。実機では15.021秒の測定中に`frameCounter`が
903（60.114Hz）増えた一方、内部時計は20.965秒進んでいました。X保存の修正後は
15.021秒に対して内部時計15.025秒となり、画面キャプチャでも14秒間に表示が
14秒進むことを確認しました。

VBlank NMIでは`RDNMI`も読み、手動コントローラーI/Oのために`NMITIMEN`を
一時的に無効化・再有効化した際、同じVBlankフラグからNMIが再発火しないように
しています。MesenCEは120 emulator frameに対するSFC側`frameCounter`の差を
±1以内として毎回検査します。
