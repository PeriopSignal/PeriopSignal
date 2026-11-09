import XCTest
import CoreGraphics
@testable import PeriopSignal

/// Review 1.10 (checks): every chosen toggle chip reads "✓ Warfarin" on a one-line row, as every chosen toggle chip did in
/// 1.9, and a row that fit one line in 1.10 still does. The rows named in the review, measured at the width a system
/// page gives them: the page's 20-pt margins, then the item's content inset (48 pt leading, under the item's title, and
/// 14 trailing; PatientHistorySections.section), so 273 pt on a 375-pt phone and 300 pt on the CI simulator's 402.
final class ChipChecks110Tests: XCTestCase {
    /// A chip row under a system-page item.
    private func systemRow(_ screen: CGFloat) -> CGFloat { screen - 40 - 48 - 14 }
    /// A chip row straight inside a group (Preprocedure rows, the review's 375-pt measure): the margins and the row's 14.
    private func groupRow(_ screen: CGFloat) -> CGFloat { screen - 40 - 28 }

    private func chips(_ options: [(String, String)]) -> [ChipChoice] { options.map { ChipChoice($0.0, $0.1) } }

    private var anticoagulants: [ChipChoice] { chips(HistorySections.anticoagulantKinds.map { ($0.0, $0.1) }) }
    private let device = [ChipChoice("pacemaker", "Pacemaker"), ChipChoice("icd", "ICD"), ChipChoice("dependent", "Pacer dependent")]
    private let ctd = [ChipChoice("marfan", "Marfan syndrome"), ChipChoice("eds", "Ehlers-Danlos syndrome")]
    private let cad = [ChipChoice("ischemia", "Ongoing (unstable) ischemia"), ChipChoice("cabg", "Prior CABG")]
    private var adrenal: [ChipChoice] { chips(HistorySections.adrenalKinds.map { ($0.0, $0.1) }) }
    private var lesions: [ChipChoice] { chips(PatientHistoryDetails.lesions.map { ($0.id, $0.label) }) }
    private let repair = [ChipChoice("aortic-repair-open", "Open"), ChipChoice("evar", "EVAR"), ChipChoice("tevar", "TEVAR")]

    /// The named rows with what the screenshots choose (demo-pages19 and demo-cardio).
    private var named: [(name: String, options: [ChipChoice], on: Set<String>)] {
        [("anticoagulant kinds", anticoagulants, ["warfarin"]),
         ("pacemaker / ICD", device, ["pacemaker", "dependent"]),
         ("connective tissue", ctd, ["marfan"]),
         ("CAD", cad, ["cabg"]),
         ("adrenal", adrenal, ["steroids"]),
         ("aortic valve", lesions, ["stenosis"]),
         ("mitral valve", lesions, ["prosthetic"]),
         ("prior repair", repair, ["tevar"])]
    }

    private func describe(_ f: ChipMetrics.Form?) -> String {
        guard let f else { return "wraps (✓ on the chosen chips)" }
        return (f.check ? "✓ " : "no ✓ ") + (f.short ? "short" : "full") + "/\(f.density)"
    }

    private func assertCheck(_ name: String, _ options: [ChipChoice], _ on: Set<String>, in width: CGFloat, _ screen: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        let f = ChipMetrics.lineFit(options, choice: false, in: width, selected: on)
        XCTAssertEqual(f?.check, true, "\(name) at \(screen): \(describe(f))", file: file, line: line)
        XCTAssertEqual(f?.short, false, "\(name): full words", file: file, line: line)
    }

    func testNamedRowsKeepTheirCheckOnOneLineAt375() {
        // On a 375-pt phone, under the item's title.
        assertCheck("anticoagulant kinds, Warfarin", anticoagulants, ["warfarin"], in: systemRow(375), "375 (system page)")
        assertCheck("Pacemaker + Pacer dependent", device, ["pacemaker", "dependent"], in: systemRow(375), "375 (system page)")
        // At the review's 375-pt measure (a row straight inside a group).
        assertCheck("anticoagulant kinds, Warfarin", anticoagulants, ["warfarin"], in: groupRow(375), "375")
        assertCheck("Pacemaker + Pacer dependent", device, ["pacemaker", "dependent"], in: groupRow(375), "375")
        assertCheck("Ongoing (unstable) ischemia | Prior CABG", cad, ["cabg"], in: groupRow(375), "375")
        assertCheck("adrenal kinds, Chronic steroids", adrenal, ["steroids"], in: groupRow(375), "375")
    }

