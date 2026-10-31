import XCTest
@testable import PeriopSignal

/// The procedure catalog: abbreviations (with case where it changes the meaning), the risk auto-fill, reading several
/// procedures and their sides from free text, and the integrity of the data.
final class ProcedureCatalogTests: XCTestCase {
    private func proc(_ id: String, file: StaticString = #filePath, line: UInt = #line) -> Procedure {
        guard let p = ProcedureCatalog.byID(id) else {
            XCTFail("no procedure \(id)", file: file, line: line)
            return ProcedureCatalog.all[0]
        }
        return p
    }

    private func ids(_ text: String) -> [String] { ProcedureCatalog.parse(text).map(\.procedure.id) }

    private func one(_ text: String, file: StaticString = #filePath, line: UInt = #line) -> ProcedureMatch? {
        let m = ProcedureCatalog.parse(text)
        XCTAssertEqual(m.count, 1, "\(text): \(m.map(\.procedure.id))", file: file, line: line)
        return m.first
    }

    // MARK: Abbreviations

    func testValveCaseChangesTheMeaning() {
        XCTAssertEqual(ProcedureCatalog.search("AVR").first?.id, "avr")
        XCTAssertEqual(ProcedureCatalog.search("AVr").first?.id, "av-repair")
        XCTAssertEqual(ProcedureCatalog.search("avr").first?.id, "avr", "lowercase reads as the usual replacement")
        XCTAssertEqual(ProcedureCatalog.search("MVr").first?.id, "mv-repair")
        XCTAssertEqual(ProcedureCatalog.search("MVR").first?.id, "mvr")
        XCTAssertEqual(ids("AVR"), ["avr"])
        XCTAssertEqual(ids("AVr"), ["av-repair"])
        XCTAssertEqual(ids("MVR"), ["mvr"])
        XCTAssertEqual(ids("MVr"), ["mv-repair"])
        XCTAssertEqual(ids("TVR"), ["tvr"])
        XCTAssertEqual(ids("TVr"), ["tv-repair"])
        XCTAssertEqual(ids("AVr and MVr"), ["av-repair", "mv-repair"])
        XCTAssertEqual(proc("avr").name, "Aortic valve replacement")
        XCTAssertEqual(proc("av-repair").name, "Aortic valve repair")
        XCTAssertEqual(proc("mvr").name, "Mitral valve replacement")
        XCTAssertEqual(proc("mv-repair").name, "Mitral valve repair")
        XCTAssertTrue(proc("mv-repair").synonyms.contains("MVr"), "the case-sensitive form is listed with the synonyms")
        XCTAssertEqual(proc("mv-repair").caseSensitive, ["MVr"])
        let mvr = proc("mv-repair")
        XCTAssertTrue(mvr.cardiac && mvr.echoFirst)
        XCTAssertEqual(mvr.incision, "Intrathoracic")
        XCTAssertEqual(ids("AKA"), ["aka"], "above knee amputation")
        XCTAssertEqual(ids("aka"), [], "but not the everyday \"aka\"")
    }

