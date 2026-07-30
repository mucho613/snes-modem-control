# snes-modem-control

[![Build](https://github.com/mucho613/snes-modem-control/actions/workflows/build.yml/badge.svg)](https://github.com/mucho613/snes-modem-control/actions/workflows/build.yml)

スーパーファミコンと NTT DATA NDM24 をコントローラーポート経由で通信させるための、実験用ドライバと Windows 向け開発ツールです。JRA PAT の実通信をロジックアナライザで観測した結果を基準に、初期化、非同期送受信、状態管理、常設診断機能を整理しています。

現時点の到達点は、NDM24 固有の `R` 初期化、`ATM0` による応答確認とスピーカー無効化、256 バイトの送受信リング、L/Rで切り替える人間向けステータス画面と32文字幅生ログ、QUsb2Snes 経由の監視・テスト・ROM 転送です。PPPはRFC 1662非同期フレーミング、LCP、PAP client、IPCP、IPv4 packet層、ICMP Echo responder/requester、汎用UDP datagram送信、NTP client、最小DNS A clientをRust参照実装と65816へ実装し、NDM24のRX/TXリングへ中断・再開可能な形で接続済みです。revision AとDFM-56Uを使うWSL2対向環境ではLCP、PAP認証、IPCPまで実対向で合格し、SFC側`10.24.0.2`と対向`10.24.0.1`を確定しました。IPv4、ICMP Echo、UDP/NTP/DNSはMesenCEおよびFXPAK PRO実機の常設セルフテストに加え、疑似PSTNのV.22bis 2400 bit/s回線上でも送受信に合格しています。PPPサーバーには、起動中だけSFCの外向きIPv4をWSLの既定回線へNATする構成も追加済みです。SFC実機から公開IPv4 `1.1.1.1`へのICMP Echo往復と、同じホストのUDP port 53を使う公開DNS A問い合わせに合格しています。NTPで取得したJST時刻はSFCのフレーム進行を基準に表示します。TCPは未実装です。

## Windows での開始

64 ビット版 Windows と Rust を用意し、PowerShell で次を実行します。

```powershell
cargo xtask bootstrap
cargo xtask check
cargo xtask mesen-test
```

最初のコマンドは、ハッシュを固定した公式 cc65 Windows スナップショットを `.tools/cc65` へ配置します。二番目のコマンドは、仕様・フォント生成物、Rust テスト、通常 ROM、スモークテスト ROM、フォント確認 ROM をまとめて検証します。三番目はMesenCEのheadless test runnerで通常ROMの常設PPPセルフテストを実行し、NDM24やFXPAK PROを使わず終了コードで合否を返します。

生成物:

- `build/normal/modem-control.sfc`
- `build/smoke/modem-control.sfc`
- `build/font-test/modem-control.sfc`
- 各ディレクトリの `.lbl`、`.map`、`.dbg`

QUsb2Snes と USB 接続済み FXPAK PRO が起動している場合、スモークテスト ROM の転送と起動は次の一行です。

```powershell
cargo xtask deploy --smoke
```

起動後の初期化テストと状態監視:

```powershell
cargo run -p ndm24-tools -- test
cargo run -p ndm24-tools -- mailbox ppp-self-test
cargo run -p ndm24-tools -- monitor
cargo run -p ndm24-tools -- ppp-monitor
cargo run -p ndm24-tools -- frame-rate --seconds 15
cargo run -p ndm24-tools -- ntp-request
cargo run -p ndm24-tools -- icmp-echo 1.1.1.1
cargo run -p ndm24-tools -- dns-query example.com --resolver 1.1.1.1
cargo run -p ndm24-tools -- identify --revision B
cargo run -p ndm24-tools -- connect-test --revision B --port COM5
cargo run -p ndm24-tools -- binary-test --revision B --port COM5
.\tools\ppp-server\ndm24-ppp-server.ps1 Install
.\tools\ppp-server\ndm24-ppp-server.ps1 Probe
```

実機を使う手順と合格条件は [ハードウェアテスト手順](docs/hardware-test.md)、取得済みの機器情報は [NDM24 AT識別情報](docs/ndm24-hardware-identification.md)、ドライバ API は [NDM24 ドライバ設計](docs/ndm24-driver.md)、PPP対向環境は [WSL2 PPPサーバー](docs/ppp-server.md)、次段階は [PPP実装方針](docs/ppp.md)を参照してください。

## 仕様と生成物の同期

プロトコル定数、状態、モデム・PPP診断 ABI、メールボックス ABI、ターミナル配色の正本は [`spec/ndm24.toml`](spec/ndm24.toml)です。フォント原本は固定コミットの [`font8x8_basic.h`](third_party/font8x8/font8x8_basic.h)です。変更後は次を実行します。

```powershell
cargo xtask generate
cargo xtask check
```

生成対象を直接編集してはいけません。`check` は正本と Assembly、Rust、文書、`font.bin`、`palette.bin`、PNGプレビューがずれている場合に失敗します。

## 関連資料

- [JRA PAT の観測結果と実装判断](docs/jra-pat-observations.md)
- [NDM24 ドライバ設計](docs/ndm24-driver.md)
- [NDM24 AT識別情報](docs/ndm24-hardware-identification.md)
- [32文字幅ターミナル](docs/terminal.md)
- [ステータス画面とアプリケーション・アダプター](docs/status-screen.md)
- [font8x8の出所・生成・確認手順](docs/font.md)
- [Windows 開発環境](docs/windows-development.md)
- [WSL2 PPPサーバー](docs/ppp-server.md)
- [生成済みモデム・PPP診断／メールボックス ABI](docs/generated/diagnostic-abi.md)
- [JRA PAT モデム設定プロファイル](profiles/jra-pat.toml)
- [第三者由来データの通知](THIRD_PARTY_NOTICES.md)
