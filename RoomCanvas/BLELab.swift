import SwiftUI
import CoreBluetooth
import UIKit

struct BLEObservation: Identifiable, Codable {
    let id: String
    var name: String
    var rssi: Int
    var count: Int
    var last: Date
    var services: [String]
    var manufacturer: String
    var serviceData: [String:String]
}
struct BLERecord: Codable {
    let time: Date
    let kind: String
    let phase: String
    let device: BLEObservation?
    let note: String
}
// Format inferred from observed SwitchBot Remote counters; not a published protocol.
struct RemotePressDetector {
    private var previous: [UInt8]?
    mutating func reset() { previous = nil }
    mutating func receive(manufacturer: String, service: String?) -> String? {
        guard manufacturer.count == 24, manufacturer.hasPrefix("6909"), service?.hasPrefix("62") == true else { return nil }
        var bytes: [UInt8] = []; var index = manufacturer.startIndex
        while index < manufacturer.endIndex { let next = manufacturer.index(index,offsetBy:2); guard let value = UInt8(manufacturer[index..<next],radix:16) else { return nil }; bytes.append(value); index = next }
        defer { previous = bytes }
        guard let old = previous, Array(old[2...7]) == Array(bytes[2...7]) else { return nil }
        let sequence = bytes[8] &- old[8], concave = bytes[10] &- old[10], round = bytes[11] &- old[11]
        guard sequence == 1 else { return nil }
        if round == 1 && concave == 0 { return "丸" }
        if concave == 1 && round == 0 { return "凹" }
        return nil
    }
}
@MainActor final class BLELab: NSObject, ObservableObject, @preconcurrency CBCentralManagerDelegate {
    @Published private(set) var running = false
    @Published private(set) var status = "停止中"
    @Published private(set) var observations: [BLEObservation] = []
    @Published private(set) var received = 0
    @Published private(set) var marks = 0
    @Published private(set) var recordCount = 0
    @Published private(set) var roundPresses = 0
    @Published private(set) var concavePresses = 0
    @Published private(set) var lastDetection: Date?
    private var detector = RemotePressDetector()
    @Published private(set) var target = UserDefaults.standard.string(forKey:"bleCallTarget") ?? ""
    @Published var notificationsEnabled = false {
        didSet { UserDefaults.standard.set(notificationsEnabled,forKey:"bleCallEnabled"); if !sending { notificationStatus = notificationsEnabled ? "次の押下で通知先へ通知します" : "自動通知はオフです" } }
    }
    @Published private(set) var notificationStatus = "自動通知はオフです"
    var onPress: ((String) async -> String)?
    private var lastAttempt = UserDefaults.standard.object(forKey:"bleLastAttempt") as? Date ?? .distantPast
    private var sending = false
    @Published var serviceFilter = ""
    @Published var background = false
    @Published private(set) var phase = "active"
    private var central: CBCentralManager?
    private var wanted = false
    private var records: [BLERecord] = []
    private var latest: [String:BLEObservation] = [:]
    private var recorded: [String:BLEObservation] = [:]
    private var publishTask: Task<Void,Never>?
    private var activeFilter: [CBUUID]?
    private var backgroundAllowed = false
    private var totalReceived = 0
    override init() {
        super.init()
        notificationsEnabled = UserDefaults.standard.object(forKey:"bleCallEnabled") as? Bool ?? false
        notificationStatus = notificationsEnabled ? "次の押下で通知先へ通知します" : "自動通知はオフです"
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf:Self.logURL), let saved = try? decoder.decode([BLERecord].self,from:data) { records = Array(saved.suffix(3000)); recordCount = records.count }
    }
    private var sessionStarted = Date()
    private var lastSave = Date.distantPast
    static var logURL: URL { FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("RoomCanvas-BLE-latest.json") }
    func resumeConfigured() {
        if notificationsEnabled && !target.isEmpty { serviceFilter = ""; background = false; start() }
    }
    func setCallEnabled(_ enabled: Bool) {
        if enabled { guard !target.isEmpty else { return }; notificationsEnabled = true; serviceFilter = ""; background = false; wanted = false; central?.stopScan(); start() }
        else { stop() }
    }
    func start() {
        guard !wanted else { return }
        let raw = serviceFilter.trimmingCharacters(in:.whitespacesAndNewlines)
        let pattern = "^([0-9a-fA-F]{4}|[0-9a-fA-F]{8}|[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$"
        guard raw.isEmpty || raw.range(of:pattern,options:.regularExpression) != nil else { status = "サービスUUIDの形式を確認してください"; return }
        guard !background || !raw.isEmpty else { status = "背景検証には実測したサービスUUIDを指定してください"; return }
        activeFilter = raw.isEmpty ? nil:[CBUUID(string:raw)]
        detector.reset(); backgroundAllowed = background; wanted = true; sessionStarted = Date()
        append(kind:"session",note:"開始 filter=\(raw.isEmpty ? "all":raw) background=\(background)")
        if central == nil { central = CBCentralManager(delegate:self,queue:.main) } else { scanIfReady() }
    }
    func stop() { notificationsEnabled = false; wanted = false; central?.stopScan(); running = false; status = "停止中"; append(kind:"session",note:"停止"); save() }
    func setPhase(_ value: ScenePhase) {
        detector.reset()
        phase = value == .active ? "active" : value == .background ? "background":"inactive"
        append(kind:"lifecycle",note:phase); save()
        if value == .background && !backgroundAllowed { central?.stopScan(); running = false; status = wanted ? "背景で休止（前面で再開）":"停止中" }
        if value == .active && wanted { scanIfReady() }
    }
    private func scanIfReady() {
        guard wanted, central?.state == .poweredOn, phase != "background" || backgroundAllowed else { return }
        central?.scanForPeripherals(withServices:activeFilter,options:[CBCentralManagerScanOptionAllowDuplicatesKey:true])
        running = true; status = activeFilter == nil ? "前面スキャン中・全広告":"スキャン中・UUID指定"
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        running = false; detector.reset()
        switch central.state {
        case .poweredOn: status = "Bluetooth使用可能"; scanIfReady()
        case .poweredOff: status = "Bluetoothがオフです"
        case .unauthorized: status = "設定アプリでBluetoothの利用を許可してください"
        case .unsupported: status = "Bluetooth非対応です"
        case .resetting: status = "Bluetooth再接続待ち"
        default: status = "Bluetooth初期化中"
        }
        append(kind:"bluetooth",note:status)
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String:Any], rssi RSSI: NSNumber) {
        guard wanted else { return }
        let id = peripheral.identifier.uuidString
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []).map(\.uuidString).sorted()
        let data = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID:Data] ?? [:]
        func hex(_ data: Data) -> String { data.map { String(format:"%02X",$0) }.joined() }
        let observation = BLEObservation(id:id,name:advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "名称なし",rssi:RSSI.intValue,count:(latest[id]?.count ?? 0)+1,last:Date(),services:services,manufacturer:hex(advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data ?? Data()),serviceData:Dictionary(uniqueKeysWithValues:data.map { ($0.key.uuidString,hex($0.value)) }))
        latest[id] = observation
        if latest.count > 100, let oldest = latest.values.min(by: { $0.last < $1.last }) { latest.removeValue(forKey:oldest.id) }
        totalReceived += 1
        if target == id, let press = detector.receive(manufacturer:observation.manufacturer,service:observation.serviceData["FD3D"]) {
            if press == "丸" { roundPresses += 1 } else { concavePresses += 1 }
            lastDetection = Date(); append(kind:"detected-press",device:observation,note:press); save(); notify(press)
        }
        if target.isEmpty || target == id {
            let previous = recorded[id]
            if previous == nil || previous?.manufacturer != observation.manufacturer || previous?.serviceData != observation.serviceData || previous?.services != observation.services || observation.last.timeIntervalSince(previous!.last) >= 5 {
                append(kind:"advertisement",device:observation,note:""); recorded[id] = observation
            }
        }
        // Publish the visible list at most once per second, keeping raw records for analysis.
        if publishTask == nil { publishTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds:1_000_000_000)
            guard let self = self else { return }
            self.received = self.totalReceived; self.recordCount = self.records.count
            self.observations = self.latest.values.sorted { $0.id < $1.id }; self.publishTask = nil
            if Date().timeIntervalSince(self.lastSave) >= 5 { self.save() }
        } }
    }
    private func notify(_ press: String) {
        guard notificationsEnabled else { return }
        guard phase == "active" else { notificationStatus = "バックグラウンド中は呼び出しを休止しています"; return }
        guard !sending, Date().timeIntervalSince(lastAttempt) >= 30 else { notificationStatus = "連続検出を抑止しました（30秒間隔）"; append(kind:"notification-suppressed",note:press); return }
        guard let handler = onPress else { notificationStatus = "通知の準備ができていません"; return }
        lastAttempt = Date(); UserDefaults.standard.set(lastAttempt,forKey:"bleLastAttempt"); sending = true; notificationStatus = "通知先へ送信中…"
        append(kind:"notification-attempt",note:press)
        Task {
            let result = await handler(press)
            self.notificationStatus = result; self.sending = false
            self.append(kind:"notification-result",note:result); self.save()
        }
    }
    func mark(_ label: String) { marks += 1; append(kind:"manual-marker",note:label); save() }
    func choose(_ id: String) { notificationsEnabled = false; detector.reset(); target = id; UserDefaults.standard.set(id,forKey:"bleCallTarget"); append(kind:"target",note:id); save() }
    func clear() { detector.reset(); roundPresses = 0; concavePresses = 0; lastDetection = nil; records = []; latest = [:]; recorded = [:]; observations = []; received = 0; totalReceived = 0; marks = 0; recordCount = 0; sessionStarted = Date(); save() }
    private func append(kind:String,device:BLEObservation? = nil,note:String) {
        records.append(BLERecord(time:Date(),kind:kind,phase:phase,device:device,note:note))
        if records.count > 3000 { records.removeFirst(records.count-3000) }
        if kind != "advertisement" { recordCount = records.count }
    }
    func save() {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        do { let data = try encoder.encode(records); try data.write(to:Self.logURL,options:.atomic); lastSave = Date() }
        catch { status = "ログ保存に失敗しました" }
    }
}
struct BLELabView: View {
    @ObservedObject var lab: BLELab
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    @State private var share = false
    var body: some View {
        NavigationView {
            Form {
                Section(header:Text("Remote BLE呼び出し検証")) {
                    Text("SwitchBot Remoteの実測に基づく検出です。広告の受信件数と押下回数は異なります。選択した候補の丸・凹の両方を呼び出しに使います。")
                    Text(lab.status).foregroundColor(.mint)
                    Text("検出：丸 \(lab.roundPresses)回 ／ 凹 \(lab.concavePresses)回").font(.title2).foregroundColor(.mint)
                    Text(lab.target.isEmpty ? "候補を選ぶと押下検出を開始します" : "選択機器のカウンター変化を検出").font(.caption)
                    TimelineView(.periodic(from:.now,by:1)) { time in
                        Text(lab.lastDetection.map { "最後の検出から \(max(0,Int(time.date.timeIntervalSince($0))))秒" } ?? "まだ押下を検出していません").font(.caption)
                    }
                    HStack { Text("受信 \(lab.received)件"); Spacer(); Text("手動記録 \(lab.marks)回"); Spacer(); Text("\(lab.phase)") }
                    HStack { Button("スキャン開始") { lab.start() }.disabled(lab.running); Spacer(); Button("停止") { lab.stop() }; Spacer(); Button("押した：丸") { lab.mark("丸ボタンを押した") }; Spacer(); Button("押した：凹") { lab.mark("凹ボタンを押した") } }
                }
                Section(header:Text("Webhook通知"),footer:Text("前面で動作中のみ、設定したWebhookへ部屋名と呼び出し時刻を送信します。30秒間隔で連打を抑止。有効状態を保存し、次回起動時も再開します。停止・機器変更ではオフになります。デモモードでは送信しません。")) {
                    Toggle("丸・凹の検出で通知先へ通知",isOn:$lab.notificationsEnabled).disabled(lab.target.isEmpty || !lab.running)
                    Text(lab.notificationsEnabled ? lab.notificationStatus : "自動通知はオフです").font(.caption)
                }
                Section(header:Text("スキャン設定"),footer:Text("最初はUUIDを空欄にして前面で検証します。背景検証は受信したサービスUUIDを指定して開始してください。ロック中の取りこぼし、OS終了後の停止はあり得ます。再起動後は手動で開始します。")) {
                    TextField("サービスUUID（未指定＝全広告）",text:$lab.serviceFilter).autocapitalization(.none).disableAutocorrection(true).disabled(lab.running)
                    Toggle("バックグラウンドでも検証",isOn:$lab.background).disabled(lab.running)
                    Text("対象：\(lab.target.isEmpty ? "全機器":lab.target)").font(.caption)
                    Button("対象を全機器に戻す") { lab.choose("") }
                }
                Section(header:Text("リモート候補（実測形式による仮分類）")) {
                    Text("丸・凹の数字は受信データの末尾2バイトです。意味は検証中で、押下回数とはまだ確定していません。候補を選ぶと、その機器だけ記録します。").font(.caption)
                    ForEach(lab.observations.filter { $0.manufacturer.hasPrefix("6909") && $0.manufacturer.count == 24 && $0.serviceData["FD3D"]?.hasPrefix("62") == true }) { item in
                        Button { lab.choose(item.id) } label: {
                            VStack(alignment:.leading) {
                                Text("候補 \(String(item.manufacturer.dropFirst(4).prefix(12)))  \(lab.target == item.id ? "選択中":"")")
                                Text("データ末尾：\(String(item.manufacturer.suffix(4)))  ・ \(item.rssi) dBm").font(.caption)
                            }
                        }
                    }
                }
                Section(header:Text("近くの機器（機器を押すと記録対象に設定）")) {
                    let pages = max(1,(lab.observations.count+4)/5)
                    ForEach(Array(lab.observations.dropFirst(min(page,pages-1)*5).prefix(5))) { item in
                        Button { lab.choose(item.id) } label: {
                            VStack(alignment:.leading,spacing:5) {
                                Text("\(item.name)  \(item.rssi) dBm  受信\(item.count)回").foregroundColor(lab.target == item.id ? .mint:.white)
                                Text(item.id).font(.caption2)
                                Text("UUID: \(item.services.joined(separator:", "))").font(.caption)
                                Text("製造者: \(item.manufacturer)\nサービス: \(item.serviceData.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }.joined(separator:" / "))").font(.system(size:11)).lineLimit(4)
                            }
                        }.buttonStyle(.plain)
                    }
                    HStack { Button("前へ") { page = max(0,page-1) }.disabled(page == 0); Spacer(); Text("\(min(page,pages-1)+1)/\(pages)"); Spacer(); Button("次へ") { page = min(pages-1,page+1) }.disabled(page >= pages-1) }
                }
                Section(header:Text("検証ログ"),footer:Text("時刻、アプリ状態、受信データ、手動押下記録を端末内に最大3000件保存します。同じ広告は5秒に1件、データ変化は毎回記録します。周囲の機器識別子を含みます。広告ログは外部へ自動送信しません。Webhook通知を有効にした場合のみ呼び出し情報を送信します。")) {
                    Text("保持中 \(lab.recordCount)件")
                    Button("JSONログを書き出す") { lab.save(); share = true }
                    Button("ログをクリア",role:.destructive) { lab.clear() }
                }
            }.buttonStyle(.borderless).navigationTitle("Bluetooth呼び出し検証").toolbar { ToolbarItem(placement:.confirmationAction) { Button("閉じる") { dismiss() } } }
        }.navigationViewStyle(.stack).preferredColorScheme(.dark).sheet(isPresented:$share) { BLEShare(url:BLELab.logURL) }
    }
}
struct BLEShare: UIViewControllerRepresentable {
    let url:URL
    func makeUIViewController(context:Context) -> UIActivityViewController { UIActivityViewController(activityItems:[url],applicationActivities:nil) }
    func updateUIViewController(_ controller:UIActivityViewController,context:Context) {}
}

