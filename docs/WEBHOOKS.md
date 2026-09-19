# Webhook通知

設定 → 呼び出し通知 / Webhookで形式を選び、URLを入力して「通知設定を保存」。デモモードをオフにして、その他ページの「呼び出す」で試します。URLは通知先への送信権限を持つ秘密情報として扱ってください。

## 対応形式

| 形式 | 本文 | 成功と扱う応答 |
|---|---|---|
| Discord | content、embeds、allowed_mentions | HTTP 2xxかつJSONのidあり |
| 汎用JSON | 以下のroom.callイベント | HTTP 2xx（本文は問わない） |
| text形式 | `{"text":"部屋名から呼び出しがあります。\n呼び出し時刻：…"}` | HTTP 2xx |

HTTPSのみ対応。URL内のユーザー名・パスワード、フラグメントは不可。リダイレクトは追従しません。必要な場合は最終的なURLを指定してください。自己署名証明書を無条件に許可する機能はありません。

## Discord

DiscordサーバーでチャンネルのWebhookを作成し、URLをコピーしてアプリに保存します。[Discord公式Webhook説明](https://support.discord.com/hc/en-us/articles/228383668-Intro-to-Webhooks)

`@everyone`は初期オフです。必要な場合だけオンにします。ユーザー・ロールの個別メンションは現在未対応。実際の通知はチャンネル権限や受信者のミュート設定等に依存します。

## 汎用JSON：自作サーバー、Cloudflare Worker、自動化サービス

自分で管理するHTTPS POST受信エンドポイントを用意します。次のJSONを受け取るようにしてください。

```json
{
  "schema_version": 1,
  "event": "room.call",
  "event_id": "生成されたUUID",
  "room": "My Room",
  "timestamp": "2026-09-19T03:00:00Z",
  "message": "My Roomから呼び出しがあります。"
}
```

Content-Typeは`application/json`。timestampはISO 8601 UTC、event_idは送信要求ごとのUUIDです。部屋名は最大100文字です。アプリは自動再送しません。

必要な場合はBearer Tokenを入力します。`Authorization: Bearer <token>`ヘッダーとして送信されます。サーバーはトークンを検証し、不正なら401/403、受理したら200または204等を返してください。URLやトークンをIssueへ貼らないでください。

Cloudflare Workerのデプロイ・認証管理はこのアプリには含まれません。Worker側で受信JSONを別サービスの形式へ変換できます。

## text形式：Slack等

SlackのIncoming Webhookなど、`text`フィールドのJSON POSTを受け付ける通知先向けです。SlackのWebhook URLを保存して試します。[Slack公式Incoming Webhooks](https://docs.slack.dev/messaging/sending-messages-using-incoming-webhooks/)

「任意のサービスと無設定で互換」という意味ではありません。Teams等、異なるJSONスキーマを必要とするサービスは汎用JSONを受けて変換する中継サーバーを用意してください。text形式ではDiscordのメンション設定は適用しません。

## 設定・移行・制限

Discordと汎用系のURLは別々に保存します。汎用JSONとtext形式は同じURL・Bearer欄を共有するため、形式変更時に再確認してください。既存版のDiscord URLは引き継ぎます。

部屋名と時刻を受信先へ送ります。予定、位置情報、SwitchBot Token / Secret、BLEの広告本体はWebhookへ送りません。URLとBearer TokenはiPadのKeychainへ保存します。

タイムアウトは15秒。2xxは受信先の受理であり、人が読んだことや端末へのプッシュ到達を意味しません。BLEの送信試行は失敗時も30秒間隔です。重複広告は送信しません。レート制限・失敗は画面で確認してください。