    func testAbbreviations() {
        let expected: [(String, String)] = [
            ("CABG", "cabg"), ("OPCAB", "opcab"), ("TAVR", "tavr"), ("TAVI", "tavr"), ("TEER", "teer"), ("MitraClip", "teer"),
            ("LVAD", "lvad"), ("OHT", "heart-transplant"), ("OLT", "liver-transplant"), ("BLT", "bilateral-lung-transplant"),
            ("SLT", "single-lung-transplant"), ("VATS", "wedge"), ("RATS", "robotic-lobectomy"), ("EGD", "egd"), ("ERCP", "ercp"),
            ("EUS", "eus"), ("TEE", "tee"), ("DCCV", "dccv"), ("PVI", "af-ablation"), ("ICD", "icd"), ("PPM", "ppm"),
            ("TKA", "tka"), ("TKR", "tka"), ("THA", "tha"), ("THR", "tha"), ("ORIF ankle", "ankle-orif"),
            ("ORIF distal radius", "distal-radius-orif"), ("ACDF", "acdf"), ("TLIF", "tlif"), ("PLIF", "plif"), ("XLIF", "xlif"),
            ("TURP", "turp"), ("TURBT", "turbt"), ("PCNL", "pcnl"), ("URS", "ureteroscopy"), ("RALP", "ralp"), ("CEA", "cea"),
            ("EVAR", "evar"), ("TEVAR", "tevar"), ("FEVAR", "fevar"), ("AAA", "open-aaa"), ("ex lap", "ex-lap"),
            ("lap chole", "lap-chole"), ("lap appy", "lap-appy"), ("lap band", "lap-band"), ("RYGB", "rygb"), ("sleeve", "sleeve"),
            ("Whipple", "whipple"), ("LAR", "open-lar"), ("APR", "apr"), ("ESS", "fess"), ("FESS", "fess"),
            ("T&A", "tonsillectomy-adenoidectomy"), ("BMT", "myringotomy-tubes"), ("PE tubes", "myringotomy-tubes"),
            ("D&C", "dc"), ("D&E", "de"), ("C-section", "cesarean"), ("CS", "cesarean"), ("LTCS", "cesarean"), ("IR", "ir"),
            ("TIPS", "tips"), ("PEG", "peg"), ("trach", "tracheostomy"), ("VP shunt", "vp-shunt"), ("crani", "craniotomy-tumor"),
        ]
        for (q, id) in expected {
            XCTAssertEqual(ProcedureCatalog.search(q).first?.id, id, "search \(q)")
            XCTAssertEqual(ids(q), [id], "parse \(q)")
        }
    }

    func testCaseHyphensAndPlurals() {
        XCTAssertEqual(ids("cabg"), ["cabg"])
        XCTAssertEqual(ids("Lap Chole"), ["lap-chole"])
        XCTAssertEqual(ids("laparoscopic cholecystectomy"), ["lap-chole"])
        XCTAssertEqual(ids("c section"), ["cesarean"])
        XCTAssertEqual(ids("C-Section"), ["cesarean"])
        XCTAssertEqual(ids("caesarean section"), ["cesarean"], "British spelling")
        XCTAssertEqual(ids("PE tube"), ["myringotomy-tubes"])
        XCTAssertEqual(ids("BMTs"), ["myringotomy-tubes"])
        XCTAssertEqual(ids("T & A"), ["tonsillectomy-adenoidectomy"])
        XCTAssertEqual(ids("VP-shunt"), ["vp-shunt"])
        XCTAssertEqual(ids("TKAs"), ["tka"])
        XCTAssertEqual(ids("bilateral inguinal hernias"), ["inguinal-hernia-open"])
        XCTAssertEqual(ids("Roux en Y gastric bypass"), ["rygb"])
        XCTAssertEqual(ids("Hartmann's reversal"), ["hartmann-reversal"])
    }

    func testSearchRanking() {
        // An exact abbreviation before names that start with it.
        XCTAssertEqual(ProcedureCatalog.search("sleeve").map(\.id).first, "sleeve")
        let sleeve = ProcedureCatalog.search("sleeve").map(\.id)
        XCTAssertTrue(sleeve.contains("sleeve-lobectomy"))
        // A prefix before a word inside the name.
        let tonsil = ProcedureCatalog.search("tonsil").map(\.id)
        XCTAssertEqual(tonsil.first, "tonsillectomy")
        if let a = tonsil.firstIndex(of: "tonsillectomy-adenoidectomy"), let b = tonsil.firstIndex(of: "tors") {
            XCTAssertLessThan(a, b, "\"Tonsillectomy and adenoidectomy\" starts with it; \"lingual tonsillectomy\" only has the word")
        } else {
            XCTFail("tonsil results \(tonsil)")
        }
        XCTAssertEqual(ProcedureCatalog.search("hip").first?.id, "tha", "the whole word before HIPEC")
        XCTAssertEqual(ProcedureCatalog.search("hernia").first?.id, "inguinal-hernia-open")
        XCTAssertEqual(ProcedureCatalog.search("knee", limit: 3).count, 3)
        XCTAssertTrue(ProcedureCatalog.search("").isEmpty)
        XCTAssertTrue(ProcedureCatalog.search("zzqx").isEmpty)
        XCTAssertLessThanOrEqual(ProcedureCatalog.search("ectomy").count, 12)
    }

    // MARK: The auto-fill

