# 第三者の権利・出典

## 日本の祝日データ

出典：内閣府「国民の祝日について」。CSVから1955〜2027年のデータをSwift辞書へ加工して内蔵しています。アプリは同じCSVの更新取得にも対応します。内閣府がRoomCanvasを作成・推奨していることを意味しません。

- 元データ：https://www8.cao.go.jp/chosei/shukujitsu/syukujitsu.csv
- 説明：https://www8.cao.go.jp/chosei/shukujitsu/gaiyou.html
- 利用規約：https://www.cao.go.jp/notice/rule.html
- 適用規約：公共データ利用規約 第1.0版（適用除外の表示があるものを除く）

このデータをRoomCanvas独自の非商用ライセンスへ変更するものではありません。出典・加工の表示を保持してください。

## Open-Meteo

天気予報はOpen-Meteo Weather APIを利用します。データはCC BY 4.0で提供され、帰属表示が必要です。画面内のOpen-Meteo表示と、設定内の出典リンクを保持してください。元データから日次の最高・最低気温・降水確率を抽出し、整数表示へ丸め、日本語の天気分類・アイコンへ変換しています。

- https://open-meteo.com/
- https://open-meteo.com/en/docs
- データライセンス：https://creativecommons.org/licenses/by/4.0/
- API利用条件・料金：https://open-meteo.com/en/pricing

データのライセンスとAPIサービスの利用条件は別です。既定の無料APIは非商用向けで、呼出制限があります。Open-Meteoのサーバーソフトウェアをこのリポジトリへ組み込んでいるわけではありません。

## Appleプラットフォーム

SwiftUI、UIKit、EventKit、Core Bluetooth、Core Location、CryptoKit、Security等を利用します。SF Symbolsはシステムの`Image(systemName:)`で参照し、フォントやシンボルファイル自体は再配布していません。Apple SDK・プラットフォーム利用にはAppleの各条件が適用されます。

## 外部サービスと商標

SwitchBot、Discord、Slack、Google、Apple等の名称は各権利者に帰属します。本プロジェクトはこれらの企業による公式アプリではありません。APIやWebhookの利用には各サービスの条件が別途適用されます。

SwitchBot API仕様：https://github.com/OpenWonderLabs/SwitchBotAPI

BLE押下の実装は実測した広告カウンターに基づくもので、SwitchBotの全リモート製品への互換認証ではありません。

## 同梱依存関係

第三者のアプリ用ライブラリ・フォントは同梱していません。ビルド用ツール自体はリポジトリに含めません。今後追加する際は、この文書に依存関係とライセンスを追記してください。
