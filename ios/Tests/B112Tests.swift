import XCTest
import UIKit
@testable import PeriopSignal

/// 1.12 helper B (Ben, Nov 10): the PMH without system labels (19), the handoff's airway course in one short line (20),
/// sharing a summary as an image, a PDF or text (21), and the preprocedure imaging (15) with its place in the summaries.
final class B112Tests: XCTestCase {
    private func block(_ blocks: [SummaryBlock], _ key: String, file: StaticString = #filePath, line: UInt = #line) throws -> SummaryBlock {
        try XCTUnwrap(blocks.first { $0.key == key }, "no \(key) block in \(blocks.map(\.key))", file: file, line: line)
    }

    private func has(_ blocks: [SummaryBlock], _ key: String) -> Bool { blocks.contains { $0.key == key } }

    // MARK: 19. PMH without system labels

    private var systems: PatientRecord {
        var r = PatientRecord()
        r.ageYears = 70
        r.problems = ["htn", "cad", "copd", "esrd-dialysis"]
        r.asaClass = 4
        return r
    }

    func testThePMHListsTheProblemsWithNoSystemHeadings() throws {
        let r = systems
        let systemNames = Set(PatientCatalog.allSystems.map(\.name))
        let history = PatientSummary.historyLines(r).filter { systemNames.contains($0.label ?? "") }
        XCTAssertGreaterThanOrEqual(history.count, 2, "the record spans several systems: \(history.map { $0.label ?? "" })")
        for blocks in [PatientBriefs.preop(r), PatientBriefs.handoff(r)] {
            let pmh = try block(blocks, "pmh")
            XCTAssertEqual(pmh.label, "PMH (ASA IV)")
            XCTAssertTrue(pmh.text.hasPrefix(history.map(\.text).joined(separator: "; ")), "the systems' order, joined by \"; \": \(pmh.text)")
            for name in systemNames { XCTAssertFalse(pmh.text.contains(name + ":"), "\(name) heading in: \(pmh.text)") }
            XCTAssertFalse(pmh.text.contains(" · "), pmh.text)
        }
        XCTAssertTrue(PatientBriefs.plainText(PatientBriefs.handoff(r)).contains("PMH (ASA IV): " + history.map(\.text).joined(separator: "; ")))
    }

    func testTheTabAndThePagesKeepTheirSystemHeadings() {
        let lines = PatientSummary.historyLines(systems)
        XCTAssertTrue(lines.contains { $0.label == "Cardiovascular" }, "the history lines (the tab's words) keep the heading")
        XCTAssertTrue(lines.contains { $0.label == "Respiratory" })
    }

    func testAlertPhrasesKeepTheirLabelAndTheirRed() throws {
        var r = systems
        r.problems.insert("hiatal-hernia")
        r.problems.insert("gi-bleed")
        for blocks in [PatientBriefs.preop(r), PatientBriefs.handoff(r)] {
            let pmh = try block(blocks, "pmh")
            XCTAssertTrue(pmh.text.contains(PatientWarnings.aspirationLabel + ": "), pmh.text)
            XCTAssertTrue(pmh.text.contains(PatientWarnings.heparinLabel + ": "), pmh.text)
            XCTAssertTrue(pmh.marks.contains { $0.hasPrefix(PatientWarnings.aspirationLabel) }, "still in bold red")
            XCTAssertTrue(pmh.marks.allSatisfy { pmh.text.contains($0) }, "every mark is in the text")
        }
    }

    func testOtherConditionsAreAProblemNotAHeading() throws {
        var r = systems
        r.otherHistory = "Hereditary angioedema"
        let pmh = try block(PatientBriefs.handoff(r), "pmh")
        XCTAssertTrue(pmh.text.hasSuffix("Hereditary angioedema") || pmh.text.contains("Hereditary angioedema; "), pmh.text)
        XCTAssertFalse(pmh.text.contains("Other conditions:"), pmh.text)
    }

