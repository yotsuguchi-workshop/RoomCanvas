import Foundation
import CryptoKit
@main struct Checks {
 @MainActor static func main() async {
  let store = RoomStore()
  let cal = Calendar.current
  let start = cal.startOfDay(for: Date())
  let tomorrow = cal.date(byAdding: .day, value: 1, to: start)!
  store.events = [
   RoomEvent(id: "ended", title: "ended", start: start.addingTimeInterval(-3600), end: start, allDay: false, calendar: "test"),
   RoomEvent(id: "overnight", title: "overnight", start: start.addingTimeInterval(-3600), end: start.addingTimeInterval(3600), allDay: false, calendar: "test"),
   RoomEvent(id: "all-day", title: "all day", start: start, end: tomorrow, allDay: true, calendar: "test"),
   RoomEvent(id: "tomorrow", title: "tomorrow", start: tomorrow, end: tomorrow.addingTimeInterval(3600), allDay: false, calendar: "test")]
  precondition(Set(store.events(on: start).map(\.id)) == Set(["overnight","all-day"]))
  precondition(store.events(on: tomorrow).map(\.id) == ["tomorrow"])
  let key = SymmetricKey(data: Data(repeating: 0x0b, count: 20))
  let digest = HMAC<SHA256>.authenticationCode(for: Data("Hi There".utf8), using: key).map { String(format:"%02x", $0) }.joined()
  precondition(digest == "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7")
  func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date { RoomCalendar.value.date(from: DateComponents(year:year,month:month,day:day,hour:hour,minute:minute))! }
  for instant in [0.0, 0.25, 0.999, 59.999, 86400.7, -0.25] {
   let delay = RoomCalendar.nextClockDelay(after: Date(timeIntervalSince1970: instant))
   precondition(delay > 0 && delay <= 1.011)
   precondition(abs(instant + delay - (floor(instant) + 1.01)) < 0.00001)
  }
  precondition(RoomCalendar.clock(date(2026,9,19,0,5)) == "午前12:05:00")
  precondition(RoomCalendar.clock(date(2026,9,19,12,25)) == "午後12:25:00")
  precondition(RoomCalendar.clock(date(2026,9,19,22,5)) == "午後10:05:00")
  precondition(RoomCalendar.dayKind(date(2026,5,3), holidays:BundledHolidays.names) == 1)
  precondition(RoomCalendar.dayKind(date(2026,9,19), holidays:BundledHolidays.names) == 7)
  precondition(RoomCalendar.dayKind(date(2026,9,22), holidays:BundledHolidays.names) == 8)
  precondition(RoomCalendar.dayKind(date(2026,9,24), holidays:BundledHolidays.names) == 0)
  precondition(BundledHolidays.names["2027-03-22"] != nil)
  precondition(HolidayStore.parse(Data("<html>failure</html>".utf8)) == nil)
  precondition(DiscordCall.url("https://discord.com/api/webhooks/123/test-token")?.query == "wait=true")
  precondition(DiscordCall.url("https://discord.com.evil.example/api/webhooks/123/token") == nil)
  precondition(DiscordCall.url("http://discord.com/api/webhooks/123/token") == nil)
  precondition(DiscordCall.url("https://example.com/api/webhooks/123/token") == nil)
  let payload = DiscordCall.payload(room:"@everyone My Room",at:date(2026,9,19))
  precondition((payload["allowed_mentions"] as? [String:[String]])?["parse"] == [])
  precondition((payload["embeds"] as? [[String:Any]])?.first?["timestamp"] != nil)
  let mentionPayload = DiscordCall.payload(room:"Room @here <@123>",at:date(2026,9,19),mentionEveryone:true)
  precondition((mentionPayload["allowed_mentions"] as? [String:[String]])?["parse"] == ["everyone"])
  let content = mentionPayload["content"] as! String
  precondition(content.hasPrefix("@everyone\n"))
  precondition(!content.contains("@here") && !content.contains("<@123>"))
  print("PASS: explicit everyone mention and neutralized room-name mentions")
  let jsonRequest = try! CallWebhook.request(provider:.json,url:"https://example.com/hooks/room",room:"Test Room",at:date(2026,9,19),bearer:"example-token")
  precondition(jsonRequest.httpMethod == "POST")
  precondition(jsonRequest.value(forHTTPHeaderField:"Authorization") == "Bearer example-token")
  let generic = try! JSONSerialization.jsonObject(with:jsonRequest.httpBody!) as! [String:Any]
  precondition(generic["event"] as? String == "room.call" && generic["room"] as? String == "Test Room")
  precondition(UUID(uuidString:generic["event_id"] as! String) != nil)
  precondition(generic["schema_version"] as? Int == 1 && generic["timestamp"] as? String != nil)
  let textRequest = try! CallWebhook.request(provider:.text,url:"https://example.com/hooks/room",room:"<!channel>",at:date(2026,9,19))
  let textPayload = try! JSONSerialization.jsonObject(with:textRequest.httpBody!) as! [String:String]
  precondition(textPayload.keys.sorted() == ["text"] && !textPayload["text"]!.contains("<!channel>"))
  precondition(CallWebhook.url("http://example.com") == nil)
  precondition(CallWebhook.url("https://user:password@example.com") == nil)
  precondition(CallWebhook.url("https://example.com/#secret") == nil)
  precondition((try? CallWebhook.request(provider:.json,url:"https://example.com",room:"Test",at:Date(),bearer:"bad\nheader")) == nil)
  precondition(CallWebhook.accepted(provider:.json,status:204,data:Data()))
  precondition(!CallWebhook.accepted(provider:.json,status:302,data:Data()))
  precondition(!CallWebhook.accepted(provider:.json,status:500,data:Data()))
  precondition(!CallWebhook.accepted(provider:.discord,status:200,data:Data()))
  precondition(CallWebhook.accepted(provider:.discord,status:200,data:Data("{\"id\":\"123\"}".utf8)))
  var remote = RemotePressDetector()
  precondition(remote.receive(manufacturer:"690900000000000001E00000",service:"62206400") == nil)
  precondition(remote.receive(manufacturer:"690900000000000002E00001",service:"62206400") == "丸")
  precondition(remote.receive(manufacturer:"690900000000000002E00001",service:"62206400") == nil)
  precondition(remote.receive(manufacturer:"690900000000000003E00101",service:"62206400") == "凹")
  remote.reset()
  precondition(remote.receive(manufacturer:"690900000000000003E00101",service:"62206400") == nil)
  print("PASS: generic/text webhook payload, HTTPS validation, auth, response handling, BLE baseline/duplicate/button detection")
  let device = SBDevice(id:"test-plug",name:"Test",type:"Plug Mini (JP)",infrared:false,cloud:true)
  for power in ["on","off","unknown","fail"] {
    var posts: [[String:String]] = []; var gets = 0
    let sut = DeviceStore(demoOverride:false,api: { _,method,body in
      if method == "GET" { gets += 1; if power == "fail" { throw RoomFailure.message("offline") }; return try JSONSerialization.data(withJSONObject:["body":["power":power]]) }
      posts.append(body!); return Data("{}".utf8)
    })
    sut.devices = [device]; sut.states[device.id] = SBStatus(power:power == "on" ? "off":"on") // intentionally wrong cache: must read the device
    await sut.togglePower(device)
    precondition(gets >= 1)
    if power == "on" || power == "off" { precondition(posts.count == 1); precondition(posts[0]["command"] == (power == "on" ? "turnOff":"turnOn")) }
    else { precondition(posts.isEmpty) }
  }
  var favoritePosts: [[String:String]] = []
  let favoriteStore = DeviceStore(demoOverride:false, api: { _,method,body in
    precondition(method == "POST"); favoritePosts.append(body!); return Data("{}".utf8)
  })
  let fanDevice = SBDevice(id:"test-fan",name:"扇風機",type:"Fan",infrared:true,cloud:true)
  favoriteStore.devices = [fanDevice]
  for action in [SBAction(label:"首振り",command:"swing"), SBAction(label:"学習電源",command:"電源",custom:true), SBAction(label:"冷房",command:"setAll",parameter:"25,2,3,on")] {
    let favorite = FavoriteAction(deviceID:fanDevice.id,deviceName:fanDevice.name,action:action)
    let restored = try! JSONDecoder().decode(FavoriteAction.self,from:JSONEncoder().encode(favorite))
    await favoriteStore.runFavorite(restored)
    precondition(favoritePosts.last == action.payload)
  }
  let count = favoritePosts.count
  await favoriteStore.runFavorite(FavoriteAction(deviceID:"missing",deviceName:"削除済み",action:SBAction(label:"オン",command:"turnOn")))
  precondition(favoritePosts.count == count)
  print("PASS: favorite action persistence, exact command/parameters/custom type dispatch, missing device no-send")
  print("PASS: Japanese 12h clock, weekend/holiday precedence, substitute holiday, invalid holiday response, Discord URL allowlist and no mentions, fresh device state toggle, unknown/offline no-send")
  print("PASS: midnight exclusion, overnight overlap, all-day exclusive end, next-day inclusion, RFC 4231 HMAC-SHA256")
 }
}
