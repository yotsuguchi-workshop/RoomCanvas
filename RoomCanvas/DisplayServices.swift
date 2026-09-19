import SwiftUI
import CoreLocation

// Keep all date screens on one Gregorian, Sunday-first calendar.
enum RoomCalendar {
    // A small margin avoids displaying the previous second due to early wake-up.
    static func nextClockDelay(after date: Date) -> TimeInterval {
        let seconds = date.timeIntervalSince1970
        return floor(seconds) + 1.01 - seconds
    }
    static var value: Calendar { var c = Calendar(identifier: .gregorian); c.locale = Locale(identifier: "ja_JP"); c.timeZone = .current; c.firstWeekday = 1; return c }
    static func key(_ date: Date) -> String { let c = value.dateComponents([.year,.month,.day], from: date); return String(format: "%04d-%02d-%02d", c.year!,c.month!,c.day!) }
    static func clock(_ date: Date) -> String { let c = value.dateComponents([.hour,.minute,.second], from: date); return String(format: "%@%d:%02d:%02d", c.hour! < 12 ? "午前" : "午後", c.hour! % 12 == 0 ? 12 : c.hour! % 12, c.minute!, c.second!) }
    static func dayKind(_ date: Date, holidays: [String:String]) -> Int { let weekday = value.component(.weekday, from: date); if weekday == 1 { return 1 }; if weekday == 7 { return 7 }; return holidays[key(date)] == nil ? 0 : 8 }
}
@MainActor final class HolidayStore: ObservableObject {
    @Published private(set) var names: [String:String] = BundledHolidays.names
    @Published var message = "内蔵祝日データ（1955〜2027年）"
    @Published var loading = false
    init() { if let data = UserDefaults.standard.data(forKey: "holidaysCache"), let cached = try? JSONDecoder().decode([String:String].self, from: data) { names.merge(cached) { _,new in new } } }
    func name(_ date: Date) -> String? { names[RoomCalendar.key(date)] }
    func color(_ date: Date) -> Color { switch RoomCalendar.dayKind(date, holidays: names) { case 1: return .sunday; case 7: return .saturday; case 8: return .holiday; default: return .white } }
    static func parse(_ data: Data) -> [String:String]? {
        guard let csv = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .shiftJIS) else { return nil }
        var values: [String:String] = [:]
        for row in csv.components(separatedBy: .newlines) {
            let parts = row.split(separator: ",", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let d = parts[0].split(separator: "/").compactMap { Int($0) }
            guard d.count == 3, (1955...2200).contains(d[0]), (1...12).contains(d[1]), (1...31).contains(d[2]), !parts[1].isEmpty else { continue }
            values[String(format: "%04d-%02d-%02d",d[0],d[1],d[2])] = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard values.count > 1000, values["2026-09-22"] != nil, values["2027-01-01"] != nil else { return nil }
        return values
    }
    func update(force: Bool = false) async {
        guard !loading else { return }
        let last = UserDefaults.standard.object(forKey: "holidayChecked") as? Date ?? .distantPast
        guard force || Date().timeIntervalSince(last) > 604800 else { return }
        loading = true; defer { loading = false }
        do {
            var request = URLRequest(url: URL(string: "https://www8.cao.go.jp/chosei/shukujitsu/syukujitsu.csv")!); request.timeoutInterval = 15
            let (data,response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, let parsed = Self.parse(data) else { throw RoomFailure.message("祝日形式不正") }
            names = BundledHolidays.names.merging(parsed) { _,new in new }
            UserDefaults.standard.set(try JSONEncoder().encode(parsed), forKey: "holidaysCache"); UserDefaults.standard.set(Date(), forKey: "holidayChecked")
            message = "内閣府データ更新済み · \(String((names.keys.max() ?? "2027").prefix(4)))年まで"
        } catch { message = "更新できませんでした · 内蔵／保存済み祝日を使用" }
    }
}
struct WeatherReading: Codable {
    let region: String; let code: Int; let high: Double?; let low: Double?; let rain: Double?; let day: String; let updated: Date
    var title: String { switch code { case 0,1: return "晴れ"; case 2: return "晴れ時々曇り"; case 3: return "曇り"; case 45,48: return "霧"; case 51...67,80...82: return "雨"; case 71...77,85,86: return "雪"; case 95...99: return "雷雨"; default: return "天気不明" } }
    var icon: String { switch code { case 0,1: return "sun.max.fill"; case 2: return "cloud.sun.fill"; case 3: return "cloud.fill"; case 45,48: return "cloud.fog.fill"; case 51...67,80...82: return "cloud.rain.fill"; case 71...77,85,86: return "cloud.snow.fill"; case 95...99: return "cloud.bolt.rain.fill"; default: return "questionmark.circle" } }
    static func number(_ value: Double?, unit: String) -> String { value.map { String(format: "%.0f",$0) + unit } ?? "—" + unit }
}
@MainActor final class WeatherStore: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published var reading: WeatherReading?
    @Published var message = "設定で現在地または地域を選択"
    @Published var loading = false
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var timeout: Task<Void,Never>?
    private var lastAttempt = Date.distantPast
    private var generation = 0
    private var activeConfig = ""
    var demo: Bool { UserDefaults.standard.object(forKey: "demo") as? Bool ?? true }
    var mode: String { UserDefaults.standard.string(forKey: "weatherMode") ?? "location" }
    var config: String { "\(demo)|\(mode)|\(UserDefaults.standard.string(forKey: "weatherRegion") ?? "")" }
    override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyKilometer }
    func refresh(force: Bool = false, requestPermission: Bool = false) async {
        let changed = activeConfig != config
        if changed { generation += 1; manager.stopUpdatingLocation(); timeout?.cancel(); loading = false; reading = nil; activeConfig = config }
        guard !loading, force || changed || Date().timeIntervalSince(lastAttempt) > 1800 else { return }
        lastAttempt = Date()
        if demo { reading = WeatherReading(region: "デモ", code: 0, high: 28, low: 21, rain: 10, day: RoomCalendar.key(Date()), updated: Date()); message = "サンプル"; return }
        loading = true; generation += 1; let id = generation
        if mode == "manual" { await manual(id: id); return }
        switch manager.authorizationStatus {
        case .authorizedAlways,.authorizedWhenInUse:
            message = "現在地を取得中…"; manager.requestLocation(); scheduleTimeout(id)
        case .notDetermined:
            if requestPermission { manager.requestWhenInUseAuthorization(); scheduleTimeout(id) }
            else { await manual(id: id) }
        default: await manual(id: id)
        }
    }
    private func scheduleTimeout(_ id: Int) { timeout?.cancel(); timeout = Task { try? await Task.sleep(nanoseconds: 12_000_000_000); guard !Task.isCancelled, generation == id, loading else { return }; manager.stopUpdatingLocation(); await manual(id: id) } }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard mode == "location", !demo else { return }
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways { loading = false; Task { await refresh(force: true) } }
        else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted { Task { await manual(id: generation) } }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        timeout?.cancel(); guard mode == "location", !demo, activeConfig == config, loading, let location = locations.last, abs(location.timestamp.timeIntervalSinceNow) < 300 else { return }
        let id = generation
        let lat = (location.coordinate.latitude * 100).rounded()/100, lon = (location.coordinate.longitude * 100).rounded()/100
        Task { await fetch(lat: lat, lon: lon, region: "現在地", id: id) }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { guard loading, !demo, mode == "location", activeConfig == config else { return }; timeout?.cancel(); Task { await manual(id: generation) } }
    private func manual(id: Int) async {
        guard id == generation, !demo, activeConfig == config else { return }
        let region = UserDefaults.standard.string(forKey: "weatherRegion") ?? ""
        guard !region.isEmpty, UserDefaults.standard.object(forKey: "weatherLatitude") != nil else { loading = false; message = "現在地を利用できません · 設定で地域を選択"; return }
        await fetch(lat: UserDefaults.standard.double(forKey: "weatherLatitude"), lon: UserDefaults.standard.double(forKey: "weatherLongitude"), region: region + (mode == "location" ? "（代替地域）" : ""), id: id)
    }
    func selectRegion(_ name: String) async {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        message = "地域を検索中…"
        do {
            geocoder.cancelGeocode()
            let places = try await geocoder.geocodeAddressString(name, in: nil, preferredLocale: Locale(identifier: "ja_JP"))
            guard let place = places.first, let location = place.location else { throw RoomFailure.message("地域が見つかりません") }
            UserDefaults.standard.set(name, forKey: "weatherRegion"); UserDefaults.standard.set(location.coordinate.latitude, forKey: "weatherLatitude"); UserDefaults.standard.set(location.coordinate.longitude, forKey: "weatherLongitude"); UserDefaults.standard.set("manual", forKey: "weatherMode")
            await refresh(force: true)
        } catch { message = "地域が見つかりません。市区町村名で試してください。" }
    }
    private func fetch(lat: Double, lon: Double, region: String, id: Int) async {
        let key = config
        do {
            var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
            components.queryItems = [URLQueryItem(name:"latitude",value:String(lat)), URLQueryItem(name:"longitude",value:String(lon)), URLQueryItem(name:"daily",value:"weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),URLQueryItem(name:"timezone",value:"auto"),URLQueryItem(name:"forecast_days",value:"1")]
            var request = URLRequest(url: components.url!); request.timeoutInterval = 15
            let (data,response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw RoomFailure.message("天気通信エラー") }
            struct Response: Decodable { struct Daily: Decodable { let time:[String]; let weather_code:[Int?]; let temperature_2m_max:[Double?]; let temperature_2m_min:[Double?]; let precipitation_probability_max:[Double?] }; let daily:Daily }
            let d = try JSONDecoder().decode(Response.self, from: data).daily
            guard let day = d.time.first, let firstCode = d.weather_code.first, let code = firstCode else { throw RoomFailure.message("天気データなし") }
            guard id == generation, config == key, !demo else { return }
            reading = WeatherReading(region: region,code:code,high:d.temperature_2m_max.first ?? nil,low:d.temperature_2m_min.first ?? nil,rain:d.precipitation_probability_max.first ?? nil,day:day,updated:Date()); message = "Open-Meteo · \(region)"
        } catch { if id == generation && config == key { message = reading == nil ? "天気を取得できません · 設定で再取得" : "更新失敗 · 前回の予報" } }
        if id == generation { loading = false }
    }
}
