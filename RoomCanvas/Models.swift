import SwiftUI
import EventKit
import CryptoKit
import Security

struct RoomEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    let calendar: String
}
struct RoomScene: Identifiable, Decodable {
    let sceneId: String
    let sceneName: String
    var id: String { sceneId }
}
enum RoomFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
enum Vault {
    static func read(_ key: String) -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "RoomCanvas", kSecAttrAccount as String: key, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ key: String, _ value: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "RoomCanvas", kSecAttrAccount as String: key]
        if value.isEmpty { SecItemDelete(query as CFDictionary); return }
        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw RoomFailure.message("安全な保存に失敗しました") }
        } else if status != errSecSuccess { throw RoomFailure.message("安全な保存に失敗しました") }
    }
}

struct CalendarOption: Equatable {
    let calendarIdentifier: String
    let title: String
    let sourceTitle: String
}
struct CalendarSnapshot {
    let calendars: [CalendarOption]
    let events: [RoomEvent]
    let hasSelection: Bool
}
/// EventKit objects stay on this serial queue; only value snapshots cross to UI.
// Queue confinement protects the only mutable property, store.
final class CalendarReader: @unchecked Sendable {
    private let queue = DispatchQueue(label: "RoomCanvas.calendar", qos: .userInitiated)
    private var store: EKEventStore?
    func read(month: Date, selectedIDs: Set<String>) async -> CalendarSnapshot {
        await withCheckedContinuation { continuation in
            queue.async {
                dispatchPrecondition(condition: .notOnQueue(.main))
                if self.store == nil { self.store = EKEventStore() }
                let store = self.store!
                let calendars = store.calendars(for: .event)
                let selected = calendars.filter { selectedIDs.contains($0.calendarIdentifier) }
                let choices = calendars.map { CalendarOption(calendarIdentifier: $0.calendarIdentifier, title: $0.title, sourceTitle: $0.source.title) }
                guard !selected.isEmpty else {
                    continuation.resume(returning: CalendarSnapshot(calendars: choices, events: [], hasSelection: false)); return
                }
                let calendar = RoomCalendar.value
                let interval = calendar.dateInterval(of: .month, for: month)!
                let start = calendar.date(byAdding: .day, value: -7, to: interval.start)!
                let end = calendar.date(byAdding: .day, value: 7, to: interval.end)!
                let predicate = store.predicateForEvents(withStart: start, end: end, calendars: selected)
                var seen = Set<String>()
                let events = store.events(matching: predicate).compactMap { event -> RoomEvent? in
                    let id = "\(event.eventIdentifier ?? event.calendar.calendarIdentifier + (event.title ?? ""))-\(event.startDate.timeIntervalSince1970)"
                    guard seen.insert(id).inserted else { return nil }
                    return RoomEvent(id: id, title: event.title ?? "予定", start: event.startDate, end: event.endDate, allDay: event.isAllDay, calendar: event.calendar.title)
                }.sorted { $0.start < $1.start }
                continuation.resume(returning: CalendarSnapshot(calendars: choices, events: events, hasSelection: true))
            }
        }
    }
}

