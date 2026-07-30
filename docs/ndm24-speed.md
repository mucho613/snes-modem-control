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
