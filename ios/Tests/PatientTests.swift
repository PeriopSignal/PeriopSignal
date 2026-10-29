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
        XCTAssertEqual(s?.reasons.first?.level, 3, "the highest class leads")
        XCTAssertEqual(s?.topFindings, ["Coronary disease or MI, over 3 months", "Coronary stent, over 3 months", "COPD"])
        XCTAssertNil(s?.reasons.first { $0.finding == "COPD" }?.example, "an example that repeats the finding is not shown")
        XCTAssertEqual(s?.reasons.first { $0.finding.hasPrefix("BMI") }?.finding, "BMI 30.3", "BMI to one decimal")
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
        XCTAssertEqual(PatientFunctional.dasi(r) ?? 0, 58.2, accuracy: 0.001, "the 12 weights sum to 58.2")
        r.dasi = ["self-care", "walk-indoors", "walk-blocks", "stairs", "light-housework", "moderate-housework", "yardwork", "sex"]
        XCTAssertEqual(PatientFunctional.dasi(r) ?? 0, 28.7, accuracy: 0.001)
        XCTAssertEqual(PatientFunctional.dasiText(34.45), "DASI 34.45 of 58.2 · above 34", "not rounded down to 34")
        XCTAssertEqual(PatientFunctional.dasiText(34), "DASI 34 of 58.2 · 34 or less: poor")

        XCTAssertEqual(PatientFunctional.riskModifiers(demo), ["prior coronary stent"])
        XCTAssertTrue(PatientFunctional.cardiacStep(demo).title.hasPrefix("Good functional capacity"), "RCRI 3 with 4 METs or more")
        var poor = demo; poor.mets = "lt4"
        XCTAssertTrue(PatientFunctional.cardiacStep(poor).title.hasPrefix("Poor or unknown"))
        XCTAssertTrue(PatientFunctional.cardiacStep(poor).alert)
        var dasiWins = poor; dasiWins.dasi = Set(PatientFunctional.dasiItems.map(\.id))
        XCTAssertTrue(PatientFunctional.cardiacStep(dasiWins).title.hasPrefix("Good"), "a recorded DASI above 34 decides")
        var normal = poor; normal.labs["ntprobnp"] = 180
        XCTAssertEqual(PatientFunctional.cardiacStep(normal).title, "Natriuretic peptide normal: proceed")
        var raised = poor; raised.labs["bnp"] = 92.5
        XCTAssertEqual(PatientFunctional.cardiacStep(raised).title, "Natriuretic peptide raised", "BNP over 92")
        var edge = poor; edge.labs["bnp"] = 92
        XCTAssertFalse(PatientFunctional.cardiacStep(edge).alert, "BNP 92 is not over 92")
        var nt = poor; nt.labs["ntprobnp"] = 300
        XCTAssertTrue(PatientFunctional.cardiacStep(nt).alert, "NT-proBNP 300 or more")
        var low = PatientRecord(); low.ageYears = 60; low.problems = ["htn"]
        XCTAssertTrue(PatientFunctional.cardiacStep(low).title.hasPrefix("Low estimated risk"))
        low.frail = true
        XCTAssertFalse(PatientFunctional.cardiacStep(low).title.hasPrefix("Low"), "frailty adds risk beyond the RCRI")
        var em = demo; em.urgency = .emergency
        XCTAssertTrue(PatientFunctional.cardiacStep(em).title.hasPrefix("Emergency"))
        var active = demo; active.activeCardiac = ["acs"]
        XCTAssertTrue(PatientFunctional.cardiacStep(active).title.hasPrefix("Acute cardiac condition"))
    }

    func testMaskVentilationPredictors() {
        XCTAssertEqual(PatientAirway.langeron(demo), ["age over 55", "BMI over 26", "snoring"])
        XCTAssertEqual(PatientAirway.kheterpal(demo), ["male", "sleep apnea", "Mallampati III"])
        XCTAssertEqual(PatientAirway.maskRisk(demo).filter { $0.alert }.count, 2)
        var young = PatientRecord(); young.ageYears = 30; young.sex = .female; young.heightCm = 165; young.weightKg = 60
        XCTAssertTrue(PatientAirway.maskRisk(young).isEmpty)
        var child = demo; child.ageYears = 10
        XCTAssertTrue(PatientAirway.maskRisk(child).isEmpty, "adult predictors only")
        XCTAssertEqual(PatientAirway.mallampatiLine(4), "Mallampati IV: soft palate not visible")
        XCTAssertEqual(PatientAirway.mallampatiLine(3), "Mallampati III: soft palate and the base of the uvula visible")
    }

    func testNumbersShowAsTyped() {
        XCTAssertEqual(NumText.exact(12.8), "12.8")
        XCTAssertEqual(NumText.exact(96.5), "96.5")
        XCTAssertEqual(NumText.exact(162), "162")
        XCTAssertEqual(NumText.exact(1.25), "1.25")
        XCTAssertEqual(Double(NumText.exact(0.1 + 0.2)), 0.1 + 0.2, "exact parses back to the same value")
        XCTAssertEqual(NumText.short(34.449), "34.45")
        XCTAssertEqual(NumText.short(30.299, places: 1), "30.3")
        XCTAssertEqual(NumText.short(1800), "1800")
        var r = demo; r.weightKg = 96.5
        XCTAssertTrue(r.oneLiner.contains("96.5 kg"), "a typed weight is not rounded")
    }

    func testHandoffText() {
        let t = HandoffWriter.text(demo)
        for s in ["ANESTHESIA HANDOFF", "67-year-old man", "Laparoscopic sigmoid colectomy", "ASA III", "Penicillin", "Mallampati III",
                  "Intubation easy", "PACU", "RCRI 3", "No notable events", "Crystalloid 1800 mL", "Hb 12.8", "Creatinine 1.1",
                  "Medications: Metoprolol", "Langeron", "Call if: "] {
            XCTAssertTrue(t.contains(s), "handoff has \(s)")
        }
        XCTAssertFalse(t.contains("(Beta-blocker"), "the flags do not repeat the typed list")
        XCTAssertFalse(t.contains("Cardiac evaluation"), "the cardiac step stays out of the handoff")
        var hard = demo; hard.intubation = "difficult"; hard.airwayFollowUp = ["told"]
        let h = HandoffWriter.text(hard)
        XCTAssertTrue(h.contains("Difficult-airway follow-up: Patient told. Still to do: document"), h)
        var alert = demo; alert.medFlags.insert("sglt2")
        XCTAssertTrue(HandoffWriter.text(alert).contains("Medication alerts: SGLT2 inhibitor"))
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
        var c = demo
        c.urgency = .timeSensitive; c.maskGrade = 2; c.sga = "easy"; c.airwayFollowUp = ["told"]; c.callIf = "SBP under 90"; c.frail = true
        let c2 = try JSONDecoder().decode(PatientRecord.self, from: try JSONEncoder().encode(c))
        XCTAssertEqual(c2.urgency, .timeSensitive)
        XCTAssertEqual(c2.maskGrade, 2)
        XCTAssertEqual(c2.sga, "easy")
        XCTAssertEqual(c2.airwayFollowUp, ["told"])
        XCTAssertEqual(c2.callIf, "SBP under 90")
        XCTAssertTrue(c2.frail)
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
