import SwiftUI

struct MonthGrid: View {
    let month:Date; let selected:Date
    @ObservedObject var holidays:HolidayStore
    let events:[RoomEvent]; let compact:Bool
    let select:(Date)->Void
    private var days:[Date?] {
        let cal = RoomCalendar.value, start = RoomCalendar.value.dateInterval(of:.month,for:month)!.start
        let offset = cal.component(.weekday,from:start)-1, count = cal.range(of:.day,in:.month,for:month)!.count
        return Array(repeating:nil,count:offset) + (0..<count).map { cal.date(byAdding:.day,value:$0,to:start) } + Array(repeating:nil,count:42-offset-count)
    }
    var body: some View {
        GeometryReader { area in
            VStack(spacing:compact ? 4:10) {
                Text(month.formatted(.dateTime.year().month(.wide).locale(Locale(identifier:"ja_JP")))).font(compact ? .headline:.title2).frame(maxWidth:.infinity,alignment:.leading).frame(height:30)
                HStack(spacing:2) { ForEach(Array(["日","月","火","水","木","金","土"].enumerated()),id:\.offset) { index,day in Text(day).font(.system(size:compact ? 12:17)).foregroundColor(index == 0 ? .sunday:index == 6 ? .saturday:.secondaryInk).frame(maxWidth:.infinity) } }.frame(height:20)
                let height = max(20,(area.size.height - (compact ? 65:88))/6)
                VStack(spacing:2) {
                    ForEach(0..<6,id:\.self) { row in
                        HStack(spacing:2) {
                            ForEach(0..<7,id:\.self) { col in
                                if let date = days[row*7+col] {
                                    let picked = RoomCalendar.value.isDate(date,inSameDayAs:selected)
                                    Button { select(date) } label: {
                                        VStack(spacing:1) {
                                            Text(String(RoomCalendar.value.component(.day,from:date))).font(.system(size:compact ? 17:25,weight:picked ? .bold:.regular)).foregroundColor(holidays.color(date))
                                            if !compact { Circle().fill(hasEvent(date) ? Color.mint:.clear).frame(width:4,height:4) }
                                        }.frame(maxWidth:.infinity).frame(height:height).background(picked ? Color.mint.opacity(0.17):.clear).cornerRadius(8)
                                    }.buttonStyle(.plain).accessibilityLabel(date.formatted(date:.complete,time:.omitted) + (holidays.name(date).map { "、"+$0 } ?? ""))
                                } else { Color.clear.frame(maxWidth:.infinity).frame(height:height) }
                            }
                        }
                    }
                }
            }
        }
    }
    private func hasEvent(_ date:Date)->Bool { let end = RoomCalendar.value.date(byAdding:.day,value:1,to:date)!; return events.contains { $0.start < end && $0.end > date } }
}
struct AgendaSummary: View {
    @ObservedObject var store:RoomStore
    @ObservedObject var holidays:HolidayStore
    let date:Date; let privateTitles:Bool; let open:()->Void
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            Button(action:open) { HStack { Text("今日の予定").font(.title3.bold()); Spacer(); Image(systemName:"arrow.up.right").font(.caption) } }.buttonStyle(.plain)
            if let name = holidays.name(date) { Text(name).font(.caption).foregroundColor(holidays.color(date)) }
            if store.events(on:date).isEmpty { Text(store.calendarUpdated == nil && !store.demo ? "カレンダー未接続":"予定はありません").font(.subheadline).foregroundColor(.secondaryInk) }
            ForEach(Array(store.events(on:date).prefix(3))) { event in
                HStack(spacing:12) {
                    Text(event.allDay ? "終日":event.start.formatted(date:.omitted,time:.shortened)).font(.system(size:16)).monospacedDigit().foregroundColor(.mint).frame(width:60,alignment:.leading)
                    Text(privateTitles ? "予定あり":event.title).font(.system(size:18)).lineLimit(1)
                }.frame(minHeight:32)
            }
            Spacer(minLength:0)
            Button(store.events(on:date).count > 3 ? "全\(store.events(on:date).count)件の予定を見る":"予定を開く") { open() }.font(.caption).foregroundColor(.secondaryInk)
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
    }
}
struct CalendarScreen:View {
    @ObservedObject var store:RoomStore
    @ObservedObject var holidays:HolidayStore
    let privateTitles:Bool
    @Environment(\.dismiss) private var dismiss
    @State private var eventPage = 0
    var body: some View {
        GeometryReader { area in
            VStack(spacing:12) {
                HStack(spacing:14) {
                    Card(fill:true) {
                        VStack(spacing:14) {
                            MonthGrid(month:store.month,selected:store.selectedDay,holidays:holidays,events:store.events,compact:false) { date in store.selectedDay = date; eventPage = 0 }
                            HStack {
                                Button("前月") { move(-1) }; Spacer()
                                Button("今日") { store.month = Date(); store.selectedDay = RoomCalendar.value.startOfDay(for:Date()); eventPage = 0; Task { await store.refreshCalendar() } }; Spacer()
                                Button("翌月") { move(1) }
                            }.frame(height:44).foregroundColor(.mint)
                        }
                    }.frame(width:(area.size.width-46)*0.53)
                    Card(fill:true) { agenda(capacity:max(1,Int((area.size.height-220)/110))) }
                }
                HStack { BatteryIndicator(); Spacer(); Button("閉じる") { dismiss() }.frame(width:160,height:44).background(Color.panel).cornerRadius(12) }
            }.padding(16).background(Color.canvas.ignoresSafeArea())
        }.foregroundColor(.white).preferredColorScheme(.dark).statusBar(hidden:true)
    }
    private func move(_ delta:Int) { store.month = RoomCalendar.value.date(byAdding:.month,value:delta,to:store.month)!; store.selectedDay = RoomCalendar.value.dateInterval(of:.month,for:store.month)!.start; eventPage = 0; Task { await store.refreshCalendar() } }
    private func agenda(capacity:Int)->some View {
        let events = store.events(on:store.selectedDay), pages = max(1,(events.count+capacity-1)/capacity), index = min(eventPage,pages-1)
        return VStack(alignment:.leading,spacing:16) {
            Text(store.selectedDay.formatted(.dateTime.month().day().weekday(.abbreviated).locale(Locale(identifier:"ja_JP"))) + "の予定").font(.system(size:24,weight:.semibold)).foregroundColor(holidays.color(store.selectedDay))
            if let name = holidays.name(store.selectedDay) { Text(name).font(.subheadline).foregroundColor(holidays.color(store.selectedDay)) }
            if events.isEmpty { Text("予定はありません").foregroundColor(.secondaryInk) }
            ForEach(Array(events.dropFirst(index*capacity).prefix(capacity))) { event in
                VStack(alignment:.leading,spacing:8) {
                    Text(event.allDay ? "終日":event.start.formatted(date:.omitted,time:.shortened)+" – "+event.end.formatted(date:.omitted,time:.shortened)).foregroundColor(.mint).font(.subheadline)
                    Text(privateTitles ? "予定あり":event.title).font(.system(size:24)).lineLimit(2)
                    Text(privateTitles ? "詳細は非公開":event.calendar).font(.caption).foregroundColor(.secondaryInk).lineLimit(1)
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
            Spacer(minLength:0)
            HStack { Button("前へ") { eventPage = max(0,index-1) }.disabled(index==0); Spacer(); Text("\(index+1) / \(pages)").font(.caption); Spacer(); Button("次へ") { eventPage = min(pages-1,index+1) }.disabled(index+1>=pages) }.frame(height:44)
            Text(store.calendarMessage).font(.caption).foregroundColor(.secondaryInk).lineLimit(2)
        }.onChange(of:pages) { _ in eventPage = min(eventPage,pages-1) }
    }
}
struct RoomControlsPage:View {
    @ObservedObject var store:RoomStore
    @ObservedObject var devices:DeviceStore
    @State private var tab = 0
    @State private var scenePage = 0
    @State private var confirmation:RoomScene?
    var body:some View {
        VStack(spacing:12) {
            Picker("部屋の操作",selection:$tab) { Text("機器").tag(0); Text("シーン").tag(1) }.pickerStyle(.segmented)
            if tab == 0 { DeviceBrowser(devices:devices) }
            else { scenes }
        }.alert(item:$confirmation) { scene in Alert(title:Text("\(scene.sceneName)を実行"),message:Text(store.demo ? "デモです。実際には操作しません。":"シーン内の機器を操作します。"),primaryButton:.default(Text("実行")) { Task { await store.execute(scene) } },secondaryButton:.cancel(Text("キャンセル"))) }
    }
    private var scenes:some View {
        GeometryReader { area in
            let pages = max(1,(store.scenes.count+5)/6), index = min(scenePage,pages-1)
            VStack(spacing:14) {
                HStack { Text("シーン").font(.title2.bold()); Spacer(); Button("更新") { Task { await store.fetchScenes() } } }
                LazyVGrid(columns:Array(repeating:GridItem(.flexible()),count:3),spacing:14) {
                    ForEach(Array(store.scenes.dropFirst(index*6).prefix(6))) { scene in
                        Button { confirmation = scene } label: { VStack(spacing:16) { Image(systemName:"sparkles").foregroundColor(.sand); Text(scene.sceneName).lineLimit(2) }.font(.title3).frame(maxWidth:.infinity).frame(height:max(90,(area.size.height-145)/2)).background(Color.panel).cornerRadius(20) }.disabled(store.busyScene != nil)
                    }
                }
                Spacer(minLength:0)
                HStack { Button("前へ") { scenePage=max(0,index-1) }.disabled(index==0); Spacer(); Text("\(index+1) / \(pages)"); Spacer(); Button("次へ") { scenePage=min(pages-1,index+1) }.disabled(index+1>=pages) }.frame(height:44)
                Text(store.sceneMessage).font(.caption).foregroundColor(.secondaryInk).lineLimit(2)
            }.buttonStyle(.plain)
        }
    }
}
