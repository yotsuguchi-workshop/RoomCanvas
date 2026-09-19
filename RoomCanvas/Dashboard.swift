import SwiftUI
import Combine
import EventKit

extension Color {
    static let canvas = Color(red:0.055,green:0.085,blue:0.12)
    static let panel = Color(red:0.095,green:0.13,blue:0.17)
    static let mint = Color(red:0.59,green:0.85,blue:0.74)
    static let sand = Color(red:0.94,green:0.79,blue:0.56)
    static let secondaryInk = Color(red:0.65,green:0.71,blue:0.75)
    static let sunday = Color(red:1,green:0.53,blue:0.53)
    static let saturday = Color(red:0.50,green:0.72,blue:1)
    static let holiday = Color(red:0.56,green:0.87,blue:0.62)
}
struct Card<Content: View>: View {
    let content: Content; var fill: Bool
    init(fill: Bool = false, @ViewBuilder content: () -> Content) { self.fill = fill; self.content = content() }
    var body: some View { content.padding(20).frame(maxWidth:.infinity,maxHeight:fill ? .infinity:nil,alignment:.topLeading).background(Color.panel).cornerRadius(24) }
}
enum PanelSheet: Identifiable { case settings, unlock, device(SBDevice)
    var id: String { switch self { case .settings: return "settings"; case .unlock: return "unlock"; case .device(let d): return d.id } }
}
enum DetailPage: String, Identifiable { case clock, calendar; var id:String { rawValue } }
struct Dashboard: View {
    @StateObject private var store = RoomStore()
    @StateObject private var ble = BLELab()
    @StateObject private var devices = DeviceStore()
    @StateObject private var weather = WeatherStore()
    @StateObject private var holidays = HolidayStore()
    @AppStorage("room") private var room = "My Room"
    @AppStorage("outside") private var outside = false
    @AppStorage("hideTitles") private var hideTitles = true
    @AppStorage("demo") private var demo = true
    @AppStorage("availability") private var availability = "在室"
    @State private var page = 1
    @State private var sheet: PanelSheet?
    @State private var detail: DetailPage?
    @State private var unlockToSettings = false
    @Environment(\.scenePhase) private var phase
    private let timer = Timer.publish(every:60,on:.main,in:.common).autoconnect()
    var body: some View {
        GeometryReader { area in
            VStack(spacing:12) {
                header.frame(height:48)
                mainContent.frame(maxWidth:.infinity,maxHeight:.infinity).contentShape(Rectangle())
                    .simultaneousGesture(DragGesture(minimumDistance:35).onEnded { v in
                        guard abs(v.translation.width) > 65, abs(v.translation.width) > abs(v.translation.height)*1.5 else { return }
                        page = min(2,max(0,page + (v.translation.width < 0 ? 1 : -1)))
                    })
                navigation.frame(height:44)
            }.padding(16).frame(width:area.size.width,height:area.size.height).background(Color.canvas.ignoresSafeArea())
        }.foregroundColor(.white).preferredColorScheme(.dark).statusBar(hidden:true)
        .sheet(item:$sheet,onDismiss:{ if unlockToSettings { unlockToSettings = false; sheet = .settings } }) { destination in
            switch destination {
            case .settings: SettingsView(store:store,devices:devices,weather:weather,holidays:holidays,ble:ble)
            case .unlock: UnlockView { unlockToSettings = true; sheet = nil }
            case .device(let device): DeviceControlView(device:device,devices:devices)
            }
        }
        .fullScreenCover(item:$detail,onDismiss:{ store.month = Date(); store.selectedDay = RoomCalendar.value.startOfDay(for:Date()); Task { await store.refreshCalendar() } }) { destination in
            if destination == .clock { ClockScreen(room:room,availability:availability,holidays:holidays) }
            else { CalendarScreen(store:store,holidays:holidays,privateTitles:outside && hideTitles) }
        }
        .task {
            ble.onPress = { press in
                let event = CallPopup.shared.show(room:UserDefaults.standard.string(forKey:"room") ?? "My Room",button:press)
                let result: String
                if store.demo { result = "デモモードのため通知を送信しませんでした" }
                else if store.calling || Date().timeIntervalSince(store.lastCall ?? .distantPast) < 30 { result = "直前の呼び出しから30秒以内のため送信を抑止しました" }
                else {
                    await store.call(room:UserDefaults.standard.string(forKey:"room") ?? "My Room")
                    result = store.callMessage
                }
                CallPopup.shared.update(result,event:event)
                return result
            }
            ble.resumeConfigured()
            if availability == "集中中" { availability = "作業中" }; if availability == "不在" { availability = "外出" }
            UIApplication.shared.isIdleTimerDisabled = true
            await refresh(); await weather.refresh(requestPermission:true); await holidays.update()
        }
        .onReceive(timer) { _ in Task { await store.refreshCalendar(); if page == 1 && !outside { await devices.refreshSensor() }; await weather.refresh() } }
        .onReceive(NotificationCenter.default.publisher(for:.EKEventStoreChanged).debounce(for:.milliseconds(500),scheduler:RunLoop.main)) { _ in Task { await store.refreshCalendar() } }
        .onChange(of:phase) { value in ble.setPhase(value); UIApplication.shared.isIdleTimerDisabled = value == .active; if value == .active { Task { await refresh(); await weather.refresh() } } }
        .onChange(of:outside) { _ in page = 1; detail = nil }
        .onChange(of:demo) { _ in Task { await refresh(); await weather.refresh(force:true) } }
    }
    private func refresh() async { await store.refreshCalendar(); await devices.fetch(); await store.fetchScenes() }
    private var header: some View {
        HStack {
            Text(room).font(.system(size:28,weight:.semibold)).lineLimit(1)
            Spacer()
            RemoteCallIndicator(remote:ble)
            BatteryIndicator()
            if demo { Text("DEMO").font(.caption.bold()).foregroundColor(.sand) }
            Button { sheet = outside && !Vault.read("pinHash").isEmpty ? .unlock:.settings } label: { Label(outside ? "管理":"設定",systemImage:outside ? "lock":"slider.horizontal.3").padding(.horizontal,18).frame(height:44).background(Color.white.opacity(0.07)).cornerRadius(12) }
        }.buttonStyle(.plain)
    }
    private var navigation: some View {
        HStack(spacing:14) {
            ForEach(Array(["部屋の操作","ダッシュボード","その他"].enumerated()),id:\.offset) { index,title in
                Button { page = index } label: { Text(title).font(.system(size:17,weight:.semibold)).frame(width:180,height:44).background(page == index ? Color.mint:Color.white.opacity(0.07)).foregroundColor(page == index ? .canvas:.white).cornerRadius(13) }
            }
        }.buttonStyle(.plain)
    }
    @ViewBuilder private var mainContent: some View {
        if page == 0 {
            if outside { Card(fill:true) { VStack(spacing:24) { Spacer(); Image(systemName:"lock.fill").font(.system(size:44)).foregroundColor(.mint); Text("機器操作は管理者専用です").font(.title2); Button("管理設定を開く") { sheet = .unlock }; Spacer() }.frame(maxWidth:.infinity) } }
            else { RoomControlsPage(store:store,devices:devices) }
        } else if page == 2 || outside { otherPage }
        else { home }
    }
    private var home: some View {
        GeometryReader { area in
            let top = (area.size.height-14)*0.48
            VStack(spacing:14) {
                HStack(spacing:14) {
                    clockWeatherCard
                    environmentCard
                }.frame(height:top)
                Card(fill:true) {
                    VStack(spacing:8) {
                        Button { openCalendar() } label: { HStack { Text("カレンダー・予定").font(.headline); Spacer(); Text("全画面で開く ↗").font(.subheadline).foregroundColor(.mint) } }.buttonStyle(.plain)
                        HStack(alignment:.top,spacing:30) {
                            MonthGrid(month:Date(),selected:RoomCalendar.value.startOfDay(for:Date()),holidays:holidays,events:store.events,compact:true) { date in openCalendar(date) }
                            AgendaSummary(store:store,holidays:holidays,date:Date(),privateTitles:false) { openCalendar() }
                        }
                    }
                }
            }
        }
    }
    private func openCalendar(_ date: Date = Date()) { store.selectedDay = date; store.month = date; detail = .calendar; Task { await store.refreshCalendar() } }
    private var clockWeatherCard: some View {
        Card(fill:true) {
            VStack(alignment:.leading,spacing:6) {
                TimelineView(.periodic(from:.now,by:1)) { time in
                    Button { detail = .clock } label: {
                        VStack(alignment:.leading,spacing:3) {
                            Text(time.date.formatted(.dateTime.month().day().weekday(.wide).locale(Locale(identifier:"ja_JP")))).font(.system(size:20)).foregroundColor(holidays.color(time.date))
                            Text(RoomCalendar.clock(time.date)).font(.system(size:68,weight:.light,design:.rounded)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                        }.frame(maxWidth:.infinity,alignment:.leading)
                    }.buttonStyle(.plain)
                }
                WeatherSummary(weather:weather)
                Spacer(minLength:0)
                AvailabilityPicker(value:$availability).disabled(outside)
            }
        }
    }
    private var environmentCard: some View {
        Card(fill:true) {
            VStack(alignment:.leading,spacing:6) {
                Button { page = 0 } label: { HStack { Text("部屋の操作").font(.headline); Spacer(); Image(systemName:"arrow.up.right") } }.buttonStyle(.plain)
                HStack(alignment:.firstTextBaseline,spacing:14) {
                    if let sensor = devices.sensor, let state = devices.states[sensor.id] {
                        Button { sheet = .device(sensor) } label: { Text(state.temperature.map { String(format:"%.1f°C",$0) } ?? "—°C").font(.system(size:52,weight:.light,design:.rounded)).minimumScaleFactor(0.6).lineLimit(1) }.buttonStyle(.plain)
                        Text("湿度 " + (state.humidity.map { String(format:"%.0f%%",$0) } ?? "—%")).font(.system(size:23)).lineLimit(1)
                    } else { Text("—°C").font(.system(size:52,weight:.light)); Text("湿度 —%").font(.title3) }
                }.foregroundColor(.mint)
                if let air = devices.air {
                    Button { sheet = .device(air) } label: {
                        VStack(alignment:.leading,spacing:2) {
                            Text(devices.airSummary(air)).font(.system(size:14)).lineLimit(1).minimumScaleFactor(0.8)
                            Text("赤外線 · 実状態は取得不可").font(.system(size:11)).foregroundColor(.secondaryInk)
                        }.frame(maxWidth:.infinity,alignment:.leading)
                    }.buttonStyle(.plain)
                } else { Text("エアコン未登録").font(.caption).foregroundColor(.secondaryInk) }
                if devices.favorites.isEmpty {
                    Button("お気に入り操作を登録（最大4つ）") { sheet = .settings }.frame(maxWidth:.infinity,maxHeight:.infinity).foregroundColor(.mint)
                } else {
                    LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:7) {
                        ForEach(devices.favorites) { favorite in
                            Button { Task { await devices.runFavorite(favorite) } } label: {
                                VStack(spacing:2) {
                                    Text(favorite.deviceName).font(.system(size:11)).foregroundColor(.secondaryInk).lineLimit(1)
                                    Text(favorite.action.label).font(.system(size:14,weight:.medium)).lineLimit(1).minimumScaleFactor(0.65)
                                }.frame(maxWidth:.infinity,minHeight:37).padding(.horizontal,5).background(Color.white.opacity(0.07)).cornerRadius(10)
                            }.buttonStyle(.plain).disabled(devices.toggling || devices.executing != nil)
                        }
                    }
                }
                if !devices.result.isEmpty { Text(devices.result).font(.system(size:10)).foregroundColor(.sand).lineLimit(1) }
                else if let sensor = devices.sensor, let state = devices.states[sensor.id] { Text(devices.errors[sensor.id] == nil ? "\(sensor.name) · \(state.updated.formatted(date:.omitted,time:.shortened))取得" : "温湿度の更新失敗 · 前回値").font(.system(size:10)).foregroundColor(.secondaryInk).lineLimit(1) }
            }
        }
    }
    private var otherPage: some View {
        HStack(spacing:14) {
            VStack(spacing:14) {
                clockWeatherCard
                Card(fill:true) {
                    VStack(alignment:.leading,spacing:12) {
                        Text("ご用の方はこちらから").font(.title2.bold())
                        Spacer(minLength:0)
                        TimelineView(.periodic(from:.now,by:1)) { time in
                            let remaining = max(0,30-Int(time.date.timeIntervalSince(store.lastCall ?? .distantPast)))
                            Button { Task { await store.call(room:room) } } label: { Label(store.calling ? "送信中…" : remaining > 0 ? "あと\(remaining)秒":"呼び出す",systemImage:"bell.badge").font(.title2.bold()).frame(maxWidth:.infinity,minHeight:66).background(Color.mint).foregroundColor(.canvas).cornerRadius(16) }.disabled(store.calling || remaining > 0)
                        }
                        Text(store.callMessage.isEmpty ? "部屋名・呼び出し時刻を通知先へ送信":store.callMessage).font(.footnote).foregroundColor(.secondaryInk).lineLimit(3)
                        Spacer(minLength:0)
                    }
                }
            }
            Card(fill:true) { VStack(spacing:20) { AgendaSummary(store:store,holidays:holidays,date:Date(),privateTitles:outside && hideTitles) { openCalendar() }; Spacer(minLength:0); Button("時計を全画面で開く") { detail = .clock }; Button("カレンダーと予定を開く") { openCalendar() } }.frame(maxWidth:.infinity) }
        }
    }
}
struct AvailabilityPicker: View {
    @Binding var value:String
    var body: some View { HStack(spacing:7) { ForEach(["在室","外出","作業中"],id:\.self) { status in Button { value = status } label: { Text(status).font(.system(size:15,weight:.semibold)).frame(maxWidth:.infinity,minHeight:34).foregroundColor(value == status ? .canvas:.white).background(value == status ? Color.mint:Color.white.opacity(0.07)).cornerRadius(10) }.buttonStyle(.plain).accessibilityAddTraits(value == status ? .isSelected:[]) } } }
}
struct WeatherSummary: View {
    @ObservedObject var weather:WeatherStore
    var body: some View {
        HStack(spacing:12) {
            Image(systemName:weather.reading?.icon ?? "cloud").font(.system(size:38)).foregroundColor(.sand).accessibilityLabel(weather.reading?.title ?? "天気未取得")
            VStack(alignment:.leading,spacing:3) {
                if let reading = weather.reading {
                    Text("\(reading.region) · \(reading.title)").font(.system(size:14)).lineLimit(1)
                    (Text("↑\(WeatherReading.number(reading.high,unit:"°C"))  ↓\(WeatherReading.number(reading.low,unit:"°C"))  ") + Text(Image(systemName:"drop.fill")) + Text(" \(WeatherReading.number(reading.rain,unit:"%"))")).font(.system(size:17,weight:.medium)).minimumScaleFactor(0.7).lineLimit(1).accessibilityLabel("今日の最高気温 \(WeatherReading.number(reading.high,unit:"度"))、最低気温 \(WeatherReading.number(reading.low,unit:"度"))、降水確率 \(WeatherReading.number(reading.rain,unit:"パーセント"))")
                    Text("\(reading.updated.formatted(date:.omitted,time:.shortened))予報取得 · \(weather.message)").font(.system(size:9)).lineLimit(1)
                } else { Text(weather.loading ? "天気を取得中…":weather.message).font(.system(size:13)).lineLimit(2) }
            }.foregroundColor(.sand)
        }.frame(maxWidth:.infinity,alignment:.leading).frame(minHeight:62)
    }
}
struct ClockScreen: View {
    let room:String; let availability:String
    @ObservedObject var holidays:HolidayStore
    @Environment(\.dismiss) private var dismiss
    var body: some View { GeometryReader { area in
        VStack(spacing:20) {
            HStack { Text(room); Spacer(); Text(availability).foregroundColor(.mint); BatteryIndicator() }.font(.title2)
            Spacer()
            TimelineView(.periodic(from:.now,by:1)) { time in
                VStack(spacing:16) {
                    Text(time.date.formatted(.dateTime.year().month().day().weekday(.wide).locale(Locale(identifier:"ja_JP")))).font(.system(size:30)).foregroundColor(holidays.color(time.date))
                    Text(RoomCalendar.clock(time.date)).font(.system(size:area.size.width*0.15,weight:.ultraLight,design:.rounded)).monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                }
            }
            Spacer(); Button("閉じる") { dismiss() }.padding(16).background(Color.panel).cornerRadius(12)
        }.padding(26).frame(maxWidth:.infinity,maxHeight:.infinity).background(Color.canvas.ignoresSafeArea())
    }.foregroundColor(.white).preferredColorScheme(.dark).statusBar(hidden:true) }
}
@main struct RoomCanvasApp: App { var body: some Scene { WindowGroup { Dashboard().environment(\.locale,Locale(identifier:"ja_JP")) } } }

