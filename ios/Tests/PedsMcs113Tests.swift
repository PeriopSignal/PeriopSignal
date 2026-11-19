import XCTest
@testable import PeriopSignal

/// Pediatric doses, the infusion list and the mechanical support page after the Nov 19 review (Ben, "use your best judgement"):
/// an absurd weight never crashes a dose or infusion line, a weight that cannot be a child's gets "Check the weight" and no number,
/// a newborn weight adds the by-weight tube caution, the infusion list says it is adult dosing and does not take a child's weight,
/// and the mechanical support cautions sit in view, not inside the collapsed footer.
final class PedsMcs113Tests: XCTestCase {
    private func bundled() throws -> ReferenceBundle {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reference", withExtension: "json"), "reference.json is bundled with the tests")
        return try ReferenceLoader.decode(try Data(contentsOf: url))
    }

    /// Weights no dose line can show: a pasted 20-digit number, infinity, not-a-number and the largest finite value.
    private let absurd: [Double] = [1e20, 1e9, 1e300, .greatestFiniteMagnitude, .infinity, -.infinity, .nan]

    // MARK: The crash guard

    func testFmtNeverTrapsOnANumberThatCannotBeShown() {
        for v in absurd { XCTAssertEqual(PedsCalc.fmt(v), "—", "\(v)") }
        XCTAssertEqual(PedsCalc.fmt(-1e20), "—")
        XCTAssertEqual(PedsCalc.fmt(999_999_999), "999999999", "the largest shown number is just under 1e9")
        // Numbers the app shows today read exactly as before.
        XCTAssertEqual(PedsCalc.fmt(0.123), "0.12")
        XCTAssertEqual(PedsCalc.fmt(2.25), "2.3")
        XCTAssertEqual(PedsCalc.fmt(12.6), "13")
        XCTAssertEqual(PedsCalc.fmt(18), "18")
        XCTAssertEqual(PedsCalc.fmt(150), "150")
    }

    func testEveryPediatricDoseRowHandlesAnAbsurdWeight() throws {
        let peds = try XCTUnwrap(try bundled().peds)
        XCTAssertFalse(peds.drugs.isEmpty)
        for d in peds.drugs {
            for w in absurd {
                let t = PedsCalc.doseText(low: d.low, high: d.high, unit: d.unit, weightKg: w, min: d.min, max: d.max)
                XCTAssertEqual(t.text, "Check the weight", "\(d.id) at \(w): no dose, not even one held at its maximum")
                XCTAssertFalse(t.capped, "\(d.id) at \(w)")
            }
            // A weight inside the limits still gives a dose.
            let ok = PedsCalc.doseText(low: d.low, high: d.high, unit: d.unit, weightKg: 18, min: d.min, max: d.max)
            XCTAssertTrue(ok.text.hasSuffix(" " + d.unit), "\(d.id): \(ok.text)")
        }
    }

    func testEveryInfusionLineHandlesAnAbsurdWeight() throws {
        let all = try XCTUnwrap(try bundled().infusions).groups.flatMap(\.drugs)
        XCTAssertGreaterThanOrEqual(all.count, 40)
        let weightForms: [InfusionDrug.Form] = [.perKgPerMin, .perMin, .perKg, .perKgPerHour]
        for d in all {
            let weighted = d.start != nil && weightForms.contains(d.form)
            for w in absurd {
                let l = InfusionCalc.lines(for: d, weightKg: w)
                XCTAssertFalse(l.dose.isEmpty, "\(d.id) at \(w)")
                if w > 0, weighted {
                    XCTAssertEqual(l.equivalent, "Check the weight", "\(d.id) at \(w)")
                }
            }
            // The dose as written never depends on the weight.
            XCTAssertEqual(InfusionCalc.lines(for: d, weightKg: 1e20).dose, InfusionCalc.lines(for: d, weightKg: nil).dose, d.id)
        }
        // A weight so small that the per-kg form overflows is caught too.
        let ntg = InfusionDrug(id: "ntg", name: "Nitroglycerin", use: "Hypertension", form: .perMin, start: 5, startHigh: nil, unit: "mcg", titration: nil, range: nil, max: nil, bolus: nil, preparation: nil, caution: nil, offLabel: nil, source: "label")
        XCTAssertEqual(InfusionCalc.lines(for: ntg, weightKg: 1e-300).equivalent, "Check the weight")
        // And an ordinary adult weight reads as before.
        XCTAssertEqual(InfusionCalc.lines(for: ntg, weightKg: 100).equivalent, "0.05 mcg/kg/min at 100 kg")
    }

    // MARK: The weight check

    private func msg(_ kg: Double?, _ y: Int = 0, _ m: Int = 0) -> String? { PedsCalc.verdict(weightKg: kg, years: y, months: m).message }
    private func used(_ kg: Double?, _ y: Int = 0, _ m: Int = 0) -> Double? { PedsCalc.verdict(weightKg: kg, years: y, months: m).weightKg }

