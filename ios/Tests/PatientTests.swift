import XCTest
@testable import PeriopSignal

/// My Patient: body size, the ASA suggestion, score pre-fills, the stepwise cardiac evaluation, the handoff text and
/// the store's clear and undo.
final class PatientTests: XCTestCase {
    private var demo: PatientRecord { PatientDemo.record }

    func testBodySize() {
        let r = demo
        XCTAssertEqual(r.bmi ?? 0, 30.3, accuracy: 0.01)
        XCTAssertEqual(r.bsa ?? 0, 2.140, accuracy: 0.001, "DuBois, as in the echo tools")
        XCTAssertEqual(r.ibw ?? 0, 73.18, accuracy: 0.01, "Devine, men")
        XCTAssertEqual(r.lbw ?? 0, 67.29, accuracy: 0.01, "Janmahasatian, men")
        XCTAssertNil(PatientBody.ibw(heightCm: 150, sex: .female), "Devine starts at 5 feet")
        XCTAssertEqual(r.person, "67-year-old man")
        var child = PatientRecord(); child.ageYears = 0.5; child.sex = .female
        XCTAssertEqual(child.person, "6-month-old girl")
    }

    func testAsaSuggestion() {
        let s = PatientRules.asaSuggestion(demo)
        XCTAssertEqual(s?.level, 3, "COPD and coronary disease are ASA III examples")
        XCTAssertTrue(s?.reasons.first?.contains("ASA III") ?? false, "the highest class leads")
        XCTAssertFalse(s?.emergency ?? true)
        var healthy = PatientRecord(); healthy.ageYears = 30; healthy.noHistory = true
        XCTAssertEqual(PatientRules.asaSuggestion(healthy)?.level, 1)
        var unknown = PatientRecord(); unknown.ageYears = 30
        XCTAssertNil(PatientRules.asaSuggestion(unknown), "nothing recorded, no suggestion")
        var obese = PatientRecord(); obese.heightCm = 170; obese.weightKg = 120
        XCTAssertEqual(PatientRules.asaSuggestion(obese)?.level, 3, "BMI 41.5 is the ASA III example")
        var child = PatientRecord(); child.ageYears = 6; child.problems = ["copd"]
        XCTAssertNil(PatientRules.asaSuggestion(child), "the adult examples only")
        var e = demo; e.urgency = .emergency; e.asaClass = 3
        XCTAssertEqual(PatientRules.asaText(e), "ASA IIIE")
        e.asaE = false
        XCTAssertEqual(PatientRules.asaText(e), "ASA III", "the clinician's E wins")
    }

    func testScorePrefills() {
        XCTAssertEqual(PatientRules.prefill("rcri", demo).on, ["surgery", "ihd", "insulin"])
        let a = PatientRules.prefill("ariscat", demo)
        XCTAssertEqual(a.choices["age"], "51–80")
        XCTAssertEqual(a.choices["spo2"], "91–95%")
        XCTAssertEqual(a.choices["incision"], "Upper abdominal")
        XCTAssertEqual(a.choices["duration"], "> 3 h")
        XCTAssertTrue(a.on.isEmpty)
        XCTAssertEqual(PatientRules.prefill("stopbang", demo).on, ["snoring", "pressure", "age", "neck", "gender"])
        XCTAssertEqual(PatientRules.prefill("apfel", demo).on, ["nonsmoker", "history"])
        // every pre-filled id and choice exists in its score
        for id in ["rcri", "ariscat", "stopbang", "apfel"] {
            let def = try? XCTUnwrap(Scores.byID(id))
            let s = PatientRules.prefill(id, demo)
            let ids = Set(def?.items.map(\.id) ?? [])
            XCTAssertTrue(s.on.isSubset(of: ids), "\(id): \(s.on.subtracting(ids))")
            for (k, v) in s.choices {
                guard let item = def?.items.first(where: { $0.id == k }), case .choice(let options) = item.input else { return XCTFail("\(id): \(k) is not a choice") }
                XCTAssertTrue(options.contains { $0.label == v }, "\(id): \(k) has no option \(v)")
            }
        }
    }