    func testCardiacCases() {
        let cabg = proc("cabg")
        XCTAssertEqual(cabg.anesthetic, ["ga"])
        XCTAssertTrue(cabg.cardiac && cabg.echoFirst && cabg.highRisk)
        XCTAssertEqual(cabg.incision, "Intrathoracic")
        XCTAssertEqual(cabg.duration, "> 3 h")
        XCTAssertFalse(cabg.lateral)
        let tavr = proc("tavr")
        XCTAssertFalse(tavr.highRisk, "transfemoral")
        XCTAssertNotEqual(tavr.incision, "Intrathoracic")
        XCTAssertEqual(tavr.incision, "Peripheral")
        XCTAssertTrue(tavr.cardiac && tavr.echoFirst)
        XCTAssertEqual(proc("tavr-chest").incision, "Intrathoracic", "transapical or transaortic")
        XCTAssertFalse(proc("teer").highRisk)
    }

    func testLapChole() {
        guard let m = one("lap chole") else { return }
        let p = m.procedure
        XCTAssertEqual(p.id, "lap-chole")
        XCTAssertEqual(p.name, "Laparoscopic cholecystectomy")
        XCTAssertTrue(p.highRisk, "laparoscopic intraperitoneal counts as intraperitoneal")
        XCTAssertEqual(p.incision, "Upper abdominal", "laparoscopic upper abdominal is upper abdominal")
        XCTAssertEqual(p.anesthetic, ["ga"])
        XCTAssertFalse(p.cardiac || p.echoFirst || p.lateral)
    }

    func testOpenHemicolectomy() {
        guard let m = one("open hemicolectomy") else { return }
        XCTAssertTrue(m.procedure.anesthetic.contains("ga"))
        XCTAssertTrue(m.procedure.highRisk)
        XCTAssertEqual(m.procedure.duration, "> 3 h")
        XCTAssertEqual(m.procedure.incision, "Upper abdominal")
        let r = ProcedureCatalog.risk([m])
        XCTAssertEqual(r.anesthetic, ["ga"])
        XCTAssertTrue(r.highRisk)
        XCTAssertEqual(r.duration, "> 3 h")
        XCTAssertFalse(r.cardiac || r.echoFirst)
    }

    func testAorticRepairOpenVersusEndovascular() {
        let evar = proc("evar"), open = proc("open-aaa")
        XCTAssertEqual(ids("EVAR"), ["evar"])
        XCTAssertEqual(ids("open AAA repair"), ["open-aaa"])
        XCTAssertEqual(open.incision, "Upper abdominal")
        XCTAssertEqual(evar.incision, "Peripheral", "femoral access")
        XCTAssertEqual(open.duration, "> 3 h")
        XCTAssertEqual(evar.duration, "> 2–3 h")
        XCTAssertTrue(open.anesthetic.contains("neuraxial"), "GA with an epidural")
        XCTAssertTrue(open.highRisk && evar.highRisk, "aortic repair is suprainguinal vascular either way")
        XCTAssertTrue(open.echoFirst && evar.echoFirst, "major aortic surgery shows echo first, open or endovascular")
        XCTAssertFalse(open.cardiac || evar.cardiac)
        XCTAssertFalse(proc("cea").highRisk, "carotid surgery is not suprainguinal vascular")
        XCTAssertFalse(proc("fem-pop").highRisk)
        XCTAssertFalse(proc("aortobifemoral").echoFirst, "occlusive disease, not aneurysm or dissection")
    }

    func testCataractAndKnee() {
        let c = proc("cataract")
        XCTAssertEqual(c.anesthetic, ["mac"])
        XCTAssertEqual(c.incision, "Peripheral")
        XCTAssertEqual(c.duration, "≤ 2 h")
        XCTAssertTrue(c.lateral)
        XCTAssertFalse(c.highRisk)
        XCTAssertEqual(ProcedureCatalog.search("cataract").first?.id, "cataract")
        XCTAssertTrue(proc("tka").lateral)
        XCTAssertTrue(proc("tka").needsSide(nil))
        XCTAssertFalse(proc("tka").needsSide("left"))
        XCTAssertFalse(proc("lap-chole").needsSide(nil))
        XCTAssertEqual(proc("thyroidectomy-total").incision, "Peripheral", "the neck scores as peripheral")
        XCTAssertEqual(proc("acdf").incision, "Peripheral")
        XCTAssertEqual(proc("vats-lobectomy").incision, "Intrathoracic", "thoracoscopic is intrathoracic")
        XCTAssertEqual(proc("ralp").incision, "Peripheral", "pelvic laparoscopy")
        XCTAssertTrue(proc("ralp").highRisk, "but intraperitoneal")
        XCTAssertFalse(proc("inguinal-hernia-tep").highRisk, "totally extraperitoneal")
        XCTAssertTrue(proc("liver-transplant").echoFirst && proc("bilateral-lung-transplant").echoFirst)
        XCTAssertFalse(proc("kidney-transplant").echoFirst)
    }

