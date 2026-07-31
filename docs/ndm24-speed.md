# NDM24 回線速度探索

## 目的

revision A/Bそれぞれについて、疑似PSTNとI/O DATA DFM-56Uを使い、安定して
利用できる最大回線速度を測定します。Nifty実回線は最大速度の認定には使いません。
既存の`connect-test`と`binary-test`はV.22bis 2400 bit/sの固定回帰試験として
変更せず、速度探索専用runnerを分離します。

候補速度は2400、4800、7200、9600、12000、14400 bit/sです。ATコマンドが
`OK`を返すだけでは対応速度と認定せず、NDM24とDFM-56Uのexact carrier、
双方向データ完全一致、実効速度、再現性を別々に検査します。

## 非発信能力probe

最初の段階では電話回線へ発信しません。SFC上のNDM24が`READY`で、DFM-56Uが
WindowsのCOM5として利用できる状態で次を実行します。

```powershell
cargo run -p ndm24-tools -- speed-probe --revision A --port COM5
```

revision Bでは`--revision B`へ変更します。runnerはDFM-56Uへ`ATI`、`ATI3`、
`AT+MS=?`、`AT+MS?`、`AT+GCAP`を照会します。NDM24へは`AT&F`、`ATM0`の後、
`AT%B2400`、`AT%B4800`、`AT%B7200`、`AT%B9600`、`AT%B12000`、
`AT%B14400`を順に送り、圧縮無効候補`AT%C0`と自動誤り訂正候補`AT\N3`も
調べます。`OK`と`ERROR`はどちらも機器能力を表す正式な結果としてraw response、
trace、snapshotとともに保存します。

試験終了時は成功・失敗にかかわらず、NDM24へ`AT&F`、`ATM0`、`AT%B2400`を
送り、不揮発保存コマンドは使用しません。DFM-56Uも`ATZ`で既知状態へ戻します。
結果は`build/hardware-tests/<test-id>/speed-probe.json`へ保存します。

2026-07-31のrevision A probeでは6候補すべてが`OK`でした。DFM-56U
（CX93001）は`V22B`、`V32`、`V32B`と送受信別のexact speed指定に対応して
いました。これはコマンド受理結果であり、各速度の接続認定とは区別します。

## 単一速度試験

疑似PSTNを接続した状態で、指定した速度だけを試験できます。

```powershell
cargo run -p ndm24-tools -- speed-test --revision A --speed 2400
```

既定では双方向4 KiBのPRBS16を転送します。64 KiB認定試験では
`--length 65536`を指定します。DFM-56Uは速度に応じて`V22B`、`V32`、
`V32B`をfallbackなしで指定し、`ATW2`のDCE速度結果を検査します。
NDM24は`AT&F`直後に`ATM0`を適用し、圧縮無効、誤り訂正有効、`AT%B<speed>`
の順で構成します。不揮発メモリには保存しません。

NDM24とDFM-56UはいずれもDTEから電話回線より速く一括投入すると内部バッファを
溢れさせるため、送信は回線速度に合わせてpaced transferにします。SFC側は
フレーム単位のtoken bucket、Windows側は64 byte単位のpaced writeを使います。
これは測定対象の回線速度を変える処理ではなく、RS-232CのRTS/CTSを利用できない
構成での送信フロー制御です。

2026-07-31にrevision Aの2400 bit/s基準試験が合格しました。DFM-56Uは
`CONNECT 2400`を報告し、双方向4096 byteが不一致、overflowとも0でした。
実効payload速度はSFC→DFMが約1898 bit/s、DFM→SFCが約1859 bit/sでした。
終了後はNDM24が`READY`へ戻ったことを確認し、`AT&F`、`ATM0`、
`AT%B2400`を再適用しています。

同日のrevision A探索結果は次のとおりです。

| 指定速度 | DFM変調 | 試行 | 結果 |
|---:|---|---:|---|
| 2400 | V22B | 1 | `CONNECT 2400`、双方向4 KiB完全一致 |
| 4800 | V32 | 2 | 2回とも`NO CARRIER` |
| 7200 | V32B | 2 | 2回とも`NO CARRIER` |
| 9600 | V32 | 2 | 2回とも`NO CARRIER` |
| 12000 | V32B | 2 | 2回とも`NO CARRIER` |
| 14400 | V32B | 2 | 2回とも`NO CARRIER` |

したがって、この疑似PSTN、DFM-56U、圧縮無効、誤り訂正有効、fallbackなしという
条件でのrevision A探索上限は2400 bit/sです。上位速度の`AT%B`が`OK`を返すことは、
実際にそのcarrierで接続できることを意味しません。revision Bの結果とは分けて扱います。

2026-07-31のrevision B探索では2400、4800、7200、9600、12000、14400 bit/sの
全候補がexact carrierで接続し、各速度の双方向4 KiB PRBSが不一致・overflowとも
0で合格しました。特に9600 bit/sは`CONNECT 9600`とデータ完全一致まで確認して
おり、単なる`AT%B9600`のコマンド受理ではありません。

最高候補14400 bit/sでは、独立した3回の再接続それぞれで双方向64 KiB PRBSが
完全一致しました。第1回の実効payload速度はSFC→DFMが約5760 bit/s、
DFM→SFCが約11321 bit/sでした。carrier自体は`CONNECT 14400`ですが、
SFC→NDM24方向にはコントローラーポートとpoll処理による約5.6 kbit/sの実効上限が
見えています。このため、回線carrier速度とアプリケーション実効速度は別の値として
記録します。

## 認定条件

探索段階は各速度で双方向4 KiBの疑似ランダム列を完全一致させます。初回失敗時は
双方を既知状態へ戻して1回だけ再試験し、1回だけ成功した速度は不安定として最大速度
に認定しません。中間速度が不合格でも上位速度の試験は継続します。

最高候補は3回接続し直し、各回で双方向64 KiBを完全一致させた後、30分間carrierを
維持します。圧縮は無効、誤り訂正は有効とし、見かけの圧縮率ではなく実効転送速度を
測ります。最終認定速度ではLCP、PAP、IPCP、DNS、ICMP、正常切断も疑似PSTN上で
回帰確認します。

全試験でAT transcript、CONNECT結果、byte数、所要時間、不一致位置、overflow、
discard、timeout、backpressure、Data1/Data2 trace、retrain、carrier lossを
保存します。ロジックアナライザは各revisionの最高認定速度、その一段上の失敗、
またはコントローラーポート上の異常が出た試験を優先して取得します。
