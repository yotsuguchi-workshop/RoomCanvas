# 導入手順

## 1. 用意するもの

MacとXcode、Apple Account、データ通信できるUSBケーブル、iPadOS 15以降のiPadを用意します。ビルド確認環境はXcode 27です。古いXcodeではSwiftコンパイラの構文互換性を確認していません。

## 2. ソースを取得

```sh
git clone https://github.com/yotsuguchi-workshop/RoomCanvas.git
cd RoomCanvas
open RoomCanvas.xcodeproj
```

Gitを使わない場合はGitHubのCode → Download ZIPで取得して展開します。

## 3. 自分の署名を設定

1. XcodeのSettings → AccountsにApple Accountを追加。
2. 左の青いRoomCanvasプロジェクト → TARGETSのRoomCanvas → Signing & Capabilitiesを開く。
3. Automatically manage signingを有効にし、Teamに自分のチームを選ぶ。
4. Bundle Identifierを自分固有の値（例：`jp.example.myroomcanvas`）へ変更。
5. iPadを接続してロック解除し、信頼確認が出たら「信頼」。
6. Xcode上部の実行先を実際のiPadにし、▶ Run。

公開ソースのTeamは空欄です。署名証明書・秘密鍵は同梱していません。既存インストールと異なるBundle Identifierでは別アプリとなり、設定・Keychainは引き継げません。現在使っている端末を更新する場合は、従来と同じ署名チーム・Bundle Identifierを使ってください。

iPad側で開発者を信頼するよう求められた場合は、設定 → 一般 → VPNとデバイス管理で確認します。iPadOS 16以降は開発者モードが必要になる場合があります。iPadOS 15のAir 2には同じ項目はありません。

無料のPersonal Teamには利用期限・機能上の制約があります。期限切れ時は再ビルド・再インストールが必要です。常設運用でも署名は無期限ではありません。[Appleのアカウント比較](https://developer.apple.com/support/compare-memberships/)

## 4. アプリ内を設定

- 部屋名：設定で入力。
- 実運用：デモモードをオフ。
- カレンダー：iPadの設定でGoogle等のアカウントを追加し、カレンダー同期を有効化。RoomCanvasで読み取りを許可し、表示するカレンダーを選択。Googleとの同期自体はiPadOSが行います。
- 天気：現在地を許可、または地域名を入力して保存。
- 機器操作：SwitchBotアプリで取得したToken / SecretをアプリのSecureFieldに入力。
- 呼び出し：[Webhook設定](WEBHOOKS.md) → [リモートボタン登録](REMOTE_BUTTON.md)の順に進む。

## 5. アプリから抜けにくくする

iPadの設定 → アクセシビリティ → アクセスガイドをオン。解除用コードを設定し、画面の自動ロックを「しない」に設定します。RoomCanvasを開き、Air 2ではホームボタンを3回押して開始。タッチは有効のままにします。解除もホームボタン3回とコード入力です。アプリ内の管理PINとは別です。

[Appleのアクセスガイド手順](https://support.apple.com/ja-jp/111795)

## 6. IPAを作成する

開発配布用IPAを書き出せるApple署名環境を用意して実行します。

```sh
ROOMCANVAS_TEAM_ID=YOURTEAMID \
ROOMCANVAS_BUNDLE_ID=jp.example.myroomcanvas \
./scripts/build-installer.command
```

`YOURTEAMID`は自分の10文字のTeam IDです。出力は`Installer/RoomCanvas.ipa`。Apple Configurator等で、署名プロファイルに含まれる端末へインストールします。エクスポートが利用できないアカウントではXcodeのRunで導入してください。

IPAは開発署名付きであり、汎用インストーラではありません。署名プロファイルに端末識別情報が含まれる場合があるため、リポジトリへ追加しないでください。

## うまくいかない場合

- Macに端末が出ない：ロック解除、データ通信ケーブル、USBポート、信頼確認を順に確認。
- Signingエラー：Team、Bundle Identifier、Apple Account、プロファイルを確認。
- 画面は動くが通知しない：デモモード、Webhook設定、インターネット、30秒制限を確認。
- 設定が以前と違う：別のBundle Identifierでインストールしていないか確認。