    func testNamedRowsKeepTheirCheckOnOneLineOnTheCISimulator() {
        let w = systemRow(402)
        assertCheck("anticoagulant kinds, Warfarin", anticoagulants, ["warfarin"], in: w, "402")
        assertCheck("Pacemaker + Pacer dependent", device, ["pacemaker", "dependent"], in: w, "402")
        assertCheck("Prior CABG", cad, ["cabg"], in: w, "402")
        assertCheck("Chronic steroids", adrenal, ["steroids"], in: w, "402")
        assertCheck("aortic Stenosis", lesions, ["stenosis"], in: w, "402")
        assertCheck("mitral Prosthetic", lesions, ["prosthetic"], in: w, "402")
    }

    /// The rows 1.10 wrapped at 375 pt under an item's title still wrap there, the chosen chip with its ✓ (1.9's look).
    func testRowsThatWrappedIn110StillWrapWithTheirCheck() {
        XCTAssertNil(ChipMetrics.lineFit(ctd, choice: false, in: systemRow(375), selected: ["marfan"]), "Marfan syndrome | Ehlers-Danlos syndrome")
        XCTAssertNil(ChipMetrics.lineFit(cad, choice: false, in: systemRow(375), selected: ["cabg"]), "Ongoing (unstable) ischemia | Prior CABG")
    }

    /// No new wraps: for every choice of chips, a row that fit one line in 1.10 (any of its plain forms) still does,
    /// with the ✓ where any padding fits it.
    func testChoosingChipsNeverWrapsARowThat110KeptOnOneLine() {
        let widths: [(String, CGFloat)] = [("375 system", systemRow(375)), ("402 system", systemRow(402)), ("375 group", groupRow(375)), ("402 group", groupRow(402))]
        for row in named {
            let ids = row.options.map(\.id)
            for (screen, w) in widths {
                let fitIn110 = ChipMetrics.order.contains { o in
                    w >= ChipMetrics.width(row.options.map { o.short ? $0.shown : $0.label }, density: o.density, choice: false)
                }
                for mask in 0..<(1 << ids.count) {
                    let on = Set(ids.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element))
                    let f = ChipMetrics.lineFit(row.options, choice: false, in: w, selected: on)
                    if fitIn110 { XCTAssertNotNil(f, "\(row.name) \(on.sorted()) at \(screen): one line in 1.10") }
                    if on.isEmpty { XCTAssertEqual(f != nil, fitIn110, "\(row.name) at \(screen): nothing chosen, as 1.10") }
                }
            }
        }
    }

    /// Reported, not asserted: where each named row lands with the screenshots' choice, and which rows fall back to the
    /// outline without the ✓ (no padding fits it there).
    func testReportWhereTheNamedRowsLand() {
        print("checkWidth", ChipMetrics.checkWidth)
        for row in named {
            var line = row.name + " " + row.on.sorted().joined(separator: "+") + ":"
            for screen in [CGFloat(375), 402] {
                line += " \(Int(screen)) system \(describe(ChipMetrics.lineFit(row.options, choice: false, in: systemRow(screen), selected: row.on)))"
                line += " | \(Int(screen)) group \(describe(ChipMetrics.lineFit(row.options, choice: false, in: groupRow(screen), selected: row.on)));"
            }
            let labels = row.options.map(\.label)
            let widths = [ChipMetrics.Density.regular, .tight, .dense, .compact].map { d in
                "\(d) \(Int(ChipMetrics.width(labels, density: d, choice: false)))/\(Int(ChipMetrics.width(labels, density: d, choice: false, checked: row.options.map { row.on.contains($0.id) })))"
            }
            print("CHIPROW", line, "widths plain/✓:", widths.joined(separator: ", "))
        }
    }
}
