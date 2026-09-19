import SwiftUI

struct SBDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let type: String
    let infrared: Bool
    let cloud: Bool
    var sensor: Bool { ["Hub 2", "Hub 3", "Meter", "MeterPlus", "Meter Plus", "Meter Pro", "Meter Pro(CO2)", "Meter Pro CO2", "WoIOSensor", "Outdoor Meter"].contains(type) }
    var ceiling: Bool { ["Ceiling Light", "Ceiling Light Pro"].contains(type) }
    var canPower: Bool {
        if infrared { return ["Air Conditioner", "Fan", "Light", "TV", "DVD", "Speaker", "IPTV/Streamer", "Set Top Box", "Camera", "Vacuum Cleaner", "Water Heater", "Air Purifier"].contains(type) }
        return ceiling || ["Plug", "Plug Mini (JP)", "Plug Mini (US)", "Plug Mini (EU)", "Color Bulb", "Strip Light"].contains(type)
    }
    var powerOnly: Bool { !infrared && canPower }
    var supportsStatus: Bool { !infrared && (sensor || ceiling || canPower || type == "Bot") }
    var icon: String {
        if sensor { return "thermometer" }
        if type == "Air Conditioner" { return "snowflake" }
        if type.contains("Light") || type.contains("Bulb") { return "lightbulb" }
        if type.contains("Fan") { return "fanblades" }
        if type == "Bot" { return "hand.tap" }
        if type.contains("Plug") { return "powerplug" }
        return "slider.horizontal.3"
    }
}
struct SBStatus: Equatable {
    var power: String?
    var temperature: Double?
    var humidity: Double?
    var brightness: Double?
    var colorTemperature: Double?
    var battery: Double?
    var deviceMode: String?
    var updated = Date()
    var summary: String {
        var values: [String] = []
        if let value = temperature { values.append(String(format: "%.1f°C", value)) }
        if let value = humidity { values.append(String(format: "%.0f%%", value)) }
        if deviceMode == "pressMode" { values.append("押すモード") }
        else if deviceMode == "customizeMode" { values.append("カスタムモード") }
        else if let value = power { values.append(value.lowercased() == "on" ? "オン" : value.lowercased() == "off" ? "オフ" : value) }
        if let value = brightness { values.append(String(format: "明るさ %.0f%%", value)) }
        if let value = battery { values.append(String(format: "電池 %.0f%%", value)) }
        return values.isEmpty ? "状態を取得しました" : values.joined(separator: " · ")
    }
    static func decode(_ object: [String: Any]) -> SBStatus {
        func number(_ key: String) -> Double? { (object[key] as? NSNumber)?.doubleValue ?? Double(object[key] as? String ?? "") }
        return SBStatus(power: object["power"] as? String, temperature: number("temperature"), humidity: number("humidity"), brightness: number("brightness"), colorTemperature: number("colorTemperature"), battery: number("battery"), deviceMode: object["deviceMode"] as? String)
    }
}
struct SBAction: Identifiable, Codable {
    var id: String { "\(custom):\(command):\(parameter)" }
    let label: String
    let command: String
    var parameter = "default"
    var custom = false
    var payload: [String: String] { ["command": command, "parameter": parameter, "commandType": custom ? "customize" : "command"] }
}

struct FavoriteAction: Identifiable, Codable {
    var id = UUID().uuidString
    let deviceID: String
    let deviceName: String
    let action: SBAction
}

@MainActor final class DeviceStore: ObservableObject {
    @Published var devices: [SBDevice] = []
    @Published var states: [String: SBStatus] = [:]
    @Published var errors: [String: String] = [:]
    @Published var message = "機器を読み込んでください"
    @Published var loading = false
    @Published var executing: String?
    @Published var result = ""
    @Published private(set) var favorites: [FavoriteAction] = UserDefaults.standard.data(forKey: "sbFavoriteActions").flatMap { try? JSONDecoder().decode([FavoriteAction].self, from: $0) } ?? []
    var favoriteIDs: Set<String> { Set(favorites.map(\.deviceID)) }
    @Published var sensorID = UserDefaults.standard.string(forKey: "sbSensor") ?? ""
    private var reading = Set<String>()
    @Published private(set) var toggling = false
    private var lastFetch = Date.distantPast
    private var loadedDemo: Bool?
    private let demoOverride: Bool?
    private let api: (String, String, [String:String]?) async throws -> Data
    init(demoOverride: Bool? = nil, api: @escaping (String, String, [String:String]?) async throws -> Data = { path,method,body in try await SwitchBot.request(path:path,method:method,body:body) }) { self.demoOverride = demoOverride; self.api = api }
    var demo: Bool { demoOverride ?? (UserDefaults.standard.object(forKey: "demo") as? Bool ?? true) }
    var sensor: SBDevice? { devices.first { $0.id == sensorID && $0.sensor } ?? devices.first { $0.sensor } }
    @Published var airID = UserDefaults.standard.string(forKey: "sbAir") ?? ""
    @Published var airCommands: [String: AirCommand] = (UserDefaults.standard.data(forKey: "sbAirCommands").flatMap { try? JSONDecoder().decode([String:AirCommand].self, from: $0) }) ?? [:]
    var air: SBDevice? { devices.first { $0.id == airID && $0.type == "Air Conditioner" } ?? devices.first { $0.type == "Air Conditioner" } }
    func selectAir(_ id: String) { airID = id; UserDefaults.standard.set(id, forKey: "sbAir") }
    func airSummary(_ device: SBDevice) -> String {
        guard let command = airCommands[device.id] else { return "エアコン · このアプリからは未送信" }
        return "送信済：" + command.summary
    }