    func testDasiAndCardiacStep() {
        var r = PatientRecord()
        r.dasi = Set(PatientFunctional.dasiItems.map(\.id))
        let d = PatientFunctional.dasi(r)
        XCTAssertEqual(d?.score ?? 0, 58.2, accuracy: 0.001)
        XCTAssertEqual(d?.mets ?? 0, 9.893, accuracy: 0.001)
        XCTAssertTrue(PatientFunctional.cardiacStep(demo).title.contains("good functional capacity"), "RCRI 3 with 4 METs or more")
        var poor = demo; poor.mets = "lt4"
        XCTAssertTrue(PatientFunctional.cardiacStep(poor).alert)
        var em = demo; em.urgency = .emergency
        XCTAssertTrue(PatientFunctional.cardiacStep(em).title.hasPrefix("Emergency"))
        var active = demo; active.activeCardiac = ["acs"]
        XCTAssertTrue(PatientFunctional.cardiacStep(active).title.hasPrefix("Active"))
    }

    func testHandoffText() {
        let t = HandoffWriter.text(demo)
        for s in ["ANESTHESIA HANDOFF", "67-year-old man", "Laparoscopic sigmoid colectomy", "ASA III", "Penicillin", "Mallampati III",
                  "Intubation easy", "PACU", "RCRI 3", "No notable events", "Crystalloid 1800 mL"] {
            XCTAssertTrue(t.contains(s), "handoff has \(s)")
        }
        XCTAssertFalse(t.contains("Optional("))
        XCTAssertFalse(t.contains("nil"))
        XCTAssertEqual(HandoffWriter.text(PatientRecord()).components(separatedBy: "\n").first, "ANESTHESIA HANDOFF")
    }

    func testRecordCoding() throws {
        let data = try JSONEncoder().encode(demo)
        let back = try JSONDecoder().decode(PatientRecord.self, from: data)
        var a = demo, b = back
        a.updated = nil; b.updated = nil
        XCTAssertEqual(a.lines.map(\.text), b.lines.map(\.text))
        XCTAssertEqual(a.problems, b.problems)
        XCTAssertEqual(a.scores["rcri"]?.points, b.scores["rcri"]?.points)
        let empty = try JSONDecoder().decode(PatientRecord.self, from: Data("{\"weightKg\": 70, \"future\": 1}".utf8))
        XCTAssertEqual(empty.weightKg, 70, "an older or newer file still opens")
        XCTAssertTrue(PatientRecord().isEmpty)
        XCTAssertFalse(demo.isEmpty)
    }

    @MainActor func testStoreClearAndUndo() {
        let store = PatientStore(url: nil)
        XCTAssertTrue(store.isEmpty)
        store.update { $0.weightKg = 80; $0.ageYears = 50 }
        XCTAssertEqual(store.weightKg, 80)
        XCTAssertNotNil(store.record.updated)
        store.clear()
        XCTAssertTrue(store.isEmpty)
        XCTAssertTrue(store.canUndo)
        store.undoClear()
        XCTAssertEqual(store.weightKg, 80)
        XCTAssertFalse(store.canUndo)
        store.clear()
        store.update { $0.ageYears = 20 }
        XCTAssertFalse(store.canUndo, "an edit after clearing ends the undo")
    }

    func testPrompts() {
        let ids = PatientRules.prompts(demo).map(\.id)
        XCTAssertEqual(Array(ids.prefix(4)), ["rcri", "ariscat", "stopbang", "apfel"])
        XCTAssertEqual(PatientRules.prompts(demo).first?.done, "RCRI 3 · Class IV · 3 or more")
        var blocked = demo; blocked.medFlags.insert("anticoagulant")
        XCTAssertTrue(PatientRules.prompts(blocked).contains { $0.route == "neuraxial" }, "a block is planned with an anticoagulant")
        for p in PatientRules.prompts(blocked) { XCTAssertNotNil(RefRoute(key: p.route), "\(p.route) opens a tool") }
    }
}
