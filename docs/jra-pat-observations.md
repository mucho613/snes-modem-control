# JRA PAT の観測結果と実装判断

この文書は、JRA PAT の「お知らせ（開催案内 1 件）」取得時に SFC と NTT DATA NDM24 の間をロジックアナライザで観測した調査資料から、現行ドライバが依存する内容を整理したものです。観測事実、推定、実装判断を意識して分けています。

元資料は開発者が保持する `NTT_Data_Modem_NDM24.md` です。リポジトリには要約と再現用 fixture だけを置き、元のロジックアナライザ capture はまだ収録していません。ビット境界、タイミング、ハードウェア revision 差の判断が必要になった時点で、元 capture の提供または再観測を依頼します。

## 観測された起動と初期化

| 順序 | 観測 | 現行実装 |
|---:|---|---|
| 1 | `$4201` の対象 I/O bit を `$00`、続いて `$80` にする | 起動時と明示初期化時に low→release |
| 2 | 最初に Data1/Data2 を 16 bit 読む | 状態・識別用 poll16 として記録 |
| 3 | `R` だけを送る | raw `$52` を MSB first で送信 |
| 4 | `AT CR LF` を送る | reset guard 後に非同期 enqueue |
| 5 | echo と `OK CR LF` を受信 | echo を無視し `OK` で `READY` |

`R` の厳密な意味は未確認です。送信時に NDM24 の電源ランプが一定時間点滅するため、初期化または reset に相当すると推定しています。ただし、確証が得られるまではコードと文書の名称を「NDM24 固有の raw `R` 初期化」とし、標準 AT reset とは扱いません。

## 16 bit poll と 9 bit transfer

JRA PAT は最初に 16 bit を読み、その後 Data2 の ready 状態を待ちます。ready を確認すると 9 bit 単位の読み取りへ切り替え、echo と結果コードを連続して取得します。

観測中、`CR` が一度見えた時点では ready が成立せず、その後の待機 poll でも Data1 に同じ `CR` が繰り返し見えました。後に ready と RX-present が両方成立した時点で、同じ `CR` が改めて有効なデータとして返りました。

このため現行実装は次の規則を採用します。

- 16 bit poll のデータ部は常に破棄し、状態・識別にだけ使う。
- 9 bit transfer は ready と RX-present の両方が成立したバイトだけを受理する。
- ready がない候補、RX-present がない候補、リング満杯時の候補は理由別に数え、トレースへ残す。
- RX-present がない時に見える直前値を重複データとして上位層へ渡さない。

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