    // MARK: Parse

    func testSeveralProcedures() {
        XCTAssertEqual(ids("CABG x3 + AVR"), ["cabg", "avr"])
        XCTAssertEqual(ids("CABGx3"), ["cabg"])
        XCTAssertEqual(ids("CABG x 4, MVr"), ["cabg", "mv-repair"])
        XCTAssertEqual(ids("lap chole and ERCP"), ["lap-chole", "ercp"])
        XCTAssertEqual(ids("ex lap, LOA, small bowel resection"), ["ex-lap", "adhesiolysis", "small-bowel-resection"])
        XCTAssertEqual(ids("TURBT/cysto"), ["turbt", "cystoscopy"])
        XCTAssertEqual(ids("ESS/FESS"), ["fess"], "the same procedure twice in a row is one")
        XCTAssertEqual(ids("TEE/DCCV"), ["tee-dccv"])
        XCTAssertEqual(ids("EGD/colonoscopy"), ["egd-colonoscopy"])
        let text = "planned: lap chole + ERCP"
        let m = ProcedureCatalog.parse(text)
        XCTAssertEqual(m.map(\.text), ["lap chole", "ERCP"])
        XCTAssertEqual(m.first.map { String(text[$0.range]) }, "lap chole")
    }

    func testSides() {
        func side(_ text: String) -> String? { ProcedureCatalog.parse(text).first?.side }
        XCTAssertEqual(side("left TKA"), "left")
        XCTAssertEqual(side("R THA"), "right")
        XCTAssertEqual(side("L TKA"), "left")
        XCTAssertEqual(side("rt CEA"), "right")
        XCTAssertEqual(side("lt knee scope"), "left")
        XCTAssertEqual(side("bilat TKA"), "bilateral")
        XCTAssertEqual(side("b/l TKA"), "bilateral")
        XCTAssertEqual(side("bilateral inguinal hernia repair"), "bilateral")
        XCTAssertEqual(side("left and right TKA"), "bilateral")
        XCTAssertEqual(side("TKA, left"), "left")
        XCTAssertEqual(side("THA (L)"), "left")
        XCTAssertEqual(side("R. THA"), "right")
        XCTAssertEqual(side("cataract OS"), "left")
        XCTAssertEqual(side("BMT"), "bilateral", "B is for bilateral")
        XCTAssertEqual(side("TKA"), nil)
        XCTAssertEqual(side("left hemicolectomy"), nil, "part of the name, and the procedure has no side")
        XCTAssertEqual(ids("left hemicolectomy"), ["open-left-hemi"])
        let two = ProcedureCatalog.parse("left TKA and right THA")
        XCTAssertEqual(two.map(\.procedure.id), ["tka", "tha"])
        XCTAssertEqual(two.map(\.side), ["left", "right"])
        let after = ProcedureCatalog.parse("TKA left, THA right")
        XCTAssertEqual(after.map(\.side), ["left", "right"])
        guard let tka = one("left TKA"), let hernia = one("bilateral inguinal hernia repair") else { return }
        XCTAssertEqual(tka.displayName, "Left total knee arthroplasty")
        XCTAssertEqual(tka.text, "left TKA")
        XCTAssertFalse(tka.needsSide)
        XCTAssertEqual(hernia.displayName, "Bilateral open inguinal hernia repair")
        XCTAssertTrue(one("TKA")?.needsSide ?? false)
        XCTAssertEqual(proc("cea").displayName(side: "right"), "Right carotid endarterectomy")
        XCTAssertEqual(proc("tka").displayName(side: nil), "Total knee arthroplasty")
    }

