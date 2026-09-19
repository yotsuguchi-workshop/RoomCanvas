# データの扱い

アプリ独自の解析・広告SDKや開発者への自動テレメトリ送信はありません。

| データ | 保存・送信先 |
|---|---|
| SwitchBot Token / Secret、Webhook URL、Bearer Token、PINのsalt・ハッシュ | iPadのKeychain |
| 部屋名、対象機器、表示設定、お気に入り操作 | iPadのUserDefaults |
| カレンダー | EventKitで端末内の同期済み予定を読み取り。Webhookへ送信しない |
| 現在地 | 天気取得用に約1km単位に丸めた緯度経度をOpen-Meteoへ送信 |
| 手動地域名 | Appleのジオコーディングで座標を検索 |
| 部屋名・呼び出し時刻 | 自分が指定したWebhook URLへHTTPS送信 |
| BLEログ | 端末のDocumentsに最大3000件。周辺機器名・識別子・受信データを含む |

BLEログは診断画面から消去・書き出しできます。公開Issueに生ログを載せないでください。Webhook URLはURLそのものが秘密情報になるサービスがあります。

Keychainの情報はアプリ削除後も残る場合があります。利用を終了するときは設定欄を空欄で保存し、外部サービス側のWebhookやTokenも失効させてください。端末の紛失に備え、iPadのパスコードを設定してください。