    func testNoWeightIsNotImplausible() {
        XCTAssertNil(msg(nil)); XCTAssertNil(used(nil))
        XCTAssertNil(msg(nil, 5, 0))
    }

    func testWeightLimitsWithNoAge() {
        // 0.4 kg to 150 kg are inside; the message is the short one.
        XCTAssertEqual(used(0.4), 0.4); XCTAssertNil(msg(0.4))
        XCTAssertEqual(used(150), 150); XCTAssertNil(msg(150))
        XCTAssertEqual(used(18), 18)
        for bad in [0.39, 0.0, -3, 150.1, 1e20, .infinity, -.infinity, .nan] as [Double] {
            XCTAssertNil(used(bad), "\(bad)")
            XCTAssertEqual(msg(bad), "Check the weight", "\(bad): no age entered, so the age is not the reason")
        }
    }

    func testWeightAgainstTheAgeEstimate() {
        // 5 years: the estimate is 18 kg, so 6 to 54 kg stand.
        XCTAssertEqual(PedsCalc.estimatedWeight(years: 5, months: 0), 18)
        XCTAssertEqual(used(54, 5), 54); XCTAssertEqual(used(6, 5), 6)
        XCTAssertEqual(msg(54.01, 5), "Check the weight against the age"); XCTAssertNil(used(54.01, 5))
        XCTAssertEqual(msg(5.99, 5), "Check the weight against the age"); XCTAssertNil(used(5.99, 5))
        // 6 months: the estimate is 7 kg, so about 2.33 to 21 kg.
        XCTAssertEqual(used(21, 0, 6), 21); XCTAssertEqual(msg(21.01, 0, 6), "Check the weight against the age")
        XCTAssertEqual(used(2.34, 0, 6), 2.34); XCTAssertEqual(msg(2.33, 0, 6), "Check the weight against the age")
        // Over 150 kg with an age entered: the age is the reason. Under 0.4 kg stays the number's own fault.
        XCTAssertEqual(msg(150.1, 16), "Check the weight against the age"); XCTAssertEqual(msg(1e20, 0, 3), "Check the weight against the age")
        XCTAssertEqual(msg(0.39, 5), "Check the weight"); XCTAssertEqual(msg(0, 5), "Check the weight")
        // A teenager has no estimate (it stops at 12 years): only the absolute limits apply.
        XCTAssertNil(PedsCalc.estimatedWeight(years: 14, months: 0))
        XCTAssertEqual(used(150, 14), 150); XCTAssertEqual(used(30, 14), 30); XCTAssertEqual(used(0.4, 14), 0.4)
        // Under 1 month there is no estimate either, so a newborn weight is only held to the absolute limits.
        XCTAssertEqual(used(2.5, 0, 0), 2.5)
    }

    func testTheAgeEstimateItselfIsAlwaysAccepted() throws {
        for y in 0...12 {
            for m in 0...11 {
                guard let e = PedsCalc.estimatedWeight(years: y, months: m) else { continue }
                XCTAssertEqual(used(e, y, m), e, "\(y) y \(m) mo: the \"Use the APLS estimate\" button must never be refused")
                XCTAssertEqual(used(Double(PedsCalc.fmt(e)), y, m), Double(PedsCalc.fmt(e)), "\(y) y \(m) mo, as the button writes it")
            }
        }
    }

    func testTheFieldTextIsReadForTheCheck() {
        func v(_ t: String, _ y: Int = 0, _ m: Int = 0) -> PedsCalc.WeightVerdict { PedsCalc.verdict(text: t, years: y, months: m) }
        // Nothing typed, or no number: no weight and no warning (the field's own "Required" prompt speaks).
        XCTAssertNil(v("").message); XCTAssertNil(v("").weightKg)
        XCTAssertNil(v("  ").message)
        XCTAssertNil(v("abc").message); XCTAssertNil(v("2.5.3").message)
        // A 0 or a negative number was typed: it is named, not treated as empty.
        XCTAssertEqual(v("0").message, "Check the weight")
        XCTAssertEqual(v("-5").message, "Check the weight")
        XCTAssertEqual(v("inf").message, "Check the weight")
        XCTAssertEqual(v("nan").message, "Check the weight")
        XCTAssertEqual(v("99999999999999999999").message, "Check the weight", "20 digits pasted into the field")
        XCTAssertEqual(v("99999999999999999999", 4).message, "Check the weight against the age")
        // A comma is a decimal point, as in the weight field.
        XCTAssertEqual(v("2,5").weightKg, 2.5)
        XCTAssertEqual(v(" 18 ", 5).weightKg, 18)
        XCTAssertEqual(PedsCalc.typedWeight("2,5"), 2.5)
    }

    // MARK: The newborn airway line