@MainActor final class RoomStore: ObservableObject {
    @Published var events: [RoomEvent] = []
    @Published var calendars: [CalendarOption] = []
    @Published var calendarMessage = "カレンダーを接続してください"
    @Published var calendarUpdated: Date?
    @Published var scenes: [RoomScene] = []
    @Published var sceneMessage = "SwitchBotのシーンを接続できます"
    @Published var busyScene: String?
    @Published var calling = false
    @Published var callMessage = ""
    @Published var lastCall: Date? = UserDefaults.standard.object(forKey: "lastCall") as? Date
    @Published var selectedDay = RoomCalendar.value.startOfDay(for: Date())
    @Published var month = RoomCalendar.value.startOfDay(for: Date())
    let eventStore = EKEventStore()
    private let calendarReader = CalendarReader()
    private var calendarReading = false
    private var calendarReadPending = false
    private var calendarPermissionPending = false
    var calendarIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "calendarIDs") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "calendarIDs") }
    }
    var demo: Bool { UserDefaults.standard.object(forKey: "demo") as? Bool ?? true }
    func refreshCalendar(request: Bool = false) async {
        if calendarReading { calendarReadPending = true; calendarPermissionPending = calendarPermissionPending || request; return }
        calendarReading = true
        defer {
            calendarReading = false
            if calendarReadPending {
                calendarReadPending = false
                let needsPermission = calendarPermissionPending
                calendarPermissionPending = false
                Task { await refreshCalendar(request: needsPermission) }
            }
        }
        if demo {
            let day = RoomCalendar.value.startOfDay(for: Date())
            events = [(9, "朝のプランニング", 1), (13, "プロジェクトミーティング", 2), (17, "明日の準備", 1)].enumerated().map { i, value in
                RoomEvent(id: "demo-\(i)", title: value.1, start: RoomCalendar.value.date(byAdding: .hour, value: value.0, to: day)!, end: RoomCalendar.value.date(byAdding: .hour, value: value.0 + value.2, to: day)!, allDay: false, calendar: "サンプル")
            }
            calendars = []; calendarMessage = "デモの予定を表示中"; calendarUpdated = nil; return
        }
        do {
            var allowed = EKEventStore.authorizationStatus(for: .event) == .authorized
            if #available(iOS 17.0, *) { allowed = EKEventStore.authorizationStatus(for: .event) == .fullAccess }
            if !allowed && request {
                if #available(iOS 17.0, *) { allowed = try await eventStore.requestFullAccessToEvents() }
                else { allowed = try await eventStore.requestAccess(to: .event) }
            }
            guard allowed else { events = []; calendars = []; calendarUpdated = nil; calendarMessage = "設定からカレンダーへのアクセスを許可してください"; return }
            let requestedMonth = month
            let requestedIDs = calendarIDs
            let snapshot = await calendarReader.read(month: requestedMonth, selectedIDs: requestedIDs)
            guard !demo, month == requestedMonth, calendarIDs == requestedIDs else {
                calendarReadPending = true
                return
            }
            if calendars != snapshot.calendars { calendars = snapshot.calendars }
            if events != snapshot.events { events = snapshot.events }
            calendarUpdated = snapshot.hasSelection ? Date() : nil
            calendarMessage = snapshot.hasSelection ? "iPadのカレンダーと同期" : "設定で表示するカレンダーを選択してください"

        } catch { events = []; calendarUpdated = nil; calendarMessage = "カレンダーの読み込みに失敗しました" }
    }
    func events(on day: Date) -> [RoomEvent] {
        let start = RoomCalendar.value.startOfDay(for: day)
        let end = RoomCalendar.value.date(byAdding: .day, value: 1, to: start)!
        return events.filter { $0.start < end && $0.end > start }
    }
    func fetchScenes() async {
        if demo { scenes = [RoomScene(sceneId: "demo-focus", sceneName: "集中する"), RoomScene(sceneId: "demo-relax", sceneName: "くつろぐ"), RoomScene(sceneId: "demo-off", sceneName: "おやすみ")]; sceneMessage = "デモ・実際の機器は動きません"; return }
        do {
            let data = try await SwitchBot.request(path: "scenes")
            struct Response: Decodable { let body: [RoomScene] }
            scenes = try JSONDecoder().decode(Response.self, from: data).body
            sceneMessage = scenes.isEmpty ? "SwitchBotアプリで手動シーンを作成してください" : "実行するシーンを選んでください"
        } catch { scenes = []; sceneMessage = error.localizedDescription }
    }
    func execute(_ scene: RoomScene) async {
        guard busyScene == nil else { return }
        busyScene = scene.id; defer { busyScene = nil }
        if demo { sceneMessage = "デモ：\(scene.sceneName)を選択しました"; return }
        do { _ = try await SwitchBot.request(path: "scenes/\(scene.id)/execute", method: "POST"); sceneMessage = "\(scene.sceneName)：実行要求を受け付けました" }
        catch { sceneMessage = error.localizedDescription }
    }
    func call(room: String) async {
        guard !calling, Date().timeIntervalSince(lastCall ?? .distantPast) >= 30 else { return }
        calling = true; defer { calling = false }
        if demo { callMessage = "デモ：呼び出しを試しました。通知は送信していません。"; lastCall = Date(); return }
        do {
            let provider = WebhookProvider(rawValue:UserDefaults.standard.string(forKey:"webhookProvider") ?? "discord") ?? .discord
            let rawURL = Vault.read(provider == .discord ? "discordWebhook" : "genericWebhook")
            let request = try CallWebhook.request(provider:provider,url:rawURL,room:room,at:Date(),bearer:Vault.read("webhookBearer"),mentionEveryone:UserDefaults.standard.object(forKey:"discordEveryone") as? Bool ?? false)
            let session = URLSession(configuration:.ephemeral,delegate:WebhookNoRedirect(),delegateQueue:nil)
            defer { session.finishTasksAndInvalidate() }
            let (data, response) = try await session.data(for:request)
            guard let http = response as? HTTPURLResponse, CallWebhook.accepted(provider:provider,status:http.statusCode,data:data) else { throw RoomFailure.message("Webhookで受理されませんでした") }

            lastCall = Date(); UserDefaults.standard.set(lastCall, forKey: "lastCall")
            callMessage = "通知先が呼び出しを受け付けました。"
        } catch { callMessage = "送信できませんでした。通知先や通信状態を確認してください。" }
    }
}