struct RemoteCallSettingsView: View {
    @ObservedObject var remote: BLELab
    @Environment(\.dismiss) private var dismiss
    @State private var diagnostics = false
    var body: some View {
        NavigationView {
            Form {
                Section(header:Text("リモートボタンから呼び出し"),footer:Text("アプリを前面表示して使用してください。画面ロック・バックグラウンドでは休止し、前面に戻ると再開します。")) {
                    Toggle("呼び出しを有効にする",isOn:Binding(get:{ remote.notificationsEnabled },set:{ remote.setCallEnabled($0) })).disabled(remote.target.isEmpty)
                    Text(remote.target.isEmpty ? "呼び出しボタンが未登録です" : "呼び出しボタン登録済み（丸・凹の両方）")
                    Text(remote.status).foregroundColor(.mint)
                    Text("有効状態は保存され、アプリの次回起動時にも自動再開します。").font(.caption)
                }
                Section(header:Text("通知"),footer:Text("同じ信号の再受信では送信しません。連続する呼び出しは30秒に1回まで。再接続時の最初の信号は基準値として扱います。")) {
                    Text("通知先へ部屋名・イベント・時刻を送信")
                    Text(remote.notificationStatus).font(.subheadline)
                    Text("検出：丸 \(remote.roundPresses)回 ／ 凹 \(remote.concavePresses)回").font(.caption)
                }
                Section(header:Text("機器の登録・診断")) {
                    Button("機器を選択・受信ログを確認") { diagnostics = true }
                    Text("検証済み：SwitchBot Remote。別の機器を選択した場合は、呼び出しを有効にし直してください。").font(.caption)
                }
            }.buttonStyle(.borderless).navigationTitle("呼び出しボタン")
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("完了") { dismiss() } } }
        }.navigationViewStyle(.stack).preferredColorScheme(.dark).sheet(isPresented:$diagnostics) { BLELabView(lab:remote) }
    }
}
struct RemoteCallIndicator: View {
    @ObservedObject var remote: BLELab
    var body: some View {
        if remote.notificationsEnabled {
            Label(remote.running ? "呼び出し待受中":"呼び出し休止中",systemImage:remote.running ? "bell.badge":"bell.slash")
                .font(.caption).foregroundColor(remote.running ? .mint:.sand)
        }
    }
}

