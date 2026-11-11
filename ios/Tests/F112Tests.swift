import XCTest
@testable import PeriopSignal

/// 1.12 helper F (Ben, Nov 11): a Malignancy item on the Heme & Oncology page (the common cancers, several at once; Other;
/// status; Metastatic; treatment), how it is summarized and typed, and "ECMO reconfiguration" in the procedure list.
final class F112Tests: XCTestCase {
    private var now: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 8))! }

    private func adult(_ problems: Set<String> = []) -> PatientRecord {
        var r = PatientRecord()
        r.ageYears = 60
        r.problems = problems
        return r
    }

    private var item: HistorySection { HistorySections.heme.first { $0.id == "malignancy" }! }

    private func read(_ s: String) -> PatientNoteReading { PatientNote.read(s, now: now) }
    private func malignancy(_ s: String) -> [PatientNoteFinding] { read(s).findings.filter { $0.id.hasPrefix("problem:malignancy") } }
    private func quickMalignancy(_ s: String) -> [PatientNoteFinding] {
        QuickAdd.read(s, record: PatientRecord(), tab: .preop, now: now).findings.filter { $0.id.hasPrefix("problem:malignancy") }
    }
    private func applied(_ s: String) -> PatientRecord {
        var r = PatientRecord()
        PatientNote.apply(read(s).findings.map(\.change), to: &r)
        return r
    }
    private func quickApplied(_ s: String) -> PatientRecord {
        var r = PatientRecord()
        PatientNote.apply(QuickAdd.read(s, record: PatientRecord(), tab: .preop, now: now).findings.map(\.change), to: &r)
        return r
    }
    /// What a typed record says, as the finding keeps it.
    private func typed(_ f: PatientNoteFinding) -> PatientMalignancy.Typed? {
        if case .detail(_, "malignancy", let v) = f.change { return PatientMalignancy.decode(v) }
        return nil
    }

    // MARK: 1. The page and the list

    func testTheSystemIsHemeAndOncologyWithOneMalignancyItem() throws {
        let heme = try XCTUnwrap(PatientCatalog.systems.first { $0.id == "heme" })
        XCTAssertEqual(heme.name, "Heme & Oncology")
        XCTAssertEqual(heme.problems.last?.id, "malignancy")
        XCTAssertEqual(heme.problems.last?.label, "Malignancy")
        XCTAssertEqual(HistorySections.otherTitle("heme"), "Other hematologic disorders", "its wording stays")
        XCTAssertEqual(HistorySections.heme.dropLast(2).last?.id, "malignancy", "the last item before the two closing fields")
        XCTAssertEqual(item.title, "Malignancy")
    }

    func testTheCommonCancersAreOnePlainList() {
        XCTAssertEqual(PatientMalignancy.sites.map(\.label),
                       ["Lung", "Esophageal", "Head and neck", "Thyroid", "Colorectal", "Gastric", "Pancreatic", "Liver (HCC)", "Prostate", "Bladder", "Kidney",
                        "Ovarian", "Uterine", "Cervical", "Breast", "Melanoma", "Lymphoma", "Leukemia", "Multiple myeloma", "Brain", "Sarcoma"])
        XCTAssertEqual(Set(PatientMalignancy.sites.map(\.id)).count, 21, "ids are unique")
        let words = Dictionary(uniqueKeysWithValues: PatientMalignancy.sites.map { ($0.id, $0.words) })
        XCTAssertEqual(words["lung"], "lung cancer")
        XCTAssertEqual(words["liver"], "hepatocellular carcinoma")
        XCTAssertEqual(words["lymphoma"], "lymphoma")
        XCTAssertEqual(words["myeloma"], "multiple myeloma")
        XCTAssertEqual(PatientMalignancy.statuses.map(\.label), ["Active", "In remission"])
        XCTAssertEqual(PatientMalignancy.treatments.map(\.label), ["Chemotherapy", "Radiation"])
    }

    func testTheChipRowsKeepTheOneLineRule() {
        // Under the item's title on a 375-pt phone (PatientHistorySections.section: 40 + 48 + 14 around the row).
        let row: CGFloat = 375 - 40 - 48 - 14
        let cancers = PatientMalignancy.sites.map { ChipChoice($0.id, $0.label) } + [ChipChoice("other", "Other")]
        XCTAssertNil(ChipMetrics.lineFit(cancers, choice: false, in: row), "the long list wraps, as the other long lists do")
        XCTAssertNil(ChipMetrics.lineFit(cancers, choice: false, in: 402 - 40 - 48 - 14))
        let status = PatientMalignancy.statuses.map { ChipChoice($0.id, $0.label) }
        XCTAssertNotNil(ChipMetrics.lineFit(status, choice: true, in: row), "Active · In remission on one line")
        let treatment = PatientMalignancy.treatments.map { ChipChoice($0.id, $0.label) }
        XCTAssertNotNil(ChipMetrics.lineFit(treatment, choice: false, in: row, selected: ["chemo", "radiation"]), "Chemotherapy · Radiation, both chosen, on one line")
        XCTAssertNotNil(ChipMetrics.lineFit([ChipChoice("metastatic", "Metastatic")], choice: false, in: row, selected: ["metastatic"]))
    }

    // MARK: 2. What is recorded

    func testSeveralCancersCanBeChosen() {
        var r = PatientRecord()
        HistorySections.select(item, &r)
        XCTAssertTrue(r.has("malignancy"))
        XCTAssertTrue(HistorySections.isSelected(item, system: "heme", r))
        PatientMalignancy.setSites(["breast", "lung", "lymphoma"], &r)
        XCTAssertEqual(PatientMalignancy.selected(r), ["lung", "breast", "lymphoma"])
        XCTAssertEqual(r.hx.malignancies, ["lung", "breast", "lymphoma"])
        XCTAssertEqual(PatientMalignancy.words(r), "lung cancer; breast cancer; lymphoma", "in the list's order, whatever the order chosen")
        PatientMalignancy.setSites(["lung"], &r)
        XCTAssertEqual(r.hx.malignancies, ["lung"])
        XCTAssertTrue(r.has("malignancy"), "the item stays chosen with its last cancer taken off")
        XCTAssertFalse(r.noHistory)
        var quiet = PatientRecord()
        quiet.noHistory = true
        PatientMalignancy.setSite("lung", true, &quiet)
        XCTAssertFalse(quiet.noHistory, "a cancer is a history")
    }

    func testStatusMetastaticAndTreatment() {
        var r = adult()
        PatientMalignancy.setSite("lung", true, &r)
        PatientMalignancy.setStatus("active", &r)
        PatientMalignancy.setMetastatic(true, &r)
        PatientMalignancy.setTreatment(["chemo", "radiation"], &r)
        XCTAssertEqual(PatientMalignancy.words(r), "lung cancer (active, metastatic; chemotherapy, radiation)")
        PatientMalignancy.setStatus("remission", &r)
        XCTAssertEqual(r.hx.malignancyStatus, "remission", "one status at a time")
        XCTAssertEqual(PatientMalignancy.words(r), "lung cancer (in remission, metastatic; chemotherapy, radiation)")
        PatientMalignancy.setStatus(nil, &r)
        XCTAssertNil(r.hx.malignancyStatus, "optional: a second tap clears it")
        PatientMalignancy.setStatus("not-a-status", &r)
        XCTAssertNil(r.hx.malignancyStatus)
        PatientMalignancy.setTreatment(["chemo"], &r)
        PatientMalignancy.setMetastatic(false, &r)
        XCTAssertEqual(PatientMalignancy.words(r), "lung cancer (chemotherapy)")
        PatientMalignancy.setTreatment(["chemo", "surgery"], &r)
        XCTAssertEqual(r.hx.malignancyTreatment, ["chemo"], "only the two treatments are kept")
        var bare = adult()
        PatientMalignancy.setMetastatic(true, &bare)
        XCTAssertTrue(bare.has("malignancy"), "a detail chosen chooses the item")
    }

    func testTheSummaryPhrases() {
        XCTAssertNil(PatientMalignancy.words(adult(["htn"])), "nothing recorded: nothing said")
        XCTAssertEqual(PatientMalignancy.words(adult(["malignancy"])), "malignancy", "chosen with nothing else")
        var remission = adult(["malignancy"])
        remission.hx.malignancies = ["breast", "lymphoma"]
        remission.hx.malignancyStatus = "remission"
        XCTAssertEqual(PatientMalignancy.words(remission), "breast cancer; lymphoma (in remission)")
        var other = adult(["malignancy"])
        other.hx.malignancyOther = "thymoma"
        XCTAssertEqual(PatientMalignancy.words(other), "thymoma", "the typed Other as typed")
        other.hx.malignancies = ["lung"]
        other.hx.malignancyMetastatic = true
        XCTAssertEqual(PatientMalignancy.words(other), "lung cancer; thymoma (metastatic)")
        var meta = adult(["malignancy"])
        meta.hx.malignancyMetastatic = true
        XCTAssertEqual(PatientMalignancy.words(meta), "malignancy (metastatic)")
        var all = adult(["anemia", "malignancy"])
        all.hx.malignancies = ["lung"]
        XCTAssertEqual(HistorySections.hemeItems(all), ["anemia", "lung cancer"], "with the hematologic problems")
        let heme = PatientCatalog.allSystems.first { $0.id == "heme" }!
        XCTAssertEqual(HistorySections.items(heme, all), ["anemia", "lung cancer"])
        XCTAssertEqual(PatientPreop.tileWords(heme, all), "Anemia; lung cancer", "the tile's subtitle")
    }

    func testClearingTheItemClearsEverythingUnderIt() {
        var r = adult()
        HistorySections.select(item, &r)
        PatientMalignancy.setSites(["lung", "prostate"], &r)
        r.hx.malignancyOther = "thymoma"
        PatientMalignancy.setStatus("active", &r)
        PatientMalignancy.setMetastatic(true, &r)
        PatientMalignancy.setTreatment(["radiation"], &r)
        HistorySections.clear(item, system: "heme", &r)
        XCTAssertTrue(r.problems.isEmpty, "the prostate problem goes with it: one fact")
        XCTAssertTrue(r.hx.malignancies.isEmpty)
        XCTAssertEqual(r.hx.malignancyOther, "")
        XCTAssertNil(r.hx.malignancyStatus)
        XCTAssertFalse(r.hx.malignancyMetastatic)
        XCTAssertTrue(r.hx.malignancyTreatment.isEmpty)
        XCTAssertFalse(HistorySections.isSelected(item, system: "heme", r))
    }

    func testNothingAboutACancerChangesTheAsaAScoreOrAnAlert() {
        let p = PatientCatalog.problem("malignancy")
        XCTAssertNotNil(p)
        XCTAssertNil(p?.asa); XCTAssertNil(p?.peds); XCTAssertNil(p?.rcri); XCTAssertNil(p?.stopBang)
        var r = adult(["malignancy"])
        r.hx.malignancies = ["lung", "lymphoma", "leukemia"]
        r.hx.malignancyStatus = "active"; r.hx.malignancyMetastatic = true; r.hx.malignancyTreatment = ["chemo", "radiation"]
        XCTAssertNil(PatientRules.asaSuggestion(r)?.level, "no class from a cancer")
        XCTAssertTrue(PatientRules.prefill("rcri", r).on.isEmpty)
        XCTAssertTrue(PatientWarnings.lines(r).isEmpty, "no warning")
        XCTAssertTrue(HistorySections.sections("heme")!.flatMap(\.members).contains("malignancy"))
        XCTAssertTrue(PatientWarnings.tags("malignancy", r).isEmpty)
        XCTAssertTrue(PatientWarnings.tags("prostate-cancer", r).isEmpty)
    }

    // MARK: 3. Prostate is one fact on two pages

    func testProstateIsTheGenitourinaryItem() throws {
        var r = PatientRecord()
        PatientMalignancy.setSite("prostate", true, &r)
        XCTAssertTrue(r.has("prostate-cancer"), "the chip writes the Genitourinary problem")
        XCTAssertTrue(r.has("malignancy"))
        XCTAssertTrue(r.hx.malignancies.isEmpty, "it is not stored twice")
        let gu = try XCTUnwrap(HistorySections.renal.first { $0.id == "prostate" })
        XCTAssertTrue(HistorySections.isSelected(gu, system: "renal", r))
        // Recorded on the Genitourinary page only: Malignancy shows it chosen.
        var g = adult(["prostate-cancer"])
        XCTAssertEqual(PatientMalignancy.selected(g), ["prostate"])
        XCTAssertTrue(HistorySections.isSelected(item, system: "heme", g), "the item opens with Prostate chosen")
        XCTAssertEqual(PatientMalignancy.words(g), "prostate cancer")
        PatientMalignancy.setSite("prostate", false, &g)
        XCTAssertFalse(g.has("prostate-cancer"), "taking the chip off takes it off the other page too")
        // Taking the Genitourinary item off takes the chip off.
        var h = adult(["prostate-cancer", "bph", "malignancy"])
        h.hx.malignancies = ["lung"]
        HistorySections.clear(gu, system: "renal", &h)
        XCTAssertEqual(PatientMalignancy.selected(h), ["lung"])
    }

    func testProstateCancerIsPrintedOnceInASummary() throws {
        var r = adult(["prostate-cancer", "bph", "malignancy"])
        r.hx.malignancies = ["lung"]
        r.hx.malignancyStatus = "active"
        let lines = PatientSummary.historyLines(r)
        XCTAssertEqual(lines.filter { $0.text.contains("prostate cancer") }.count, 1)
        XCTAssertEqual(lines.first { $0.label == "Heme & Oncology" }?.text, "lung cancer; prostate cancer (active)")
        XCTAssertEqual(lines.first { $0.label == "Renal" }?.text, "BPH")
        for blocks in [PatientBriefs.preop(r), PatientBriefs.handoff(r)] {
            let pmh = try XCTUnwrap(blocks.first { $0.key == "pmh" })
            XCTAssertEqual(pmh.text.components(separatedBy: "prostate cancer").count - 1, 1, pmh.text)
            XCTAssertTrue(pmh.text.contains("lung cancer; prostate cancer (active)"), pmh.text)
            XCTAssertFalse(pmh.text.contains("Heme & Oncology"), "no system label in the PMH")
        }
        // The pages and tiles each say what their page holds.
        let renal = PatientCatalog.allSystems.first { $0.id == "renal" }!
        let heme = PatientCatalog.allSystems.first { $0.id == "heme" }!
        XCTAssertEqual(HistorySections.items(renal, r), ["BPH", "prostate cancer"])
        XCTAssertEqual(PatientPreop.tileWords(renal, r), "BPH; prostate cancer")
        XCTAssertEqual(PatientPreop.tileWords(heme, r), "Lung cancer; prostate cancer (active)")
        XCTAssertEqual(HistorySections.renalItems(adult(["aki", "bph", "prostate-cancer"])), ["AKI", "BPH", "prostate cancer"])
    }

    func testThePhraseIsInThePMHAndTheHandoff() throws {
        var r = adult(["htn", "malignancy"])
        r.hx.malignancies = ["lung"]
        r.hx.malignancyStatus = "active"; r.hx.malignancyMetastatic = true; r.hx.malignancyTreatment = ["chemo", "radiation"]
        for blocks in [PatientBriefs.preop(r), PatientBriefs.handoff(r)] {
            let pmh = try XCTUnwrap(blocks.first { $0.key == "pmh" })
            XCTAssertTrue(pmh.text.contains("lung cancer (active, metastatic; chemotherapy, radiation)"), pmh.text)
        }
    }

    // MARK: 4. Saved records keep opening

    func testARecordSavedBefore112Opens() throws {
        let json = #"{"problems":["prostate-cancer","anemia"],"hx":{"thyroidType":"hypo","vteDate":"09/2026"}}"#
        let r = try JSONDecoder().decode(PatientRecord.self, from: Data(json.utf8))
        XCTAssertTrue(r.hx.malignancies.isEmpty)
        XCTAssertEqual(r.hx.malignancyOther, "")
        XCTAssertNil(r.hx.malignancyStatus)
        XCTAssertFalse(r.hx.malignancyMetastatic)
        XCTAssertTrue(r.hx.malignancyTreatment.isEmpty)
        XCTAssertEqual(r.hx.thyroidType, "hypo", "the rest of the details are kept")
        XCTAssertEqual(PatientMalignancy.words(r), "prostate cancer", "its prostate cancer opens as Malignancy with Prostate chosen")
        XCTAssertEqual(PatientMalignancy.selected(r), ["prostate"])
        let empty = try JSONDecoder().decode(PatientHistoryDetails.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, PatientHistoryDetails())
    }

    func testTheNewFieldsRoundTrip() throws {
        var r = adult(["malignancy"])
        r.hx.malignancies = ["lung", "breast"]
        r.hx.malignancyOther = "thymoma"
        r.hx.malignancyStatus = "remission"
        r.hx.malignancyMetastatic = true
        r.hx.malignancyTreatment = ["chemo", "radiation"]
        let back = try JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back.hx, r.hx)
        XCTAssertEqual(PatientMalignancy.words(back), PatientMalignancy.words(r))
    }

    // MARK: 5. Typing: a cancer

    func testTheCommonCancersAreRead() {
        let lines: [(String, String)] = [
            ("lung cancer", "lung"), ("NSCLC", "lung"), ("non-small cell lung cancer", "lung"), ("breast ca", "breast"), ("Breast Ca", "breast"),
            ("breast cancer", "breast"), ("colon cancer", "colorectal"), ("colorectal cancer", "colorectal"), ("rectal adenocarcinoma", "colorectal"),
            ("HCC", "liver"), ("hcc", "liver"), ("hepatocellular carcinoma", "liver"), ("lymphoma", "lymphoma"), ("Hodgkin lymphoma", "lymphoma"),
            ("leukemia", "leukemia"), ("AML", "leukemia"), ("multiple myeloma", "myeloma"), ("melanoma", "melanoma"),
            ("pancreatic carcinoma", "pancreatic"), ("gastric cancer", "gastric"), ("bladder cancer", "bladder"), ("RCC", "kidney"),
            ("renal cell carcinoma", "kidney"), ("kidney cancer", "kidney"), ("ovarian cancer", "ovarian"), ("endometrial cancer", "uterine"),
            ("cervical cancer", "cervical"), ("thyroid cancer", "thyroid"), ("papillary thyroid carcinoma", "thyroid"),
            ("esophageal cancer", "esophageal"), ("SCC of the head and neck", "head-neck"), ("squamous cell carcinoma of the larynx", "head-neck"),
            ("tongue cancer", "head-neck"), ("osteosarcoma", "sarcoma"), ("glioblastoma", "brain"), ("brain cancer", "brain"),
        ]
        for (line, site) in lines {
            for r in [applied(line), quickApplied("54F, HTN, " + line)] {
                XCTAssertTrue(r.has("malignancy"), line)
                XCTAssertEqual(r.hx.malignancies, [site], line)
            }
        }
    }

    func testSomeCancerWordsAreNotRead() {
        for line in ["MM", "SCC", "squamous cell carcinoma of the skin", "basal cell carcinoma", "ductal carcinoma in situ", "cervical spine fusion",
                     "Ca 8.9", "breast ca 8.9", "cancer center"] {
            XCTAssertTrue(malignancy(line).isEmpty, line + ": " + malignancy(line).map(\.label).joined(separator: ", "))
            XCTAssertFalse(applied(line).has("malignancy"), line)
        }
    }

    func testSeveralCancersInOneLineAreOneFinding() throws {
        let f = malignancy("lung cancer, breast cancer, lymphoma")
        XCTAssertEqual(f.map(\.id), ["problem:malignancy"])
        XCTAssertEqual(f.first.flatMap(typed)?.sites, ["lung", "breast", "lymphoma"])
        XCTAssertEqual(applied("lung cancer, breast cancer, lymphoma").hx.malignancies, ["lung", "breast", "lymphoma"])
        XCTAssertEqual(f.first?.label, "Malignancy: lung cancer; breast cancer; lymphoma")
    }

    func testACancerNotOnTheListIsKeptAsTyped() {
        let r = applied("testicular cancer")
        XCTAssertTrue(r.has("malignancy"))
        XCTAssertTrue(r.hx.malignancies.isEmpty)
        XCTAssertEqual(r.hx.malignancyOther, "testicular cancer")
        XCTAssertEqual(PatientMalignancy.words(r), "testicular cancer")
        XCTAssertEqual(applied("cholangiocarcinoma").hx.malignancyOther, "cholangiocarcinoma")
    }

    func testAnUnnamedCancerIsTheItemAlone() {
        for line in ["history of cancer", "malignancy", "carcinoma"] {
            let f = malignancy(line)
            XCTAssertEqual(f.map(\.id), ["problem:malignancy"], line)
            let r = applied(line)
            XCTAssertTrue(r.has("malignancy"), line)
            XCTAssertEqual(PatientMalignancy.words(r), "malignancy", line)
        }
        let m = applied("metastatic cancer")
        XCTAssertTrue(m.hx.malignancyMetastatic)
        XCTAssertEqual(PatientMalignancy.words(m), "malignancy (metastatic)")
    }

    // MARK: 6. Typing: the state and the treatment

    func testMetastaticStatusAndTreatmentAreFiled() {
        let metastatic = applied("metastatic lung cancer")
        XCTAssertTrue(metastatic.hx.malignancyMetastatic)
        XCTAssertEqual(metastatic.hx.malignancies, ["lung"])
        for line in ["lung cancer with mets", "lung ca, metastatic", "lung cancer, mets"] {
            XCTAssertTrue(applied(line).hx.malignancyMetastatic, line)
        }
        XCTAssertEqual(applied("lymphoma in remission").hx.malignancyStatus, "remission")
        XCTAssertEqual(applied("lymphoma, in remission").hx.malignancyStatus, "remission")
        XCTAssertEqual(applied("active lung cancer").hx.malignancyStatus, "active")
        XCTAssertEqual(applied("lung cancer s/p chemo").hx.malignancyTreatment, ["chemo"])
        XCTAssertEqual(applied("lung cancer s/p chemoradiation").hx.malignancyTreatment, ["chemo", "radiation"])
        XCTAssertEqual(applied("lung cancer s/p XRT").hx.malignancyTreatment, ["radiation"])
        XCTAssertEqual(applied("breast cancer on chemo and XRT").hx.malignancyTreatment, ["chemo", "radiation"])
        let all = applied("metastatic lung cancer s/p chemo and XRT")
        XCTAssertEqual(PatientMalignancy.words(all), "lung cancer (metastatic; chemotherapy, radiation)")
        let comma = applied("lung cancer, metastatic, on chemo")
        XCTAssertEqual(PatientMalignancy.words(comma), "lung cancer (metastatic; chemotherapy)")
    }

    func testOnlyTheWordsAboutACancerAreFiled() {
        // METs are not metastases, and a status or treatment with no cancer files nothing.
        let mets = applied("lung cancer, <4 METs")
        XCTAssertFalse(mets.hx.malignancyMetastatic)
        XCTAssertEqual(applied("4 METs").hx.malignancyMetastatic, false)
        XCTAssertFalse(applied("in remission").has("malignancy"))
        XCTAssertFalse(applied("s/p chemo").has("malignancy"))
        XCTAssertFalse(applied("metastatic").has("malignancy"))
        XCTAssertFalse(applied("alcohol use disorder in remission").has("malignancy"))
        // Said not to be.
        let non = applied("lung cancer, no mets")
        XCTAssertEqual(non.hx.malignancies, ["lung"])
        XCTAssertFalse(non.hx.malignancyMetastatic)
        XCTAssertFalse(applied("non-metastatic breast cancer").hx.malignancyMetastatic)
        XCTAssertNil(applied("lymphoma in partial remission").hx.malignancyStatus)
    }

    func testChemoIsNotAPastOperation() {
        let r = read("lung cancer s/p chemo")
        XCTAssertFalse(r.findings.contains { $0.id.hasPrefix("psh:") })
        XCTAssertEqual(r.previous, "")
        XCTAssertEqual(r.other, "")
        XCTAssertEqual(applied("breast cancer s/p lumpectomy, chemo").hx.malignancyTreatment, ["chemo"])
    }

    func testCancersWithDifferentWordsAreSeparateFindings() throws {
        let line = "metastatic lung cancer s/p chemo, lymphoma in remission"
        let f = malignancy(line)
        XCTAssertEqual(f.map(\.id), ["problem:malignancy", "problem:malignancy#2"])
        let first = try XCTUnwrap(typed(f[0])), second = try XCTUnwrap(typed(f[1]))
        XCTAssertEqual(first.sites, ["lung"])
        XCTAssertTrue(first.metastatic)
        XCTAssertEqual(first.treatment, ["chemo"])
        XCTAssertNil(first.status)
        XCTAssertEqual(second.sites, ["lymphoma"])
        XCTAssertEqual(second.status, "remission")
        XCTAssertFalse(second.metastatic)
        XCTAssertTrue(second.treatment.isEmpty)
        XCTAssertEqual(f.map(\.label), ["Malignancy: lung cancer (metastatic; chemotherapy)", "Malignancy: lymphoma (in remission)"])
        XCTAssertNotNil(f[0].note, "the review says the state is kept for the whole list")
        // The quick-add bar gives the same two chips.
        XCTAssertEqual(quickMalignancy(line).map(\.label), f.map(\.label))
        // Nothing typed about one cancer is put on the other until the chips are added.
        var r = PatientRecord()
        PatientNote.apply([f[1].change], to: &r)
        XCTAssertEqual(r.hx.malignancies, ["lymphoma"])
        XCTAssertFalse(r.hx.malignancyMetastatic)
    }

    func testTheSameWordsInSeparateSentencesAreOneFinding() {
        let same = malignancy("Lung cancer in remission. Breast cancer in remission.")
        XCTAssertEqual(same.map(\.id), ["problem:malignancy"])
        XCTAssertEqual(same.first.flatMap(typed)?.sites, ["lung", "breast"])
        XCTAssertEqual(same.first.flatMap(typed)?.status, "remission")
        let differ = malignancy("Lung cancer in remission. Breast cancer.")
        XCTAssertEqual(differ.map(\.id), ["problem:malignancy", "problem:malignancy#2"])
    }

    func testProstateWithItsStateFilesBothPlaces() {
        let plain = read("prostate cancer")
        XCTAssertEqual(plain.findings.map(\.id).filter { $0.hasPrefix("problem:") }, ["problem:prostate-cancer"], "as before: only the existing item")
        let r = applied("metastatic prostate cancer")
        XCTAssertTrue(r.has("prostate-cancer"))
        XCTAssertTrue(r.has("malignancy"))
        XCTAssertTrue(r.hx.malignancyMetastatic)
        XCTAssertEqual(PatientMalignancy.selected(r), ["prostate"])
        XCTAssertEqual(PatientMalignancy.words(r), "prostate cancer (metastatic)")
        let mixed = applied("lung cancer, prostate cancer")
        XCTAssertEqual(PatientMalignancy.selected(mixed), ["lung", "prostate"])
        XCTAssertEqual(PatientMalignancy.words(mixed), "lung cancer; prostate cancer")
        XCTAssertTrue(quickApplied("54F, prostate cancer").has("prostate-cancer"))
    }

    func testTheReviewKnowsWhatIsAlreadyRecorded() throws {
        let f = try XCTUnwrap(malignancy("lung cancer in remission").first)
        var r = PatientRecord()
        XCTAssertEqual(PatientNote.status(f, in: r), .new)
        PatientNote.apply([f.change], to: &r)
        XCTAssertEqual(PatientNote.status(f, in: r), .recorded)
        r.hx.malignancyStatus = "active"
        XCTAssertEqual(PatientNote.status(f, in: r), .replaces("active"))
        PatientNote.apply([f.change], to: &r)
        XCTAssertEqual(r.hx.malignancyStatus, "remission")
        // A line that says less never takes anything off.
        PatientNote.apply([try XCTUnwrap(malignancy("breast cancer").first).change], to: &r)
        XCTAssertEqual(r.hx.malignancies, ["lung", "breast"])
        XCTAssertEqual(r.hx.malignancyStatus, "remission")
    }

    // MARK: 7. Typing: what is not the patient's

    func testNegationsFamilyHistoryAndScreensFileNothing() {
        let lines = ["no hx of cancer", "denies lung cancer", "mother had breast cancer", "FH colon cancer", "family history of breast cancer",
                     "cancer screening", "skin cancer screening", "BRCA positive", "at risk for lung cancer", "screening for lung cancer",
                     "rule out lymphoma", "possible lymphoma", "concern for melanoma"]
        for line in lines {
            XCTAssertTrue(malignancy(line).isEmpty, line + ": " + malignancy(line).map(\.label).joined(separator: ", "))
            XCTAssertFalse(applied(line).has("malignancy"), line)
            XCTAssertTrue(quickMalignancy("54F, " + line).isEmpty, "quick add: " + line)
        }
        XCTAssertTrue(quickMalignancy("no hx of cancer, mother had breast cancer, skin cancer screening, BRCA positive").isEmpty)
        // The patient's own, beside a relative's.
        XCTAssertEqual(applied("mother had breast cancer, patient has lymphoma").hx.malignancies, ["lymphoma"])
    }

    func testACancerWordInsideAProcedureNameStaysTheProcedures() {
        for line in ["ovarian cancer debulking", "melanoma excision", "excision of melanoma", "tongue cancer resection", "gallbladder cancer resection"] {
            XCTAssertTrue(malignancy("scheduled for " + line).isEmpty, line + ": " + malignancy("scheduled for " + line).map(\.label).joined(separator: ", "))
        }
        let debulk = QuickAdd.read("ovarian cancer debulking", record: PatientRecord(), tab: .preop, now: now).findings
        XCTAssertTrue(debulk.contains { $0.id == "procedure" })
        XCTAssertTrue(debulk.filter { $0.id.hasPrefix("problem:malignancy") }.isEmpty)
    }

    func testTheDiagnosisAfterForIsReadAsWellAsTheOperation() {
        let note = read("scheduled for lobectomy for lung cancer")
        XCTAssertTrue(note.findings.contains { $0.id == "procedure" })
        XCTAssertEqual(note.findings.filter { $0.id.hasPrefix("problem:malignancy") }.compactMap(typed).first?.sites, ["lung"])
        let bar = QuickAdd.read("lobectomy for lung cancer", record: PatientRecord(), tab: .preop, now: now).findings
        XCTAssertTrue(bar.contains { $0.id == "procedure" }, "the procedure")
        XCTAssertEqual(bar.filter { $0.id.hasPrefix("problem:malignancy") }.compactMap(typed).first?.sites, ["lung"], "and the malignancy")
    }

    func testTheNewAbbreviationsAreKnown() {
        let r = read("HCC, RCC, XRT, NSCLC, AML")
        XCTAssertTrue(r.unknown.isEmpty, r.unknown.map(\.token).joined(separator: ", "))
        for p in PatientNote.malignancyPatterns { XCTAssertNotNil(p.re, p.pattern) }
        for p in PatientNote.allPatterns { XCTAssertNotNil(p.re, p.pattern) }
        for p in MedAbbreviations.allPatterns { XCTAssertNotNil(p.re, p.pattern) }
    }

    // MARK: 8. The procedure list: ECMO

    private func first(_ q: String) -> String? { ProcedureCatalog.search(q).first?.name }

    func testECMOCannulationStillComesFirst() {
        XCTAssertEqual(first("ECMO cannulation"), "ECMO cannulation")
        XCTAssertEqual(first("ECMO"), "ECMO cannulation")
        XCTAssertEqual(first("VA ECMO"), "ECMO cannulation")
        XCTAssertEqual(first("VV ECMO"), "ECMO cannulation")
    }

    func testECMOReconfigurationIsFoundByItsWords() throws {
        for q in ["ECMO reconfiguration", "reconfiguration", "VA to VV", "VV to VA", "VA to VAV", "VAV ECMO", "VVA ECMO", "ECMO cannula exchange",
                  "cannula exchange", "ECMO revision", "ECMO cannula revision", "ECMO configuration change"] {
            XCTAssertEqual(first(q), "ECMO reconfiguration", q)
            XCTAssertEqual(PlannedProcedure.parse(q).first?.catalogID, "ecmo-reconfiguration", "parsed: " + q)
        }
        let ids = ProcedureCatalog.all.map(\.id)
        XCTAssertEqual(ids.filter { $0 == "ecmo-reconfiguration" }.count, 1)
        let ecmo = ids.firstIndex(of: "ecmo"), reconfig = ids.firstIndex(of: "ecmo-reconfiguration"), decannulation = ids.firstIndex(of: "ecmo-decannulation")
        XCTAssertNotNil(ecmo); XCTAssertNotNil(reconfig)
        XCTAssertTrue(ecmo! < reconfig! && reconfig! - ecmo! <= 4, "next to the other ECMO entries")
        XCTAssertNotNil(decannulation)
    }

    func testECMOReconfigurationTakesNothingFromTheOtherEntries() {
        XCTAssertEqual(first("ECMO conversion"), "ECMO to VAD conversion")
        XCTAssertEqual(first("ECMO to VAD"), "ECMO to VAD conversion")
        XCTAssertEqual(first("ECMO to LVAD"), "ECMO to VAD conversion")
        XCTAssertEqual(first("decannulation"), "ECMO decannulation")
        XCTAssertEqual(first("ECMO decannulation"), "ECMO decannulation")
        XCTAssertEqual(first("central ECMO"), "Central ECMO cannulation")
        XCTAssertEqual(PlannedProcedure.parse("ECMO to VAD").first?.catalogID, "ecmo-to-vad")
        XCTAssertEqual(PlannedProcedure.parse("ECMO decannulation").first?.catalogID, "ecmo-decannulation")
        XCTAssertEqual(PlannedProcedure.parse("VA ECMO").first?.catalogID, "ecmo")
    }

    func testECMOReconfigurationHasTheSettingsOfECMOCannulation() throws {
        let a = try XCTUnwrap(ProcedureCatalog.byID("ecmo")), b = try XCTUnwrap(ProcedureCatalog.byID("ecmo-reconfiguration"))
        XCTAssertEqual(b.name, "ECMO reconfiguration")
        XCTAssertEqual(b.anesthetic, a.anesthetic)
        XCTAssertEqual(b.incision, a.incision)
        XCTAssertEqual(b.duration, a.duration)
        XCTAssertEqual(b.highRisk, a.highRisk)
        XCTAssertEqual(b.cardiac, a.cardiac)
        XCTAssertEqual(b.echoFirst, a.echoFirst)
        XCTAssertEqual(b.lateral, a.lateral)
        XCTAssertEqual(ProcedureCatalog.risk("ECMO reconfiguration"), ProcedureCatalog.risk("ECMO cannulation"))
    }
}
