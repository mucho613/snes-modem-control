# 32文字幅ターミナル

## 目的

添付の実機記録で使用していた低解像度ターミナルを標準画面とします。80×24高解像度POCとそのHDMA、window、生成素材は削除し、NDM24通信の内容を目視できる単純な経路へ戻しています。

起動時は次のヘッダーを表示します。

```text
modem-control-test
--------------------------------
```

通常ROMはこの画面で待機します。スモークテストROMはraw `R`による初期化後に`AT CR LF`を送り、NDM24から返ったechoと結果コードを続けて表示します。送信内容をローカルechoしないため、NDM24のechoと二重表示になりません。

## 表示構成

- SNES BG mode 0
- 8×8 pixel font
- 32列×64行の循環tilemap
- BG1 tilemap base: VRAM `$4000`
- 受信に追従する自動vertical scroll
- VBlankごとに最大32バイト描画
- VBlank内部ではX/Yを16ビット幅へ正規化してから描画処理を呼び、割り込み時のCPU幅にかかわらず保存・復元するスタック量を一致させる

印字可能ASCIIにはPublic Domain表記のあるfont8x8を使用します。背景は完全な黒、文字はSFC BGR555の`$6F7B`（`RGB(222,222,222)`相当）です。`assets/font.bin`、`assets/palette.bin`は直接編集せず、`cargo xtask generate`で生成します。

列数、行数、tilemap、表示キュー、描画上限、配色の正本は`spec/ndm24.toml`の`[terminal]`です。フォントの出所と確認方法は [font8x8の出所・生成・確認手順](font.md)にあります。

## 表示ミラー

通信RXと表示RXは所有権を分離しています。

```mermaid
flowchart LR
    M["NDM24 accepted RX"] --> R["255-byte communication RX ring"]
    M --> T["255-byte display mirror"]
    R --> A["AT parser / future PPP"]
    T --> V["VBlank renderer"]
    V --> P["32-column terminal"]
```

表示ミラーは256バイトを確保し、read indexとwrite indexの一致を空状態に使うため実容量は255バイトです。満杯の場合は最古の表示待ちバイトを捨て、最新の出力を保存します。破棄数は診断ABIの32ビット `terminal_dropped` で確認できます。

この破棄は表示だけに作用します。通信RXリング、AT解析、将来のPPP入力は変更しません。

## 文字処理

| byte | 動作 |
|---:|---|
| `$0D` | 現在行の先頭へ移動 |
| `$0A` | 次の行の先頭へ移動 |
| `$08` | カーソルを1文字戻す |
| `$20`–`$7E` | ASCII tileを描画 |
| その他 | 描画せず無視 |

ANSI escape sequence、色、任意cursor positioningは未対応です。未対応文字を描画しない場合も、元の通信RXデータは変更しません。