@MainActor final class CallPopup: ObservableObject {
    static let shared = CallPopup()
    @Published var room = ""
    @Published var button = ""
    @Published var time = Date()
    @Published var result = "通知先へ送信中…"
    private var window: UIWindow?
    private weak var previousKey: UIWindow?
    private var eventID = UUID()
    @discardableResult func show(room: String, button: String) -> UUID {
        eventID = UUID(); self.room = room; self.button = button; time = Date(); result = "通知先へ送信中…"
        if window == nil, let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }) {
            previousKey = scene.windows.first(where: \.isKeyWindow)
            let popupWindow = UIWindow(windowScene:scene)
            popupWindow.windowLevel = .alert + 1
            popupWindow.backgroundColor = .clear
            let controller = UIHostingController(rootView:CallPopupView(popup:self))
            controller.view.backgroundColor = .clear; controller.view.accessibilityViewIsModal = true
            popupWindow.rootViewController = controller; window = popupWindow
            popupWindow.makeKeyAndVisible()
        }
        UIAccessibility.post(notification:.announcement,argument:"呼び出しがありました")
        return eventID
    }
    func update(_ text: String, event: UUID) { guard event == eventID else { return }; result = text }
    func close() { window?.isHidden = true; window = nil; previousKey?.makeKey(); previousKey = nil }
}
struct CallPopupView: View {
    @ObservedObject var popup: CallPopup
    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
            VStack(spacing:20) {
                Image(systemName:"bell.badge.fill").font(.system(size:52)).foregroundColor(.mint)
                Text("呼び出しがありました").font(.system(size:34,weight:.bold))
                Text(popup.room).font(.title2)
                Text("\(RoomCalendar.clock(popup.time)) ・ \(popup.button)ボタン").font(.title3).foregroundColor(.secondaryInk)
                Text(popup.result).font(.system(size:18)).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
                Button { popup.close() } label: {
                    Text("確認しました").font(.title3.bold()).frame(maxWidth:.infinity,minHeight:58).background(Color.mint).foregroundColor(.canvas).cornerRadius(14).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }.padding(32).frame(maxWidth:560).background(Color.panel).cornerRadius(26).padding(24)
        }.foregroundColor(.white).preferredColorScheme(.dark).statusBar(hidden:true)
    }
}
