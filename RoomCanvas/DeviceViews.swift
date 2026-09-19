import SwiftUI

struct DeviceBrowser: View {
    @ObservedObject var devices: DeviceStore
    @State private var page = 0
    @State private var selected: SBDevice?
    var body: some View {
        GeometryReader { area in
            let pages = max(1, (devices.devices.count + 5) / 6)
            let index = min(page, pages - 1)
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) { Text("部屋の機器").font(.title.bold()); Text(devices.message).font(.caption).foregroundColor(.secondaryInk) }
                    Spacer()
                    Button { Task { await devices.fetch(force: true) } } label: { Label(devices.loading ? "読み込み中" : "更新", systemImage: "arrow.clockwise").padding(12) }.disabled(devices.loading)
                }
                if devices.devices.isEmpty {
                    Spacer()
                    Text(devices.loading ? "SwitchBotに接続しています…" : "設定でTokenとSecretを保存してください").foregroundColor(.secondaryInk).frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
                        ForEach(Array(devices.devices.dropFirst(index * 6).prefix(6))) { device in
                            VStack(alignment: .leading, spacing: 6) {
                                Button { if device.powerOnly { Task { await devices.togglePower(device) } } else { selected = device } } label: {
                                    VStack(alignment: .leading, spacing: 7) {
                                        HStack { Image(systemName: device.icon).font(.system(size: 24)).foregroundColor(device.sensor ? .mint : .sand); Spacer(); if device.powerOnly { PowerStateIcon(value:devices.powerState(device.id)) }; if devices.favoriteIDs.contains(device.id) { Image(systemName: "star.fill").foregroundColor(.sand) } }
                                        Text(device.name).font(.system(size: 21, weight: .semibold)).lineLimit(1)
                                        Text(devices.summary(device)).font(.system(size: 13)).foregroundColor(.secondaryInk).lineLimit(2)
                                        Spacer(minLength: 0)
                                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).contentShape(Rectangle())
                                }.buttonStyle(.plain).disabled(devices.toggling || devices.executing != nil)
                                HStack {
                                    Text(device.powerOnly ? "タップで電源切替" : device.infrared ? "赤外線リモコン" : device.type).font(.caption2).foregroundColor(.secondaryInk).lineLimit(1)
                                    Spacer()
                                    Button("詳細") { selected = device }.font(.subheadline).foregroundColor(.mint).frame(minWidth: 46, minHeight: 30)
                                }
                            }.padding(16).frame(height: max(155, (area.size.height - 210) / 2)).background(Color.panel).cornerRadius(22)

                        }
                    }
                    Spacer(minLength: 0)
                    if !devices.result.isEmpty { Text(devices.result).font(.caption).foregroundColor(.sand).lineLimit(2) }
                    HStack { Button("前へ") { page = max(0, index - 1) }.disabled(index == 0); Spacer(); Text("\(index + 1) / \(pages)").foregroundColor(.secondaryInk); Spacer(); Button("次へ") { page = min(pages - 1, index + 1) }.disabled(index + 1 >= pages) }.frame(height: 44)
                }
            }.onChange(of: pages) { _ in page = min(page, pages - 1) }
        }
        .sheet(item: $selected) { device in DeviceControlView(device: device, devices: devices) }
        .task { await devices.fetch() }
    }
}