struct BatteryIndicator: View {
    @State private var level: Float = -1
    @State private var state: UIDevice.BatteryState = .unknown
    private var charging: Bool { state == .charging || state == .full }
    private var percent: Int? { level >= 0 ? Int((min(1,level)*100).rounded()) : nil }
    private var icon: String {
        if charging { return "battery.100.bolt" }
        guard let percent = percent else { return "battery.0" }
        return percent > 85 ? "battery.100" : percent > 60 ? "battery.75" : percent > 35 ? "battery.50" : percent > 10 ? "battery.25" : "battery.0"
    }
    var body: some View {
        HStack(spacing:5) {
            Image(systemName:icon).font(.system(size:20))
            Text(percent.map { "\($0)%" } ?? "—%").font(.system(size:15,weight:.semibold)).monospacedDigit()
            if charging { Text(state == .full ? "充電完了":"充電中").font(.system(size:11)) }
        }.foregroundColor(charging ? .mint : (percent ?? 100) <= 20 ? .sand : .secondaryInk)
        .fixedSize().accessibilityElement(children:.ignore)
        .accessibilityLabel("バッテリー残量 \(percent.map { "\($0)パーセント" } ?? "取得できません")\(charging ? "、充電器接続中":"")")
        .onAppear { UIDevice.current.isBatteryMonitoringEnabled = true; update() }
        .onReceive(NotificationCenter.default.publisher(for:UIDevice.batteryLevelDidChangeNotification)) { _ in update() }
        .onReceive(NotificationCenter.default.publisher(for:UIDevice.batteryStateDidChangeNotification)) { _ in update() }
        .onReceive(NotificationCenter.default.publisher(for:UIApplication.didBecomeActiveNotification)) { _ in update() }
    }
    private func update() { level = UIDevice.current.batteryLevel; state = UIDevice.current.batteryState }
}