    func testFunctionAndCardiacFlagsKeepTheirLabelsInThePMH() throws {
        var r = systems
        r.mets = "lt4"
        let pmh = try block(PatientBriefs.preop(r), "pmh")
        XCTAssertTrue(pmh.text.contains("Functional capacity: "), pmh.text)
    }

    // MARK: 20. The airway course, one short line

    private func record(_ f: (inout PatientRecord) -> Void) -> PatientRecord {
        var r = PatientRecord()
        f(&r)
        return r
    }

    func testAnEasyAirwayReadsAsBensShortLine() throws {
        let r = record {
            $0.mask = "easy"; $0.intubation = "easy"; $0.airwayDevice = "Video laryngoscope"; $0.laryngoscopyGrade = "1"; $0.attempts = 1
            $0.tube = "8.0 cuffed ETT (23 cm)"
            $0.airwayAtEnd = "intubated"; $0.ventilation = "AC/VC 450 × 18, PEEP 8, FiO₂ 60%"
        }
        let want = "Easy Mask, Easy VL Intubation, ETT 8.0 at 23 cm. Remains intubated, AC/VC 450 × 18, PEEP 8, FiO₂ 60%"
        let c = try XCTUnwrap(PatientBriefs.airwayCourse(r))
        XCTAssertEqual(c.text, want)
        XCTAssertFalse(c.alert)
        XCTAssertTrue(c.marks.isEmpty)
        XCTAssertEqual(try block(PatientBriefs.handoff(r), "airway").text, want)
        XCTAssertEqual(PatientBriefs.plainText(PatientBriefs.handoff(r)), "Airway course: " + want, "one line when copied")
    }

    func testTheDevicesAreDLVLAndFiberoptic() {
        func line(_ device: String) -> String {
            PatientBriefs.airwayCourse(record { $0.intubation = "easy"; $0.airwayDevice = device })?.text ?? ""
        }
        XCTAssertEqual(line("Direct laryngoscope"), "Easy DL Intubation")
        XCTAssertEqual(line("Video laryngoscope"), "Easy VL Intubation")
        XCTAssertEqual(line("Fiberoptic scope"), "Easy Fiberoptic Intubation")
        XCTAssertEqual(line("Flexible scope"), "Easy Fiberoptic Intubation", "a saved 1.9 name")
        XCTAssertEqual(PatientBriefs.airwayCourse(record { $0.intubation = "easy" })?.text, "Easy Intubation", "no device recorded")
    }

    func testAnLMACaseReadsLMAWithItsSizeAndMaskNotUsedIsLeftOut() throws {
        let typed = record { $0.mask = "none"; $0.sga = "easy"; $0.airwayDevice = "Supraglottic airway"; $0.tube = "LMA 4"; $0.airwayAtEnd = "extubated" }
        XCTAssertEqual(PatientBriefs.airwayCourse(typed)?.text, "LMA 4. Extubated", "\"Mask not used\" is omitted; the LMA reads LMA 4")
        let numberOnly = record { $0.sga = "easy"; $0.airwayDevice = "Supraglottic airway"; $0.tube = "4" }
        XCTAssertEqual(PatientBriefs.airwayCourse(numberOnly)?.text, "LMA 4")
        let noSize = record { $0.sga = "easy" }
        XCTAssertEqual(PatientBriefs.airwayCourse(noSize)?.text, "LMA")
        let hard = record { $0.sga = "difficult"; $0.sgaNote = "Leak, second size"; $0.airwayDevice = "Supraglottic airway"; $0.tube = "LMA 3" }
        let c = try XCTUnwrap(PatientBriefs.airwayCourse(hard))
        XCTAssertEqual(c.text, "Difficult LMA 3, leak, second size")
        XCTAssertTrue(c.alert)
        XCTAssertEqual(c.marks, ["Difficult LMA 3, leak, second size"])
    }