    func testUnderThreeKgAddsTheByWeightTubeCaution() {
        let line = "Under 3 kg: choose tube size and depth by weight from your neonatal chart; the values shown are by age."
        XCTAssertEqual(PedsCalc.newbornAirwayNote(weightKg: 2.5), line)
        XCTAssertEqual(PedsCalc.newbornAirwayNote(weightKg: 0.4), line)
        XCTAssertEqual(PedsCalc.newbornAirwayNote(weightKg: 2.99), line)
        XCTAssertNil(PedsCalc.newbornAirwayNote(weightKg: 3), "3 kg is not under 3 kg")
        XCTAssertNil(PedsCalc.newbornAirwayNote(weightKg: 18))
        XCTAssertNil(PedsCalc.newbornAirwayNote(weightKg: nil))
        XCTAssertNil(PedsCalc.newbornAirwayNote(weightKg: .nan))
        // The sizes themselves are still by age only: no new size is worked out from the weight.
        XCTAssertEqual(PedsCalc.ettSizes(years: 0, months: 0).uncuffed, "3.0–3.5")
        XCTAssertEqual(PedsCalc.ettSizes(years: 0, months: 0).cuffed, "3.0")
        // An implausible weight never reaches the line (the screen passes the verdict's weight).
        XCTAssertNil(PedsCalc.newbornAirwayNote(weightKg: PedsCalc.verdict(text: "0.3", years: 0, months: 0).weightKg))
        XCTAssertNotNil(PedsCalc.newbornAirwayNote(weightKg: PedsCalc.verdict(text: "2.5", years: 0, months: 1).weightKg))
    }

    // MARK: The medications and hematology screen is adult dosing

    func testInfusionsLineAndWeightFromMyPatient() {
        var child = PatientRecord()
        child.ageYears = 8; child.weightKg = 28
        XCTAssertEqual(InfusionsView.adultNote(for: child), "Adult doses: the case is a child")
        XCTAssertNil(InfusionsView.patientWeight(for: child), "a child's weight is not filled into the adult list")
        child.ageYears = 17.9
        XCTAssertNil(InfusionsView.patientWeight(for: child))

        var adult = PatientRecord()
        adult.ageYears = 67; adult.weightKg = 82
        XCTAssertEqual(InfusionsView.adultNote(for: adult), "Adult doses")
        XCTAssertEqual(InfusionsView.patientWeight(for: adult), 82)
        adult.ageYears = 18
        XCTAssertEqual(InfusionsView.patientWeight(for: adult), 82, "18 is an adult, as on the pediatric and ACLS screens")

        // No age recorded (or no case): adult doses, and the weight is taken as before.
        var unknown = PatientRecord()
        unknown.weightKg = 70
        XCTAssertEqual(InfusionsView.adultNote(for: unknown), "Adult doses")
        XCTAssertEqual(InfusionsView.patientWeight(for: unknown), 70)
        XCTAssertNil(InfusionsView.patientWeight(for: PatientRecord()))
    }

    // MARK: Mechanical support

    func testMcsCautionsAreInViewNotOnlyInTheFooter() throws {
        let m = try XCTUnwrap(try bundled().mcs)
        XCTAssertFalse(m.cautions.isEmpty, "reference.json mcs.cautions is not empty")
        XCTAssertFalse(m.cautionLines.isEmpty, "the view model exposes the cautions for the page")
        XCTAssertEqual(m.cautionLines, m.cautions, "all of them, in the order written")
        XCTAssertTrue(m.cautionLines.contains { $0.contains("Verify all LVAD rows") })
        // The footer holds the legend and sources, so the cautions are not repeated there.
        XCTAssertTrue(m.footerHasContent)
        XCTAssertTrue(m.footerCautions.isEmpty)
        // They are kept in the footer too only when the footer would otherwise be empty.
        var bare = m
        bare.legend = ""; bare.sources = []
        XCTAssertFalse(bare.footerHasContent)
        XCTAssertEqual(bare.footerCautions, bare.cautionLines)
        // A blank caution is never shown.
        var blank = m
        blank.cautions = ["  ", "Reference only.", ""]
        XCTAssertEqual(blank.cautionLines, ["Reference only."])
    }

    func testMcsLegendNamesTheRctTag() throws {
        let m = try XCTUnwrap(try bundled().mcs)
        XCTAssertTrue(m.legend.contains("RCT = from a randomized trial."))
        // Every tag in the device numbers that starts with a word the legend defines is covered by it.
        let flags = Set(m.devices.flatMap(\.rows).compactMap { $0.count > 2 ? $0[2] : nil })
        XCTAssertTrue(flags.contains("RCT"), "the LVAD or Impella tables carry an RCT row")
        for tag in ["Mfr", "Per your team", "Review", "Verify", "G", "RCT"] {
            XCTAssertTrue(m.legend.contains(tag), "the legend explains \(tag)")
        }
    }
}
