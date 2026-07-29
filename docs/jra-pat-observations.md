# JRA PAT の観測結果と実装判断

この文書は、JRA PAT の「お知らせ（開催案内 1 件）」取得時に SFC と NTT DATA NDM24 の間をロジックアナライザで観測した調査資料から、現行ドライバが依存する内容を整理したものです。観測事実、推定、実装判断を意識して分けています。

元資料は開発者が保持する `NTT_Data_Modem_NDM24.md` です。リポジトリには要約と再現用 fixture だけを置き、元のロジックアナライザ capture はまだ収録していません。ビット境界、タイミング、ハードウェア revision 差の判断が必要になった時点で、元 capture の提供または再観測を依頼します。

## 観測された起動と初期化

| 順序 | 観測 | 現行実装 |
|---:|---|---|
| 1 | `$4201` の対象 I/O bit を `$00`、続いて `$80` にする | 起動時は全bitをreleaseする `$FF`。raw `R` ではlow→releaseを繰り返さない |
| 2 | 最初に Data1/Data2 を 16 bit 読む | 状態・識別用 poll16 として記録 |
| 3 | `R` だけを送る | raw `$52` を MSB first で送信 |
| 4 | `AT CR LF` を送る | reset guard 後に非同期 enqueue |
| 5 | echo と `OK CR LF` を受信 | echo を無視し `OK` で `READY` |

`R` の厳密な意味は未確認です。送信時に NDM24 の電源ランプが一定時間点滅するため、初期化または reset に相当すると推定しています。ただし、確証が得られるまではコードと文書の名称を「NDM24 固有の raw `R` 初期化」とし、標準 AT reset とは扱いません。

現行driverへ過去の動作済み命令列をそのまま移植した実機試験でも、raw `R` 送信時の電源ランプ点滅を再現できました。点滅中の内部初期化を避けるため、現行設定は600フレーム（NTSCで約10秒）待ってから `AT CR LF` を送ります。1フレーム待機では300フレームtimeoutを2回消費した後の3回目だけが成功し、600フレーム待機では初回probeで成功しました。

## 16 bit poll と 9 bit transfer

JRA PAT は最初に 16 bit を読み、その後 Data2 の対象bitを待ちます。対象bitを確認すると 9 bit 単位の読み取りへ切り替え、echo と結果コードを連続して取得します。本書では以前このbitを `ready` と呼んでいましたが、送信バッファの空・非空を保証しないことが実機試験で判明したため、現在は `transfer hint` と記します。

現行driverの実機トレースでは、最初のburstが `A=$4180 / Data2=$4000`、`T=$5480 / Data2=$0000` でした。次のburstでも `CR=$0D80`、`LF=$0A80`、`O=$4F80`、`K=$4B80` はData2が立った状態で続き、末尾の `CR=$0D80` でData2が0になりました。そこで停止すると、次フレームの16-bit pollには一度だけ `LF=$0A83 / Data2=$0000` が現れ、以後は同じデータ値でRX-presentだけが落ちた `$0A03` になりました。この末尾LFは、Data2にかかわらず9-bit transferを継続することで取得できます。

疑似PSTN接続試験では別の16-bit poll挙動が確認されました。`AT&F` と `ATX3` の先頭 `A` が `Data1=$4183 / Data2=$4000` として現れ、直後の9-bit transferは次の `T` から始まりました。16-bit pollで当該byteが消費されるため、これを常に状態観測用として破棄すると受信echoとターミナル表示から実データが欠落します。破棄カウンタも `AT&F` と `ATX3` で1ずつ増え、画面上の欠落と一致しました。

16-bit pollでもRX-presentだけを受理条件にしたrevision B再試験では、`AT&F`、`AT%B2400`、`ATS7=60`、`ATX3`、`ATDT0` のechoがすべて完全になり、全transactionのRX discard counterは0のままでした。`ATDT0` transactionではecho 6byteと `CR LF CONNECT 2400 CR LF` 16byteの合計22byteを受理しています。

Data2が0でもRX-presentが成立する限り9-bit transferを継続する試験では、`AT CR CR LF OK CR LF` の9byteを欠落なく取得しました。`T` 後の `CR` と結果コード末尾の `CR` 後の `LF` は、いずれも直前transferのData2が0でも返っています。このためData2=0は「次byteなし」または「NDM24送信バッファが空」の確定通知ではありません。

観測中、`CR` が一度見えた時点ではtransfer hintが成立せず、その後の待機pollでもData1に同じ `CR` が繰り返し見えました。後にtransfer hintとRX-presentが両方成立した時点で、同じ `CR` が改めて返りました。

このため現行実装は次の規則を採用します。

- 16-bit pollでもData1のRX-presentが成立した場合、Data2の値にかかわらずData1上位byteを受理する。
- 16-bit pollでRX-presentがない場合、データ部は状態・識別用として破棄する。
- 9-bit transferは先頭8bitをデータ、9番目をtransfer RX-presentとして扱う。
- 9-bit reportの下位byte mask `$80` が1の現在byteを、Data2 transfer hintにかかわらず受理する。
- Data2 `$40` は、待機中に9-bit transferを開始するhintとして使う。
- いったん9-bit transferを開始した後は、Data2にかかわらずRX-presentが成立する間は連続転送する。
- RX-presentが0の候補とリング満杯時の候補は理由別に数え、トレースへ残す。
- 物理信号として観測したactive-low RX-presentと、9-bit report末尾で得るasserted-high flagの対応には、回路または取込段での反転が含まれる可能性がある。名称は同一視せず、再観測対象とする。

この判定は `spec/ndm24.toml` の mask、65816 実装、Rust の `receive_decision` と単体テストで同期しています。

公開されている NDM24 I/O の別資料として [fullsnes の SFC Modem 記述](https://problemkaputt.de/fullsnes.htm#snesaddonsfcmodemforjrapat)も参照します。ただし、観測 capture と相違する場合、現行ドライバの受信可否は上記 JRA PAT 実測を優先します。

## 観測された AT 設定列

通信開始前に次の順序が観測されています。

```text
AT
ATZ
AT&F
ATS7=60
ATS8=3
ATT
ATL0
AT%B2400
ATS6=4
ATS9=6
ATS10=14
ATS11=95
ATS91=15
ATX4
ATD<接続先>
```

電話番号は用途・個人環境に属するためリポジトリへ固定しません。再利用可能な一覧は [`profiles/jra-pat.toml`](../profiles/jra-pat.toml)に置いています。現行のスモークテストが送るのは `AT` だけで、発信しません。

## 未確定事項

- raw `R` の厳密な機能と必要な待ち時間
- Data2 の他の信号（RTS、DCD、DTR と推定されるもの）の割り当て
- 2 種類の NDM24 hardware revision 間の timing 差
- 長時間連続転送時の最適な poll 回数

これらを変更する際は、両 revision の実機、常設トレース、必要に応じたロジックアナライザ再観測を組み合わせます。