    func testADifficultAirwayKeepsItsDetailsInRed() throws {
        let r = record {
            $0.mask = "difficult"; $0.maskNote = "2-person"
            $0.intubation = "difficult"; $0.airwayDevice = "Video laryngoscope"; $0.laryngoscopyGrade = "3"; $0.attempts = 2; $0.intubationNote = "Bougie"
            $0.tube = "7.5 ETT at 22 cm"
            $0.airwayAtEnd = "extubated"
        }
        let want = "Difficult Mask (2-person), Difficult VL Intubation, grade 3, 2 attempts, bougie, ETT 7.5 at 22 cm. Extubated"
        let c = try XCTUnwrap(PatientBriefs.airwayCourse(r))
        XCTAssertEqual(c.text, want)
        XCTAssertTrue(c.alert)
        XCTAssertEqual(c.marks, ["Difficult Mask (2-person)", "Difficult VL Intubation, grade 3, 2 attempts, bougie"])
        XCTAssertTrue(c.marks.allSatisfy { c.text.contains($0) }, "the red parts are in the line")
        let b = try block(PatientBriefs.handoff(r), "airway")
        XCTAssertEqual(b.text, want)
        XCTAssertTrue(b.alert)
        XCTAssertEqual(b.marks, c.marks)
    }

    func testNothingRecordedAsDifficultIsEverDropped() throws {
        // A difficult intubation says its view and attempts even when they are 1 and 2a.
        let mild = try XCTUnwrap(PatientBriefs.airwayCourse(record { $0.intubation = "difficult"; $0.laryngoscopyGrade = "2a"; $0.attempts = 1 }))
        XCTAssertEqual(mild.text, "Difficult Intubation, grade 2a, 1 attempt")
        // Every adjunct typed with it stays, and so does the mask's own note.
        let adjuncts = try XCTUnwrap(PatientBriefs.airwayCourse(record {
            $0.mask = "difficult"; $0.maskNote = "Oral airway, two hands"; $0.intubation = "difficult"; $0.intubationNote = "Stylet, bougie, second operator"
        }))
        XCTAssertTrue(adjuncts.text.contains("Difficult Mask (oral airway, two hands)"), adjuncts.text)
        XCTAssertTrue(adjuncts.text.contains("stylet, bougie, second operator"), adjuncts.text)
        // A difficult LMA, and a difficult mask with nothing said about why.
        XCTAssertEqual(PatientBriefs.airwayCourse(record { $0.mask = "difficult" })?.text, "Difficult Mask")
        XCTAssertTrue(PatientBriefs.airwayCourse(record { $0.mask = "difficult" })?.alert ?? false)
    }

    func testAGradeOneOrTwoViewAndASingleAttemptAreNotSaidOnAnEasyAirway() throws {
        for grade in ["1", "2a", "2b"] {
            let c = try XCTUnwrap(PatientBriefs.airwayCourse(record { $0.intubation = "easy"; $0.airwayDevice = "Direct laryngoscope"; $0.laryngoscopyGrade = grade; $0.attempts = 1 }))
            XCTAssertEqual(c.text, "Easy DL Intubation", "grade \(grade)")
            XCTAssertFalse(c.alert)
        }
    }