    func testUnknownTextReturnsNothing() {
        XCTAssertTrue(ProcedureCatalog.parse("").isEmpty)
        XCTAssertTrue(ProcedureCatalog.parse("hello world").isEmpty)
        XCTAssertTrue(ProcedureCatalog.parse("follow up in clinic tomorrow with the patient").isEmpty)
        XCTAssertTrue(ProcedureCatalog.parse("left, right, bilateral").isEmpty)
        XCTAssertTrue(ProcedureCatalog.parse("12345 ; --").isEmpty)
        XCTAssertNil(ProcedureCatalog.risk([]).incision)
        XCTAssertNil(ProcedureCatalog.risk([]).duration)
        XCTAssertTrue(ProcedureCatalog.risk([]).anesthetic.isEmpty)
        XCTAssertFalse(ProcedureCatalog.risk("hello").highRisk)
    }

    // MARK: Risk of several procedures

    func testRiskOfSeveral() {
        let heart = ProcedureCatalog.risk("CABG x3 + AVR")
        XCTAssertTrue(heart.cardiac && heart.echoFirst && heart.highRisk)
        XCTAssertEqual(heart.incision, "Intrathoracic")
        XCTAssertEqual(heart.duration, "> 3 h")
        XCTAssertEqual(heart.anesthetic, ["ga"])

        let gi = ProcedureCatalog.risk("lap chole and ERCP")
        XCTAssertEqual(gi.anesthetic, ["ga"], "GA covers the ERCP's sedation")
        XCTAssertTrue(gi.highRisk)
        XCTAssertEqual(gi.incision, "Upper abdominal")
        XCTAssertEqual(gi.duration, "≤ 2 h")

        XCTAssertEqual(ProcedureCatalog.risk("TLIF").duration, "> 2–3 h")
        XCTAssertEqual(ProcedureCatalog.risk("multilevel ACDF and TLIF").duration, "> 3 h", "two over 2 h: one step up")
        XCTAssertEqual(ProcedureCatalog.risk("TLIF and kyphoplasty").duration, "> 2–3 h", "only one over 2 h")
        XCTAssertEqual(ProcedureCatalog.risk("ACL reconstruction").duration, "> 2–3 h")
        XCTAssertEqual(ProcedureCatalog.risk("bilateral ACL reconstruction").duration, "> 3 h", "a bilateral case counts twice")
        XCTAssertEqual(ProcedureCatalog.risk("left TKA").duration, "≤ 2 h")

        XCTAssertEqual(ProcedureCatalog.risk("TKA and THA").anesthetic, ["neuraxial", "regional"], "no GA: the union")
        XCTAssertEqual(ProcedureCatalog.risk("cataract and carpal tunnel release").anesthetic, ["mac"])
        XCTAssertEqual(ProcedureCatalog.risk("open AAA repair").anesthetic, ["ga", "neuraxial"])
        XCTAssertEqual(ProcedureCatalog.risk("open AAA repair and EGD").anesthetic, ["ga", "neuraxial"])
        XCTAssertEqual(ProcedureCatalog.risk("lap chole and TKA").anesthetic, ["ga"], "the spinal and block were the TKA's own plan")

        XCTAssertEqual(ProcedureCatalog.risk("EGD and cataract").incision, "Peripheral")
        XCTAssertEqual(ProcedureCatalog.risk("TKA and Whipple").incision, "Upper abdominal")
        XCTAssertEqual(ProcedureCatalog.risk("Whipple and VATS wedge").incision, "Intrathoracic")
        XCTAssertFalse(ProcedureCatalog.risk("TAVR").highRisk)
        XCTAssertTrue(ProcedureCatalog.risk("TAVR").cardiac)

        var record = PatientRecord()
        ProcedureCatalog.risk("open hemicolectomy").apply(to: &record)
        XCTAssertEqual(record.anesthetic, ["ga"])
        XCTAssertTrue(record.highRiskSurgery)
        XCTAssertEqual(record.incision, "Upper abdominal")
        XCTAssertEqual(record.duration, "> 3 h")
    }

    // MARK: Data

