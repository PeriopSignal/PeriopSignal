import XCTest
@testable import PeriopSignal

/// Medical abbreviations in Fill from a note: the built-in list (MedAbbreviations), how PatientNote reads them, and the
/// user's own list (AbbreviationStore).
final class MedAbbreviationsTests: XCTestCase {
    /// 30 October 2026, 08:00 on the device's clock.
    private var now: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 8))! }

    private func read(_ text: String, user: [String: String] = [:], choices: [String: String] = [:]) -> PatientNoteReading {
        PatientNote.read(text, now: now, abbreviations: user, choices: choices)
    }
    private func ids(_ r: PatientNoteReading) -> Set<String> { Set(r.findings.map(\.id)) }
    private func change(_ r: PatientNoteReading, _ id: String) -> PatientNoteChange? { r.findings.first { $0.id == id }?.change }
    private func meaning(_ token: String, in text: String) -> String? { MedAbbreviations.scan(text).first { $0.token == token }?.meaning?.text }

    func testListCompilesAndEachSpellingIsOnce() {
        for p in MedAbbreviations.allPatterns { XCTAssertNotNil(p.re, p.pattern) }
        XCTAssertGreaterThan(MedAbbreviations.count, 500)
        var seen = Set<String>()
        for e in MedAbbreviations.all {
            let k = e.caseSensitive ? "=" + e.key : "~" + e.key.lowercased()
            XCTAssertFalse(seen.contains(k), "listed twice: " + e.key)
            seen.insert(k)
            XCTAssertFalse(e.meanings.isEmpty, e.key)
            for h in e.hints { XCTAssertTrue(e.meanings.contains { $0.id == h.meaning }, e.key + ": " + h.meaning) }
        }
    }

    func testCaseMatters() {
        XCTAssertEqual(MedAbbreviations.lookup("AVR")?.meanings.first?.text, "aortic valve replacement")
        XCTAssertEqual(MedAbbreviations.lookup("AVr")?.meanings.first?.text, "aortic valve repair")
        XCTAssertNil(MedAbbreviations.lookup("avr"))
        XCTAssertEqual(MedAbbreviations.lookup("MVr")?.meanings.first?.text, "mitral valve repair")
        XCTAssertEqual(MedAbbreviations.lookup("htn")?.meanings.first?.text, "hypertension")
        XCTAssertEqual(MedAbbreviations.lookup("MG")?.meanings.first?.text, "myasthenia gravis")
        XCTAssertNil(MedAbbreviations.lookup("mg"), "a milligram")

        XCTAssertEqual(change(read("s/p AVR 2018"), "problem:prosthetic-valve-aortic"), .prosthesis("aortic", ""))
        let repaired = read("s/p AVr 2018")
        XCTAssertNil(change(repaired, "problem:prosthetic-valve-aortic"), "a repair is not a prosthetic valve")
        XCTAssertEqual(change(repaired, "cardiac-surgery"), .cardiacSurgery("AVr 2018"), "a valve repair is previous cardiac surgery")
        XCTAssertTrue(repaired.unknown.isEmpty)
    }

    func testAbbreviatedHistory() {
        let r = read("HTN, HLD, DM2, CAD s/p CABG x3 2015, AVr 2020, OSA on CPAP, NKA")
        let found = ids(r)
        for id in ["problem:htn", "problem:hyperlipidemia", "problem:dm", "problem:cabg", "problem:osa", "problem:cpap", "nkda"] {
            XCTAssertTrue(found.contains(id), id)
        }
        XCTAssertFalse(found.contains("problem:prosthetic-valve-aortic"), "AVr is a repair")
        XCTAssertFalse(found.contains("problem:cad"), "CAD with a CABG files the CABG under CAD (1.8.1)")
        XCTAssertEqual(change(r, "cardiac-surgery"), .cardiacSurgery("CABG x3 2015"))
        XCTAssertEqual(r.previous, "AVr 2020", "a valve repair is a past operation")
        XCTAssertEqual(r.other, "")
        XCTAssertTrue(r.ambiguous.isEmpty)
        XCTAssertTrue(r.unknown.isEmpty)
        XCTAssertNotNil(change(read("AVR 2020"), "problem:prosthetic-valve-aortic"))
        XCTAssertEqual(MedAbbreviations.read("HTN, s/p AVr").expanded, "hypertension, status post aortic valve repair")
        // Read through their meanings where no rule reads them as written.
        XCTAssertNotNil(change(read("PMH: SSS, PH, MG"), "problem:arrhythmia"), "sick sinus syndrome")
        XCTAssertNotNil(change(read("PMH: SSS, PH, MG"), "problem:pulm-htn"))
        XCTAssertNotNil(change(read("PMH: SSS, PH, MG"), "problem:neuromuscular"), "myasthenia gravis")
        XCTAssertEqual(change(read("On BB and DOAC"), "flag:betablocker"), .medFlag("betablocker"))
        XCTAssertEqual(change(read("On BB and DOAC"), "flag:anticoagulant"), .medFlag("anticoagulant"))
    }

    func testNoKnownAllergies() {
        XCTAssertEqual(MedAbbreviations.lookup("NKA")?.meanings.first?.text, "no known allergies")
        XCTAssertEqual(MedAbbreviations.lookup("NKDA")?.meanings.first?.text, "no known drug allergies")
        XCTAssertEqual(change(read("NKA"), "nkda"), .nkda)
        XCTAssertEqual(change(read("nkda"), "nkda"), .nkda)
        XCTAssertEqual(change(read("NKMA"), "nkda"), .nkda, "read through its meaning")
    }

    func testRoomAir() {
        let r = read("SpO2 97% on RA")
        XCTAssertEqual(r.ambiguous.first?.chosen?.text, "room air")
        XCTAssertEqual(r.ambiguous.first?.fromContext, true)
        XCTAssertNil(change(r, "problem:ra"))
        XCTAssertNil(r.findings.first { $0.id == "vital:spo2" }?.note, "room air is not oxygen")
        XCTAssertNotNil(change(read("RA on methotrexate"), "problem:ra"), "rheumatoid arthritis, from its treatment")
        XCTAssertEqual(meaning("RA", in: "RA dilated on TTE"), "right atrium")

        let plain = read("Hx RA, HTN")
        XCTAssertEqual(plain.ambiguous.first?.id, "RA@ra-arthritis")
        XCTAssertEqual(plain.ambiguous.first?.fromContext, false)
        XCTAssertNotNil(plain.findings.first { $0.id == "problem:ra" }?.note, "read from the usual meaning: said so")
        let atrium = read("Hx RA, HTN", choices: ["RA@ra-arthritis": "ra-atrium"])
        XCTAssertNil(change(atrium, "problem:ra"), "the user's choice is read")
        XCTAssertEqual(atrium.ambiguous.first?.chosenID, "ra-atrium")
        XCTAssertEqual(atrium.other, "right atrium")
        XCTAssertNil(change(read("Hx RA, HTN", choices: ["RA@ra-arthritis": MedAbbreviations.asWritten]), "problem:ra"))
    }

    func testMitralStenosisByContext() {
        XCTAssertEqual(meaning("MS", in: "severe MS, mean gradient 10 mmHg"), "mitral stenosis")
        XCTAssertEqual(meaning("MS", in: "MS with MVA 1.0 cm2"), "mitral stenosis")
        XCTAssertEqual(meaning("MS", in: "MS on ocrelizumab"), "multiple sclerosis")
        let bare = MedAbbreviations.scan("PMH: MS, HTN").first { $0.key == "MS" }
        XCTAssertEqual(bare?.fromContext, false)
        XCTAssertEqual(bare?.defaultMeaning?.id, "ms-sclerosis")
        XCTAssertEqual(bare?.options.map(\.id), ["ms-sclerosis", "ms-mitral", "ms-morphine"])
        XCTAssertEqual(change(read("severe MS"), "valve:mitral:stenosis"), .valve("mitral", "stenosis", "severe"))
        XCTAssertEqual(read("PMH: MS, HTN").other, "multiple sclerosis")
        // Chosen as mitral stenosis, it files the mitral valve's stenosis (1.8.1), not Other conditions.
        let mitral = read("PMH: MS, HTN", choices: ["MS@ms-sclerosis": "ms-mitral"])
        XCTAssertEqual(change(mitral, "valve:mitral:stenosis"), .valve("mitral", "stenosis", nil))
        XCTAssertEqual(mitral.other, "")
    }

    func testEmbolismAndAsaClassByContext() {
        XCTAssertEqual(meaning("PE", in: "CTA chest positive for PE"), "pulmonary embolism")
        XCTAssertEqual(meaning("PE", in: "PE on anticoagulation"), "pulmonary embolism")
        XCTAssertEqual(meaning("PE", in: "PE: lungs clear"), "physical exam")
        XCTAssertNotNil(change(read("h/o PE on apixaban"), "problem:vte"))
        XCTAssertEqual(meaning("ASA", in: "ASA 3"), "ASA physical status")
        XCTAssertEqual(meaning("ASA", in: "ASA 81 mg daily"), "aspirin")
        XCTAssertEqual(change(read("ASA 3"), "asa"), .asa(3, false))
        XCTAssertEqual(change(read("Takes ASA daily"), "flag:aspirin"), .medFlag("aspirin"))
        XCTAssertEqual(meaning("MAC", in: "for TAVR under MAC"), "monitored anesthesia care")
        XCTAssertEqual(meaning("MAC", in: "DL with MAC 3, grade 1 view"), "Macintosh blade")
    }

    func testInfusions() {
        let r = read("Nitro gtt at 0.5 mcg/kg/min")
        XCTAssertEqual(change(r, "infusion:nitroglycerin"), .infusion("nitroglycerin", "0.5 mcg/kg/min"))
        XCTAssertEqual(r.findings.first { $0.id == "infusion:nitroglycerin" }?.label, "Infusion: nitroglycerin at 0.5 mcg/kg/min")
        XCTAssertNil(change(r, "meds"), "the infusion is not listed again as a medicine")
        var rec = PatientRecord()
        PatientNote.apply([.infusion("nitroglycerin", "0.5 mcg/kg/min")], to: &rec)
        XCTAssertEqual(rec.homeInfusions.map(\.drug), ["Nitroglycerin"])
        XCTAssertEqual(rec.homeInfusions.first?.rate, "0.5 mcg/kg/min")
        func finding(_ c: PatientNoteChange) -> PatientNoteFinding { PatientNoteFinding(id: "infusion:nitroglycerin", section: "Medications", label: "", change: c) }
        XCTAssertEqual(PatientNote.status(finding(.infusion("nitroglycerin", "0.5 mcg/kg/min")), in: rec), .recorded)
        XCTAssertEqual(PatientNote.status(finding(.infusion("nitroglycerin", "1 mcg/kg/min")), in: rec), .replaces("0.5 mcg/kg/min"))
        XCTAssertEqual(r.other, "")
        XCTAssertEqual(change(read("epi gtt at 0.05"), "infusion:epinephrine"), .infusion("epinephrine", "0.05"))
        XCTAssertEqual(change(read("On vaso 0.04 u/min"), "infusion:vasopressin"), .infusion("vasopressin", "0.04 u/min"), "a rate per minute")
        XCTAssertNil(change(read("Fentanyl 25 mcg/hr patch"), "infusion:fentanyl"))
        XCTAssertEqual(change(read("on a heparin drip"), "flag:anticoagulant"), .medFlag("anticoagulant"))
        XCTAssertNil(change(read("weaned off the levo gtt"), "infusion:norepinephrine"), "an infusion that was stopped")
        XCTAssertEqual(MedAbbreviations.lookup("gtt")?.meanings.first?.text, "infusion")
        XCTAssertEqual(MedAbbreviations.lookup("GTT")?.meanings.first?.text, "glucose tolerance test")
    }

    func testUnknownAbbreviations() {
        let r = MedAbbreviations.read("XYZQ noted; the patient takes 5 mg twice daily; HR 80; Dr. AB to see")
        XCTAssertEqual(r.unknown.map(\.token), ["XYZQ"])
        for word in ["the", "The", "mg", "HR", "mL", "IU", "III", "PLAN", "AVr"] { XCTAssertNil(MedAbbreviations.candidate(word), word) }
        XCTAssertEqual(MedAbbreviations.candidate("XYZQ"), "XYZQ")
        XCTAssertEqual(MedAbbreviations.candidate("XYZQs"), "XYZQ", "a plural")
        XCTAssertNil(MedAbbreviations.candidate("ABCDEFG"), "longer than an abbreviation")
        XCTAssertEqual(read("Hx of XYZQ, HTN").unknown.map(\.token), ["XYZQ"])
        let example = read(PatientNote.example)
        XCTAssertEqual(example.unknown.map(\.token), ["POEC"])
        XCTAssertEqual(example.ambiguous.map(\.id), ["RA@ra-air"])
    }

    func testUserAbbreviations() {
        let user = ["XYZQ": "pulmonary hypertension", "POEC": "pre-op evaluation clinic"]
        let r = read("Hx of XYZQ, HTN", user: user)
        XCTAssertTrue(r.unknown.isEmpty)
        XCTAssertNotNil(change(r, "problem:pulm-htn"), "the user's meaning is read")
        XCTAssertNotNil(change(r, "problem:htn"))
        XCTAssertEqual(MedAbbreviations.scan("XYZQ", user: user).first?.source, .user)
        XCTAssertEqual(read("Seen in POEC last week", user: user).other, "Seen in pre-op evaluation clinic last week", "kept with its meaning")
        XCTAssertEqual(MedAbbreviations.read("XYZQs and HTN", user: user).expanded, "pulmonary hypertension and hypertension")
    }

    func testExpansionMapsRangesBack() {
        let text = "HTN, s/p AVr 2020"
        let x = MedAbbreviations.expand(text, MedAbbreviations.scan(text).compactMap { a in
            a.meaning.map { AbbreviationReplacement(range: a.range, text: $0.text) }
        })
        XCTAssertEqual(x.text, "hypertension, status post aortic valve repair 2020")
        let ns = text as NSString
        XCTAssertEqual(ns.substring(with: x.source((x.text as NSString).range(of: "valve repair"))), "AVr")
        XCTAssertEqual(ns.substring(with: x.source((x.text as NSString).range(of: "2020"))), "2020")
        XCTAssertEqual(x.target(NSRange(location: 0, length: 3)), NSRange(location: 0, length: 12))
    }

    @MainActor func testStoreKeepsMeaningsOnThisPhone() {
        let suite = "ps.abbrev.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(AbbreviationStore.key, "ps.abbrev.user")
        let store = AbbreviationStore(defaults: defaults)
        XCTAssertTrue(store.isEmpty)
        store.save(" XYZQ ", meaning: " pulmonary\nhypertension ")
        XCTAssertEqual(store.items, ["XYZQ": "pulmonary hypertension"])
        XCTAssertEqual(defaults.dictionary(forKey: AbbreviationStore.key) as? [String: String], ["XYZQ": "pulmonary hypertension"])
        store.save("POEC", meaning: " ")
        XCTAssertNil(store.items["POEC"], "an empty meaning is not saved")
        XCTAssertEqual(AbbreviationStore(defaults: defaults).items, store.items, "read back on the next launch")
        store.remove("XYZQ")
        XCTAssertTrue(store.isEmpty)
        XCTAssertNil(defaults.object(forKey: AbbreviationStore.key))
    }
}
