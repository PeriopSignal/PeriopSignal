import XCTest
@testable import PeriopSignal

/// The procedure list about doubled (1.8.3, Ben: all specialties, cardiac, thoracic and vascular in the most depth):
/// uniqueness and validity across the list, reading new names and the OR's abbreviations (with Ben's own case), and
/// the RCRI and ARISCAT inputs of representative new entries by the header's rules.
final class ProcedureCatalog183Tests: XCTestCase {
    private var now: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 8))! }

    private func proc(_ id: String, file: StaticString = #filePath, line: UInt = #line) -> Procedure {
        guard let p = ProcedureCatalog.byID(id) else {
            XCTFail("no procedure \(id)", file: file, line: line)
            return ProcedureCatalog.all[0]
        }
        return p
    }

    private func ids(_ text: String) -> [String] { ProcedureCatalog.parse(text).map(\.procedure.id) }

    /// Lower case, without accents, every run of other characters one space: how two spellings of a form compare.
    private func folded(_ s: String) -> String {
        let f = s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
        return f.map { $0.isLetter || $0.isNumber ? String($0) : " " }.joined()
            .split(separator: " ").joined(separator: " ")
    }

    // MARK: The list

    func testIdsNamesAndAliasesAreUnique() {
        let all = ProcedureCatalog.all
        XCTAssertGreaterThanOrEqual(all.count, 1000, "about doubled")
        XCTAssertEqual(Set(all.map(\.id)).count, all.count, "unique ids")
        // A name or alias belongs to one procedure, whatever its case, hyphens or punctuation; a case-sensitive form
        // ("AVr", "AKA") is compared in its own case.
        var owner: [String: String] = [:]
        for p in all {
            for form in [p.name] + p.synonyms {
                let key = p.caseSensitive.contains(form) ? "=" + form : folded(form)
                if let o = owner[key], o != p.id {
                    XCTFail("\"\(form)\" is in both \(o) and \(p.id)")
                }
                owner[key] = p.id
            }
        }
    }

    func testEveryEntryIsValid() {
        let anesthetics: Set<String> = ["ga", "mac", "neuraxial", "regional"]
        for p in ProcedureCatalog.all {
            XCTAssertTrue(ProcedureCatalog.incisions.contains(p.incision), p.id)
            XCTAssertTrue(ProcedureCatalog.durations.contains(p.duration), p.id)
            XCTAssertFalse(p.anesthetic.isEmpty, p.id)
            XCTAssertTrue(p.anesthetic.isSubset(of: anesthetics), p.id)
            XCTAssertFalse(p.specialty.isEmpty, p.id)
            XCTAssertNotNil(p.name.first.map(\.isUppercase), p.id)
            // Lee 1999: a chest opened is high risk, and only the cardiac cases, where the app hides the RCRI, differ.
            if p.incision == "Intrathoracic" && !p.cardiac { XCTAssertTrue(p.highRisk, p.id) }
            if p.cardiac { XCTAssertTrue(p.echoFirst, p.id) }
            for s in [p.name] + p.synonyms {
                XCTAssertEqual(s, s.trimmingCharacters(in: .whitespaces), "\(p.id): \"\(s)\"")
                XCTAssertFalse(s.isEmpty, p.id)
            }
        }
        let sections = Set(ProcedureCatalog.all.map(\.specialty))
        for s in ["Trauma", "Burns", "Pain medicine", "Psychiatry", "Transplant", "Cardiac cath & EP", "Interventional radiology",
                  "GI endoscopy", "Dental & oral"] {
            XCTAssertTrue(sections.contains(s), s)
        }
        let count = { (s: String) in ProcedureCatalog.all.filter { $0.specialty == s }.count }
        XCTAssertGreaterThanOrEqual(count("Cardiac"), 75)
        XCTAssertGreaterThanOrEqual(count("Thoracic"), 50)
        XCTAssertGreaterThanOrEqual(count("Vascular"), 60)
    }

    /// The OR's own words and abbreviations no other list in the app uses for something else.
    func testNoAliasIsAnAirwayOrDeviceWord() {
        for p in ProcedureCatalog.all {
            for s in p.synonyms {
                let f = folded(s)
                XCTAssertFalse(["dlt", "lma", "ett", "sga", "double lumen tube", "bronchial blocker", "ecp", "percutaneous rvad"].contains(f),
                               "\(p.id): \(s)")
            }
        }
        XCTAssertEqual(ids("DLT"), [], "a double-lumen tube, not a double lung transplant")
        XCTAssertEqual(ids("ECP"), [], "an Impella model")
    }

    // MARK: Reading

    func testBensCase() {
        let text = "Open left iliac aneurysm repair (infrarenal clamp)"
        let m = ProcedureCatalog.parse(text)
        XCTAssertEqual(m.map(\.procedure.id), ["open-iliac-aneurysm"])
        XCTAssertEqual(m.first?.side, "left", "the side written inside the name")
        XCTAssertEqual(m.first?.text, "Open left iliac aneurysm repair")
        XCTAssertEqual(m.first?.displayName, "Left open iliac artery aneurysm repair")
        let p = proc("open-iliac-aneurysm")
        XCTAssertTrue(p.highRisk, "open reconstruction of the iliac artery is suprainguinal vascular")
        XCTAssertEqual(p.incision, "Upper abdominal", "a midline or flank incision to clamp the infrarenal aorta")
        XCTAssertEqual(p.duration, "> 3 h")
        XCTAssertEqual(p.anesthetic, ["ga", "neuraxial"])
        XCTAssertTrue(p.lateral)
        XCTAssertFalse(p.cardiac)

        // The planned procedure reads as one item, with the side, from the note and from the quick-add bar.
        let items = PlannedProcedure.parse("Open left iliac aneurysm repair")
        XCTAssertEqual(items.map(\.catalogID), ["open-iliac-aneurysm"])
        XCTAssertEqual(items.first?.side, "left")
        let q = QuickAdd.read("for open left iliac aneurysm repair (infrarenal clamp)", record: PatientRecord(), tab: .preop, now: now)
        var r = PatientRecord()
        PatientNote.apply(q.findings.map(\.change), to: &r)
        XCTAssertEqual(r.procedures.map(\.catalogID), ["open-iliac-aneurysm"])
        XCTAssertEqual(r.procedures.first?.side, "left")
        XCTAssertTrue(r.highRiskSurgery)
        XCTAssertEqual(r.incision, "Upper abdominal")
        XCTAssertEqual(r.duration, "> 3 h")
        let note = PatientNote.read("72 yo M scheduled for open left iliac aneurysm repair (infrarenal clamp) tomorrow.", now: now)
        var n = PatientRecord()
        PatientNote.apply(note.findings.map(\.change), to: &n)
        XCTAssertEqual(n.procedures.map(\.catalogID), ["open-iliac-aneurysm"])
        XCTAssertEqual(n.procedures.first?.side, "left")
    }

    func testSideInsideTheName() {
        func read(_ t: String) -> [String] { ProcedureCatalog.parse(t).map { $0.procedure.id + ":" + ($0.side ?? "-") } }
        XCTAssertEqual(read("robotic left partial nephrectomy"), ["partial-nephrectomy:left"])
        XCTAssertEqual(read("lap right inguinal hernia repair"), ["inguinal-hernia-lap:right"])
        XCTAssertEqual(read("open L iliac aneurysm repair"), ["open-iliac-aneurysm:left"])
        XCTAssertEqual(read("left TKA and right THA"), ["tka:left", "tha:right"], "unchanged")
        XCTAssertEqual(read("open left hemicolectomy"), ["open-left-hemi:-"], "no side for a procedure without one")
        XCTAssertEqual(read("left hemicolectomy"), ["open-left-hemi:-"])
    }

    func testNewNamesAndAbbreviations() {
        let expected: [(String, String)] = [
            // Vascular
            ("open iliac aneurysm repair", "open-iliac-aneurysm"), ("IBE", "endo-iliac-aneurysm"),
            ("iliac branch endoprosthesis", "endo-iliac-aneurysm"), ("juxtarenal AAA repair", "juxtarenal-aaa"),
            ("EVAR explant", "aortic-graft-explant"), ("type II endoleak embolization", "endoleak-embolization"),
            ("branched TEVAR", "branched-tevar"), ("arch debranching", "arch-debranching"), ("ax-fem", "axillobifemoral"),
            ("aorto-bifem", "aortobifemoral"), ("fem-pop", "fem-pop"), ("TCAR", "tcar"), ("CEA", "cea"), ("AAA repair", "open-aaa"),
            ("EVAR", "evar"), ("AVF", "av-fistula"), ("BKA", "bka"), ("pAVF", "perc-avf"), ("HeRO graft insertion", "hero-graft"),
            ("fistulagram", "fistulagram"), ("BKA revision", "amputation-revision"), ("carotid subclavian bypass", "carotid-subclavian"),
            ("PD catheter placement", "pd-catheter"), ("SMA embolectomy", "sma-embolectomy"),
            // Cardiac, cath and EP
            ("OPCAB", "opcab"), ("MIDCAB", "midcab"), ("TAVR", "tavr"), ("TEER", "teer"), ("LAAO", "laao"), ("LVAD", "lvad"),
            ("OHT", "heart-transplant"), ("LVAD explant", "lvad-explant"), ("BiVAD implant", "bivad"), ("Dor procedure", "lv-aneurysm"),
            ("Ozaki procedure", "ozaki"), ("Impella 5.5 insertion", "axillary-impella"), ("ECMO to LVAD", "ecmo-to-vad"),
            ("cryomaze", "maze"), ("Thoraflex", "arch"), ("LARIAT", "lariat"), ("CardioMEMS implant", "cardiomems"),
            ("TAVR explant", "tavr-explant"), ("Ebstein repair", "ebstein"),
            // Thoracic, bronchoscopy, transplant
            ("VATS", "wedge"), ("RATS", "robotic-lobectomy"), ("EBUS", "ebus"), ("VATS RUL lobectomy", "vats-lobectomy"),
            ("bilobectomy", "bilobectomy"), ("Pancoast resection", "pancoast"), ("EPD", "pleurectomy-decortication"),
            ("pleuroscopy", "medical-thoracoscopy"), ("Eloesser flap", "eloesser"), ("cryobiopsy", "cryobiopsy"),
            ("SLK", "liver-transplant"), ("organ procurement", "organ-procurement"), ("double lung transplant", "bilateral-lung-transplant"),
            // Other specialties
            ("TaTME", "tatme"), ("ALPPS", "alpps"), ("OAGB", "oagb"), ("RPLND", "rplnd"), ("B-Lynch suture", "pph-laparotomy"),
            ("PLND", "plnd"), ("Girdlestone", "hip-resection-arthroplasty"), ("MACI", "cartilage-restoration"),
            ("Gamma Knife", "gamma-knife"), ("EDAS", "moyamoya"), ("LTR", "ltr"), ("TOETVA", "thyroidectomy-total"), ("TIF", "tif"),
            ("BRTO", "brto"), ("SEMLS", "semls"), ("VBT", "vbt"), ("TAPVR repair", "tapvr"), ("REBOA", "reboa"), ("ESI", "esi"),
            ("ECT", "ect"), ("lumbar drain for TEVAR", "lumbar-drain"), ("ReCell", "burn-cea"), ("blood patch", "blood-patch"),
        ]
        XCTAssertGreaterThanOrEqual(expected.count, 30)
        for (q, id) in expected {
            XCTAssertEqual(ProcedureCatalog.search(q).first?.id, id, "search \(q)")
            XCTAssertEqual(ids(q), [id], "parse \(q)")
        }
        XCTAssertEqual(ids("DLT"), [])
        XCTAssertEqual(ids("EVAR with IBE"), ["evar", "endo-iliac-aneurysm"])
        XCTAssertTrue(ProcedureCatalog.risk("EVAR with IBE").highRisk, "the EVAR")
        XCTAssertEqual(ids("redo sternotomy, MVR, TV repair"), ["redo-sternotomy", "mvr", "tv-repair"])
        XCTAssertEqual(ProcedureCatalog.search("iliac aneurysm").first?.id, "open-iliac-aneurysm")
    }

    // MARK: RCRI (Lee 1999) and ARISCAT (Canet 2010), by the header's rules

    private func check(_ id: String, high: Bool, _ incision: String, file: StaticString = #filePath, line: UInt = #line) {
        let p = proc(id, file: file, line: line)
        XCTAssertEqual(p.highRisk, high, "\(id) RCRI", file: file, line: line)
        XCTAssertEqual(p.incision, incision, "\(id) ARISCAT incision", file: file, line: line)
    }

    func testVascularRules() {
        check("open-iliac-aneurysm", high: true, "Upper abdominal")      // open iliac reconstruction: suprainguinal
        check("evar", high: true, "Peripheral")                          // endovascular repair of the aorta
        check("endoleak-repair", high: true, "Peripheral")               // endovascular, on the aorta
        check("branched-tevar", high: true, "Peripheral")
        check("endo-iliac-aneurysm", high: false, "Peripheral")          // endovascular counts only on the aorta
        check("fem-pop", high: false, "Peripheral")                      // infrainguinal
        check("iliofemoral-bypass", high: true, "Peripheral")            // open iliac reconstruction, lower quadrant
        check("juxtarenal-aaa", high: true, "Upper abdominal")
        check("visceral-debranching", high: true, "Upper abdominal")
        check("arch-debranching", high: true, "Intrathoracic")
        check("tcar", high: false, "Peripheral")                         // carotid surgery does not count
        check("carotid-subclavian", high: false, "Peripheral")
        check("mesenteric-stent", high: false, "Peripheral")             // percutaneous stenting does not count
        check("aortoiliac-embolectomy", high: false, "Peripheral")       // not a repair or reconstruction
        check("pd-catheter", high: true, "Peripheral")                   // the peritoneum is entered
        XCTAssertTrue(proc("juxtarenal-aaa").echoFirst && proc("aortic-graft-explant").echoFirst, "major aortic surgery")
        XCTAssertFalse(proc("open-iliac-aneurysm").echoFirst, "iliac, not aortic")
    }

    func testCardiacAndThoracicRules() {
        for id in ["lvad-explant", "bivad", "tah-implant", "lv-aneurysm", "endocarditis", "ebstein"] {
            let p = proc(id)
            XCTAssertTrue(p.cardiac && p.echoFirst, id)
            XCTAssertEqual(p.incision, "Intrathoracic", id)
            XCTAssertEqual(p.anesthetic, ["ga"], id)
        }
        check("axillary-impella", high: false, "Peripheral")
        XCTAssertTrue(proc("axillary-impella").cardiac)
        check("coarctation-stent", high: false, "Peripheral")            // percutaneous stenting does not count
        check("pa-stent", high: false, "Peripheral")
        check("bilobectomy", high: true, "Intrathoracic")
        check("medical-thoracoscopy", high: true, "Intrathoracic")       // thoracoscopy opens the chest, under MAC or not
        XCTAssertEqual(proc("medical-thoracoscopy").anesthetic, ["mac"])
        check("thoracentesis", high: false, "Peripheral")
        check("rib-resection", high: false, "Peripheral")                // the chest is not entered
        check("chest-wall-tumor", high: false, "Peripheral")
        check("esophageal-diversion", high: false, "Peripheral")         // the neck
        check("tracheoinnominate", high: true, "Intrathoracic")
        check("cpam", high: true, "Intrathoracic")
        check("vbt", high: true, "Intrathoracic")
        XCTAssertTrue(proc("vats-lobectomy").highRisk)
        XCTAssertEqual(proc("vats-lobectomy").incision, "Intrathoracic")
    }

    func testAbdominalAndOtherRules() {
        check("lap-chole", high: true, "Upper abdominal")                // laparoscopic intraperitoneal
        check("inguinal-hernia-tep", high: false, "Peripheral")          // totally extraperitoneal
        check("lap-umbilical-hernia", high: true, "Peripheral")          // intraperitoneal, below the upper abdomen
        check("diastasis-recti", high: false, "Upper abdominal")         // abdominal wall, not entered
        check("internal-hernia", high: true, "Upper abdominal")
        check("lap-cecectomy", high: true, "Upper abdominal")            // any colectomy
        check("oagb", high: true, "Upper abdominal")
        check("alpps", high: true, "Upper abdominal")
        check("rplnd", high: true, "Upper abdominal")
        check("robotic-simple-prostatectomy", high: true, "Peripheral")  // pelvic laparoscopy
        check("pph-laparotomy", high: true, "Peripheral")                // low transverse
        check("para-aortic-lnd", high: true, "Upper abdominal")
        check("vaginal-cuff", high: true, "Peripheral")                  // the peritoneum from the vagina
        check("robotic-kidney-transplant", high: true, "Peripheral")     // transperitoneal, unlike the open kidney transplant
        check("kidney-transplant", high: false, "Peripheral")
        check("kidney-transplant-revision", high: false, "Peripheral")
        check("lap-assisted-ercp", high: true, "Upper abdominal")
        check("tif", high: false, "Peripheral")
        check("paracentesis", high: false, "Peripheral")
        check("splenorrhaphy", high: true, "Upper abdominal")
        check("pelvic-packing", high: false, "Peripheral")               // preperitoneal
        check("reboa", high: false, "Peripheral")                        // occlusion, not repair of the aorta
        check("bladder-injury", high: true, "Peripheral")
        check("hip-resurfacing", high: false, "Peripheral")
        check("lumbar-disc-arthroplasty", high: false, "Peripheral")
        check("major-burn-excision", high: false, "Peripheral")
        check("esi", high: false, "Peripheral")
        check("ect", high: false, "Peripheral")
        XCTAssertEqual(proc("ect").anesthetic, ["ga"])
        XCTAssertEqual(proc("esi").anesthetic, ["mac"])
        XCTAssertEqual(proc("major-burn-excision").duration, "> 3 h")
    }

    /// The review's fixes (1.8.3): each entry decided by the header's rules, and the aliases that misled moved or gone.
    func testReviewFixes() {
        // Percutaneous stenting does not count, the aorta's coarctation included.
        XCTAssertFalse(proc("coarctation-stent").highRisk)
        // Pyelolithotomy: open through the flank (as an open nephrectomy), laparoscopic or robotic transperitoneal.
        check("open-pyelolithotomy", high: false, "Upper abdominal")
        check("pyelolithotomy", high: true, "Upper abdominal")
        XCTAssertEqual(ids("anatrophic nephrolithotomy"), ["open-pyelolithotomy"])
        XCTAssertEqual(ids("robotic pyelolithotomy"), ["pyelolithotomy"])
        XCTAssertEqual(proc("open-nephrectomy").highRisk, proc("open-pyelolithotomy").highRisk)
        // Vaginoplasty into the peritoneum, and an orchiectomy that takes under 2 h.
        XCTAssertEqual(ids("robotic vaginoplasty"), ["peritoneal-vaginoplasty"])
        XCTAssertTrue(proc("peritoneal-vaginoplasty").highRisk)
        XCTAssertFalse(proc("gender-affirming").highRisk)
        XCTAssertEqual(ids("orchiectomy for gender affirmation"), ["gender-orchiectomy"])
        XCTAssertEqual(proc("gender-orchiectomy").duration, "≤ 2 h")
        // PIPAC is a short laparoscopy, not cytoreduction.
        XCTAssertEqual(ids("PIPAC"), ["pipac"])
        check("pipac", high: true, "Upper abdominal")
        XCTAssertEqual(proc("pipac").duration, "≤ 2 h")
        XCTAssertEqual(proc("hipec").duration, "> 3 h")
        // Sequential single lung transplant is both lungs.
        XCTAssertEqual(ids("SSLT"), ["bilateral-lung-transplant"])
        XCTAssertFalse(proc("single-lung-transplant").synonyms.contains("SSLT"))
        // Debranching in the neck is carotid and neck vascular surgery; through the sternum it is the chest.
        // "Debranching TEVAR" keeps the TEVAR (its RCRI flag and echo-first), not only the neck debranching (1.8.3 re-check).
        XCTAssertTrue(ids("debranching TEVAR").contains("tevar"))
        XCTAssertFalse(proc("cervical-debranching").synonyms.contains("debranching TEVAR"))
        XCTAssertEqual(ids("supra-aortic debranching"), ["cervical-debranching"])
        check("cervical-debranching", high: false, "Peripheral")
        check("arch-debranching", high: true, "Intrathoracic")
        // A type II endoleak is closed by embolizing a branch, not by repairing the aorta; extensions stay aortic repair.
        XCTAssertEqual(ids("type II endoleak embolization"), ["endoleak-embolization"])
        XCTAssertEqual(ids("translumbar embolization"), ["endoleak-embolization"])
        check("endoleak-embolization", high: false, "Peripheral")
        XCTAssertEqual(ids("proximal cuff extension"), ["endoleak-repair"])
        XCTAssertEqual(ids("iliac limb extension"), ["endoleak-repair"])
        check("endoleak-repair", high: true, "Peripheral")
        // Names and durations.
        XCTAssertEqual(proc("colonic-volvulus").name, "Colonic volvulus resection")
        XCTAssertEqual(ids("cecopexy"), ["colonic-volvulus"])
        XCTAssertEqual(ids("hemipelvectomy"), ["hemipelvectomy"])
        XCTAssertEqual(proc("hemipelvectomy").duration, "> 3 h")
        XCTAssertEqual(ids("maxillomandibular advancement"), ["mma-sleep"])
        XCTAssertEqual(proc("mma-sleep").duration, "> 3 h")
        // A crash or STAT cesarean is usually under general anesthesia; the planned and urgent ones keep neuraxial.
        for t in ["STAT cesarean", "emergency cesarean section", "emergency C-section", "crash cesarean"] {
            XCTAssertEqual(ids(t), ["emergency-cesarean"], t)
        }
        XCTAssertEqual(proc("emergency-cesarean").anesthetic, ["ga"])
        XCTAssertTrue(proc("emergency-cesarean").highRisk)
        XCTAssertEqual(proc("cesarean").anesthetic, ["neuraxial"])
        XCTAssertEqual(ids("repeat C-section"), ["cesarean"])
        // Aliases that read as something else are gone.
        XCTAssertEqual(ids("PRC"), [], "packed red cells")
        XCTAssertEqual(ids("LVA"), [])
        XCTAssertEqual(ids("AVS"), [])
        XCTAssertEqual(ids("jump graft"), [])
        XCTAssertEqual(ids("pouch revision"), [])
        XCTAssertEqual(ids("minimally invasive lumbar decompression"), ["lumbar-laminectomy"], "an operation under GA, not MILD")
        XCTAssertFalse(proc("tracheostomy").synonyms.contains("tracheostomy decannulation"))
        XCTAssertFalse(proc("tracheostomy").synonyms.contains("trach change"))
        // A tracheostomy decannulation or tube change is a bedside procedure of its own, not a tracheostomy under GA
        // and an ECMO decannulation; a bare "decannulation" stays the ECMO one.
        for t in ["tracheostomy decannulation", "trach decannulation", "trach change", "tracheostomy tube change"] {
            XCTAssertEqual(ids(t), ["trach-decannulation"], t)
            XCTAssertEqual(ProcedureCatalog.search(t).first?.id, "trach-decannulation", t)
        }
        let decannulation = proc("trach-decannulation")
        XCTAssertEqual(decannulation.anesthetic, ["mac"])
        XCTAssertEqual(decannulation.incision, "Peripheral")
        XCTAssertEqual(decannulation.duration, "≤ 2 h")
        XCTAssertFalse(decannulation.highRisk)
        XCTAssertEqual(ids("decannulation"), ["ecmo-decannulation"])
        // Taking down an esophageal conduit is mediastinal surgery; a cervical esophagostomy is the neck.
        XCTAssertEqual(ids("esophagectomy takedown"), ["conduit-takedown"])
        check("conduit-takedown", high: true, "Intrathoracic")
        check("esophageal-diversion", high: false, "Peripheral")
    }

    /// "AAA" is the aneurysm, the diagnosis (Ben, 1.8.3): typed alone it names neither open repair nor EVAR, so it adds
    /// no repair by itself; the search may still list the repairs to pick from.
    func testBareAAAIsTheDiagnosis() {
        for t in ["AAA", "aaa", "rAAA", "ruptured AAA", "TAAA", "thoracoabdominal aneurysm"] {
            XCTAssertEqual(ids(t), [], t)
            XCTAssertTrue(PlannedProcedure.parse(t).allSatisfy { $0.catalogID == nil }, t)
        }
        for p in ProcedureCatalog.all {
            for s in [p.name] + p.synonyms {
                XCTAssertFalse(["aaa", "raaa", "taaa", "ruptured aaa", "thoracoabdominal aneurysm"].contains(folded(s)), "\(p.id): \(s)")
            }
        }
        // The type-ahead still offers the repairs, and a repair written out reads as one.
        let listed = ProcedureCatalog.search("AAA").map(\.id)
        XCTAssertTrue(listed.contains("open-aaa") && listed.contains("evar"), listed.joined(separator: ", "))
        XCTAssertEqual(ids("AAA repair"), ["open-aaa"])
        XCTAssertEqual(ids("open AAA"), ["open-aaa"])
        XCTAssertEqual(ids("ruptured AAA repair"), ["open-aaa"])
        XCTAssertEqual(ids("TAAA repair"), ["taaa"])
        XCTAssertEqual(ids("thoracoabdominal aneurysm repair"), ["taaa"])
        XCTAssertEqual(ids("thoracoabdominal aortic aneurysm repair"), ["taaa"])
        XCTAssertEqual(ids("EVAR for ruptured AAA"), ["evar"])
        // In the quick-add bar, "for AAA" plans no repair from the list.
        let q = QuickAdd.read("for AAA", record: PatientRecord(), tab: .preop, now: now)
        var r = PatientRecord()
        PatientNote.apply(q.findings.map(\.change), to: &r)
        XCTAssertFalse(r.procedures.contains { $0.catalogID == "open-aaa" })
        XCTAssertFalse(r.highRiskSurgery)
    }

    func testRiskOfSeveralNewProcedures() {
        let r = ProcedureCatalog.risk("left BKA and right fem pop bypass")
        XCTAssertFalse(r.highRisk)
        XCTAssertEqual(r.incision, "Peripheral")
        let a = ProcedureCatalog.risk("open left iliac aneurysm repair and right fem-pop")
        XCTAssertTrue(a.highRisk)
        XCTAssertEqual(a.incision, "Upper abdominal")
        XCTAssertEqual(a.anesthetic, ["ga", "neuraxial"])
        XCTAssertEqual(ProcedureCatalog.risk("bilobectomy and mediastinoscopy").incision, "Intrathoracic")
    }
}
