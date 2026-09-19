# RoomCanvas

古いiPadを、部屋の常設ディスプレイと操作端末に。

**非商用向けソース公開ソフトウェア**です。商用利用を制限するため、OSI定義のオープンソース（OSS）ではありません。[ライセンスの説明](docs/LICENSE_GUIDE.md)を確認してください。

## できること

- 横向き4:3の3ページ：部屋の操作／ダッシュボード／その他。通常画面はスクロールなし。
- 秒付き12時間時計、バッテリー残量、天気、室温・湿度。
- 日曜始まりの月間カレンダーと予定。日曜赤・土曜青・平日の祝日緑。
- iPadに同期されたGoogleカレンダー等を読み取り専用で表示。
- SwitchBot機器・シーンの操作。お気に入りは「機器」ではなく「機能」を最大4つ登録。
- SwitchBot Remoteの丸・凹ボタンから呼び出し。画面ポップアップとWebhook通知。
- Discord、汎用JSON、text形式のWebhook。Discordのみ任意の`@everyone`に対応。
- 外置きモードと管理PIN。アクセスガイドとの併用でアプリを固定。

## まず読む

| 目的 | ガイド |
|---|---|
| iPadへインストールする | [導入手順](docs/INSTALL.md) |
| SwitchBotリモートボタンを呼び鈴にする | [写真不要で進められる登録手順](docs/REMOTE_BUTTON.md) |
| Discord以外へ通知する | [Webhookの設定とJSON仕様](docs/WEBHOOKS.md) |
| 利用・再配布の条件を知る | [ライセンス](docs/LICENSE_GUIDE.md)・[第三者の権利と出典](THIRD_PARTY_NOTICES.md) |
| データの扱いを知る | [プライバシー](docs/PRIVACY.md) |
| 不具合を報告・改善する | [コントリビュート](CONTRIBUTING.md)・[セキュリティ](SECURITY.md) |

## 必要なもの

- iPadOS 15以降のiPad。実機確認はiPad Air 2 / iPadOS 15.8.8。
- Mac、Xcode、Apple Account、自分の署名設定。App Store配布ではありません。
- 通知を使う場合：HTTPS Webhookとインターネット接続。
- 機器操作を使う場合：SwitchBot Token / Secret。BLE呼び出しだけなら不要。

第三者ライブラリは組み込んでいません。SwiftUI、EventKit、Core Bluetooth、Core Location、CryptoKit等のApple標準フレームワークを利用しています。

## 最短の流れ

1. リポジトリを取得して`RoomCanvas.xcodeproj`をXcodeで開く。
2. TeamとBundle Identifierを自分用に設定し、接続したiPadへRunする。
3. アプリの設定で部屋名を変更し、**デモモードをオフ**にする。
4. カレンダー、天気、必要なSwitchBot機器を設定する。
5. Webhookを保存し、画面の「呼び出す」で通知を確認する。
6. リモートボタンを登録して、アプリを前面に表示したまま使う。

初回はデモモードです。デモ中は実際の機器操作・通知を送信しません。新規設定でのBLE自動通知と`@everyone`はオフです。

## 動作上の範囲

**BLE呼び出しは前面常設向けです。画面ロック・バックグラウンド中の呼び出しは休止します。** 前面復帰・アプリ起動時に有効設定を復元しますが、休止中の押下を後から通知する機能はありません。初回の広告は基準値に使います。

連打抑止は30秒。通知成功は受信サーバーの受理であり、全端末への到着・既読保証ではありません。通信失敗の自動再送はありません。緊急通報や生命・安全に関わる呼び出し用途には対応していません。

赤外線家電の実状態は取得できません。エアコンにはこのアプリから最後に送信した設定を表示します。リモートボタンのBLE形式は実測に基づくため、全機種・全ファームウェアの互換性を保証しません。

## 開発・配布

```sh
./scripts/check-policies.command
ROOMCANVAS_TEAM_ID=YOURTEAMID ./scripts/build-installer.command
```

チェックにはmacOSのXcode Command Line ToolsとPython 3が必要です。インストーラは`Installer/RoomCanvas.ipa`へ生成します。署名付きIPA、プロファイル、実機ログ、個人情報を含むスクリーンショットはGitに含めません。署名済みIPAを誰のiPadにも入れられるわけではありません。

バージョン：0.10.2。通知形式のテスト、実機向けReleaseビルドを実施。Discord以外の各社サービスへの実配信は利用先ごとに確認してください。

## ライセンス

[PolyForm Noncommercial License 1.0.0](LICENSE)。非商用の利用・改変・再配布はライセンス条件の範囲で可能です。商用利用の許諾は含みません。第三者のデータやサービスにはそれぞれの条件が適用されます。