    func testAGradeThreeOrFourViewOrMoreThanOneAttemptIsKeptOnAnEasyAirwayToo() throws {
        let g3 = try XCTUnwrap(PatientBriefs.airwayCourse(record { $0.intubation = "easy"; $0.airwayDevice = "Video laryngoscope"; $0.laryngoscopyGrade = "3" }))
        XCTAssertEqual(g3.text, "Easy VL Intubation, grade 3")
        XCTAssertEqual(g3.marks, ["grade 3"])
        XCTAssertTrue(g3.alert)
        let g4 = PatientBriefs.airwayCourse(record { $0.intubation = "easy"; $0.laryngoscopyGrade = "4" })
        XCTAssertEqual(g4?.text, "Easy Intubation, grade 4")
        let two = try XCTUnwrap(PatientBriefs.airwayCourse(record { $0.intubation = "easy"; $0.attempts = 2; $0.laryngoscopyGrade = "1" }))
        XCTAssertEqual(two.text, "Easy Intubation, 2 attempts")
        XCTAssertEqual(two.marks, ["2 attempts"])
        let both = PatientBriefs.airwayCourse(record { $0.intubation = "easy"; $0.attempts = 3; $0.laryngoscopyGrade = "3" })
        XCTAssertEqual(both?.text, "Easy Intubation, grade 3, 3 attempts")
    }

    func testVentilatorSettingsAndHowThePatientLeavesStayAfterTheTube() {
        let intubated = record { $0.intubation = "easy"; $0.tube = "7.0"; $0.airwayAtEnd = "intubated"; $0.ventilation = "VC 450 × 14, PEEP 8" }
        XCTAssertEqual(PatientBriefs.airwayCourse(intubated)?.text, "Easy Intubation, ETT 7.0. Remains intubated, VC 450 × 14, PEEP 8")
        XCTAssertEqual(PatientBriefs.airwayCourse(record { $0.airwayAtEnd = "intubated" })?.text, "Remains intubated", "no settings typed")
        XCTAssertEqual(PatientBriefs.airwayCourse(record { $0.airwayAtEnd = "extubated" })?.text, "Extubated")
        XCTAssertNil(PatientBriefs.airwayCourse(PatientRecord()))
    }

    func testTheTubeIsReadAsASizeAndADepthOrKeptAsTyped() {
        XCTAssertEqual(PatientAirwayLine.tubeText("8.0 cuffed ETT (23 cm)"), "ETT 8.0 at 23 cm")
        XCTAssertEqual(PatientAirwayLine.tubeText("7.5 ETT, 23 cm at the lip"), "ETT 7.5 at 23 cm (lip)")
        XCTAssertEqual(PatientAirwayLine.tubeText("ETT 7.5 at 22 cm at the teeth."), "ETT 7.5 at 22 cm (teeth)")
        XCTAssertEqual(PatientAirwayLine.tubeText("7.0"), "ETT 7.0")
        XCTAssertEqual(PatientAirwayLine.tubeText("23 cm"), "ETT at 23 cm")
        XCTAssertEqual(PatientAirwayLine.tubeText(""), "")
        // Any other word means the typed text stands, so nothing typed is lost.
        XCTAssertEqual(PatientAirwayLine.tubeText("uncuffed 4.0"), "ETT uncuffed 4.0")
        XCTAssertEqual(PatientAirwayLine.tubeText("37 Fr left DLT"), "37 Fr left DLT")
        XCTAssertEqual(PatientAirwayLine.tubeText("armored 7.0, 21 cm"), "ETT armored 7.0, 21 cm")
        XCTAssertEqual(PatientAirwayLine.tubeText("nasal RAE 6.5"), "ETT nasal RAE 6.5")
    }

    func testArrivalNotesAndTheOlderCardsAreNotChanged() throws {
        // The airway notes and the oxygen on arrival stay in the course (safety content).
        let r = record { $0.oxygen = PatientOxygen(device: "ra"); $0.mask = "easy"; $0.airwayNotes = "Loose upper incisor"; $0.airwayAtEnd = "extubated" }
        XCTAssertEqual(PatientBriefs.airwayCourse(r)?.text, "Oxygen on arrival: Room air. Easy Mask. Airway notes: Loose upper incisor. Extubated")
        // The Summary cards and the older handoff writer keep their longer sentences.
        let easy = record { $0.mask = "easy"; $0.intubation = "easy"; $0.airwayDevice = "Video laryngoscope"; $0.laryngoscopyGrade = "1" }
        XCTAssertEqual(PatientSummary.airwayCourseSentences(easy), ["Mask ventilation easy", "Intubation easy: video laryngoscope, grade 1"])
    }