    func addFavorite(_ action: SBAction, device: SBDevice) {
        guard !favorites.contains(where: { $0.deviceID == device.id && $0.action.id == action.id }) else { result = "この操作は登録済みです"; return }
        guard favorites.count < 4 else { result = "お気に入りは最大4操作です。設定で不要な操作を削除してください"; return }
        favorites.append(FavoriteAction(deviceID: device.id, deviceName: device.name, action: action))
        saveFavorites(); result = "\(device.name)・\(action.label)を登録しました"
    }
    func removeFavorite(_ id: String) { favorites.removeAll { $0.id == id }; saveFavorites() }
    private func saveFavorites() { if let data = try? JSONEncoder().encode(favorites) { UserDefaults.standard.set(data, forKey: "sbFavoriteActions") } }
    func runFavorite(_ favorite: FavoriteAction) async {
        guard let device = devices.first(where: { $0.id == favorite.deviceID }) else { result = "登録した機器が見つかりません。機器一覧を更新してください"; return }
        if favorite.action.command == "__togglePower", !favorite.action.custom { await togglePower(device) }
        else { await send(favorite.action, to: device) }
    }
    func selectSensor(_ device: SBDevice) { sensorID = device.id; UserDefaults.standard.set(device.id, forKey: "sbSensor") }
    func summary(_ device: SBDevice) -> String {
        if let error = errors[device.id] { return error }
        if device.infrared { return "赤外線 · 実状態は取得できません" }
        if !device.cloud { return "クラウドサービスが無効です" }
        if let status = states[device.id] { return status.summary }
        return device.supportsStatus ? "状態未取得" : "APIでの個別操作は未対応"
    }
    func fetch(force: Bool = false) async {
        guard !loading else { return }
        let demoAtStart = demo
        guard force || loadedDemo != demoAtStart || Date().timeIntervalSince(lastFetch) > 300 else { return }
        loading = true; defer { loading = false; if loadedDemo != demo { Task { await fetch(force: true) } } }
        if loadedDemo != demoAtStart { devices = []; states = [:]; errors = [:] }
        loadedDemo = demoAtStart
        if demoAtStart {
            devices = [SBDevice(id: "demo-light", name: "シーリングライト", type: "Ceiling Light Pro", infrared: false, cloud: true), SBDevice(id: "demo-ac", name: "エアコン", type: "Air Conditioner", infrared: true, cloud: true), SBDevice(id: "demo-fan", name: "扇風機", type: "Fan", infrared: true, cloud: true), SBDevice(id: "demo-bot", name: "クローゼットのライト", type: "Bot", infrared: false, cloud: true), SBDevice(id: "demo-hub", name: "ハブ", type: "Hub 2", infrared: false, cloud: true), SBDevice(id: "demo-ir", name: "モニター切り替え", type: "Others", infrared: true, cloud: true)]
            states = ["demo-light": SBStatus(power: "on", brightness: 70, colorTemperature: 4000), "demo-bot": SBStatus(battery: 100, deviceMode: "pressMode"), "demo-hub": SBStatus(temperature: 22.8, humidity: 55)]
            message = "デモ · 実際の機器は動きません"; lastFetch = Date(); return
        }
        do {
            let data = try await api("devices", "GET", nil)
            guard demo == demoAtStart else { return }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let body = json?["body"] as? [String: Any] ?? [:]
            func parse(_ key: String, infrared: Bool) -> [SBDevice] {
                (body[key] as? [[String: Any]] ?? []).compactMap { item in
                    guard let id = item["deviceId"] as? String, let name = item["deviceName"] as? String else { return nil }
                    return SBDevice(id: id, name: name, type: item[infrared ? "remoteType" : "deviceType"] as? String ?? "Unknown", infrared: infrared, cloud: item["enableCloudService"] as? Bool ?? true)
                }
            }
            var seen = Set<String>()
            devices = (parse("deviceList", infrared: false) + parse("infraredRemoteList", infrared: true)).filter { seen.insert($0.id).inserted }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            let valid = Set(devices.map(\.id)); states = states.filter { valid.contains($0.key) }; errors = errors.filter { valid.contains($0.key) }
            message = "\(devices.count)台 · 機器を選ぶと個別操作できます"; lastFetch = Date()
            for device in devices where device.supportsStatus && device.cloud { await refreshStatus(device) }
        } catch { message = "機器一覧を取得できませんでした。接続設定を確認してください。" }
    }
    func refreshSensor() async {
        guard let device = sensor else { return }
        if let updated = states[device.id]?.updated, Date().timeIntervalSince(updated) < 120 { return }
        await refreshStatus(device)
    }
    func refreshStatus(_ device: SBDevice, force: Bool = false) async {
        guard !demo, device.supportsStatus, device.cloud, !reading.contains(device.id) else { return }
        if !force, let date = states[device.id]?.updated, Date().timeIntervalSince(date) < 30 { return }
        reading.insert(device.id); defer { reading.remove(device.id) }
        do {
            let data = try await api("devices/\(Self.pathID(device.id))/status", "GET", nil)
            guard !demo, devices.contains(where: { $0.id == device.id }) else { return }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let body = json?["body"] as? [String: Any] else { throw RoomFailure.message("状態を取得できません") }
            states[device.id] = SBStatus.decode(body); errors[device.id] = nil
        } catch { errors[device.id] = "状態取得に失敗 · 再更新してください" }
    }
    func togglePower(_ device: SBDevice) async {
        guard device.powerOnly, !toggling, executing == nil else { return }
        toggling = true; defer { toggling = false }
        if !demo {
            await refreshStatus(device, force: true)
        }
        guard !reading.contains(device.id), (demo || Date().timeIntervalSince(states[device.id]?.updated ?? .distantPast) < 10), errors[device.id] == nil, let power = states[device.id]?.power?.lowercased(), ["on", "off"].contains(power) else {
            result = "現在の電源状態を取得できないため、切り替えませんでした。機器一覧を更新してください。"
            return
        }
        await send(SBAction(label: power == "on" ? "電源オフ" : "電源オン", command: power == "on" ? "turnOff" : "turnOn"), to: device)
    }
    func send(_ action: SBAction, to device: SBDevice) async {
        guard executing == nil else { return }
        guard device.cloud else { result = "SwitchBotアプリでクラウドサービスを有効にしてください"; return }
        executing = device.id; result = "送信中…"; defer { executing = nil }
        if demo { result = "デモ：\(action.label)（送信していません）"; return }
        guard !device.id.hasPrefix("demo-") else { result = "デモ画面を閉じ、機器一覧を更新してください"; return }
        do {
            _ = try await api("devices/\(Self.pathID(device.id))/commands", "POST", action.payload)
            if device.type == "Air Conditioner", !action.custom {
                var command = airCommands[device.id] ?? AirCommand()
                if action.command == "setAll" {
                    let parts = action.parameter.split(separator: ",").map(String.init)
                    if parts.count == 4 { command.temperature = Int(parts[0]); command.mode = Int(parts[1]); command.fan = Int(parts[2]); command.power = parts[3] }
                } else if action.command == "turnOff" { command.power = "off" }
                else if action.command == "turnOn" { command.power = "on" }
                command.updated = Date(); airCommands[device.id] = command
                if let data = try? JSONEncoder().encode(airCommands) { UserDefaults.standard.set(data, forKey: "sbAirCommands") }
            }
            result = device.infrared ? "送信を受け付けました。家電の実際の動作をご確認ください。" : "操作を受け付けました。状態を再取得します。"
            if !device.infrared { try? await Task.sleep(nanoseconds: 1_500_000_000); await refreshStatus(device, force: true) }
        } catch { result = "送信に失敗しました。通信状態と機器・ハブを確認してください。" }
    }
    static func pathID(_ id: String) -> String { id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "" }
}

struct AirCommand: Codable {
    var temperature: Int?
    var mode: Int?
    var fan: Int?
    var power: String?
    var updated = Date()
    var summary: String {
        let modes = [1:"自動",2:"冷房",3:"除湿",4:"送風",5:"暖房"], fans = [1:"自動",2:"弱",3:"中",4:"強"]
        return "\(power == "on" ? "ON" : power == "off" ? "OFF" : "—") · \(mode.flatMap { modes[$0] } ?? "モード—") \(temperature.map { "\($0)°C" } ?? "—°C") · 風量\(fan.flatMap { fans[$0] } ?? "—")"
    }
}
