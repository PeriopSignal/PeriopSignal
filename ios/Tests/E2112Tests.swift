import XCTest
@testable import PeriopSignal

/// 1.12 helper E2: the prosthetic valve library (note 4), insufficiency as regurgitation (note 6) and valve shorthand read
/// when typing (note 7).
final class E2112Tests: XCTestCase {
    /// 11 November 2026, 08:00 on the device's clock.
    private var now: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 8))! }

    private func read(_ s: String, choices: [String: String] = [:]) -> PatientNoteReading { PatientNote.read(s, now: now, choices: choices) }
    private func change(_ s: String, _ id: String) -> PatientNoteChange? { read(s).findings.first { $0.id == id }?.change }
    private func quick(_ s: String, tab: QuickAddTab = .preop, record: PatientRecord = PatientRecord()) -> QuickAddReading {
        QuickAdd.read(s, record: record, tab: tab, now: now)
    }
    private func applied(_ s: String) -> PatientRecord {
        var r = PatientRecord()
        PatientNote.apply(read(s).findings.map(\.change), to: &r)
        return r
    }
    private func meaning(_ token: String, in text: String) -> AbbreviationMatch? { MedAbbreviations.scan(text).first { $0.token == token } }

    /// Findings that file valve disease or an echo valve finding.
    private func valveIDs(_ s: String) -> [String] {
        read(s).findings.map(\.id).filter { self.isValveID($0) }
    }

    private func isValveID(_ id: String) -> Bool {
        id == "problem:as" || id == "problem:mr" || id.hasPrefix("valve:") || id == "problem:valve-severe" || id.hasPrefix("echo:")
    }

    // MARK: Note 4: the library

    func testTheLibraryIsOnePlainListWithTheCommonValves() {
        XCTAssertEqual(Set(ValveLibrary.rows.map(\.position)), Set(ValvePosition.allCases), "every position has rows")
        XCTAssertEqual(ValveLibrary.kinds(at: .mitral), [.bioprosthetic, .mechanical, .transcatheter, .repair])
        XCTAssertEqual(ValveLibrary.kinds(at: .aortic), [.bioprosthetic, .mechanical, .transcatheter])
        XCTAssertEqual(ValveKind.repair.label, "Repair: ring / clip")
        XCTAssertEqual(ValveKind.bioprosthetic.label, "Surgical bioprosthetic")
        let names = Set(ValveLibrary.rows.map(\.name))
        for name in ["Perimount", "Magna Ease", "Inspiris Resilia", "Mosaic", "Hancock II", "Avalus", "Epic", "Trifecta", "Perceval (sutureless)",
                     "Intuity (rapid deployment)", "St. Jude Regent", "St. Jude Masters", "On-X", "ATS Open Pivot", "CarboMedics", "SAPIEN 3",
                     "SAPIEN 3 Ultra", "Evolut R", "Evolut PRO", "Evolut FX", "Navitor", "MitraClip", "PASCAL", "Melody", "Harmony", "Physio II ring"] {
            XCTAssertTrue(names.contains(name), name)
        }
        // Each row is found where it belongs.
        XCTAssertTrue(ValveLibrary.rows(at: .aortic, .transcatheter).contains { $0.name == "SAPIEN 3" })
        XCTAssertTrue(ValveLibrary.rows(at: .pulmonic, .transcatheter).contains { $0.name == "Melody" })
        XCTAssertTrue(ValveLibrary.rows(at: .mitral, .repair).contains { $0.name == "MitraClip" })
        // Row ids are unique, so the picker lists each once.
        XCTAssertEqual(Set(ValveLibrary.rows.map(\.id)).count, ValveLibrary.rows.count)
    }

    func testSizesAreGenericOrTheModelsOwnOrTyped() {
        XCTAssertEqual(ValveLibrary.genericSizes, [19, 21, 23, 25, 27, 29, 31, 33])
        let magna = ValveLibrary.rows.first { $0.name == "Magna Ease" }!
        XCTAssertEqual(ValveLibrary.sizes(for: magna), ValveLibrary.genericSizes)
        XCTAssertEqual(ValveLibrary.sizes(for: ValveLibrary.rows.first { $0.name == "SAPIEN 3" && $0.position == .aortic }!), [20, 23, 26, 29])
        XCTAssertEqual(ValveLibrary.sizes(for: ValveLibrary.rows.first { $0.name == "Evolut R" }!), [23, 26, 29, 34])
        XCTAssertEqual(ValveLibrary.sizes(for: ValveLibrary.rows.first { $0.name == "Physio II ring" }!), [], "a typed size only")
        XCTAssertEqual(ValveLibrary.sizes(for: ValveLibrary.rows.first { $0.name == "MitraClip" }!), [])
    }

    func testChoosingWritesTheTextAsIfTyped() {
        let magna = ValveLibrary.rows.first { $0.name == "Magna Ease" }!
        let choice = ValveChoice(row: magna, size: "23")
        XCTAssertEqual(choice.detail, "23 mm Magna Ease")
        XCTAssertEqual(choice.historyText, "bioprosthetic 23 mm Magna Ease")
        XCTAssertEqual(ValveChoice(row: magna, size: "").detail, "Magna Ease", "no size")
        XCTAssertEqual(ValveChoice(row: magna, size: "27 mm").detail, "27 mm Magna Ease")
        XCTAssertEqual(ValveChoice(row: magna, size: "27mm").detail, "27 mm Magna Ease")
        XCTAssertEqual(ValveChoice(row: magna, size: "27/29").detail, "27/29 Magna Ease", "a size with other characters is kept as typed")
        let unlisted = ValveLibrary.rows.first { $0.position == .mitral && $0.kind == .mechanical && $0.name.isEmpty }!
        XCTAssertEqual(unlisted.title, "Model not listed")
        XCTAssertEqual(ValveChoice(row: unlisted, size: "29").detail, "29 mm")
        XCTAssertEqual(ValveChoice(row: unlisted, size: "29").historyText, "mechanical 29 mm")
        XCTAssertEqual(ValveChoice(row: unlisted, size: "").historyText, "mechanical")
        XCTAssertEqual(ValveLibrary.sizeText(" 25 "), "25 mm")
        XCTAssertEqual(ValveLibrary.sizeText(""), "")
    }

    func testTheEchoReadsTheLibraryTextAsItReadsTyping() {
        let magna = ValveLibrary.rows.first { $0.name == "Magna Ease" }!
        var v = EchoValve()
        v.prosthesis = magna.kind.echoKind
        v.prosthesisDetail = ValveChoice(row: magna, size: "23").detail
        XCTAssertEqual(v.prosthesisPhrase(name: "Aortic", replacement: "AVR"), "AVR bioprosthetic: 23 mm Magna Ease")
        // The echo's own kinds are the library's kinds, so the chip and the picker agree.
        XCTAssertEqual(Set(ValveKind.allCases.map(\.echoKind)), Set(EchoValve.prostheses))
        for k in ValveKind.allCases { XCTAssertEqual(ValveKind.fromEcho(k.echoKind), k) }
        XCTAssertNil(ValveKind.fromEcho(""))
        XCTAssertNil(ValveKind.fromEcho("Homemade"))
        var e = PatientEcho()
        e.aortic = v
        XCTAssertTrue(e.phrases.contains("AVR bioprosthetic: 23 mm Magna Ease"), e.phrases.joined(separator: " | "))
    }

    func testTheHistoryReadsTheLibraryTextAsItReadsTyping() throws {
        let sapien = ValveLibrary.rows.first { $0.name == "SAPIEN 3" && $0.position == .aortic }!
        var r = PatientRecord()
        r.hx.editValve("aortic") { v in
            v.prosthetic = true
            v.prosthesis = ValveChoice(row: sapien, size: "26").historyText
        }
        XCTAssertEqual(r.hx.valve("aortic").prosthesis, "transcatheter 26 mm SAPIEN 3")
        XCTAssertTrue(HistorySections.valveWords(r).contains("aortic prosthetic (transcatheter 26 mm SAPIEN 3)"), HistorySections.valveWords(r).joined(separator: " | "))
        // A saved record keeps it, and a record saved before 1.12 opens as before.
        let again = try JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(again.hx.valve("aortic").prosthesis, "transcatheter 26 mm SAPIEN 3")
        let old = try JSONDecoder().decode(PatientRecord.self, from: Data(#"{"procedure":"AVR","labs":{"k":4.1}}"#.utf8))
        XCTAssertEqual(old.procedure, "AVR")
        XCTAssertTrue(old.hx.valves.isEmpty)
    }

    // MARK: Note 6: insufficiency is regurgitation

    func testInsufficiencyFilesAsRegurgitation() {
        XCTAssertEqual(change("aortic insufficiency", "valve:aortic:regurgitation"), .valve("aortic", "regurgitation", nil))
        XCTAssertEqual(change("severe mitral insufficiency", "problem:mr"), .valve("mitral", "regurgitation", "severe"))
        XCTAssertEqual(change("moderate tricuspid valve insufficiency", "valve:tricuspid:regurgitation"), .valve("tricuspid", "regurgitation", "moderate"))
        XCTAssertEqual(change("aortic regurgitation", "valve:aortic:regurgitation"), .valve("aortic", "regurgitation", nil), "the same item as the other word")
        let r = applied("mild aortic insufficiency")
        XCTAssertEqual(r.hx.valve("aortic"), PatientValve(regurgitation: true, regurgitationGrade: "mild"))
        // AI is aortic insufficiency, and files the aortic regurgitation.
        XCTAssertEqual(change("severe AI", "valve:aortic:regurgitation"), .valve("aortic", "regurgitation", "severe"))
        XCTAssertEqual(change("AI moderate", "valve:aortic:regurgitation"), .valve("aortic", "regurgitation", "moderate"))
        XCTAssertEqual(change("mild tricuspid insufficiency", "valve:tricuspid:regurgitation"), .valve("tricuspid", "regurgitation", "mild"))
        XCTAssertEqual(change("mild TI", "valve:tricuspid:regurgitation"), .valve("tricuspid", "regurgitation", "mild"))
        XCTAssertEqual(change("TI moderate", "valve:tricuspid:regurgitation"), .valve("tricuspid", "regurgitation", "moderate"))
        // A severe pulmonic insufficiency has no valve of its own on the page: severe valve disease, valve not recorded.
        XCTAssertEqual(change("severe PI", "problem:valve-severe"), .problem("valve-severe"))
        XCTAssertEqual(change("severe pulmonic insufficiency", "problem:valve-severe"), .problem("valve-severe"))
        XCTAssertTrue(valveIDs("mild pulmonic insufficiency").isEmpty, "mild pulmonic is not filed")
        // Trace and trivial insufficiency are not valve disease.
        XCTAssertTrue(valveIDs("trace aortic insufficiency").isEmpty)
        XCTAssertTrue(valveIDs("trivial AI").isEmpty)
        // Not said of the patient: negated.
        XCTAssertTrue(valveIDs("no aortic insufficiency").isEmpty)
        XCTAssertTrue(valveIDs("denies mitral insufficiency").isEmpty)
    }

    func testTheBarChipsNameInsufficiencyAsRegurgitation() {
        let q = quick("severe AI, mild mitral insufficiency")
        let chips = QuickAdd.chips(q, record: PatientRecord()).map(\.value)
        XCTAssertTrue(chips.contains("Aortic regurgitation, severe"), chips.joined(separator: " | "))
        XCTAssertTrue(chips.contains("Mitral regurgitation, mild"), chips.joined(separator: " | "))
    }

    // MARK: Note 7: shorthand with a severity word in front or behind

    func testEachShorthandWithTheGradeInFront() {
        XCTAssertEqual(change("severe AS", "problem:as"), .valve("aortic", "stenosis", "severe"))
        XCTAssertEqual(change("moderate AI", "valve:aortic:regurgitation"), .valve("aortic", "regurgitation", "moderate"))
        XCTAssertEqual(change("mild AR", "valve:aortic:regurgitation"), .valve("aortic", "regurgitation", "mild"))
        XCTAssertEqual(change("severe MS", "valve:mitral:stenosis"), .valve("mitral", "stenosis", "severe"))
        XCTAssertEqual(change("mod MR", "problem:mr"), .valve("mitral", "regurgitation", "moderate"), "mod is moderate")
        XCTAssertEqual(change("moderate TS", "valve:tricuspid:stenosis"), .valve("tricuspid", "stenosis", "moderate"))
        XCTAssertEqual(change("severe TR", "valve:tricuspid:regurgitation"), .valve("tricuspid", "regurgitation", "severe"))
        XCTAssertEqual(change("severe PS", "problem:valve-severe"), .problem("valve-severe"))
        XCTAssertEqual(change("severe PR", "problem:valve-severe"), .problem("valve-severe"))
        XCTAssertEqual(change("severe PI", "problem:valve-severe"), .problem("valve-severe"))
    }

    func testEachShorthandWithTheGradeBehind() {
        XCTAssertEqual(change("AS severe", "problem:as"), .valve("aortic", "stenosis", "severe"))
        XCTAssertEqual(change("AI moderate", "valve:aortic:regurgitation"), .valve("aortic", "regurgitation", "moderate"))
        XCTAssertEqual(change("AR mild", "valve:aortic:regurgitation"), .valve("aortic", "regurgitation", "mild"))
        XCTAssertEqual(change("MS severe", "valve:mitral:stenosis"), .valve("mitral", "stenosis", "severe"))
        XCTAssertEqual(change("MR: moderate", "problem:mr"), .valve("mitral", "regurgitation", "moderate"))
        XCTAssertEqual(change("TS moderate", "valve:tricuspid:stenosis"), .valve("tricuspid", "stenosis", "moderate"))
        XCTAssertEqual(change("TR severe", "valve:tricuspid:regurgitation"), .valve("tricuspid", "regurgitation", "severe"))
        XCTAssertEqual(change("PS severe", "problem:valve-severe"), .problem("valve-severe"))
        XCTAssertEqual(change("PR severe", "problem:valve-severe"), .problem("valve-severe"))
        XCTAssertEqual(change("PI severe", "problem:valve-severe"), .problem("valve-severe"))
    }

    func testRangesAndTheHighestGradeIsFiled() {
        XCTAssertEqual(change("mild to moderate AR", "valve:aortic:regurgitation"), .valve("aortic", "regurgitation", "moderate"))
        XCTAssertEqual(change("moderate-to-severe TR", "valve:tricuspid:regurgitation"), .valve("tricuspid", "regurgitation", "severe"))
        XCTAssertEqual(change("mild-moderate MR", "problem:mr"), .valve("mitral", "regurgitation", "moderate"))
        XCTAssertEqual(change("AR mild to moderate", "valve:aortic:regurgitation"), .valve("aortic", "regurgitation", "moderate"))
        XCTAssertEqual(change("moderate to severe aortic stenosis", "problem:as"), .valve("aortic", "stenosis", "severe"))
        XCTAssertEqual(change("aortic stenosis severe", "problem:as"), .valve("aortic", "stenosis", "severe"), "the grade behind the words")
        XCTAssertEqual(change("mitral regurgitation: moderate", "problem:mr"), .valve("mitral", "regurgitation", "moderate"))
    }

    func testEachLesionKeepsItsOwnGradeInAList() {
        let r = read("severe AS, mod MR, mild TR")
        func g(_ id: String) -> PatientNoteChange? { r.findings.first { $0.id == id }?.change }
        XCTAssertEqual(g("problem:as"), .valve("aortic", "stenosis", "severe"))
        XCTAssertEqual(g("problem:mr"), .valve("mitral", "regurgitation", "moderate"))
        XCTAssertEqual(g("valve:tricuspid:regurgitation"), .valve("tricuspid", "regurgitation", "mild"))
        // A grade behind belongs to its own letters, not to the next lesion's.
        let behind = read("AS severe, MR mild")
        XCTAssertEqual(behind.findings.first { $0.id == "problem:as" }?.change, .valve("aortic", "stenosis", "severe"))
        XCTAssertEqual(behind.findings.first { $0.id == "problem:mr" }?.change, .valve("mitral", "regurgitation", "mild"))
        let front = read("MR severe AS")
        XCTAssertEqual(front.findings.first { $0.id == "problem:as" }?.change, .valve("aortic", "stenosis", "severe"), "the severe is the AS's")
        XCTAssertNotEqual(front.findings.first { $0.id == "problem:mr" }?.change, .valve("mitral", "regurgitation", "severe"), "and not the MR's")
    }

    func testTraceMeansTrivialAndIsNotValveDisease() {
        XCTAssertTrue(valveIDs("trace TR").isEmpty)
        XCTAssertTrue(valveIDs("trivial MR").isEmpty)
        XCTAssertTrue(valveIDs("trace TR, trivial MR, trace AI").isEmpty)
        XCTAssertTrue(valveIDs("TR trace").isEmpty)
    }

    func testTheShorthandFilesWhatTheSpelledOutWordsFile() {
        for (short, written) in [("severe AS", "severe aortic stenosis"), ("mod MR", "moderate mitral regurgitation"), ("mild AR", "mild aortic regurgitation"),
                                 ("severe MS", "severe mitral stenosis"), ("moderate TS", "moderate tricuspid stenosis"),
                                 ("severe TR", "severe tricuspid regurgitation"), ("moderate AI", "moderate aortic insufficiency"),
                                 ("severe PS", "severe pulmonic stenosis"), ("severe PR", "severe pulmonic regurgitation")] {
            let a = read(short).findings.filter { $0.section == PatientNote.Part.history }.map { [$0.id, $0.label] }
            let b = read(written).findings.filter { $0.section == PatientNote.Part.history }.map { [$0.id, $0.label] }
            XCTAssertFalse(a.isEmpty, short)
            XCTAssertEqual(a, b, short)
        }
        // And the record they fill is the same.
        XCTAssertEqual(applied("severe AS, mod MR").hx.valves, applied("severe aortic stenosis, moderate mitral regurgitation").hx.valves)
    }

    func testTheQuickAddBarReadsTheShorthand() {
        let q = quick("severe AS, mod MR, mild to moderate AR, TR severe")
        let ids = Set(q.findings.map(\.id))
        for id in ["problem:as", "problem:mr", "valve:aortic:regurgitation", "valve:tricuspid:regurgitation"] { XCTAssertTrue(ids.contains(id), id + " in " + ids.sorted().joined(separator: " | ")) }
        let chips = QuickAdd.chips(q, record: PatientRecord()).map(\.value)
        XCTAssertTrue(chips.contains("Aortic stenosis, severe"), chips.joined(separator: " | "))
        XCTAssertTrue(chips.contains("Mitral regurgitation, moderate"), chips.joined(separator: " | "))
        XCTAssertTrue(chips.contains("Aortic regurgitation, moderate"), chips.joined(separator: " | "))
        XCTAssertTrue(chips.contains("Tricuspid regurgitation, severe"), chips.joined(separator: " | "))
        // The same line filed into a record.
        var r = PatientRecord()
        let changes = QuickAdd.changes(QuickAdd.chips(q, record: r))
        PatientNote.apply(changes, to: &r)
        XCTAssertEqual(r.hx.valve("aortic"), PatientValve(stenosis: true, stenosisGrade: "severe", regurgitation: true, regurgitationGrade: "moderate"))
        XCTAssertEqual(r.hx.valve("mitral"), PatientValve(regurgitation: true, regurgitationGrade: "moderate"))
        XCTAssertEqual(r.hx.valve("tricuspid"), PatientValve(regurgitation: true, regurgitationGrade: "severe"))
    }

    func testCapitalsOnly() {
        for s in ["pain as needed", "severe as needed", "mod mr smith", "mild ai tools", "trace tr", "severe ms", "mild pr", "ps 10/5", "moderate pi", "as severe as it gets"] {
            XCTAssertTrue(valveIDs(s).isEmpty, s + ": " + valveIDs(s).joined(separator: " | "))
        }
        XCTAssertTrue(valveIDs("Mr Smith, mild Ai").isEmpty)
    }

    // MARK: Note 7: the letters that ask

    func testAmbiguousLettersAskWhenNothingSettlesThem() {
        for letters in ["MS", "PS", "PR", "AS", "AI", "PI"] {
            let r = read(letters + ", HTN")
            XCTAssertTrue(r.ambiguous.contains { $0.abbreviation == letters && !$0.fromContext }, letters + " is asked: " + r.ambiguous.map(\.abbreviation).joined(separator: ","))
        }
        // A bare one files no valve disease in silence: the default reading of the ones that could be a valve says so.
        XCTAssertNotNil(read("AS, HTN").findings.first { $0.id == "problem:as" }?.note, "read as aortic stenosis; said so")
        XCTAssertTrue(valveIDs("PI, HTN").isEmpty, "the pulsatility index is the usual reading of PI")
        XCTAssertTrue(valveIDs("PR, HTN").isEmpty, "a bare pulmonic regurgitation is not filed")
    }

    func testTheContextSettlesWhatTheLettersMean() {
        XCTAssertEqual(meaning("AS", in: "AS with fusion of the spine")?.meaning?.text, "ankylosing spondylitis")
        XCTAssertEqual(meaning("AS", in: "AS with fusion of the spine")?.fromContext, true)
        XCTAssertEqual(meaning("AS", in: "severe AS")?.meaning?.text, "aortic stenosis")
        XCTAssertEqual(meaning("AS", in: "AS severe")?.meaning?.text, "aortic stenosis")
        XCTAssertEqual(meaning("AS", in: "AS severe")?.fromContext, true)
        XCTAssertEqual(meaning("AS", in: "echo: AS, EF 55%")?.meaning?.text, "aortic stenosis")
        XCTAssertEqual(meaning("AS", in: "AS per protocol")?.meaning?.text, "as")
        XCTAssertEqual(meaning("AI", in: "dictated with an AI scribe")?.meaning?.text, "artificial intelligence")
        XCTAssertEqual(meaning("AI", in: "severe AI")?.meaning?.text, "aortic regurgitation")
        XCTAssertEqual(meaning("AI", in: "AI mild")?.meaning?.text, "aortic regurgitation")
        XCTAssertEqual(meaning("MS", in: "MS moderate")?.meaning?.text, "mitral stenosis")
        XCTAssertEqual(meaning("MS", in: "MS, mild weakness on ocrelizumab")?.meaning?.text, "multiple sclerosis")
        XCTAssertEqual(meaning("PS", in: "severe PS")?.meaning?.text, "pulmonic stenosis")
        XCTAssertEqual(meaning("PS", in: "PS 10/5")?.meaning?.text, "pressure support")
        XCTAssertEqual(meaning("PR", in: "PR severe")?.meaning?.text, "pulmonic regurgitation")
        XCTAssertEqual(meaning("PR", in: "ECG: NSR, PR 220")?.meaning?.text, "PR interval")
        XCTAssertEqual(meaning("PR", in: "PR 220")?.meaning?.text, "PR interval")
        XCTAssertEqual(meaning("PR", in: "mild PR prolongation")?.meaning?.text, "PR interval")
        XCTAssertEqual(meaning("PI", in: "severe PI")?.meaning?.text, "pulmonic regurgitation")
        let pump = meaning("PI", in: "HeartMate 3 LVAD 5400 rpm, PI 4.1, 4.8 L/min")
        XCTAssertEqual(pump?.meaning?.text, "pulsatility index")
        XCTAssertEqual(pump?.fromContext, true, "a pump's index is not asked")
        XCTAssertEqual(pump?.meaning?.reading, "PI", "and is read as written")
    }

    func testFalsePositiveLinesFileNoValve() {
        for line in ["PS 10/5", "PR interval 220", "MS Contin", "hx MS on ocrelizumab", "AS per protocol", "MR brain", "TR band", "AR glasses",
                     "ECG: NSR, PR 220", "MR angiography: no CAD", "cardiac MR next week", "ankylosing spondylitis (AS) with fusion of the spine",
                     "PS 12 PEEP 5 on the vent", "TI resection for Crohn disease"] {
            XCTAssertTrue(valveIDs(line).isEmpty, line + ": " + valveIDs(line).joined(separator: " | "))
            let q = quick(line)
            XCTAssertFalse(q.findings.contains { isValveID($0.id) },
                           "the bar: " + line + ": " + q.findings.map(\.id).joined(separator: " | "))
        }
    }

    func testAnEcgRunIsTheEcgs() {
        let q = quick("ECG: NSR, PR 220")
        XCTAssertFalse(q.findings.contains { $0.id.hasPrefix("valve:") || $0.id == "problem:valve-severe" })
        XCTAssertTrue(q.ambiguous.allSatisfy { $0.abbreviation != "PR" }, "the PR interval is settled by the ECG, not asked")
    }

    func testTheLettersAreInTheListAndTheOthersAreNot() {
        XCTAssertEqual(MedAbbreviations.lookup("AI")?.isAmbiguous, true)
        XCTAssertEqual(MedAbbreviations.lookup("PI")?.isAmbiguous, true)
        XCTAssertEqual(MedAbbreviations.lookup("PI")?.meanings.first?.id, "pi-pulsatility", "the usual reading of PI files nothing")
        XCTAssertEqual(MedAbbreviations.lookup("AS")?.meanings.map(\.id), ["as-aortic", "as-spondylitis", "as-word"])
        XCTAssertEqual(MedAbbreviations.lookup("MS")?.meanings.map(\.id), ["ms-sclerosis", "ms-mitral", "ms-morphine"], "unchanged")
        for k in ["MR", "TR", "AR", "TS"] { XCTAssertEqual(MedAbbreviations.lookup(k)?.isAmbiguous, false, k) }
        XCTAssertEqual(MedAbbreviations.lookup("TI")?.reads, false, "TI is read only with a grade")
        XCTAssertNil(MedAbbreviations.lookup("ai"), "capitals only")
        XCTAssertNil(MedAbbreviations.lookup("mr"))
        XCTAssertFalse(MedAbbreviations.scan("TI resection for Crohn disease").contains { $0.key == "TI" }, "the terminal ileum")
        XCTAssertTrue(MedAbbreviations.scan("mild TI").contains { $0.key == "TI" })
    }

    // MARK: Note 7: behind an echo cue

    func testBehindAnEchoCueTheLesionIsTheEchosFinding() {
        let r = read("TTE: severe AS, mod MR")
        func g(_ id: String) -> PatientNoteChange? { r.findings.first { $0.id == id }?.change }
        XCTAssertEqual(g("echo:aortic:stenosis"), .echoValve("aortic", "stenosis", .severe))
        XCTAssertEqual(g("echo:mitral:regurgitation"), .echoValve("mitral", "regurgitation", .moderate))
        // The history's valve disease is filed as it is for the spelled-out words.
        XCTAssertEqual(g("problem:as"), .valve("aortic", "stenosis", "severe"))
        XCTAssertEqual(g("problem:mr"), .valve("mitral", "regurgitation", "moderate"))
        XCTAssertEqual(r.findings.first { $0.id == "echo:aortic:stenosis" }?.section, PatientNote.Part.assessment)
        // The spelled-out words do the same.
        XCTAssertEqual(change("Echo: severe aortic stenosis", "echo:aortic:stenosis"), .echoValve("aortic", "stenosis", .severe))
        XCTAssertEqual(change("TEE showed moderate mitral insufficiency", "echo:mitral:regurgitation"), .echoValve("mitral", "regurgitation", .moderate))
        XCTAssertEqual(change("severe AS on echo", "echo:aortic:stenosis"), .echoValve("aortic", "stenosis", .severe))
        XCTAssertEqual(change("Echo: EF 55%, AS severe", "echo:aortic:stenosis"), .echoValve("aortic", "stenosis", .severe))
    }

    func testTraceBehindAnEchoCueIsTrivialRegurgitation() {
        XCTAssertEqual(change("Echo: trace TR", "echo:tricuspid:regurgitation"), .echoValve("tricuspid", "regurgitation", .trivial))
        XCTAssertEqual(change("TTE with trivial MR", "echo:mitral:regurgitation"), .echoValve("mitral", "regurgitation", .trivial))
        XCTAssertEqual(change("Echo: EF 55%, trace TR, trivial AI", "echo:aortic:regurgitation"), .echoValve("aortic", "regurgitation", .trivial))
        // Not disease: no history item.
        XCTAssertTrue(read("Echo: trace TR").findings.allSatisfy { !$0.id.hasPrefix("valve:") && $0.id != "problem:mr" })
        // And away from an echo, trace files nothing at all.
        XCTAssertTrue(valveIDs("trace TR").isEmpty)
        // Stenosis has no trivial grade.
        XCTAssertTrue(valveIDs("Echo: trace AS").isEmpty)
    }

    func testNoEchoCueNoEchoFinding() {
        XCTAssertNil(change("severe AS", "echo:aortic:stenosis"))
        XCTAssertNil(change("scheduled for TEE, has severe AS", "echo:aortic:stenosis"), "an echo still to come reports nothing")
        XCTAssertNotNil(change("scheduled for TEE, has severe AS", "problem:as"), "the history is filed")
        XCTAssertNil(change("TEE tomorrow, severe AS", "echo:aortic:stenosis"), "a cue does not reach past a comma without a heading")
        XCTAssertNil(change("Echo: EF 55%. Severe AS", "echo:aortic:stenosis"), "a new sentence ends the echo")
        XCTAssertNil(change("Echo: severe pulmonic stenosis", "echo:pulmonic:stenosis"), "the echo has no pulmonic valve")
        XCTAssertNil(change("Echo: AS", "echo:aortic:stenosis"), "ungraded: no grade to file")
        XCTAssertNil(change("Echo: no aortic stenosis", "echo:aortic:stenosis"), "negated")
        XCTAssertFalse(PatientNote.echoCued("severe aortic stenosis", NSRange(location: 0, length: 6)))
        XCTAssertTrue(PatientNote.echoCued("TTE: severe aortic stenosis", NSRange(location: 5, length: 22)))
    }

    func testTheEchoFindingFillsTheEchoAndShowsItsStatus() {
        var r = PatientRecord()
        let f = read("TTE: severe AS, trace TR").findings
        let aortic = f.first { $0.id == "echo:aortic:stenosis" }!
        XCTAssertEqual(PatientNote.status(aortic, in: r), .new)
        PatientNote.apply(f.map(\.change), to: &r)
        XCTAssertEqual(r.echoFindings.aortic.stenosis, .severe)
        XCTAssertEqual(r.echoFindings.tricuspid.regurgitation, .trivial)
        XCTAssertNil(r.echoFindings.mitral.regurgitation, "nothing else is set")
        XCTAssertEqual(r.echoFindings.phrases, ["Trivial TR", "Severe AS"])
        XCTAssertEqual(PatientNote.status(aortic, in: r), .recorded)
        r.echoFindings.aortic.stenosis = .moderate
        XCTAssertEqual(PatientNote.status(aortic, in: r), .replaces("moderate"))
        r.echoFindings.aortic.stenosis = .normal
        XCTAssertEqual(PatientNote.status(aortic, in: r), .replaces("none"))
        // A grade already recorded is replaced only by applying the finding.
        PatientNote.apply([aortic.change], to: &r)
        XCTAssertEqual(r.echoFindings.aortic.stenosis, .severe)
    }

    func testTheBarFilesTheEchoFindingOnThePreoperativeTabOnly() {
        let q = quick("TTE: severe AS, trace TR")
        let chips = QuickAdd.chips(q, record: PatientRecord())
        XCTAssertTrue(chips.contains { $0.destination == "Echo" && $0.value == "Severe AS" }, chips.map(\.text).joined(separator: " | "))
        XCTAssertTrue(chips.contains { $0.destination == "Echo" && $0.value == "Trivial TR" }, chips.map(\.text).joined(separator: " | "))
        XCTAssertTrue(chips.contains { $0.destination == "History" && $0.value == "Aortic stenosis, severe" })
        var r = PatientRecord()
        PatientNote.apply(QuickAdd.changes(chips), to: &r)
        XCTAssertEqual(r.echoFindings.aortic.stenosis, .severe)
        XCTAssertEqual(r.hx.valve("aortic").stenosisGrade, "severe")
        // The Intraoperative tab files neither: they are the preoperative record.
        let intraop = quick("TTE: severe AS, trace TR", tab: .intraop)
        XCTAssertFalse(intraop.findings.contains { $0.id.hasPrefix("echo:") || $0.id == "problem:as" })
        XCTAssertTrue(intraop.skipped.contains(QuickAdd.historyElsewhere))
    }

    func testEveryNewPatternCompiles() {
        for rx in PatientNote.allPatterns + MedAbbreviations.allPatterns { XCTAssertNotNil(rx.re, rx.pattern) }
    }
}