    func testCatalogIntegrity() {
        let all = ProcedureCatalog.all
        XCTAssertGreaterThanOrEqual(all.count, 400)
        XCTAssertEqual(Set(all.map(\.id)).count, all.count, "unique ids")
        let anesthetics: Set<String> = ["ga", "mac", "neuraxial", "regional"]
        let aorticOrTransplant: Set<String> = ["liver-transplant", "bilateral-lung-transplant", "single-lung-transplant"]
        for p in all {
            XCTAssertFalse(p.id.isEmpty)
            XCTAssertFalse(p.name.trimmingCharacters(in: .whitespaces).isEmpty, p.id)
            XCTAssertFalse(p.specialty.isEmpty, p.id)
            XCTAssertTrue(p.name.first?.isUppercase ?? false, "sentence case: \(p.name)")
            XCTAssertTrue(ProcedureCatalog.incisions.contains(p.incision), "\(p.id): \(p.incision)")
            XCTAssertTrue(ProcedureCatalog.durations.contains(p.duration), "\(p.id): \(p.duration)")
            XCTAssertFalse(p.anesthetic.isEmpty, p.id)
            XCTAssertTrue(p.anesthetic.isSubset(of: anesthetics), "\(p.id): \(p.anesthetic)")
            XCTAssertTrue(Set(p.caseSensitive).isSubset(of: Set(p.synonyms)), p.id)
            if p.cardiac { XCTAssertTrue(p.echoFirst, "\(p.id): cardiac surgery shows echo first") }
            if p.echoFirst {
                XCTAssertTrue(p.cardiac || aorticOrTransplant.contains(p.id) || p.specialty == "Vascular", "\(p.id) shows echo first")
            }
            if p.incision == "Intrathoracic" && !p.cardiac { XCTAssertTrue(p.highRisk, "\(p.id): intrathoracic is RCRI high risk") }
            for s in [p.name] + p.synonyms {
                XCTAssertFalse(s.trimmingCharacters(in: .whitespaces).isEmpty, p.id)
                XCTAssertNil(s.range(of: #"\d{5}"#, options: .regularExpression), "no CPT codes: \(s)")
            }
        }
        XCTAssertEqual(Set(ProcedureCatalog.incisions), ["Peripheral", "Upper abdominal", "Intrathoracic"])
        XCTAssertEqual(ProcedureCatalog.durations, ["≤ 2 h", "> 2–3 h", "> 3 h"])
        for s in ["General & colorectal", "Hepatobiliary & pancreas", "Upper GI & bariatric", "Hernia", "Breast & endocrine",
                  "Vascular", "Cardiac", "Thoracic", "Transplant", "Urology", "Gynecology & obstetrics", "Orthopedics", "Spine",
                  "Neurosurgery", "ENT & head and neck", "Ophthalmology", "Plastics", "Dental & oral", "GI endoscopy",
                  "Interventional radiology", "Cardiac cath & EP", "Bronchoscopy", "Pediatrics"] {
            XCTAssertTrue(all.contains { $0.specialty == s }, s)
        }
    }

    /// Every name and synonym reads back as exactly its own procedure, so no phrase belongs to two.
    func testEveryNameAndSynonymReadsBack() {
        for p in ProcedureCatalog.all {
            for s in [p.name] + p.synonyms {
                XCTAssertEqual(ids(s), [p.id], "parse \"\(s)\"")
                XCTAssertEqual(ProcedureCatalog.search(s, limit: 1).first?.id, p.id, "search \"\(s)\"")
            }
        }
    }

    func testValuesMatchTheRecordAndTheScores() {
        // The strings must be the ones the ARISCAT calculator and the record use.
        let ariscat = Scores.ariscat
        var options = Set<String>()
        for item in ariscat.items {
            if case .choice(let opts) = item.input { options.formUnion(opts.map(\.label)) }
        }
        for v in ProcedureCatalog.incisions + ProcedureCatalog.durations {
            XCTAssertTrue(options.contains(v), "\(v) is an ARISCAT choice")
        }
        var record = PatientRecord()
        record.incision = proc("lap-chole").incision
        record.duration = proc("whipple").duration
        let s = PatientRules.prefill("ariscat", record)
        XCTAssertEqual(s.choices["incision"], "Upper abdominal")
        XCTAssertEqual(s.choices["duration"], "> 3 h")
        XCTAssertEqual(ariscat.id, "ariscat")
    }
}