struct DeviceControlView: View {
    let device: SBDevice
    var registrationOnly = false
    @State private var registering = false
    @ObservedObject var devices: DeviceStore
    @Environment(\.dismiss) private var dismiss
    @State private var pending: SBAction?
    @State private var temperature = 24
    @State private var mode = 2
    @State private var fan = 1
    @State private var brightness = 50
    @State private var kelvin = 4000
    @State private var customName = ""
    @State private var customNames: [String] = []
    @State private var tab = 0
    @State private var customPage = 0
    @State private var actionPage = 0
    @State private var initialized = false
    private var enabled: Bool { devices.executing == nil && device.cloud }
    private var customKey: String { "sbCustomButtons." + device.id }
    private var actions: [SBAction] {
        var result: [SBAction] = []
        if device.canPower { result += [SBAction(label: "電源オン", command: "turnOn"), SBAction(label: "電源オフ", command: "turnOff")] }
        if device.type == "Bot" {
            if devices.states[device.id]?.deviceMode == "switchMode" { result += [SBAction(label: "オン", command: "turnOn"), SBAction(label: "オフ", command: "turnOff")] }
            else { result.append(SBAction(label: "ボタンを押す", command: "press")) }
        }
        if device.infrared {
            switch device.type {
            case "Fan": result += [SBAction(label: "弱", command: "lowSpeed"), SBAction(label: "中", command: "middleSpeed"), SBAction(label: "強", command: "highSpeed"), SBAction(label: "首振り", command: "swing"), SBAction(label: "タイマー", command: "timer")]
            case "Light": result += [SBAction(label: "明るく", command: "brightnessUp"), SBAction(label: "暗く", command: "brightnessDown")]
            case "TV", "IPTV/Streamer", "Set Top Box": result += [SBAction(label: "音量＋", command: "volumeAdd"), SBAction(label: "音量−", command: "volumeSub"), SBAction(label: "チャンネル＋", command: "channelAdd"), SBAction(label: "チャンネル−", command: "channelSub")]
            case "DVD", "Speaker": result += [SBAction(label: "再生", command: "Play"), SBAction(label: "一時停止", command: "Pause"), SBAction(label: "停止", command: "Stop"), SBAction(label: "次へ", command: "Next"), SBAction(label: "前へ", command: "Previous"), SBAction(label: "早送り", command: "FastForward"), SBAction(label: "巻き戻し", command: "Rewind"), SBAction(label: "消音", command: "setMute")]
            default: break
            }
        }
        return result
    }
    var body: some View {
        GeometryReader { area in
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button { dismiss() } label: { Label("戻る", systemImage: "chevron.left").padding(12) }
                    Text(device.name).font(.title.bold()).lineLimit(1)
                    Spacer()
                    if !registrationOnly && !device.sensor { Button(registering ? "登録を終了" : "操作をお気に入り登録") { registering.toggle() }.foregroundColor(.mint) }
                    if device.supportsStatus { Button { Task { await devices.refreshStatus(device, force: true) } } label: { Image(systemName: "arrow.clockwise").font(.title2).padding(12) } }
                }
                HStack { Text(devices.summary(device)).font(.headline).foregroundColor(.mint); Spacer(); if let status = devices.states[device.id], !device.infrared { Text("取得 \(status.updated.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundColor(.secondaryInk) } }
                if registering || registrationOnly {
                    Text("登録する機能を選んでください（送信はしません）").font(.subheadline).foregroundColor(.mint)
                    if device.powerOnly { actionButton(SBAction(label: "電源切替", command: "__togglePower")) }
                }
                if device.infrared { Picker("操作種類", selection: $tab) { Text("標準操作").tag(0); Text("学習ボタン").tag(1) }.pickerStyle(.segmented) }
                if tab == 1 && device.infrared { customPanel }
                else if device.sensor { sensorPanel }
                else if device.infrared && device.type == "Air Conditioner" { airConditioner }
                else if device.ceiling { lightPanel }
                else { actionGrid(actions, height: max(100, (area.size.height - 330) / 2)) }
                Spacer(minLength: 0)
                if !devices.result.isEmpty { Text(devices.result).font(.subheadline).foregroundColor(.sand).lineLimit(3) }
                if device.infrared { Text("赤外線は送信要求の受理まで確認できます。家電の実状態は取得できません。").font(.caption).foregroundColor(.secondaryInk) }
            }.padding(18).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.canvas.ignoresSafeArea())
        }.preferredColorScheme(.dark).foregroundColor(.white).statusBar(hidden: true)
        .alert(item: $pending) { action in Alert(title: Text(action.label), message: Text(devices.demo ? "デモ操作です。機器には送信しません。" : "\(device.name)にこの操作を送信します。"), primaryButton: .default(Text("送信")) { Task { await devices.send(action, to: device) } }, secondaryButton: .cancel(Text("キャンセル"))) }
        .task {
            devices.result = ""
            if device.type == "Air Conditioner", let previous = devices.airCommands[device.id] { temperature = previous.temperature ?? 24; mode = previous.mode ?? 2; fan = previous.fan ?? 1 }
            customNames = UserDefaults.standard.stringArray(forKey: customKey) ?? []
            await devices.refreshStatus(device)
            guard !initialized else { return }; initialized = true
            if let status = devices.states[device.id] { brightness = min(100, max(1, Int(status.brightness ?? 50))); kelvin = min(6500, max(2700, Int(status.colorTemperature ?? 4000))) }
        }
    }
    private func actionButton(_ action: SBAction) -> some View {
        Button { if registering || registrationOnly { devices.addFavorite(action, device: device) } else { pending = action } } label: { Text(action.label).font(.system(size: 20, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 42).padding(8).background(Color.panel).cornerRadius(15) }.buttonStyle(.plain).disabled(!(registering || registrationOnly) && !enabled)
    }
    private func actionGrid(_ values: [SBAction], height: CGFloat) -> some View {
        let pages = max(1, (values.count + 5) / 6)
        let current = min(actionPage, pages - 1)
        return VStack(spacing: 15) {
            if values.isEmpty { Text(device.infrared ? "学習ボタンを登録して操作できます。" : "この機種の個別操作は公式APIまたはこの版では未対応です。シーンに登録できる操作はシーンから実行してください。").foregroundColor(.secondaryInk).padding(24) }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 14) {
                ForEach(Array(values.dropFirst(current * 6).prefix(6))) { action in actionButton(action).frame(height: height).background(Color.panel).cornerRadius(15) }
            }
            if pages > 1 { HStack { Button("前へ") { actionPage = max(0, current - 1) }.disabled(current == 0); Spacer(); Text("\(current + 1) / \(pages)"); Spacer(); Button("次へ") { actionPage = min(pages - 1, current + 1) }.disabled(current == pages - 1) }.frame(height: 44) }
        }
    }
    private var airConditioner: some View {
        Card {
            VStack(spacing: 12) {
                AirStateView(devices:devices,device:device).frame(maxWidth:.infinity,alignment:.leading)
                Text("送信する設定").font(.headline).foregroundColor(.secondaryInk)
                Stepper("設定温度  \(temperature)°C", value: $temperature, in: 16...30).font(.system(size: 32, weight: .medium)).padding(10)
                Picker("運転モード", selection: $mode) { Text("自動").tag(1); Text("冷房").tag(2); Text("除湿").tag(3); Text("送風").tag(4); Text("暖房").tag(5) }.pickerStyle(.segmented)
                Picker("風量", selection: $fan) { Text("自動").tag(1); Text("弱").tag(2); Text("中").tag(3); Text("強").tag(4) }.pickerStyle(.segmented)
                HStack { actionButton(SBAction(label: "\(temperature)°C・\([1: "自動", 2: "冷房", 3: "除湿", 4: "送風", 5: "暖房"][mode] ?? "自動")・風量\([1: "自動", 2: "弱", 3: "中", 4: "強"][fan] ?? "自動")", command: "setAll", parameter: "\(temperature),\(mode),\(fan),on")); actionButton(SBAction(label: "停止", command: "turnOff")) }
                Text("機種によって対応する温度・モード・風量は異なります。").font(.caption).foregroundColor(.secondaryInk)
            }
        }
    }
    private var lightPanel: some View {
        Card {
            VStack(spacing: 10) {
                HStack { actionButton(SBAction(label: "点灯", command: "turnOn")); actionButton(SBAction(label: "消灯", command: "turnOff")) }
                Stepper("明るさ  \(brightness)%", value: $brightness, in: 1...100, step: 5).font(.title2)
                actionButton(SBAction(label: "明るさ \(brightness)%", command: "setBrightness", parameter: String(brightness)))
                Stepper("色温度  \(kelvin)K", value: $kelvin, in: 2700...6500, step: 100).font(.title2)
                actionButton(SBAction(label: "色温度 \(kelvin)K", command: "setColorTemperature", parameter: String(kelvin)))
            }
        }
    }
    private var sensorPanel: some View {
        Card(fill: true) {
            VStack(alignment: .leading, spacing: 25) {
                Text("部屋の環境").font(.title2)
                if let status = devices.states[device.id] {
                    if let value = status.temperature { Label(String(format: "%.1f°C", value), systemImage: "thermometer").font(.system(size: 70, weight: .light)).foregroundColor(.mint) }
                    if let value = status.humidity { Label(String(format: "%.0f%%", value), systemImage: "humidity").font(.system(size: 60, weight: .light)).foregroundColor(.mint) }
                }
                Button("このセンサーをダッシュボードに表示") { devices.selectSensor(device); devices.result = "ダッシュボードの環境センサーに設定しました" }.padding(15).background(Color.panel).cornerRadius(12)
                Text("表示は取得時点の値です。ダッシュボード表示中は約2分間隔で更新します。").font(.footnote).foregroundColor(.secondaryInk)
                Spacer()
            }
        }
    }
    private var customPanel: some View {
        let pages = max(1, (customNames.count + 5) / 6)
        let current = min(customPage, pages - 1)
        return VStack(alignment: .leading, spacing: 14) {
            Text("公式APIでは学習ボタンの一覧を取得できません。SwitchBotアプリの登録名を同じ文字で追加してください。信号の学習はSwitchBotアプリで行います。").font(.subheadline).foregroundColor(.secondaryInk)
            HStack { TextField("例：入力切替、電源、再生", text: $customName).textFieldStyle(.roundedBorder); Button("追加") { let name = customName.trimmingCharacters(in: .whitespacesAndNewlines); guard !name.isEmpty, !customNames.contains(name) else { return }; customNames.append(name); UserDefaults.standard.set(customNames, forKey: customKey); customName = "" }.frame(minWidth: 70, minHeight: 44) }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                ForEach(Array(customNames.dropFirst(current * 6).prefix(6)), id: \.self) { name in
                    actionButton(SBAction(label: name, command: name, custom: true)).contextMenu { Button("このボタンを一覧から削除", role: .destructive) { customNames.removeAll { $0 == name }; UserDefaults.standard.set(customNames, forKey: customKey) } }
                }
            }
            if pages > 1 { HStack { Button("前へ") { customPage = max(0, current - 1) }.disabled(current == 0); Spacer(); Text("\(current + 1) / \(pages)"); Spacer(); Button("次へ") { customPage = min(pages - 1, current + 1) }.disabled(current == pages - 1) }.frame(height: 44) }
            Text("ボタンを長押しすると一覧から削除できます。").font(.caption).foregroundColor(.secondaryInk)
        }
    }
}

