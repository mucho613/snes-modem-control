# NDM24 AT識別情報

NDM24自身がATコマンドで返す識別情報をhardware revision別に保存します。設定変更や回線接続を伴わない読み取り専用の照会です。ここに記す値はモデムの応答を転記したものであり、数値コードの意味を未確認のまま推測で断定しません。

## 主なrevision差

| 項目 | revision A（前期） | revision B（後期） |
|---|---|---|
| `ATI` / `ATI0` | `144` | `14400` |
| `ATI1` | `005` | `255` |
| `ATI3` | `WS-1414EV7G`、`VERSION 0.10.3`、`02-06-02-01` | `V2.200F-V32_ACF_DS1JS` |
| `ATI4` | `UMC V.32bis/FAX/VOICE MODEM` | `VER 1.05` |
| `ATI5` | country default/settingを文章で返す | `043` |
| `ATI6` | 情報行なしで `OK` | `RC144DPFSP Rev 44BC` |
| `ATI7` | 情報行なしで `OK` | `016` |
| `ATI8` / `ATI9` | 情報行なしで `OK` | `ERROR` |

両revisionとも `ATI2` はchecksum結果と最終結果の2つの `OK` を返し、`AT+GMI`、`AT+GMM`、`AT+GMR`、`AT+GSN`、`AT+GCAP` は `ERROR` を返しました。識別文字列から、両revisionはモデム内部の実装が大きく異なると判断できます。ただし、文字列と物理基板上の部品との対応は分解個体の部品表で別途確認します。

## revision A

- 取得日: 2026-07-29
- test ID: `unix-1785317352-revision-a-identification`
- 原記録: `build/hardware-tests/unix-1785317352-revision-a-identification/at-identification.json`
- 結果: 16コマンドすべて応答終端まで取得

| コマンド | 最終結果 | 情報行 |
|---|---|---|
| `ATI` | `OK` | `144` |
| `ATI0` | `OK` | `144` |
| `ATI1` | `OK` | `005` |
| `ATI2` | `OK` | `OK` |
| `ATI3` | `OK` | `WS-1414EV7G` / `VERSION 0.10.3` / `02-06-02-01` |
| `ATI4` | `OK` | `UMC V.32bis/FAX/VOICE MODEM` |
| `ATI5` | `OK` | `COUNTRY DEFAULT : 043` / `COUNTRY SETTING : 043` |
| `ATI6` | `OK` | なし |
| `ATI7` | `OK` | なし |
| `ATI8` | `OK` | なし |
| `ATI9` | `OK` | なし |
| `AT+GMI` | `ERROR` | なし |
| `AT+GMM` | `ERROR` | なし |
| `AT+GMR` | `ERROR` | なし |
| `AT+GSN` | `ERROR` | なし |
| `AT+GCAP` | `ERROR` | なし |

`ATI3`、`ATI4`、`ATI5` のraw responseはそれぞれ55、42、59byteあり、各コマンドで32byteのpoll budget exhaustionが1回発生しました。いずれも次のメインループで受信を継続し、RX discard、overflow、trace overwriteなしで完全な応答を取得しています。poll budget exhaustionはデータ損失ではなく、1回の `modemPoll` を有限時間で戻す設計が働いた記録です。

取得終了時のドライバは `READY`、RX ring indexは104/104、TX ring indexは110/110でした。`last_error`、timeout、RX/TX overflow、RX discard、terminal drop、trace overwriteはいずれも0です。poll budget exhaustionは上記3件だけで、コマンド別の前後カウンタも原記録に保存しています。

## revision B

- 取得日: 2026-07-29
- test ID: `unix-1785316604-revision-b-identification`
- 原記録: `build/hardware-tests/unix-1785316604-revision-b-identification/at-identification.json`
- 結果: 16コマンドすべて応答終端まで取得

| コマンド | 最終結果 | 情報行 |
|---|---|---|
| `ATI` | `OK` | `14400` |
| `ATI0` | `OK` | `14400` |
| `ATI1` | `OK` | `255` |
| `ATI2` | `OK` | `OK` |
| `ATI3` | `OK` | `V2.200F-V32_ACF_DS1JS` |
| `ATI4` | `OK` | `VER 1.05` |
| `ATI5` | `OK` | `043` |
| `ATI6` | `OK` | `RC144DPFSP Rev 44BC` |
| `ATI7` | `OK` | `016` |
| `ATI8` | `ERROR` | なし |
| `ATI9` | `ERROR` | なし |
| `AT+GMI` | `ERROR` | なし |
| `AT+GMM` | `ERROR` | なし |
| `AT+GMR` | `ERROR` | なし |
| `AT+GSN` | `ERROR` | なし |
| `AT+GCAP` | `ERROR` | なし |

`ATI6` の `RC144DPFSP Rev 44BC` はモデム自身が返した識別文字列です。物理基板上の部品型番との対応は、分解個体の部品表と照合するまで確定扱いにしません。`ATI3`～`ATI7` の各値もrevision Aとの比較対象として原文のまま保持します。

`ATI2` の完全な応答は `ATI2 CR CR LF OK CR LF CR LF OK CR LF` です。最初の `OK` は情報行、最後の `OK` はATコマンドの最終結果です。最終結果の検出後に到着した6byteもRX ringから回収しており、欠落ではありません。

取得終了時のドライバは `READY`、RX ring indexは65/65、TX ring indexは110/110でした。`last_error`、timeout、RX/TX overflow、poll limit、RX discard、terminal drop、trace overwriteはいずれも0です。raw byte列、コマンド別trace、照会前後のカウンタは原記録に保存しています。

予備取得では `AT+GCAP` が一度だけ10秒以内に応答終端へ到達せずタイムアウトしました。ROMを再起動して同じ16コマンドを再取得した上記の正式記録では、`AT+GCAP` は `ERROR` を返して正常に完了しています。revision B固有の確定事項とはせず、revision A取得時とrevision B再試験時の再現性確認項目にします。

## 取得方法

初期probeが `READY` になった後に次を実行します。

```powershell
cargo run -p ndm24-tools -- identify --revision B
```

revision Aでは引数だけを `--revision A` に変更します。応答終端が得られない場合も、それ以前の結果と失敗コマンドの前後snapshotを含む部分レポートを保存します。
