# @nifty 実回線ダイヤルアップ試験

## 状態

実回線試験用のSFC側PAP資格情報経路とWindows CLIは実装済みですが、
まだ発信していません。最初にDFM-56Uを同じアナログ電話ポートへ単独接続し、
WSL2の`pppd` clientでLCPが提示する認証方式とIPCP/DNSを記録します。
NDM24とDFM-56Uを同じ回線へ同時接続しません。

DFM-56Uをアナログ電話ポートへ単独接続し、USB bus IDを`usbipd list`で確認した
後、Windows PowerShellから次を実行します。既定値は現在確認済みの
`Ubuntu-22.04`とbus ID `6-3`です。

```powershell
.\tools\nifty-reference\nifty-reference.ps1
```

このrunnerにも正確な`DIAL`入力が必要です。資格情報は標準入力から`pppd`の
option streamへ渡し、引数や一時設定ファイルには置きません。`pppd`の出力は
保存前にID、password、PAP/CHAP payloadをredactし、30秒のPPP観測後または
全体120秒で終了してDTRを落とします。

SFC側は現在PAP clientを実装し、CHAP要求にはPAPをConfigure-Nakします。
DFM-56U基準試験でCHAP-MD5からPAPへの収束を確認できた場合だけ、NDM24で
次段階へ進みます。MS-CHAP、EAPなど別方式が必須なら発信試験を止め、
先に対応方針を決めます。

## 接続条件

- アクセスポイント: `0570-077-705`
- CLI内部の発信列: `ATDT0570077705`
- NDM24設定: `AT&F`、`ATM0`、`AT%B2400`、`ATS7=60`、`ATX4`
- `ATX3`によるblind dialへのfallbackなし
- 自動再発信なし
- 発信・PPP・後始末を含む上限120秒
- PPP成立後のアプリケーション試験は、IPCPで得たPrimary DNSを使う
  `example.com`のA問い合わせ1回だけ

[Nifty公式ダイヤルアップ設定](https://support.nifty.com/support/manual/internet/dialup/ap/index.htm)
では、接続のユーザー名は@nifty ID、パスワードはログインパスワードです。
[@nifty IDの形式](https://faq.support.nifty.com/4240)は英字3文字と数字5文字、
[ログインパスワード](https://faq.support.nifty.com/4257)は6～24文字です。
CLIは公式に記載された文字だけを受理します。

## 資格情報の扱い

`nifty-dial`はIDを標準入力、パスワードをマスク入力で受け取ります。
コマンドライン引数、環境変数、設定ファイル、ROM、source、Git管理ファイル、
JSON reportへは保存しません。

転送はmailbox ABI version 9の3命令を使います。

1. `pap_credentials_clear`
2. `pap_peer_id_set`
3. `pap_password_set`

途中で失敗した場合は、SFC自身とCLIの双方がclearを試みます。SFCはmailbox
arguments、PPP送信元buffer、送信ringの消費済みslotをzero化し、認証終了、
失敗、切断時にWRAM上の一時資格情報を消去します。Windows側も入力文字列、
mailbox arguments、QUsb2Snes実行payloadを使用後にzero化します。ただし、
OSやUSB stack内部の一時コピーを完全に消去できる保証まではしません。

## 実行ガード

次のコマンドは実際に通話料金が発生するため、DFM-56U基準試験、MesenCE、
FXPAK PRO、疑似PSTN回帰試験、物理配線の再確認がすべて済むまで実行しません。

```powershell
cargo run -p ndm24-tools -- nifty-dial
```

実行時にも料金警告を表示し、利用者が正確に`DIAL`と入力しなければ発信しません。
成功・失敗を問わず、資格情報clear、LCP Close、PPP receive停止を試みます。
上限や後始末に失敗した場合は、NDM24がオンフックへ戻ったことを物理的に確認
します。

## 記録方針

Git管理文書には認証方式、MRU/ACCM、IPCP/DNS option、成否だけを残します。
割り当てられたpublic IP addressは伏せます。完全なIPCP transcriptが必要な
場合は、Gitから除外されている`build/hardware-tests/`以下だけに保存します。
PAP/CHAP payload、@nifty ID、ログインパスワードはローカルartifactにも
保存しません。