    // MARK: 15. Preprocedure imaging

    func testImagingKeepsWhatWasTypedAndNamesTheItemsThatHoldText() {
        var im = PatientImaging()
        XCTAssertNil(im.linkTitle)
        im.set(.ct, "CT chest 10/2026")
        im.set(.mri, "  ")
        XCTAssertEqual(im.linkTitle, "Imaging: CT")
        im.set(.mri, "MRI brain 09/2026")
        XCTAssertEqual(im.linkTitle, "Imaging: CT · MRI")
        im.set(.other, "Carotid duplex")
        XCTAssertEqual(im.linkTitle, "Imaging: CT · MRI · Other")
        XCTAssertEqual(im.typed(.mri), "MRI brain 09/2026")
        im.set(.mri, " ")
        XCTAssertEqual(im.typed(.mri), " ", "the box shows exactly what was typed")
        XCTAssertEqual(im.held, [.ct, .other])
        XCTAssertEqual(PatientImaging.Item.allCases.map(\.extraKey), ["imaging:ct", "imaging:mri", "imaging:other"])
        XCTAssertEqual(PatientImaging.Item.allCases.map(\.label), ["CT", "MRI", "Other imaging"])
    }

    func testOnlyTheChosenItemsReachTheLines() {
        var im = PatientImaging()
        im.ct = "CT chest: 4.8 cm ascending aorta"; im.mri = "MRI brain: no acute findings"; im.other = "Carotid duplex"
        XCTAssertTrue(im.chosenLines([]).isEmpty, "typed but not chosen: not in a summary")
        XCTAssertEqual(im.chosenLines(["imaging:mri"]), ["MRI: MRI brain: no acute findings"])
        XCTAssertEqual(im.chosenLines(["imaging:other", "imaging:ct"]), ["CT: CT chest: 4.8 cm ascending aorta", "Other imaging: Carotid duplex"], "the page's order")
        XCTAssertEqual(im.chosenLines(["preop:alb", "intraop:k", "imaging:xray"]), [], "keys that are not imaging add nothing")
        im.mri = ""
        XCTAssertEqual(im.chosenLines(["imaging:mri"]), [], "an item no longer holding text is ignored")
        im.ct = "line one\n\n  line two  "
        XCTAssertEqual(im.chosenLines(["imaging:ct"]), ["CT: line one line two"], "one line in a summary")
    }

    func testTheImagingBlockFollowsTheCardiacWorkupInBothSummaries() throws {
        let r = PatientDemo112Summary.summary
        XCTAssertEqual(r.handoffExtras, ["imaging:ct", "imaging:mri"])
        for blocks in [PatientBriefs.preop(r), PatientBriefs.handoff(r)] {
            let keys = blocks.map(\.key)
            let w = try XCTUnwrap(keys.firstIndex(of: "workup"))
            XCTAssertEqual(keys.firstIndex(of: "imaging"), w + 1, "after the cardiac workup: \(keys)")
            let b = try block(blocks, "imaging")
            XCTAssertEqual(b.label, "Imaging")
            XCTAssertEqual(b.text, "CT: CT chest 10/2026: ascending aorta 4.8 cm\nMRI: MRI brain 09/2026: no acute findings")
        }
        XCTAssertTrue(PatientBriefs.plainText(PatientBriefs.handoff(r)).contains("Imaging:\n  CT: CT chest 10/2026"))
    }

    func testImagingThatIsNotChosenOrEmptyMakesNoBlock() {
        var r = PatientDemo112Summary.summary
        r.handoffExtras = []
        XCTAssertFalse(has(PatientBriefs.preop(r), "imaging"))
        XCTAssertFalse(has(PatientBriefs.handoff(r), "imaging"))
        r.handoffExtras = ["imaging:ct"]
        r.imaging = PatientImaging()
        XCTAssertFalse(has(PatientBriefs.handoff(r), "imaging"), "chosen, nothing typed")
        r.imaging.other = "Carotid duplex"
        XCTAssertFalse(has(PatientBriefs.handoff(r), "imaging"), "the other item was not the one chosen")
    }

