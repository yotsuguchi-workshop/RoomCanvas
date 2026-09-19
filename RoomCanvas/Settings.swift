import SwiftUI
import CryptoKit

struct SettingsView: View {
    @ObservedObject var store: RoomStore
    @ObservedObject var devices: DeviceStore
    @ObservedObject var weather: WeatherStore
    @ObservedObject var holidays: HolidayStore
    @ObservedObject var ble: BLELab
    @State private var showBLE = false
    @AppStorage("discordEveryone") private var discordEveryone = false
    @State private var webhookProvider = UserDefaults.standard.string(forKey:"webhookProvider") ?? "discord"
    @State private var genericURL = Vault.read("genericWebhook")
    @State private var webhookBearer = Vault.read("webhookBearer")
    @Environment(\.dismiss) private var dismiss
    @AppStorage("room") private var room = "My Room"
    @AppStorage("hideTitles") private var hideTitles = true
    @AppStorage("demo") private var demo = true
    @AppStorage("outside") private var outside = false
    @State private var token = Vault.read("switchToken")
    @State private var secret = Vault.read("switchSecret")
    @State private var notifyURL = Vault.read("discordWebhook")
    @State private var region = UserDefaults.standard.string(forKey: "weatherRegion") ?? ""
    @AppStorage("weatherMode") private var weatherMode = "location"
    @AppStorage("availability") private var availability = "在室"
    @State private var regionSearching = false
    @State private var pin = ""
    @State private var pinAgain = ""
    @State private var message = ""
    @State private var loading = false
    @State private var favoriteDevice: SBDevice?
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("ディスプレイ")) {
                    TextField("部屋の名前", text: $room)
                    Picker("在室状況", selection: $availability) { Text("在室").tag("在室"); Text("外出").tag("外出"); Text("作業中").tag("作業中") }.pickerStyle(.segmented)
                    Toggle("外置きモード", isOn: Binding(get: { outside }, set: { value in
                        if value && Vault.read("pinHash").isEmpty { message = "外置きモードには先に管理PINを設定してください" }
                        else { outside = value; if value { dismiss() } }
                    }))
                    Toggle("デモモード", isOn: $demo)
                    Text("デモではサンプル予定を表示し、通知・機器操作は行いません。").font(.caption).foregroundColor(.secondary)
                    Toggle("外置きでは予定の名前を隠す", isOn: $hideTitles)
                }
                Section(header: Text("天気"), footer: Text("現在地を許可すると、約1km単位に丸めた位置をOpen-Meteoへ送って今日の予報を取得します。取得できない場合は保存した手動地域を使います。↑最高気温・↓最低気温・雨粒：今日の最大降水確率。")) {
                    Picker("取得方法", selection: $weatherMode) { Text("現在地").tag("location"); Text("手動地域").tag("manual") }.pickerStyle(.segmented)
                    Button("現在地の利用を許可・再取得") { weatherMode = "location"; Task { await weather.refresh(force: true, requestPermission: true) } }
                    TextField("地域名（例：さいたま市）", text: $region)
                    Menu("地域の候補") { ForEach(["札幌市","仙台市","さいたま市","東京都千代田区","横浜市","新潟市","名古屋市","金沢市","京都市","大阪市","神戸市","広島市","高松市","福岡市","鹿児島市","那覇市"], id: \.self) { name in Button(name) { region = name } } }
                    Button(regionSearching ? "検索中…" : "この地域を保存して天気を取得") { Task { regionSearching = true; await weather.selectRegion(region); regionSearching = false } }.disabled(regionSearching)
                    Text(weather.message).font(.caption).foregroundColor(.secondary)
                    Link("天気データ：Open-Meteo", destination: URL(string: "https://open-meteo.com/")!)
                }
                Section(header: Text("祝日")) {
                    Text("日曜は赤、土曜は青、平日の祝日は緑。土日と祝日が重なる場合は土日の色を優先します。").font(.caption)
                    Button(holidays.loading ? "更新中…" : "内閣府の祝日データを更新") { Task { await holidays.update(force: true) } }.disabled(holidays.loading)
                    Text(holidays.message).font(.caption).foregroundColor(.secondary)
                    Link("祝日データ：内閣府", destination: URL(string: "https://www8.cao.go.jp/chosei/shukujitsu/gaiyou.html")!)
                }
                Section(header: Text("Googleカレンダー / iPadのカレンダー")) {
                    Text("iPadの設定でGoogleアカウントを追加し、カレンダー同期をオンにしてください。以下から表示対象を選択します。").font(.subheadline)
                    Button("カレンダーを接続・更新") { Task { demo = false; await store.refreshCalendar(request: true) } }
                    ForEach(store.calendars, id: \.calendarIdentifier) { calendar in
                        Toggle(calendar.title + " · " + calendar.sourceTitle, isOn: Binding(get: { store.calendarIDs.contains(calendar.calendarIdentifier) }, set: { value in var selected = store.calendarIDs; if value { selected.insert(calendar.calendarIdentifier) } else { selected.remove(calendar.calendarIdentifier) }; store.calendarIDs = selected; Task { await store.refreshCalendar() } }))
                    }
                    Text(store.calendarMessage).font(.caption).foregroundColor(.secondary)
                }
                Section(header: Text("SwitchBot"), footer: Text("TokenとSecretはiPadのKeychainに保存します。SwitchBotの機器一覧と手動シーンを読み込みます。機器画面から個別操作・状態表示ができます。")) {
                    SecureField("Open Token", text: $token)
                    SecureField("Secret", text: $secret)
                    Button(loading ? "接続中…" : "保存して機器とシーンを読み込む") { Task {
                        loading = true; defer { loading = false }
                        do { try Vault.save("switchToken", token.trimmingCharacters(in: .whitespacesAndNewlines)); try Vault.save("switchSecret", secret.trimmingCharacters(in: .whitespacesAndNewlines)); demo = false; await store.fetchScenes(); await devices.fetch(force: true); message = devices.message } catch { message = error.localizedDescription }
                    } }.disabled(loading)
                    Text(store.sceneMessage).font(.caption).foregroundColor(.secondary)
                }
                Section(header: Text("ダッシュボードのお気に入り操作"), footer: Text("機器と機能を選んで最大4操作を登録します。同じ機器の複数機能も登録できます。従来のお気に入り機器は、使う機能を選び直してください。")) {
                    ForEach(devices.favorites) { favorite in
                        HStack { Text("\(favorite.deviceName)・\(favorite.action.label)"); Spacer(); Button("削除", role: .destructive) { devices.removeFavorite(favorite.id) } }
                    }
                    Menu("操作を追加（機器を選択）") {
                        ForEach(devices.devices.filter { !$0.sensor }) { device in Button(device.name) { favoriteDevice = device } }
                    }.disabled(devices.favorites.count >= 4 || devices.devices.isEmpty)
                    if devices.devices.isEmpty { Text("先にSwitchBotの機器を読み込んでください").font(.caption) }
                    Picker("表示するエアコン", selection: Binding(get: { devices.airID }, set: { devices.selectAir($0) })) {
                        Text("自動選択").tag("")
                        ForEach(devices.devices.filter { $0.type == "Air Conditioner" }) { device in Text(device.name).tag(device.id) }
                    }
                    Picker("温湿度センサー", selection: Binding(get: { devices.sensorID }, set: { id in if id.isEmpty { devices.sensorID = ""; UserDefaults.standard.set("", forKey: "sbSensor") }; if let sensor = devices.devices.first(where: { $0.id == id }) { devices.selectSensor(sensor) } })) {
                        Text("自動選択").tag("")
                        ForEach(devices.devices.filter { $0.sensor }) { device in Text(device.name).tag(device.id) }
                    }
                }
                Section(header: Text("呼び出し通知 / Webhook"), footer: Text("URLとBearer TokenはKeychainに保存します。汎用JSONはroom.callイベント、text形式はSlack等の受信側に対応する場合に利用できます。受信側の仕様を確認してください。")) {
                    Picker("送信形式",selection:$webhookProvider) { ForEach(WebhookProvider.allCases) { provider in Text(provider.title).tag(provider.rawValue) } }
                    if webhookProvider == "discord" {
                        Toggle("@everyoneを付ける",isOn:$discordEveryone)
                        SecureField("Discord Webhook URL",text:$notifyURL).keyboardType(.URL).textInputAutocapitalization(.never).disableAutocorrection(true)
                    } else {
                        SecureField("HTTPS Webhook URL",text:$genericURL).keyboardType(.URL).textInputAutocapitalization(.never).disableAutocorrection(true)
                        SecureField("Bearer Token（必要な場合）",text:$webhookBearer).textInputAutocapitalization(.never).disableAutocorrection(true)
                    }
                    Button("通知設定を保存") {
                        do {
                            let discord = webhookProvider == "discord"
                            let value = (discord ? notifyURL:genericURL).trimmingCharacters(in:.whitespacesAndNewlines)
                            guard value.isEmpty || (discord ? DiscordCall.url(value):CallWebhook.url(value)) != nil else { throw RoomFailure.message("有効なHTTPS URLを入力してください") }
                            guard !webhookBearer.contains("\r"), !webhookBearer.contains("\n") else { throw RoomFailure.message("Tokenの改行を取り除いてください") }
                            try Vault.save(discord ? "discordWebhook":"genericWebhook",value)
                            if !discord { try Vault.save("webhookBearer",webhookBearer) }
                            UserDefaults.standard.set(webhookProvider,forKey:"webhookProvider")
                            message = "通知設定を保存しました。その他ページの呼び出しボタンで確認できます。"
                        } catch { message = error.localizedDescription }
                    }
                }
                Section(header: Text("呼び出しボタン")) { Button("リモートボタンの設定") { showBLE = true } }
                Section(header: Text("外置きの管理PIN"), footer: Text("外置きモードから室内モードへ戻すときに必要です。iPadのアクセスガイドと併用すると、来訪者による他アプリへの移動を防げます。PINは忘れないよう保管してください。")) {
                    SecureField("新しいPIN（数字6桁以上）", text: $pin).keyboardType(.numberPad)
                    SecureField("PINをもう一度", text: $pinAgain).keyboardType(.numberPad)
                    Button("PINを保存") {
                        guard pin.count >= 6, pin.allSatisfy({ $0.isASCII && $0.isNumber }), pin == pinAgain else { message = "同じ数字6桁以上のPINを2回入力してください"; return }
                        do { let salt = UUID().uuidString; try Vault.save("pinSalt", salt); try Vault.save("pinHash", Self.hash(pin, salt: salt)); pin = ""; pinAgain = ""; message = "PINを保存しました。外置きモードを使えます。" } catch { message = error.localizedDescription }
                    }

                }
                if !message.isEmpty { Section { Text(message).foregroundColor(.orange).accessibilityIdentifier("settingsResult") } }
                Section(header:Text("ライセンス・出典")) {
                    NavigationLink("非商用ライセンスと第三者の権利") { LegalView() }
                }
                Section { Text("RoomCanvas 0.10.2 · iPadOS 15以降\n時刻はiPadのタイムゾーンを使用します。カレンダーは60秒ごとに端末内の予定を読み直します。Google側との同期頻度はiPadの設定に依存します。").font(.caption).foregroundColor(.secondary) }
            }.navigationTitle("ディスプレイ設定").toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } } }
        }.navigationViewStyle(.stack).sheet(item: $favoriteDevice) { device in DeviceControlView(device: device, registrationOnly: true, devices: devices) }
        .sheet(isPresented: $showBLE) { RemoteCallSettingsView(remote: ble) }
        .preferredColorScheme(.dark)
        .onChange(of: weatherMode) { _ in Task { await weather.refresh(force: true) } }
    }
    static func hash(_ pin: String, salt: String) -> String { SHA256.hash(data: Data((salt + pin).utf8)).map { String(format: "%02x", $0) }.joined() }
}
struct UnlockView: View {
    let unlocked: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""
    @State private var message = ""
    @AppStorage("unlockFailures") private var failures = 0
    @AppStorage("unlockBlockedUntil") private var blockedUntil = 0.0
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("管理設定を開く")) {
                    SecureField("管理PIN", text: $pin).keyboardType(.numberPad).accessibilityIdentifier("unlockPIN")
                    Button("ロック解除") {
                        guard Date().timeIntervalSince1970 >= blockedUntil else { message = "試行回数が多いため、1分ほど待ってください"; return }
                        if !Vault.read("pinHash").isEmpty && SettingsView.hash(pin, salt: Vault.read("pinSalt")) == Vault.read("pinHash") { failures = 0; blockedUntil = 0; unlocked() }
                        else { failures += 1; pin = ""; message = "PINが違います"; if failures >= 5 { blockedUntil = Date().timeIntervalSince1970 + 60; failures = 0; message = "1分ほど待って再度お試しください" } }
                    }
                    if !message.isEmpty { Text(message).foregroundColor(.orange) }
                }
            }.navigationTitle("管理者の確認").toolbar { ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } } }
        }.navigationViewStyle(.stack).preferredColorScheme(.dark)
    }
}

struct LegalView: View {
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                Text("RoomCanvasは非商用向けソース公開ソフトウェアです。商用利用の許諾は含みません。").font(.headline)
                ForEach(["NOTICE","LICENSE","THIRD_PARTY_NOTICES.md"],id:\.self) { name in
                    Text((Bundle.main.resourceURL.flatMap { try? String(contentsOf:$0.appendingPathComponent("Legal").appendingPathComponent(name),encoding:.utf8) }) ?? name).font(.footnote).textSelection(.enabled)
                }
            }.padding()
        }.navigationTitle("ライセンス・出典")
    }
}
