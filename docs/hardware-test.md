# NDM24 ハードウェアテスト

## 安全上の前提

秋月電子通商の [PIC 簡易疑似電話交換機](https://akizukidenshi.com/catalog/g/g117755/) を NDM24 と相手側モデムの間に置き、閉じた疑似 PSTN を構成します。この装置は発信側のダイヤル内容を交換先の選択に使わず、2 ポート間を 1 対 1 で接続する仕様です。配線・ring cadence・電源条件は製品の[取扱説明書](https://akizukidenshi.com/goodsaffix/manu030.pdf)を正本とします。

疑似交換機のポートを公衆電話網や外部の電話設備へ接続しません。NDM24 の公衆 PSTN 用個体と分解・計測用個体も取り違えないよう、個体 ID と hardware revision を試験記録に残します。

## 配線

```mermaid
flowchart LR
    S["SFC + FXPAK PRO"] -->|"controller port 2"| N["NDM24 under test"]
    N <-->|"analog line 1"| X["PIC 簡易疑似電話交換機"]
    X <-->|"analog line 2"| P["peer modem"]
    P <-->|"USB serial"| W["Windows PC<br/>ndm24-tools peer"]
    W <-->|"USB / QUsb2Snes"| S
```

## クイックテスト

1. NDM24、SFC、FXPAK PRO、QUsb2Snes を接続します。
2. `cargo xtask deploy --smoke` で ROM を転送して起動します。
3. `cargo run -p ndm24-tools -- test` を実行します。
4. command が `passed` になり、診断状態が `ready` であることを確認します。
5. `cargo run -p ndm24-tools -- monitor --once` を保存します。
6. `cargo run -p ndm24-tools -- trace-live` を保存します。

合格条件:

- `AT` に対する `OK` を受け、有限時間内に `READY` になる。
- raw `R` 後は約10秒待ってから初回probeが始まり、`tx_bytes=4`、`timeout=0` で成功する。
- 初回probeの表示ミラー末尾が `41 54 0D 0D 0A 4F 4B 0D 0A`（`AT CR CR LF OK CR LF`）になる。
- `last_error`、RX/TX overflow が 0。
- 9-bit RX-presentが1のecho/応答だけを受理し、Data2 hintが0になった後もRX-presentが続く末尾文字を欠落しない。
- 16-bit pollでもData2 hintにかかわらずRX-presentが成立した先頭byteを受理し、AT echoの先頭を欠落しない。
- `READY` 遷移後はAT probeの末尾LFがRX queueに残っていない。
- エラー時は `ERROR` へ遷移し、トレースが凍結する。

## AT識別情報

NDM24を回線へ接続せず、初期probeが `READY` になった状態で次を実行します。

```powershell
cargo run -p ndm24-tools -- identify --revision B
```

`ATI`、`ATI0`～`ATI9`とV.250の `AT+GMI`、`AT+GMM`、`AT+GMR`、`AT+GSN`、`AT+GCAP` を照会します。いずれも読み取り専用で、設定変更や発信は行いません。未対応コマンドの `ERROR` もrevision固有の結果として保存します。各応答はtraceのRX accepted eventからraw byte列を復元し、終端検出後100ms以内に後着したbyteもRX ringから取得して統合します。ATI2のchecksum結果 `OK` のように終端結果と同じ情報行が先行する場合は、最後の行だけを終端として除外します。応答終端が得られずタイムアウトした場合も、それ以前の全結果と失敗コマンドの前後snapshot、受信・送信byte数差分、利用可能なtraceを保存して照会を終了します。行単位の情報とsnapshotは `build/hardware-tests/<test-id>/at-identification.json` へ記録します。

合格条件:

- 対応コマンドは `OK` または `ERROR` などの終端結果まで完了する。無応答のコマンドはタイムアウトとして明示され、後続コマンドを実行しない。
- raw responseをtraceから欠落なく復元でき、trace overwriteとRX discardが0。
- 全照会後も `READY` で、RX ringが空、error、timeout、RX/TX overflowが0。
- 32byteを超える連続応答ではpoll budget exhaustionを許容する。コマンド別の増分を記録し、次のメインループで継続してraw responseが完全に取得できたことを確認する。

## 疑似 PSTN 接続テスト

1. 疑似交換機の line 1 に NDM24、line 2 に相手側モデムを接続します。
2. 後期hardware revisionを `revision B`、前期を `revision A` として試験記録へ記載します。
3. smoke ROMを転送し、初期 `AT` probeが `READY` になったことを確認します。
4. `cargo run -p ndm24-tools -- connect-test --revision B --port COM5` を実行します。revision Aでは引数を `--revision A` に変更します。
5. 接続試験合格後、`cargo run -p ndm24-tools -- binary-test --revision B --port COM5` を実行します。revision Aでは同様に引数を変更します。
6. quick run の後、`cargo run -p ndm24-tools -- connect-test --revision B --port COM5 --hold-seconds 1800` で30分のcarrier soakを行います。revision Aでは同様に引数を変更します。

`connect-test` はDFM-56Uへ `ATZ`、`ATE0`、`AT&D2`、`AT+MS=V22B,0,2400,2400,2400,2400`、`ATS0=1` を送り、各 `OK` を確認します。NDM24側はホスト駆動の汎用AT transactionで `AT&F`、`AT%B2400`、`ATS7=60`、`ATX3`、`ATDT0` を1回ずつ実行します。疑似交換機にダイヤルトーンはなく、オフフックから数秒後に相手側を呼び出すため、`ATX3` でdial tone待ちを無効にします。番号 `0` は発信動作を開始するための非実在値で、疑似交換機はroutingに使いません。report schema version 2以降は各transaction前後のRX discard counterと、接続保持終了時にRX ringへ残っていたraw byte列を保存します。version 3以降はDTRを下げた1秒後、`NO CARRIER` parserを開始する直前のraw RX列も保存します。

接続試験の合格条件:

- DFM-56UとNDM24の両側が `CONNECT` を返す。
- V.22bis 2400bpsで10秒間carrierを保持する。
- DFM-56UのDTR低下後、NDM24が `NO CARRIER` を返す。
- `last_error`、timeout、RX/TX overflow、poll limitが0。
- AT parserが末尾LFまで消費し、試験終了時のRX ringが空。
- 日時・revision・AT transcript・SFC snapshot・transaction別traceを `build/hardware-tests/<test-id>/connect-test.json` へ保存する。

`binary-test` は接続設定に加えてDFM-56Uへ `AT&K0` を送り、DTE flow controlを無効にします。接続後、全256値を昇順にNDM24→DFM-56U、DFM-56U→NDM24へ1回ずつ転送します。SFC側mailboxの1命令は最大31byteとし、TX ringが空になったことを確認してから次のchunkへ進みます。DFM-56U→NDM24ではV.22bis上のchunk到着時間と100msの余裕を待ち、RX ringを直接記録してからmailboxでdrainします。これにより回線・低レベルpollの結果とmailbox返却値を分離して診断します。report schema version 3以降は、NDM24→DFM-56Uの256byte送信が終わった直後にtraceをfreezeして `sfc_to_peer_trace` へ保存し、後半の受信試験でTX eventが上書きされることを防ぎます。

report schema version 4以降は通常の31byte chunk試験に加え、SFCの255byte TX ringを `0x00`～`0xFE` で一度に満たす最大burst試験を行います。DFM-56Uで受信した列を完全比較し、burst前後のsnapshotと直後のtraceを独立保存します。255byteは32-transferのpoll budgetを7回使い切り、最後の31byteで完了するため、この区間に限ってpoll limit countの増分7とflagを期待値として扱います。通常送信では見えないNDM24入力bufferの飽和やbackpressure信号を探索するための試験です。

QUsb2Snesからmailboxを読む際は、96byte全体が2回連続で一致するまで制御結果を確定しません。SFC専用outputは別のQUsb2Snes接続から32byteだけを2回読み、一致した値を採用します。完了済みの制御欄と更新前のoutput欄が混在した一時的な読み取りを、受信データとして扱わないためです。

mailbox ABI version 4では、version 3のarguments/output所有権分離を維持し、デバッグ専用の255byte TX stress命令を追加します。arguments 32byteはホスト→SFC専用、output 32byteはSFC→ホスト専用で、FXPAK PROの `SETX` でホストが書いた領域をSFC出力として再利用しません。

binary pattern試験の合格条件:

- 双方向とも受信列が `0x00`～`0xFF` と完全一致し、最大burstのSFC→DFM-56U受信列も `0x00`～`0xFE` と完全一致して、欠落、重複、順序変更がない。
- 転送後のRX/TX ringが空で、error、timeout、RX/TX overflowが0。poll limitは最大burstによる増分7だけを許容し、それ以外の増加は不合格とする。
- DTR切断後にNDM24が `NO CARRIER` を返して `READY` へ戻る。
- expected/received byte列、chunkごとのdrain前RX ring、AT transcript、SFC snapshot、SFC送信直後trace、受信試験traceを `build/hardware-tests/<test-id>/binary-pattern-test.json` へ保存する。

接続失敗時は自動再発信しません。30分soak中もRX/TX ring、error、timeout、overflow、poll limit、discardを監視し、保持終了後のDTR切断、`NO CARRIER`、`READY`復帰までを同じconnect reportへ保存します。

## hardware revision matrix

各試験は 2 種類の NDM24 hardware revision で実施します。技適番号そのものは個体管理表に記録し、ここでは revision A/B とします。

| 試験 | revision A | revision B |
|---|---|---|
| raw `R` とランプ挙動 | 合格 (2026-07-29) | 合格 (2026-07-29) |
| `AT` quick test | 合格 (2026-07-29) | 合格 (2026-07-29) |
| AT識別情報 | 取得済み (2026-07-29) | 取得済み (2026-07-29) |
| 疑似 PSTN connect | 合格 (2026-07-29) | 合格 (2026-07-29) |
| binary pattern | 合格 (2026-07-29) | 合格 (2026-07-29) |
| TX 255byte最大burst | 合格 (2026-07-29) | 合格 (2026-07-29) |
| 30 分 soak | 合格 (2026-07-29) | 未実施 |
| NMITIMEN gating回帰 | 合格 (2026-07-29) | 合格 (2026-07-29) |

revision B の最新の疑似 PSTN connect 合格記録は test ID `unix-1785329111-revision-b` です。`AT&F`、`AT%B2400`、`ATS7=60`、`ATX3`、`ATDT0` のechoはすべて完全で、各transaction前後のRX discard counterは0のままでした。DFM-56U は `RING`、`CONNECT 115200` を返し、NDM24 は `CONNECT 2400` を受信して `CONNECTED` へ遷移しました。10秒保持中の未処理RXは0byteです。DFM-56UのDTRを下げた直後にはキャリア切断過渡の `07 99 62 A1 74 DD 6B EE 1E` が入り、続く `NO CARRIER` を受信して `READY` へ戻りました。最終snapshotはRX read/write indexがともに105、TX read/write indexがともに42で、error、timeout、RX/TX overflow、poll limit、discard、terminal droppedがすべて0です。transaction別trace、双方のAT transcript、切断前後のraw RX列は `build/hardware-tests/unix-1785329111-revision-b/connect-test.json` に保存されています。

revision B の最新のbinary pattern合格記録は test ID `unix-1785330333-revision-b` です。V.22bis 2400bpsで `0x00`～`0xFF` を双方へ256byteずつ転送し、NDM24→DFM-56U、DFM-56U→NDM24とも不一致0でした。さらにTX ring全容量へ一度にqueueした `0x00`～`0xFE` の255byte最大burstもDFM-56Uで完全一致しました。burst前後のTX byte countは298から553、TX ringは42/42から41/41へ一周して空に戻り、予定どおりpoll budgetを7回使い切りました。stress traceに残った96件のTX eventはすべてData2=`$0200`で、途中の状態変化はありません。最終状態は `READY`、RX read/write index 105/105、TX read/write index 41/41です。error、timeout、RX/TX overflow、discard、terminal droppedは0、poll limitは最大burstの期待値7です。記録は `build/hardware-tests/unix-1785330333-revision-b/binary-pattern-test.json` に保存しています。

revision B のAT識別情報は [NDM24 AT識別情報](ndm24-hardware-identification.md)にまとめています。正式記録のtest IDは `unix-1785316604-revision-b-identification` で、16コマンドすべてが `OK` または `ERROR` まで完了し、最終状態は `READY`、error、timeout、overflow、discard、trace overwriteはいずれも0でした。

revision A のAT識別情報も同じ文書にまとめています。正式記録のtest IDは `unix-1785317352-revision-a-identification` です。16コマンドすべてが完了し、最終状態は `READY`、error、timeout、overflow、discard、trace overwriteはいずれも0でした。`ATI3`、`ATI4`、`ATI5` の長い応答ではpoll budget exhaustionが各1回発生しましたが、次のメインループで継続され、raw responseは欠落なく取得できています。

revision A のquick testではraw `R`を含む初期化と `AT` probeを2回実行し、最終状態は `READY`、RX read/write indexは9/9、TX read/write indexは4/4でした。error、timeout、RX/TX overflow、poll limit、discard、terminal droppedはすべて0です。その後、raw `R`による初期化を単独で再実行し、電源ランプが一定時間点滅することを目視確認しました。後続の `AT` probeも成功し、`READY`へ復帰しています。

revision A の疑似 PSTN connect合格記録はtest ID `unix-1785319664-revision-a` です。DFM-56Uは `CONNECT 115200`、NDM24は `CONNECT 2400` を返し、10秒保持中の未処理RXは0byteでした。DTR切断直後にはキャリア切断過渡の `F0 0D C9 D7 5D 3A D8 79 FD 1A 05` が入り、その後 `NO CARRIER` を受信して `READY` へ戻りました。最終RX read/write indexは107/107、TX read/write indexは42/42で、error、timeout、RX/TX overflow、poll limit、discard、terminal droppedはすべて0です。記録は `build/hardware-tests/unix-1785319664-revision-a/connect-test.json` に保存しています。

revision A の最新のbinary pattern合格記録はtest ID `unix-1785330743-revision-a` です。V.22bis 2400bpsで通常の `0x00`～`0xFF` を双方へ256byteずつ転送し、さらにTX ring全容量へ一度にqueueした `0x00`～`0xFE` の255byte最大burstをNDM24→DFM-56Uへ転送しました。3列とも不一致0です。burst前後のTX byte countは298から553、TX ringは42/42から41/41へ一周して空に戻り、poll budgetを期待値どおり7回使い切りました。stress traceに残った96件のTX eventはすべてData2=`$0200`で、途中の状態変化はありません。最終状態は `READY`、RX read/write index 107/107、TX read/write index 41/41です。error、timeout、RX/TX overflow、discard、terminal droppedは0、poll limitは最大burstの期待値7です。記録は `build/hardware-tests/unix-1785330743-revision-a/binary-pattern-test.json` に保存しています。

revision A の30分carrier soak合格記録はtest ID `unix-1785320450-revision-a` です。V.22bis 2400bpsのcarrierを1800秒保持し、5分ごとの中間snapshotはいずれも `CONNECTED`、RX/TX ring空、error、timeout、RX/TX overflow、poll limit、discard、terminal droppedが0でした。保持終了後、DTR切断直後にキャリア切断過渡の `01 A1 20 46 D3 E3 DE 74 C8 FE D2 87` が入り、その後 `NO CARRIER` を受信して `READY`へ復帰しました。最終RX read/write indexは108/108、TX read/write indexは42/42で、全エラーカウンタは0です。記録は `build/hardware-tests/unix-1785320450-revision-a/connect-test.json` に保存しています。

NMITIMEN gatingの初回候補実装に対するrevision A回帰試験は、疑似PSTN connectがtest ID `unix-1785323651-revision-a`、binary patternが `unix-1785323703-revision-a` で合格しました。ただし、実機試験後の静的確認でDP=`$4000`から `.lobyte($4200)` を使っていたため、NMITIMENではなく `$4000` を書いていたことが判明しました。この2記録は既存動作に回帰がないことだけを示し、NMI gatingの合格根拠には使用しません。

実際の `$4200` を操作する最初の修正版では、VBlank中にNMI enableを復元したときの即時NMI再発火により、フレームカウンターが実時間より異常に速く進み、`AT` probeが無応答のままtimeoutしました。最終実装では無効化前と復元前に `$4212` (`HVBJOY`) bit 7が0になるまで待ち、切り替えを表示期間中に限定しています。生成ROMの静的確認では `$4212` のabsolute read、`$4200` のabsolute `STZ` / `STA` を確認し、誤ったdirect-page `$00` 書き込みがないことも確認しました。

最終実装のrevision A回帰では、起動時probeが受信9byte、timeout 0で `READY` へ到達しました。続くNMI有効状態からのクイック再初期化も約10秒で合格し、`reinitialize=2`、累計受信18byte、timeout 0、`reset_start_frame=1392` でした。この試験はraw `R`区間でNMIを退避・復元した後、NMIで更新される600フレームのguardを完走しなければ成功しないため、NMI復帰の動作確認を兼ねます。

同じ最終実装によるrevision A疑似PSTN connectはtest ID `unix-1785324347-revision-a`、binary patternは `unix-1785324397-revision-a` で合格しました。connectの最終状態は `READY`、RX read/write index 107/107、TX read/write index 42/42で、error、timeout、RX/TX overflow、poll limit、discard、terminal droppedはすべて0です。binary patternの最終状態も `READY`、双方向の全byte列が一致し、RX read/write index 205/205、TX read/write index 80/80、全エラーカウンターは0です。

revision Bでも同じNMITIMEN gating最終実装を再試験しました。交換中に入った過渡データを除外するためROMを再起動して診断状態を初期化し、起動時probeとNMI有効状態からのクイック再初期化を取り直しています。最終状態は `READY`、累計受信18byte、送信8byte、`reinitialize=2`で、timeout、RX/TX overflow、poll limit、discard、terminal droppedはすべて0でした。続く疑似PSTN connectとbinary patternも上記の最新test IDで合格したため、revision BのNMITIMEN gating回帰を合格とします。

実機試験を行うまでは、ビルド成功をハードウェア合格として扱いません。差が出た場合は診断 snapshot、trace、QUsb2Snes 時刻、必要に応じてロジックアナライザ capture を同じ試験 ID に紐付けます。