    func testAnImagingEditStaysUntilRegenerateWhenTheExtrasChange() throws {
        var r = PatientDemo112Summary.summary
        PatientBriefs.setEdit(&r, .handoff, key: "imaging", text: "CT: aortic root 4.8 cm (my words)")
        XCTAssertEqual(try block(PatientBriefs.handoff(r), "imaging").text, "CT: aortic root 4.8 cm (my words)")
        XCTAssertTrue(try block(PatientBriefs.handoff(r), "imaging").edited)
        r.handoffExtras = ["imaging:ct", "imaging:mri", "imaging:other"]
        r.imaging.other = "Carotid duplex"
        XCTAssertEqual(try block(PatientBriefs.handoff(r), "imaging").text, "CT: aortic root 4.8 cm (my words)", "the edit stays")
        PatientBriefs.regenerate(&r, .handoff)
        XCTAssertTrue(try block(PatientBriefs.handoff(r), "imaging").text.contains("Other imaging: Carotid duplex"), "Regenerate brings the extras in")
        // The preprocedure summary's own edits are separate.
        XCTAssertFalse(try block(PatientBriefs.preop(r), "imaging").edited)
    }

    func testImagingSavedWithARecordComesBack() throws {
        var r = PatientRecord()
        r.imaging.ct = "CT chest"
        r.handoffExtras = ["imaging:ct"]
        let back = try JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back.imaging.typed(.ct), "CT chest")
        let old = try JSONDecoder().decode(PatientRecord.self, from: Data(#"{"procedure":"Lap chole","imaging":{"ct":"CT abdomen"}}"#.utf8))
        XCTAssertEqual(old.imaging.typed(.ct), "CT abdomen")
        XCTAssertEqual(old.imaging.typed(.mri), "", "a missing line is empty")
    }

    // MARK: 21. Sharing

    func testTheShareMenuOffersImagePDFAndTextOnlyInThatOrder() {
        XCTAssertEqual(BriefShareFormat.allCases, [.image, .pdf, .text])
        XCTAssertEqual(BriefShareFormat.allCases.map(\.title), ["Image", "PDF", "Text only"])
    }

    func testPagesBreakOnlyBetweenBlocks() {
        let pages = BriefPages.paginate([300, 300, 300], available: 700, spacing: 10)
        XCTAssertEqual(pages.map(\.blocks), [[0, 1], [2]])
        XCTAssertEqual(pages[0].bodyHeight, 610)
        XCTAssertFalse(pages.contains { $0.oversize })
        // Every block is on exactly one page, in order.
        let heights: [CGFloat] = [120, 400, 80, 520, 90, 300, 300, 60]
        let many = BriefPages.paginate(heights, available: 700, spacing: 12)
        XCTAssertEqual(many.flatMap(\.blocks), Array(heights.indices))
        for p in many { XCTAssertLessThanOrEqual(p.bodyHeight, 700, "a page holds what fits") }
        XCTAssertTrue(BriefPages.paginate([], available: 700, spacing: 10).isEmpty)
        // A block that exactly fills a page, and one more, go on two pages.
        XCTAssertEqual(BriefPages.paginate([700, 10], available: 700, spacing: 10).map(\.blocks), [[0], [1]])
    }

    func testABlockTallerThanAPageGetsAPageOfItsOwnThatRunsAsTallAsItNeeds() {
        let pages = BriefPages.paginate([100, 1200, 100, 100], available: 700, spacing: 10)
        XCTAssertEqual(pages.map(\.blocks), [[0], [1], [2, 3]])
        XCTAssertEqual(pages.map(\.oversize), [false, true, false])
        let geo = BriefPages.Geometry.phone
        XCTAssertEqual(geo.pageHeight(body: 300, oversize: false), 844)
        XCTAssertGreaterThan(geo.pageHeight(body: 1200, oversize: true), 1200, "the block, the margins and the footer")
        XCTAssertGreaterThanOrEqual(geo.pageHeight(body: 790, oversize: true), 844, "never shorter than a phone page")
        XCTAssertEqual(geo.width, 390)
        XCTAssertEqual(geo.height, 844)
        XCTAssertEqual(BriefPages.Geometry.letter.width, 612)
    }

    func testTheFooterSaysThePageAndWhenItWasMade() {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 9, minute: 41))!
        XCTAssertEqual(BriefPages.footer(page: 2, of: 3, now: now), "Periop Signal · page 2 of 3 · generated 09:41")
    }

    @MainActor private func context() -> BriefPages.Context {
        BriefPages.Context(record: PatientDemo112Summary.summary, refs: ReferenceStore(), patient: PatientStore(url: nil))
    }

    @MainActor func testTheImageIsWhitePagesAtPhoneSizeInThreeTimes() throws {
        let ctx = context()
        let blocks = PatientBriefs.handoff(ctx.record)
        let images = BriefPages.images(blocks, ctx)
        XCTAssertFalse(images.isEmpty)
        for img in images {
            XCTAssertEqual(img.size.width * img.scale, 1170, "390 pt at 3x")
        }
        XCTAssertEqual(images[0].size.height * images[0].scale, 2532, "a phone's height at 3x")
        // White page, dark ink, whatever the phone's appearance.
        let cg = try XCTUnwrap(images[0].cgImage)
        let pixel = try pixels(cg)
        XCTAssertEqual(pixel(2, 2), [255, 255, 255], "the corner is white")
        XCTAssertTrue((0..<cg.height).contains { y in (0..<cg.width).contains { x in pixel(x, y).allSatisfy { $0 < 90 } } }, "the text is dark on it")
    }

    @MainActor func testEveryBlockIsWholeOnOnePageAndPagesAreNumbered() {
        let ctx = context()
        let blocks = PatientBriefs.handoff(ctx.record)
        let sheets = BriefPages.sheets(blocks, ctx, geo: .phone)
        XCTAssertEqual(sheets.flatMap { $0.blocks.map(\.key) }, blocks.map(\.key), "no block split, none lost, in order")
        for (i, s) in sheets.enumerated() {
            XCTAssertTrue(s.footer.hasPrefix("Periop Signal · page \(i + 1) of \(sheets.count) · generated "), s.footer)
        }
    }

    @MainActor func testALongBlockHasAPageOfItsOwn() throws {
        var r = PatientDemo112Summary.long
        r.disposition = "PACU"
        let ctx = BriefPages.Context(record: r, refs: ReferenceStore(), patient: PatientStore(url: nil))
        let blocks = PatientBriefs.handoff(r)
        let sheets = BriefPages.sheets(blocks, ctx, geo: .phone)
        let tall = sheets.filter { $0.height > 844 }
        XCTAssertEqual(tall.count, 1, "heights: \(sheets.map(\.height))")
        XCTAssertEqual(tall.first?.blocks.map(\.key), ["concerns"], "the long block alone")
        XCTAssertTrue(sheets.filter { $0.height <= 844 }.allSatisfy { $0.height == 844 })
        let images = BriefPages.images(blocks, ctx)
        XCTAssertEqual(images.count, sheets.count)
        let big = try XCTUnwrap(images.first { $0.size.height > 844 })
        XCTAssertEqual(big.size.width * big.scale, 1170)
    }

    @MainActor func testThePDFIsLetterWidthAndKeepsBlocksWhole() throws {
        let ctx = context()
        let blocks = PatientBriefs.handoff(ctx.record)
        let data = try XCTUnwrap(BriefPages.pdf(blocks, ctx))
        XCTAssertEqual(String(decoding: data.prefix(5), as: UTF8.self), "%PDF-")
        let doc = try XCTUnwrap(CGDataProvider(data: data as CFData).flatMap { CGPDFDocument($0) })
        let sheets = BriefPages.sheets(blocks, ctx, geo: .letter)
        XCTAssertEqual(doc.numberOfPages, sheets.count)
        let page = try XCTUnwrap(doc.page(at: 1))
        XCTAssertEqual(page.getBoxRect(.mediaBox).width, 612)
        XCTAssertEqual(sheets.flatMap { $0.blocks.map(\.key) }, blocks.map(\.key), "blocks whole across the page breaks")
        XCTAssertNil(BriefPages.pdf([], ctx), "nothing to draw")
        let url = try XCTUnwrap(BriefPages.pdfFile(blocks, ctx))
        XCTAssertEqual(url.pathExtension, "pdf")
        XCTAssertFalse(url.lastPathComponent.lowercased().contains("demo"), "no identifier in the name")
    }

    private func figure() throws -> RegionalFigure {
        let json = """
        {"figure": {"box": [200, 420], "outline": "M10 10 L190 10 L190 410 L10 410 Z", "head": {"cx": 100, "cy": 30, "rx": 17, "ry": 22}, "landmarks": {},
          "regions": [{"id": "chest", "name": "Anterior chest and breast", "views": {}}]},
         "blocks": [], "map": {"chest": {"blocks": []}}}
        """
        return try JSONDecoder().decode(RegionalData.self, from: Data(json.utf8)).figure
    }

    @MainActor func testTheLinesDiagramStandsInItsPlaceUnderLinesAndDevices() throws {
        let plain = context()
        var drawn = plain
        drawn.figure = try figure()
        let lines = try block(PatientBriefs.handoff(plain.record), "lines")
        XCTAssertEqual(lines.figure, .diagram(arrivalOnly: false))
        let without = BriefPages.height(of: [lines], plain, width: 350, spacing: 12)
        let with = BriefPages.height(of: [lines], drawn, width: 350, spacing: 12)
        XCTAssertGreaterThan(with, without + 60, "the figure stands beside the list: \(without) -> \(with)")
        // The pages are laid out and drawn with it.
        let blocks = PatientBriefs.handoff(plain.record)
        XCTAssertEqual(BriefPages.sheets(blocks, drawn, geo: .phone).flatMap { $0.blocks.map(\.key) }, blocks.map(\.key))
        XCTAssertFalse(BriefPages.images(blocks, drawn).isEmpty)
        XCTAssertNotNil(BriefPages.pdf(blocks, drawn))
    }

    @MainActor func testTextOnlyIsTheTextAndItsFooterWithNoPictures() {
        let blocks = PatientBriefs.handoff(PatientDemo112Summary.summary)
        let items = HandoffShare.textOnlyItems(blocks)
        XCTAssertEqual(items.count, 1)
        let item = items.first as? HandoffShare.TextItem
        XCTAssertNotNil(item)
        XCTAssertTrue(item?.plain.hasSuffix("Check against the chart.") ?? false)
        XCTAssertTrue(item?.plain.contains("PMH (ASA IV): ") ?? false)
    }

    /// The pixel at (x, y) of an image, as [r, g, b].
    private func pixels(_ cg: CGImage) throws -> (Int, Int) -> [Int] {
        let width = cg.width, height = cg.height
        let ctx = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        let base = try XCTUnwrap(ctx.data).assumingMemoryBound(to: UInt8.self)
        let data = Array(UnsafeBufferPointer(start: base, count: width * height * 4))
        return { x, y in
            let i = (y * width + x) * 4
            return [Int(data[i]), Int(data[i + 1]), Int(data[i + 2])]
        }
    }
}
