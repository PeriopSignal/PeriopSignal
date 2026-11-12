import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import PeriopSignal

/// 1.12 helper I (Ben, Nov 11): the case's name travels with a sent patient, and an opt-in AirDrop link
/// (periopsignal://receive?v=1&z=...) opens the app directly. The link could not be exercised over real AirDrop; these
/// tests cover everything short of it: the packet, the link's making and defensive reading, what the share sheet is
/// given for each activity, the receive rules for the name, and where an incoming URL goes.
final class I112Tests: XCTestCase {
    private let sent = Date(timeIntervalSince1970: 1_793_354_400)
    /// PatientDemo.record is computed: every access makes new ids for its procedures and surgeries, so one value is
    /// used throughout and records compare equal after a round trip.
    private let demo = PatientDemo.record

    private func packet(room: String? = "OR 12") -> PatientPacket {
        PatientPacket(record: demo, sent: sent, room: room)
    }

    private func linkURL(_ z: String, v: String = "1", scheme: String = "periopsignal", host: String = "receive") -> URL {
        URL(string: "\(scheme)://\(host)?v=\(v)&z=\(z)")!
    }

    /// Text that does not compress: a fixed pseudo-random run of letters and digits.
    private func noise(_ n: Int) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        var x: UInt64 = 0x9E3779B97F4A7C15
        var out = ""
        out.reserveCapacity(n)
        for _ in 0..<n {
            x = x &* 6364136223846793005 &+ 1442695040888963407
            out.append(alphabet[Int((x >> 33) % UInt64(alphabet.count))])
        }
        return out
    }

    // MARK: 1. The case's name travels in the packet

    func testPacketCarriesTheRoomWhenThereIsOne() throws {
        let data = try packet().encoded()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["room"] as? String, "OR 12")
        XCTAssertEqual(json["format"] as? Int, 1, "the format stays 1")
        let back = try PatientPacket.decode(data)
        XCTAssertEqual(back.room, "OR 12")
        XCTAssertEqual(back.caseName, "OR 12")
        XCTAssertEqual(back, packet())
        XCTAssertEqual(back.record, demo)
    }

    func testPacketWithoutARoomHasNoRoomKey() throws {
        let data = try packet(room: nil).encoded()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["room"], "no name, no key")
        let back = try PatientPacket.decode(data)
        XCTAssertNil(back.room)
        XCTAssertNil(back.caseName)
        for blank in ["", "   ", "\n\t "] {
            XCTAssertNil(PatientPacket(record: demo, room: blank).room, "a blank name is no name")
        }
    }

    func testAnOldPacketWithNoRoomKeyStillDecodes() throws {
        // What 1.11 sends: the same JSON without the key.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: try packet().encoded()) as? [String: Any])
        json.removeValue(forKey: "room")
        let old = try JSONSerialization.data(withJSONObject: json)
        XCTAssertFalse(String(decoding: old, as: UTF8.self).contains("\"room\""))
        let back = try PatientPacket.decode(old)
        XCTAssertNil(back.room)
        XCTAssertEqual(back.record, demo)
    }

    func testAPacketWithAnUnknownExtraKeyStillDecodes() throws {
        // What an older app sees from a newer one (and the reverse): keys it does not know are skipped.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: try packet().encoded()) as? [String: Any])
        json["somethingNewer"] = ["a": 1]
        json["roomColor"] = "blue"
        let data = try JSONSerialization.data(withJSONObject: json)
        let back = try PatientPacket.decode(data)
        XCTAssertEqual(back.room, "OR 12")
        XCTAssertEqual(back.record, demo)
    }

    func testTheRoomsPhoneIsNeverSent() throws {
        let c = PatientCase(number: 2, record: demo, room: "OR 12", roomPhone: "216-555-0142")
        let p = PatientPacket(of: c, sent: sent)
        XCTAssertEqual(p.room, "OR 12")
        let bytes = try p.encoded()
        let text = String(decoding: bytes, as: UTF8.self)
        XCTAssertFalse(text.contains("216-555-0142"))
        XCTAssertFalse(text.contains("5550142"))
        XCTAssertFalse(text.contains("roomPhone"))
        // And through the link.
        let url = try XCTUnwrap(PatientLink.url(for: p))
        XCTAssertFalse(url.absoluteString.contains("5550142"))
        // A case without a name sends no name.
        XCTAssertNil(PatientPacket(of: PatientCase(number: 3, record: demo, roomPhone: "216-555-0142"), sent: sent).room)
    }

    func testTheRoomIsTrimmedAndCappedAtFortyCharacters() throws {
        XCTAssertEqual(PatientPacket(record: PatientRecord(), room: "  OR 12 \n").room, "OR 12")
        let long = String(repeating: "A", count: 100)
        XCTAssertEqual(PatientPacket(record: PatientRecord(), room: long).room?.count, 40)
        XCTAssertEqual(PatientPacket.cleanRoom("OR\u{0007} 1\u{0000}2"), "OR 12", "control characters out")
        // A file or link can come from anywhere: the name is cleaned again where it is shown and used.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: try packet().encoded()) as? [String: Any])
        json["room"] = "  " + String(repeating: "Z", count: 500)
        let back = try PatientPacket.decode(try JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(back.caseName?.count, 40)
        json["room"] = "   "
        XCTAssertNil(try PatientPacket.decode(try JSONSerialization.data(withJSONObject: json)).caseName)
    }

    func testTheFileNameDoesNotHoldTheCaseName() throws {
        XCTAssertEqual(PatientPacket.fileName, "Patient handoff.periop")
        let item = try XCTUnwrap(PatientShareItem(packet: packet()))
        XCTAssertEqual(item.fileURL.lastPathComponent, "Patient handoff.periop")
        XCTAssertFalse(item.fileURL.path.contains("OR 12"))
    }

    // MARK: Receiving the name

    @MainActor func testOpeningAsANewCaseTakesTheSentName() {
        let store = PatientStore(url: nil)
        store.update { $0.ageYears = 40 }
        store.setRoom("OR 5", phone: "216-555-0105")
        let before = store.currentCase.id
        store.openReceived(packet(room: "OR 12"), asNewCase: true)
        XCTAssertEqual(store.cases.count, 2)
        XCTAssertNotEqual(store.currentCase.id, before)
        XCTAssertEqual(store.currentCase.room, "OR 12")
        XCTAssertEqual(store.currentCase.label, "OR 12")
        XCTAssertEqual(store.currentCase.roomPhone, "", "the sender's room phone is not a thing; the new case has none")
        XCTAssertEqual(store.record, demo.withUpdated(store.record.updated))
        let first = store.cases.first { $0.id == before }
        XCTAssertEqual(first?.room, "OR 5", "the other case is untouched")
        XCTAssertEqual(first?.record.ageYears, 40)
    }

    @MainActor func testANewCaseWithNoSentNameIsNumberedAsToday() {
        let store = PatientStore(url: nil)
        store.update { $0.ageYears = 40 }
        store.openReceived(packet(room: nil), asNewCase: true)
        XCTAssertEqual(store.cases.count, 2)
        XCTAssertEqual(store.currentCase.room, "")
        XCTAssertEqual(store.currentCase.label, "Case 2")
    }

    @MainActor func testNamesAreNotUniqueSoAnExistingNameIsStillUsed() {
        let store = PatientStore(url: nil)
        store.update { $0.ageYears = 40 }
        store.setRoom("OR 12", phone: "")
        store.openReceived(packet(room: "OR 12"), asNewCase: true)
        XCTAssertEqual(store.cases.count, 2)
        XCTAssertEqual(store.cases.map(\.room), ["OR 12", "OR 12"])
    }

    @MainActor func testReplacingKeepsTheReceiversOwnName() {
        let store = PatientStore(url: nil)
        store.update { $0.ageYears = 40 }
        store.setRoom("OR 5", phone: "216-555-0105")
        store.openReceived(packet(room: "OR 12"), asNewCase: false)
        XCTAssertEqual(store.cases.count, 1)
        XCTAssertEqual(store.currentCase.room, "OR 5", "the receiver named their case")
        XCTAssertEqual(store.currentCase.roomPhone, "216-555-0105")
        XCTAssertEqual(store.record.ageYears, demo.ageYears, "the patient is replaced")
        XCTAssertNotEqual(store.record.ageYears, 40)
    }

    @MainActor func testReplacingTakesTheSentNameWhenTheCaseHasNone() {
        let store = PatientStore(url: nil)
        store.update { $0.ageYears = 40 }
        store.setRoom("", phone: "216-555-0105")
        store.openReceived(packet(room: "OR 12"), asNewCase: false)
        XCTAssertEqual(store.currentCase.room, "OR 12")
        XCTAssertEqual(store.currentCase.roomPhone, "216-555-0105", "the receiver's phone stays")
        XCTAssertEqual(store.cases.count, 1)
        XCTAssertTrue(store.canUndoReceive, "the replaced patient can still be brought back")
    }

    @MainActor func testOpeningThisPatientOnAnEmptyPhoneTakesTheName() {
        let store = PatientStore(url: nil)
        XCTAssertTrue(store.isEmpty)
        store.openReceived(packet(room: "OR 12"), asNewCase: false)
        XCTAssertEqual(store.currentCase.room, "OR 12")
        XCTAssertEqual(store.record.ageYears, demo.ageYears)
        // No sent name: nothing is named.
        let other = PatientStore(url: nil)
        other.openReceived(packet(room: nil), asNewCase: false)
        XCTAssertEqual(other.currentCase.room, "")
    }

    func testTheSheetSaysWhatWillHappenToTheName() {
        XCTAssertNil(PatientReceiveRule.note(sent: nil, own: "OR 5", hasPatient: true, canAddCase: true), "no name, nothing to say")
        XCTAssertEqual(PatientReceiveRule.note(sent: "OR 12", own: "", hasPatient: false, canAddCase: true), "This case will be named OR 12.")
        XCTAssertEqual(PatientReceiveRule.note(sent: "OR 12", own: "OR 5", hasPatient: false, canAddCase: true), "This case keeps its name, OR 5.")
        XCTAssertNil(PatientReceiveRule.note(sent: "OR 12", own: "OR 12", hasPatient: false, canAddCase: true), "the same name: nothing differs")
        XCTAssertEqual(PatientReceiveRule.note(sent: "OR 12", own: "OR 5", hasPatient: true, canAddCase: true),
                       "A new case is named OR 12. Replace keeps your case name, OR 5.")
        XCTAssertEqual(PatientReceiveRule.note(sent: "OR 12", own: "", hasPatient: true, canAddCase: true),
                       "A new case is named OR 12. Replace names this case OR 12.")
        XCTAssertEqual(PatientReceiveRule.note(sent: "OR 12", own: "OR 5", hasPatient: true, canAddCase: false),
                       "Replace keeps your case name, OR 5.", "no new case offered at the limit")
    }

    func testTheNoteUnderSendNamesTheCaseOnlyWhenItHasAName() {
        let today = "In Messages, they tap the file, then Share, then Periop Signal. Send only to the colleague taking over, through channels your institution approves; Messages keeps a copy in the conversation."
        XCTAssertEqual(PatientSendText.note(airDropLink: false, caseNamed: false), today, "unchanged for an unnamed case")
        XCTAssertEqual(PatientSendText.note(airDropLink: false, caseNamed: true), today + " The case's name is sent with it.")
        let on = PatientSendText.note(airDropLink: true, caseNamed: false)
        XCTAssertTrue(on.hasPrefix("By AirDrop it opens straight in their Periop Signal. In Messages, they tap the file, then Share, then Periop Signal."))
        XCTAssertTrue(on.hasSuffix("through channels your institution approves; Messages keeps a copy in the conversation."))
        XCTAssertFalse(on.contains("case's name"))
        XCTAssertTrue(PatientSendText.note(airDropLink: true, caseNamed: true).hasSuffix("The case's name is sent with it."))
    }

    @MainActor func testTheTransferFileCarriesTheName() async throws {
        let data = try PatientPacket(record: demo, room: "OR 12").encoded()
        XCTAssertEqual(try PatientPacket.decode(data).room, "OR 12")
        let transfer = PatientTransfer(record: demo, room: "OR 12")
        XCTAssertEqual(transfer.room, "OR 12")
        XCTAssertNil(PatientTransfer(record: demo).room, "the old call still means no name")
    }

    // MARK: 2. The AirDrop link

    func testLinkRoundTrip() throws {
        let p = packet()
        let url = try XCTUnwrap(PatientLink.url(for: p))
        XCTAssertEqual(url.scheme, "periopsignal")
        XCTAssertEqual(url.host, "receive")
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.first { $0.name == "v" }?.value, "1")
        let z = try XCTUnwrap(items.first { $0.name == "z" }?.value)
        XCTAssertFalse(z.isEmpty)
        XCTAssertNil(z.rangeOfCharacter(from: CharacterSet(charactersIn: "+/=")), "base64url, no padding")
        XCTAssertNil(z.rangeOfCharacter(from: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")).inverted))
        let back = try PatientLink.decode(url)
        XCTAssertEqual(back, p)
        XCTAssertEqual(back.record, demo, "the record is equal after encode, URL, decode")
        XCTAssertEqual(back.room, "OR 12")
        XCTAssertLessThan(url.absoluteString.count, PatientLink.maxLinkLength)
    }

    func testBase64URLRoundTripsEveryByteValue() throws {
        let all = Data((0...255).map { UInt8($0) })
        for n in [1, 2, 3, 4, 5, 255, 256] {
            let d = all.prefix(n)
            let s = PatientLink.base64URL(Data(d))
            XCTAssertEqual(PatientLink.fromBase64URL(s), Data(d), "\(n) bytes")
        }
        XCTAssertNil(PatientLink.fromBase64URL("abc="), "padding is not part of it")
        XCTAssertNil(PatientLink.fromBase64URL("ab+/"), "standard base64 characters are not")
        XCTAssertNil(PatientLink.fromBase64URL("a"), "one character is never valid")
    }

    func testDeflateAndInflateRoundTripAndCap() throws {
        let text = Data(String(repeating: "periop signal ", count: 400).utf8)
        let packed = try XCTUnwrap(PatientLink.deflate(text))
        XCTAssertLessThan(packed.count, text.count / 4)
        XCTAssertEqual(PatientLink.inflate(packed, limit: 1_000_000), text)
        XCTAssertNil(PatientLink.inflate(packed, limit: text.count - 1), "past the cap fails")
        XCTAssertEqual(PatientLink.inflate(packed, limit: text.count), text, "exactly at the cap is fine")
        XCTAssertNil(PatientLink.inflate(Data(), limit: 100))
    }

    private func assertRejected(_ url: URL, _ problem: PatientPacket.Problem? = nil, file: StaticString = #filePath, line: UInt = #line) async {
        await MainActor.run {
            let inbox = PatientInbox()
            inbox.receiveLink(url)
            XCTAssertNil(inbox.pending, "a bad link opens nothing", file: file, line: line)
            XCTAssertNotNil(inbox.problem, "and says so", file: file, line: line)
            if let problem { XCTAssertEqual(inbox.problem, problem.message, file: file, line: line) }
        }
    }

    func testABadLinkSetsAProblemAndLeavesPendingNil() async throws {
        let good = try XCTUnwrap(PatientLink.url(for: packet()))
        let z = try XCTUnwrap(URLComponents(url: good, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "z" }?.value)

        await assertRejected(linkURL(z, scheme: "https"), .notAPatient)
        await assertRejected(linkURL(z, scheme: "otherapp"), .notAPatient)
        await assertRejected(linkURL(z, host: "patient"), .notAPatient)
        await assertRejected(linkURL(z, host: "post"), .notAPatient)
        await assertRejected(linkURL(z, v: "0"), .notAPatient)
        await assertRejected(linkURL(z, v: "abc"), .notAPatient)
        await assertRejected(linkURL(z, v: "2"), .newerFormat)
        await assertRejected(URL(string: "periopsignal://receive?v=1")!, .notAPatient)
        await assertRejected(URL(string: "periopsignal://receive?z=\(z)")!, .notAPatient)
        await assertRejected(URL(string: "periopsignal://receive/extra?v=1&z=\(z)")!, .notAPatient)
        await assertRejected(linkURL(""), .notAPatient)
        await assertRejected(linkURL("!!!!not-base64!!!!"), .unreadable)
        await assertRejected(linkURL("ab+/cd=="), .unreadable)
        await assertRejected(linkURL("A"), .unreadable)
        // Valid base64url, but not a compressed packet.
        let words = PatientLink.base64URL(Data("this is not a compressed patient, only some words".utf8))
        await assertRejected(linkURL(words))
        // Compressed, but not a patient.
        let other = PatientLink.base64URL(try XCTUnwrap(PatientLink.deflate(Data("{\"hello\":1}".utf8))))
        await assertRejected(linkURL(other), .notAPatient)
        // A newer packet format inside a good link.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: try packet().encoded()) as? [String: Any])
        json["format"] = 2
        let newer = PatientLink.base64URL(try XCTUnwrap(PatientLink.deflate(try JSONSerialization.data(withJSONObject: json))))
        await assertRejected(linkURL(newer), .newerFormat)
    }

    @MainActor func testAnOversizePayloadIsRefusedBeforeItIsReadAndFast() {
        // Well past the limit: refused on the length alone, before the link is parsed (timed on the call itself).
        let url = linkURL(String(repeating: "A", count: PatientLink.maxPayload + 1_000))
        let inbox = PatientInbox()
        let start = Date()
        inbox.receiveLink(url)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
        XCTAssertNil(inbox.pending)
        XCTAssertEqual(inbox.problem, PatientPacket.Problem.tooLarge.message)
        // Just past it: refused as well, by the payload check.
        let edge = PatientInbox()
        edge.receiveLink(linkURL(String(repeating: "A", count: PatientLink.maxPayload + 1)))
        XCTAssertNil(edge.pending)
        XCTAssertEqual(edge.problem, PatientPacket.Problem.tooLarge.message)
    }

    @MainActor func testASmallPayloadThatWouldInflatePastTheCapFailsCleanlyAndFast() throws {
        // 5 MB of zeros packs to a few KB, far under the payload limit, and would inflate 5 times past the cap.
        let bomb = Data(count: 5_000_000)
        let packed = try XCTUnwrap(PatientLink.deflate(bomb))
        XCTAssertLessThan(packed.count, PatientLink.maxPayload / 2, "a small payload")
        let url = linkURL(PatientLink.base64URL(packed))
        XCTAssertNil(PatientLink.inflate(packed, limit: PatientPacket.maxBytes))
        let inbox = PatientInbox()
        let start = Date()
        inbox.receiveLink(url)
        XCTAssertLessThan(Date().timeIntervalSince(start), 3, "stopped at the cap, not after inflating it all")
        XCTAssertNil(inbox.pending)
        XCTAssertEqual(inbox.problem, PatientPacket.Problem.tooLarge.message)
    }

    @MainActor func testAGoodLinkOnlyFillsPendingAndOpensNothing() throws {
        let inbox = PatientInbox()
        let store = PatientStore(url: nil)
        let url = try XCTUnwrap(PatientLink.url(for: packet()))
        inbox.receiveLink(url)
        XCTAssertEqual(inbox.pending, packet())
        XCTAssertNil(inbox.problem)
        XCTAssertTrue(store.isEmpty, "nothing was opened; the user answers the sheet")
        // A later bad link does not clear a waiting patient, and a good one replaces it, as a file does.
        inbox.receiveLink(linkURL("zzzz", v: "9"))
        XCTAssertNotNil(inbox.problem)
        XCTAssertEqual(inbox.pending, packet())
    }

    func testTheTabLinkIsStillTheTabLinkAndNotAPatientLink() {
        XCTAssertFalse(PatientLink.isPatientLink(URL(string: "periopsignal://patient")!))
        XCTAssertFalse(PatientLink.isPatientLink(URL(string: "periopsignal://mypatient")!))
        XCTAssertFalse(PatientLink.isPatientLink(URL(string: "periopsignal://post/abc")!))
        XCTAssertFalse(PatientLink.isPatientLink(URL(string: "https://receive/")!))
        XCTAssertFalse(PatientLink.isPatientLink(URL(fileURLWithPath: "/tmp/Patient handoff.periop")))
        XCTAssertTrue(PatientLink.isPatientLink(URL(string: "periopsignal://receive?v=1&z=x")!))
        XCTAssertTrue(PatientLink.isPatientLink(URL(string: "PERIOPSIGNAL://Receive?v=1&z=x")!), "scheme and host are not case sensitive")
    }

    @MainActor func testAnIncomingPatientLinkIsTakenBeforeTheRouter() throws {
        let router = Router()
        router.selectedTab = .feed
        let inbox = PatientInbox()
        IncomingURL.handle(try XCTUnwrap(PatientLink.url(for: packet())), inbox: inbox, router: router)
        XCTAssertEqual(router.selectedTab, .patient, "My Patient is selected")
        XCTAssertNotNil(inbox.pending)
        XCTAssertNil(router.pendingPostID)
        XCTAssertNil(router.pendingRefRoute)
        XCTAssertFalse(router.openQuiz)
        XCTAssertFalse(router.showWelcome)
        XCTAssertFalse(router.openSaved)

        // A bad link also selects My Patient (to show the alert) and still never reaches the router's other routes.
        let router2 = Router()
        router2.selectedTab = .more
        let inbox2 = PatientInbox()
        IncomingURL.handle(linkURL("!!!"), inbox: inbox2, router: router2)
        XCTAssertEqual(router2.selectedTab, .patient)
        XCTAssertNil(inbox2.pending)
        XCTAssertNotNil(inbox2.problem)
    }

    @MainActor func testTheTabLinkAndOtherLinksStillGoToTheRouter() {
        let router = Router()
        router.selectedTab = .feed
        let inbox = PatientInbox()
        IncomingURL.handle(URL(string: "periopsignal://patient")!, inbox: inbox, router: router)
        XCTAssertEqual(router.selectedTab, .patient)
        XCTAssertNil(inbox.pending)
        XCTAssertNil(inbox.problem)
        IncomingURL.handle(URL(string: "periopsignal://post/abc123")!, inbox: inbox, router: router)
        XCTAssertEqual(router.selectedTab, .feed)
        XCTAssertEqual(router.pendingPostID, "abc123")
        IncomingURL.handle(URL(string: "periopsignal://more")!, inbox: inbox, router: router)
        XCTAssertEqual(router.selectedTab, .more)
    }

    @MainActor func testAPatientFileStillGoesToTheInbox() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("I112-\(UUID().uuidString).periop")
        try packet().encoded().write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let router = Router()
        let inbox = PatientInbox()
        IncomingURL.handle(file, inbox: inbox, router: router)
        XCTAssertEqual(router.selectedTab, .patient)
        XCTAssertEqual(inbox.pending?.room, "OR 12", "the file carries the name too")
    }

    // MARK: Sending: what the share sheet gets

    func testAirDropGetsTheLinkAndEveryOtherActivityGetsTheFile() throws {
        let p = packet()
        let item = try XCTUnwrap(PatientShareItem(packet: p))
        let vc = UIActivityViewController(activityItems: [], applicationActivities: nil)
        let link = try XCTUnwrap(item.activityViewController(vc, itemForActivityType: .airDrop) as? URL)
        XCTAssertEqual(link.scheme, "periopsignal")
        XCTAssertEqual(link, PatientLink.url(for: p))
        XCTAssertEqual(try PatientLink.decode(link), p)

        for other in [UIActivity.ActivityType.message, .mail, .copyToPasteboard, .print, UIActivity.ActivityType("com.example.unknown")] {
            let file = try XCTUnwrap(item.activityViewController(vc, itemForActivityType: other) as? URL, other.rawValue)
            XCTAssertTrue(file.isFileURL, other.rawValue)
            XCTAssertEqual(file.lastPathComponent, "Patient handoff.periop", "the same suggested name as today")
            XCTAssertEqual(try Data(contentsOf: file), try p.encoded(), "exactly the file that is sent today")
        }
        let none = try XCTUnwrap(item.activityViewController(vc, itemForActivityType: nil) as? URL)
        XCTAssertTrue(none.isFileURL)
        let placeholder = try XCTUnwrap(item.activityViewControllerPlaceholderItem(vc) as? URL)
        XCTAssertEqual(placeholder, item.fileURL, "the placeholder is the file")
        XCTAssertEqual(item.activityViewController(vc, dataTypeIdentifierForActivityType: .message), "org.periopsignal.patient")
        XCTAssertEqual(item.activityViewController(vc, dataTypeIdentifierForActivityType: .airDrop), "public.url")
    }

    func testTheFileCarriesThePatientTypeSoMessagesKeepsTheAttachment() throws {
        let item = try XCTUnwrap(PatientShareItem(packet: packet()))
        XCTAssertEqual(item.fileURL.pathExtension, PatientPacket.fileExtension)
        XCTAssertEqual(PatientPacket.identifier, "org.periopsignal.patient")
        XCTAssertEqual(UTType.periopPatient.identifier, PatientPacket.identifier)
        XCTAssertTrue(PatientInbox.handles(item.fileURL), "the receiving app reads it as a patient file")
        XCTAssertEqual(try PatientPacket.decode(try Data(contentsOf: item.fileURL)), packet())
    }

    func testALinkLongerThanSixtyThousandCharactersFallsBackToTheFileForAirDrop() throws {
        var r = demo
        r.medications = noise(90_000)
        let p = PatientPacket(record: r, sent: sent, room: "OR 12")
        XCTAssertLessThan(try p.encoded().count, PatientPacket.maxBytes, "still an ordinary patient file")
        XCTAssertNil(PatientLink.url(for: p), "too long for a link")
        let item = try XCTUnwrap(PatientShareItem(packet: p))
        XCTAssertNil(item.link)
        let vc = UIActivityViewController(activityItems: [], applicationActivities: nil)
        let forAirDrop = try XCTUnwrap(item.activityViewController(vc, itemForActivityType: .airDrop) as? URL)
        XCTAssertTrue(forAirDrop.isFileURL, "AirDrop sends the file as today")
        XCTAssertEqual(forAirDrop.lastPathComponent, "Patient handoff.periop")
        XCTAssertEqual(try PatientPacket.decode(try Data(contentsOf: forAirDrop)), p)
        XCTAssertEqual(item.activityViewController(vc, dataTypeIdentifierForActivityType: .airDrop), "org.periopsignal.patient")
        // The ordinary demo patient is well under the limit.
        XCTAssertNotNil(PatientLink.url(for: packet()))
    }

    func testTheSendFilesAreRemovable() throws {
        let item = try XCTUnwrap(PatientShareItem(packet: packet()))
        XCTAssertTrue(FileManager.default.fileExists(atPath: item.fileURL.path))
        PatientSendFiles.purge(olderThan: 600)
        XCTAssertTrue(FileManager.default.fileExists(atPath: item.fileURL.path), "a fresh one stays")
        PatientSendFiles.purge()
        XCTAssertFalse(FileManager.default.fileExists(atPath: item.fileURL.path), "the launch clean-up removes it")
    }

    // MARK: The switch

    /// 1.12 follow-up (Ben, Nov 12: "make this on by default"): a phone that never touched the switch reads ON now; it was off.
    @MainActor func testTheAirDropLinkSwitchIsOnByDefaultAndKept() {
        let key = "ps.send.airDropLink"
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.removeObject(forKey: key)
        let prefs = Preferences()
        XCTAssertTrue(prefs.airDropLink, "on by default")
        prefs.airDropLink = false
        XCTAssertFalse(Preferences().airDropLink, "kept when turned off")
        prefs.airDropLink = true
        XCTAssertTrue(Preferences().airDropLink)
    }
}

private extension PatientRecord {
    /// The record as the store holds it after receiving: the same but for the `updated` stamp the store sets.
    func withUpdated(_ date: Date?) -> PatientRecord {
        var r = self
        r.updated = date
        return r
    }
}