// Filled mint = ON, outlined gray = OFF, question mark = unknown.
struct PowerStateIcon: View {
    let value: Bool?
    var body: some View {
        Image(systemName: value == nil ? "questionmark.circle" : value == true ? "power.circle.fill" : "power.circle")
            .font(.system(size:22,weight:.medium))
            .foregroundColor(value == true ? .mint : .secondaryInk)
            .accessibilityLabel(value == nil ? "電源状態不明" : value == true ? "現在オン" : "現在オフ")
    }
}

struct AirStateView: View {
    @ObservedObject var devices: DeviceStore
    let device: SBDevice
    var body: some View {
        let command = devices.demo ? nil : devices.airCommands[device.id]
        VStack(alignment:.leading,spacing:2) {
            HStack(spacing:5) {
                PowerStateIcon(value: command?.power == "on" ? true : command?.power == "off" ? false : nil)
                Text(device.name).font(.system(size:14,weight:.medium)).lineLimit(1)
                Text(command.map { "送信済：" + ($0.power == "on" ? "ON" : $0.power == "off" ? "OFF" : "不明") } ?? "状態不明")
                    .font(.system(size:12)).foregroundColor(.secondaryInk)
            }
            if let command = command, command.power == "on" {
                Text(command.summary.replacingOccurrences(of:"ON · ",with:""))
                    .font(.system(size:14)).foregroundColor(.mint).lineLimit(1).minimumScaleFactor(0.75)
            }
            Text(command.map { "実状態は取得不可 · " + $0.updated.formatted(date:.abbreviated,time:.shortened) + "送信" } ?? "赤外線 · 実状態は取得不可／このアプリから未送信")
                .font(.system(size:10)).foregroundColor(.secondaryInk).lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}