enum SwitchBot {
    static func request(path: String, method: String = "GET", body: [String: String]? = nil) async throws -> Data {
        let token = Vault.read("switchToken"), secret = Vault.read("switchSecret")
        guard !token.isEmpty && !secret.isEmpty else { throw RoomFailure.message("設定でSwitchBotのToken・Secretを保存してください") }
        let timestamp = String(Int64(Date().timeIntervalSince1970 * 1000)), nonce = UUID().uuidString
        let signature = Data(HMAC<SHA256>.authenticationCode(for: Data((token + timestamp + nonce).utf8), using: SymmetricKey(data: Data(secret.utf8)))).base64EncodedString()
        guard let url = URL(string: "https://api.switch-bot.com/v1.1/" + path) else { throw RoomFailure.message("接続先が不正です") }
        var request = URLRequest(url: url); request.httpMethod = method; request.timeoutInterval = 15
        if let body = body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        for (key, value) in ["Authorization": token, "sign": signature, "t": timestamp, "nonce": nonce, "Content-Type": "application/json"] { request.setValue(value, forHTTPHeaderField: key) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw RoomFailure.message("SwitchBotと通信できませんでした") }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], json["statusCode"] as? Int == 100 else { throw RoomFailure.message("SwitchBotが要求を受け付けませんでした。設定と機器を確認してください") }
        return data
    }
}


enum WebhookProvider: String, CaseIterable, Identifiable {
    case discord, json, text
    var id: String { rawValue }
    var title: String { switch self { case .discord:return "Discord"; case .json:return "汎用JSON"; case .text:return "text形式（Slack等）" } }
}
final class WebhookNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
enum CallWebhook {
    static func url(_ raw: String) -> URL? {
        guard let c = URLComponents(string:raw), c.scheme == "https", let host = c.host, !host.isEmpty, c.user == nil, c.password == nil, c.fragment == nil else { return nil }
        return c.url
    }
    static func request(provider:WebhookProvider,url raw:String,room:String,at date:Date,bearer:String = "",mentionEveryone:Bool = false) throws -> URLRequest {
        guard let url = provider == .discord ? DiscordCall.url(raw):url(raw) else { throw RoomFailure.message("通知先のHTTPS URLを確認してください") }
        var request = URLRequest(url:url); request.httpMethod = "POST"; request.timeoutInterval = 15
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        if provider != .discord && !bearer.isEmpty {
            guard !bearer.contains("\r"), !bearer.contains("\n") else { throw RoomFailure.message("Bearer Tokenに改行は使用できません") }
            request.setValue("Bearer " + bearer,forHTTPHeaderField:"Authorization")
        }
        let payload:[String:Any]
        switch provider {
        case .discord: payload = DiscordCall.payload(room:room,at:date,mentionEveryone:mentionEveryone)
        case .json: payload = ["schema_version":1,"event":"room.call","event_id":UUID().uuidString,"room":String(room.prefix(100)),"timestamp":ISO8601DateFormatter().string(from:date),"message":"\(String(room.prefix(100)))から呼び出しがあります。"]
        case .text: payload = ["text":"\(String(room.prefix(100)).replacingOccurrences(of:"<",with:"＜").replacingOccurrences(of:">",with:"＞"))から呼び出しがあります。\n呼び出し時刻：\(ISO8601DateFormatter().string(from:date))"]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject:payload); return request
    }
    static func accepted(provider:WebhookProvider,status:Int,data:Data) -> Bool {
        guard (200...299).contains(status) else { return false }
        if provider != .discord { return true }
        return ((try? JSONSerialization.jsonObject(with:data)) as? [String:Any])?["id"] as? String != nil
    }
}
enum DiscordCall {
    static func url(_ value: String) -> URL? {
        guard var c = URLComponents(string: value), c.scheme == "https", ["discord.com", "ptb.discord.com", "canary.discord.com"].contains(c.host ?? ""), c.user == nil, c.password == nil, c.port == nil, c.fragment == nil else { return nil }
        let parts = c.path.split(separator: "/").map(String.init)
        let offset = parts.count == 5 && parts[1].hasPrefix("v") ? 1 : 0
        guard parts.count == 4 + offset, parts[0] == "api", parts[1 + offset] == "webhooks", !parts[2 + offset].isEmpty, parts[2 + offset].allSatisfy({ $0.isASCII && $0.isNumber }), !parts[3 + offset].isEmpty else { return nil }
        var query = (c.queryItems ?? []).filter { $0.name == "thread_id" }
        query.append(URLQueryItem(name: "wait", value: "true")); c.queryItems = query
        return c.url
    }
    static func payload(room: String, at date: Date, mentionEveryone: Bool = false) -> [String:Any] {
        ["content": (mentionEveryone ? "@everyone\n" : "") + "\(String(room.prefix(100)).replacingOccurrences(of: "@", with: "＠"))から呼び出しがあります。", "allowed_mentions": ["parse": mentionEveryone ? ["everyone"] : [String]()], "embeds": [["title": "呼び出しイベント", "fields": [["name": "部屋名", "value": String(room.prefix(100)).isEmpty ? "My Room" : String(room.prefix(100))], ["name": "呼び出し時刻", "value": date.formatted(date: .numeric, time: .standard)]], "timestamp": ISO8601DateFormatter().string(from: date), "color": 9886141]]]
    }
}
