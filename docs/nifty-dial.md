# @nifty 実回線ダイヤルアップ試験

## 状態

実回線試験用のSFC側一時資格情報経路、PAP/CHAP-MD5 client、Windows CLIは
実装済みです。
2026-07-31にDFM-56Uをアナログ電話ポートへ単独接続し、WSL2の`pppd`
clientで基準試験を行いました。続いてrevision AのNDM24を使ったSFC実機試験でも、
Niftyへの発信、CHAP-MD5認証、IPCP、DNS問い合わせ、正常切断まで合格しました。
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

DFM-56U基準試験ではNiftyがCHAP-MD5を要求し、そのままChallenge、
Response、Successへ進みました。PAPへのfallbackは観測されていません。
SFC側も同じCHAP-MD5を優先して受理し、PAPは閉じたfixtureとの互換性のため
残します。MD5標準vectorと完全なChallenge/Response/Success transcriptは
MesenCE常設セルフテストで検証します。

基準試験で観測した条件は次のとおりです。

- Niftyの初回LCP Request: MRU 1524、ACCM 0、CHAP-MD5、PFC、ACFC
- `pppd`がPFC/ACFCをRejectすると、次のRequestから両optionが除外された
- CHAP Challengeは16byte、Success Messageは空
- IPCPはlocal/peer IPv4とPrimary/Secondary DNSまで成立した
- 割当local/peer public IPはGit管理文書では非公開
- Primary DNS `61.207.9.37`、Secondary DNS `61.207.9.5`
- 30秒の観測後、同一IdentifierのTerminate-Request/Ackで終了
- DTR drop後、DFM-56UはWindowsのCOM5へ復帰

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

転送はmailbox ABI version 9の3命令を使います。命令名は互換性のため
`pap_*`のままですが、格納先はPAP/CHAP-MD5共通です。

1. `pap_credentials_clear`
2. `pap_peer_id_set`
3. `pap_password_set`

途中で失敗した場合は、SFC自身とCLIの双方がclearを試みます。SFCはmailbox
arguments、PPP送信元buffer、送信ringの消費済みslotをzero化し、認証終了、
失敗、切断時にWRAM上の一時資格情報を消去します。Windows側も入力文字列、
mailbox arguments、QUsb2Snes実行payloadを使用後にzero化します。ただし、
OSやUSB stack内部の一時コピーを完全に消去できる保証まではしません。

## 実行ガード

次のコマンドは実際に通話料金が発生するため、CHAP-MD5実装、MesenCE、
FXPAK PRO、疑似PSTN回帰試験、物理配線の再確認がすべて済むまで実行しません。

```powershell
cargo run -p ndm24-tools -- nifty-dial
```

実行時にも料金警告を表示し、利用者が正確に`DIAL`と入力しなければ発信しません。
成功・失敗を問わず、資格情報clear、LCP Close、PPP receive停止を試みます。
上限や後始末に失敗した場合は、NDM24がオンフックへ戻ったことを物理的に確認
します。

DNS、ICMP、NTPなどを別のPowerShellから試す場合は、`--hold`を指定します。
接続直後の既定DNS試験が成功すると、runnerは最大10分間接続を維持します。

```powershell
cargo run -p ndm24-tools -- nifty-dial --hold
```

runnerに待機メッセージが表示された後、別のPowerShellでアプリケーション
コマンドを実行します。終了時はrunner側でEnterを押すかCtrl+Cを入力します。
どちらも資格情報clear、LCP Close、PPP receive停止からなる通常の後始末へ
合流します。操作がなくても10分で自動的に同じ切断処理を開始します。
`--hold`を付けない従来動作は、既定DNS試験の直後に切断し、発信から後始末まで
引き続き120秒を上限とします。hold時の全体上限は後始末15秒を含む12分です。

## 記録方針

Git管理文書には認証方式、MRU/ACCM、IPCP/DNS option、成否だけを残します。
割り当てられたpublic IP addressは伏せます。完全なIPCP transcriptが必要な
場合は、Gitから除外されている`build/hardware-tests/`以下だけに保存します。
PAP/CHAP payload、@nifty ID、ログインパスワードはローカルartifactにも
保存しません。

## SFC実機試験結果

2026-07-31にrevision AのNDM24を発信確認済みのアナログ電話ポートへ単独接続し、
`nifty-dial`で1回だけ発信しました。`AT&F`、`ATM0`、`AT%B2400`、
`ATS7=60`、`ATX4`はすべて`OK`となり、`ATDT0570077705`で`CONNECT`しました。
LCP、CHAP-MD5、IPCPはすべて成立し、IPCPで得たPrimary DNS
`61.207.9.37`を使う`example.com`のA問い合わせも成功しました。回答2件を
82frameで受信し、FCS、IPv4 checksum、UDP checksum、DNS drop/timeoutは
すべて0でした。

試験後は一時資格情報の長さがともに0で、clear済みを示す診断状態になりました。
LCP/IPCPは`Closed`、PPP receiveは停止し、`NO CARRIER`とcarrier lossを
確認しています。割り当てられたpublic IP address、@nifty ID、password、
CHAP payloadはGit管理文書や試験artifactへ保存していません。
