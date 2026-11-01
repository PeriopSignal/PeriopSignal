import XCTest
@testable import PeriopSignal

/// Labs: the catalog, flags, the summary and fishbone, MELD 3.0, MELD-Na, Child-Turcotte-Pugh and right heart
/// catheterization. Every expected score was worked out independently, with a separate Python implementation of each
/// formula from the OPTN policy text; MELD-Na also against the OPTN board's own worked example (November 2013).
final class PatientLabsTests: XCTestCase {
    // MARK: Catalog

    func testCatalog() {
        let keys = PatientLabs.catalog.map(\.key)
        XCTAssertEqual(Set(keys).count, keys.count, "no key twice")
        XCTAssertEqual(PatientLabs.tests(.main).map(\.key),
                       ["hb", "hct", "wbc", "plt", "inr", "fibrinogen", "na", "k", "cl", "hco3", "bun", "cr", "gfr",
                        "glucose", "a1c", "albumin", "tbili"],
                       "fibrinogen under INR, GFR under creatinine")
        XCTAssertEqual(PatientLabs.tests(.cardiac).map(\.key), ["bnp", "ntprobnp", "troponin", "troponin99"])
        XCTAssertEqual(PatientLabs.tests(.liver).map(\.key), ["ast", "alt", "alp"])
        XCTAssertEqual(PatientLabs.tests(.thyroid).map(\.key), ["tsh", "ft4", "ft3"])
        // Records saved before this catalog keep reading: every existing key, with its label and unit.
        for f in PatientCatalog.labs {
            XCTAssertEqual(PatientLabs.test(f.id)?.label, f.label, f.id)
            XCTAssertEqual(PatientLabs.test(f.id)?.unit, f.unit, f.id)
        }
        XCTAssertEqual(PatientLabs.test("gfr")?.unit, "mL/min/1.73 m²")
        XCTAssertEqual(PatientLabs.test("fibrinogen")?.unit, "mg/dL")
        XCTAssertEqual(PatientLabs.test("hb")?.rangeText(for: .female), "12–16")
        XCTAssertEqual(PatientLabs.test("hb")?.rangeText(for: .male), "14–18")
        XCTAssertEqual(PatientLabs.test("hb")?.rangeText(for: nil), "12–18", "sex unknown: both ranges together")
        XCTAssertEqual(PatientLabs.test("gfr")?.rangeText(for: nil), "60 or more")
        XCTAssertEqual(PatientLabs.test("bnp")?.rangeText(for: nil), "92 or less")
        XCTAssertEqual(PatientLabs.test("ntprobnp")?.rangeText(for: nil), "under 300")
        XCTAssertNil(PatientLabs.test("troponin")?.rangeText(for: nil), "read against the assay's 99th percentile")
        XCTAssertTrue(PatientLabs.isPlausible("k", 4.2))
        XCTAssertFalse(PatientLabs.isPlausible("k", 42), "a typing error")
        XCTAssertFalse(PatientLabs.isPlausible("na", .nan))
        XCTAssertTrue(PatientLabs.entered(.cardiac, in: ["bnp": 40]))
        XCTAssertFalse(PatientLabs.entered(.cardiac, in: ["hb": 12]))
    }

    // MARK: Flags

    func testFlags() {
        XCTAssertEqual(PatientLabs.flag("hb", 13, sex: .male), .low, "men 14–18 g/dL")
        XCTAssertEqual(PatientLabs.flag("hb", 13, sex: .female), .normal, "women 12–16 g/dL")
        XCTAssertEqual(PatientLabs.flag("hb", 13, sex: nil), .normal, "sex unknown: only outside both ranges")
        XCTAssertEqual(PatientLabs.flag("hb", 11.9, sex: nil), .low)
        XCTAssertEqual(PatientLabs.flag("hb", 17, sex: .female), .high)
        XCTAssertEqual(PatientLabs.flag("k", 5.0, sex: nil), .normal, "the limit itself is normal")
        XCTAssertEqual(PatientLabs.flag("k", 5.1, sex: nil), .high)
        XCTAssertEqual(PatientLabs.flag("k", 3.4, sex: nil), .low)
        XCTAssertEqual(PatientLabs.flag("na", 131, sex: nil), .low)
        XCTAssertEqual(PatientLabs.flag("plt", 98, sex: nil), .low)
        XCTAssertEqual(PatientLabs.flag("inr", 1.6, sex: nil), .high)
        XCTAssertEqual(PatientLabs.flag("fibrinogen", 150, sex: nil), .low)
        XCTAssertEqual(PatientLabs.flag("cr", 1.2, sex: .female), .high)
        XCTAssertEqual(PatientLabs.flag("cr", 1.2, sex: .male), .normal)
        XCTAssertEqual(PatientLabs.flag("gfr", 59, sex: nil), .low, "KDIGO: decreased under 60")
        XCTAssertEqual(PatientLabs.flag("gfr", 60, sex: nil), .normal)
        XCTAssertEqual(PatientLabs.flag("gfr", 130, sex: nil), .normal, "no upper limit")
        XCTAssertEqual(PatientLabs.flag("a1c", 6.1, sex: nil), .high)
        XCTAssertEqual(PatientLabs.flag("tbili", 0.2, sex: nil), .normal, "a low bilirubin is not flagged")
        XCTAssertEqual(PatientLabs.flag("tbili", 1.4, sex: nil), .high)
        XCTAssertEqual(PatientLabs.flag("ast", 8, sex: nil), .normal)
        XCTAssertEqual(PatientLabs.flag("alt", 85, sex: nil), .high)
        XCTAssertEqual(PatientLabs.flag("tsh", 0.3, sex: nil), .low)
        XCTAssertEqual(PatientLabs.flag("ft4", 2.1, sex: nil), .high)
        XCTAssertEqual(PatientLabs.flag("ft3", 2.0, sex: nil), .low)
        XCTAssertEqual(PatientLabs.flag("unknown", 1, sex: nil), .normal)
        XCTAssertEqual(LabFlag.low.mark, "L")
        XCTAssertEqual(LabFlag.high.mark, "H")
        XCTAssertFalse(LabFlag.normal.isAbnormal)
    }

    /// BNP over 92, NT-proBNP 300 or more and troponin above the assay's 99th percentile, as the stepwise cardiac
    /// evaluation reads them (2024 AHA/ACC Figure 1, footnote §).
    func testCardiacFlagsMatchTheCardiacEvaluation() {
        XCTAssertEqual(PatientLabs.flag("bnp", 92, sex: nil), .normal)
        XCTAssertEqual(PatientLabs.flag("bnp", 92.5, sex: nil), .high)
        XCTAssertEqual(PatientLabs.flag("ntprobnp", 299, sex: nil), .normal)
        XCTAssertEqual(PatientLabs.flag("ntprobnp", 300, sex: nil), .high)
        XCTAssertEqual(PatientLabs.flag("troponin", 20, sex: nil, troponin99: 14), .high)
        XCTAssertEqual(PatientLabs.flag("troponin", 14, sex: nil, troponin99: 14), .normal, "not above the percentile")
        XCTAssertEqual(PatientLabs.flag("troponin", 400, sex: nil), .normal, "not read without the assay's 99th percentile")
        for (key, value) in [("bnp", 92.0), ("bnp", 93), ("ntprobnp", 299), ("ntprobnp", 300)] {
            var r = PatientRecord()
            r.labs[key] = value
            XCTAssertEqual(PatientFunctional.biomarkerRaised(r), PatientLabs.flag(key, value, sex: nil) == .high, key + " " + NumText.short(value))
        }
    }

    // MARK: Summary

    func testSummaryAndFishbone() {
        var r = PatientRecord()
        r.sex = .female
        r.labs = ["hb": 9.8, "plt": 98, "wbc": 7.2, "na": 131, "k": 4.1, "cr": 1.42, "glucose": 142, "inr": 1.6,
                  "fibrinogen": 180, "troponin": 20, "troponin99": 14, "tsh": 2.1, "retired-key": 5]
        let s = PatientLabs.summary(r)
        XCTAssertEqual(s.items.map(\.key), ["hb", "wbc", "plt", "inr", "fibrinogen", "na", "k", "cr", "glucose", "troponin", "tsh"],
                       "catalog order; the 99th percentile and unknown keys are not items")
        XCTAssertEqual(s.line, "Hb 9.8 L · WBC 7.2 · Plt 98 L · INR 1.6 H · Fib 180 L · Na 131 L · K 4.1 · Cr 1.42 H · Glu 142 H · Troponin 20 H · TSH 2.1")
        XCTAssertEqual(s.abnormal.map(\.key), ["hb", "plt", "inr", "fibrinogen", "na", "cr", "glucose", "troponin"])
        let trop = s.items.first { $0.key == "troponin" }
        XCTAssertEqual(trop?.note, "assay's 99th percentile 14 ng/L")
        XCTAssertEqual(trop?.rated, true)
        XCTAssertEqual(s.items.first?.unit, "g/dL")

        let fb = s.fishbone
        XCTAssertEqual(fb.hb?.text, "9.8")
        XCTAssertEqual(fb.hb?.flag, .low)
        XCTAssertEqual(fb.wbc?.text, "7.2")
        XCTAssertEqual(fb.plt?.text, "98")
        XCTAssertNil(fb.hct)
        XCTAssertEqual(fb.na?.flag, .low)
        XCTAssertEqual(fb.k?.flag, .normal)
        XCTAssertNil(fb.cl)
        XCTAssertNil(fb.hco3)
        XCTAssertNil(fb.bun)
        XCTAssertEqual(fb.cr?.text, "1.42")
        XCTAssertEqual(fb.cr?.flag, .high, "women 0.50–1.10 mg/dL")
        XCTAssertEqual(fb.glucose?.flag, .high)
        XCTAssertEqual(fb.inr?.text, "1.6")
        XCTAssertEqual(fb.fibrinogen?.flag, .low)
        XCTAssertTrue(fb.hasCBC)
        XCTAssertTrue(fb.hasBMP)
        XCTAssertTrue(fb.hasCoags)
        XCTAssertEqual(fb.cbc.count, 4)
        XCTAssertEqual(fb.bmp.count, 7)

        var noLimit = r
        noLimit.labs["troponin99"] = nil
        let unread = PatientLabs.summary(noLimit).items.first { $0.key == "troponin" }
        XCTAssertEqual(unread?.flag, .normal)
        XCTAssertEqual(unread?.rated, false)
        XCTAssertEqual(unread?.note, "not flagged without the assay's 99th percentile")

        let empty = PatientLabs.summary([:], sex: nil)
        XCTAssertTrue(empty.isEmpty)
        XCTAssertTrue(empty.fishbone.isEmpty)
        XCTAssertEqual(empty.line, "")
        XCTAssertFalse(PatientLabs.summary(["inr": 1.0], sex: nil).fishbone.hasCBC)
        XCTAssertTrue(PatientLabs.summary(["inr": 1.0], sex: nil).fishbone.hasCoags)
    }

    // MARK: MELD 3.0

    func testMeld3() {
        func m3(_ sex: PatientSex, _ bili: Double, _ na: Double, _ inr: Double, _ cr: Double, _ alb: Double,
                dialysis: Bool = false) -> (exact: Double, score: Int) {
            PatientLabs.meld3(sex: sex, bilirubin: bili, sodium: na, inr: inr, creatinine: cr, albumin: alb, dialysis: dialysis)
        }
        // Every value at its bound: 6, the floor; a woman gets 1.33 more.
        XCTAssertEqual(m3(.male, 1, 137, 1, 1, 3.5).exact, 6, accuracy: 1e-9)
        XCTAssertEqual(m3(.male, 1, 137, 1, 1, 3.5).score, 6)
        XCTAssertEqual(m3(.female, 1, 137, 1, 1, 3.5).exact, 7.33, accuracy: 1e-9)
        XCTAssertEqual(m3(.female, 1, 137, 1, 1, 3.5).score, 7)
        // Bilirubin, INR and creatinine under 1.0 count as 1.0; sodium over 137 as 137, albumin over 3.5 as 3.5.
        XCTAssertEqual(m3(.male, 0.4, 140, 0.9, 0.6, 4.2).exact, 6, accuracy: 1e-9)
        // Worked example (independent Python): bilirubin 4.2, sodium 127, INR 1.2, creatinine 1.9, albumin 2.8.
        XCTAssertEqual(m3(.female, 4.2, 127, 1.2, 1.9, 2.8).exact, 27.910123, accuracy: 1e-5)
        XCTAssertEqual(m3(.female, 4.2, 127, 1.2, 1.9, 2.8).score, 28)
        XCTAssertEqual(m3(.male, 4.2, 127, 1.2, 1.9, 2.8).score, 27, "1.33 less for a man")
        XCTAssertEqual(m3(.male, 2.5, 130, 1.6, 1.4, 2.9).exact, 23.140104, accuracy: 1e-5)
        XCTAssertEqual(m3(.female, 1.8, 134, 1.3, 1.1, 3.2).exact, 15.996422, accuracy: 1e-5)
        XCTAssertEqual(m3(.female, 1.8, 134, 1.3, 1.1, 3.2).score, 16, "15.996 rounds to 16")
        // Sodium 125–137.
        XCTAssertEqual(m3(.male, 2, 120, 1.3, 1.2, 3).exact, m3(.male, 2, 125, 1.3, 1.2, 3).exact, accuracy: 1e-9)
        XCTAssertEqual(m3(.male, 2, 125, 1.3, 1.2, 3).exact, 22.178616, accuracy: 1e-5)
        // Albumin 1.5–3.5.
        XCTAssertEqual(m3(.female, 2, 132, 1.4, 1.1, 1.0).exact, m3(.female, 2, 132, 1.4, 1.1, 1.5).exact, accuracy: 1e-9)
        XCTAssertEqual(m3(.female, 2, 132, 1.4, 1.1, 1.5).exact, 21.230427, accuracy: 1e-5)
        // Creatinine capped at 3.0, and dialysis counts as 3.0 whatever the creatinine.
        XCTAssertEqual(m3(.male, 2, 135, 1.3, 3.0, 3).exact, 25.011242, accuracy: 1e-5)
        XCTAssertEqual(m3(.male, 2, 135, 1.3, 5.0, 3).exact, m3(.male, 2, 135, 1.3, 3.0, 3).exact, accuracy: 1e-9)
        XCTAssertEqual(m3(.male, 2, 135, 1.3, 1.2, 3, dialysis: true).exact, m3(.male, 2, 135, 1.3, 3.0, 3).exact, accuracy: 1e-9)
        XCTAssertEqual(m3(.male, 2, 135, 1.3, 0.8, 3, dialysis: true).score, 25)
        // Kim 2021: the creatinine term tops out near 12 points (11.14 × ln 3).
        XCTAssertEqual(m3(.male, 1, 137, 1, 3, 3.5).exact - 6, 12.238541, accuracy: 1e-5)
        // Kim 2021: from a creatinine of about 2.75 up, a lower albumin lowers the score a little; below it, raises it.
        XCTAssertGreaterThan(m3(.male, 2, 135, 1.3, 1.5, 2.0).exact, m3(.male, 2, 135, 1.3, 1.5, 3.0).exact)
        XCTAssertLessThan(m3(.male, 2, 135, 1.3, 2.9, 2.0).exact, m3(.male, 2, 135, 1.3, 2.9, 3.0).exact)
        // The OPTN maximum, 40.
        XCTAssertEqual(m3(.male, 30, 125, 4, 3, 1.5).exact, 46.073047, accuracy: 1e-5)
        XCTAssertEqual(m3(.male, 30, 125, 4, 3, 1.5).score, 40)
    }

    // MARK: MELD-Na

    func testMeldNa() {
        func na(_ bili: Double, _ sodium: Double, _ inr: Double, _ cr: Double, dialysis: Bool = false) -> (initial: Int, exact: Double, score: Int) {
            PatientLabs.meldNa(bilirubin: bili, sodium: sodium, inr: inr, creatinine: cr, dialysis: dialysis)
        }
        // The OPTN board's worked example (November 2013): MELD(i) 2.0039, so 20; 20 + 1.32 × 10 − 0.033 × 20 × 10 = 26.6.
        XCTAssertEqual(na(4.2, 127, 1.2, 1.9).initial, 20)
        XCTAssertEqual(na(4.2, 127, 1.2, 1.9).exact, 26.6, accuracy: 1e-9)
        XCTAssertEqual(na(4.2, 127, 1.2, 1.9).score, 27)
        XCTAssertEqual(na(4.2, 133, 1.2, 1.9).score, 23, "the same labs with sodium 133")
        // Sodium is added only above an initial MELD of 11.
        XCTAssertEqual(na(3.8, 128, 1, 1).initial, 11)
        XCTAssertEqual(na(3.8, 128, 1, 1).score, 11, "MELD(i) 11: no sodium term")
        XCTAssertEqual(na(3.9, 128, 1, 1).initial, 12)
        XCTAssertEqual(na(3.9, 128, 1, 1).score, 20, "12 + 1.32 × 9 − 0.033 × 12 × 9 = 20.3")
        XCTAssertEqual(na(1.5, 128, 1.1, 1.0).score, 9)
        // Creatinine capped at 4.0 (not 3.0), and dialysis counts as 4.0.
        XCTAssertEqual(na(2, 135, 1.3, 4.0).score, 26)
        XCTAssertEqual(na(2, 135, 1.3, 6.0).exact, na(2, 135, 1.3, 4.0).exact, accuracy: 1e-9)
        XCTAssertEqual(na(2, 135, 1.3, 1.2, dialysis: true).exact, na(2, 135, 1.3, 4.0).exact, accuracy: 1e-9)
        // Sodium 125–137.
        XCTAssertEqual(na(3, 120, 1.5, 1.2).score, 26)
        XCTAssertEqual(na(3, 120, 1.5, 1.2).exact, na(3, 125, 1.5, 1.2).exact, accuracy: 1e-9)
        XCTAssertEqual(na(3, 140, 1.5, 1.2).score, 17, "over 137 counts as 137: no sodium points")
        // The maximum, 40.
        XCTAssertEqual(na(30, 125, 4, 4).initial, 48)
        XCTAssertEqual(na(30, 125, 4, 4).score, 40)
    }

    // MARK: Child-Turcotte-Pugh

    func testChildPugh() {
        func pts(_ bili: Double, _ alb: Double, _ inr: Double, _ asc: LiverAscites, _ enc: LiverEncephalopathy) -> ChildPughPoints {
            PatientLabs.childPughPoints(bilirubin: bili, albumin: alb, inr: inr, ascites: asc, encephalopathy: enc)
        }
        XCTAssertEqual(pts(1.5, 3.6, 1.2, .absent, .absent).total, 5)
        XCTAssertEqual(pts(1.99, 3.51, 1.69, .absent, .absent).total, 5, "just inside the 1-point bands")
        // Band edges: bilirubin 2 and 3, albumin 3.5 and 2.8, INR 1.7 and 2.3 are all 2 points.
        let low = pts(2.0, 3.5, 1.7, .slight, .grade1to2)
        XCTAssertEqual([low.bilirubin, low.albumin, low.inr, low.ascites, low.encephalopathy], [2, 2, 2, 2, 2])
        XCTAssertEqual(low.total, 10)
        let high = pts(3.0, 2.8, 2.3, .absent, .absent)
        XCTAssertEqual([high.bilirubin, high.albumin, high.inr], [2, 2, 2])
        XCTAssertEqual(high.total, 8)
        let worst = pts(3.1, 2.7, 2.31, .moderate, .grade3to4)
        XCTAssertEqual([worst.bilirubin, worst.albumin, worst.inr, worst.ascites, worst.encephalopathy], [3, 3, 3, 3, 3])
        XCTAssertEqual(worst.total, 15)
        XCTAssertEqual(ChildPughClass(points: 5), .a)
        XCTAssertEqual(ChildPughClass(points: 6), .a)
        XCTAssertEqual(ChildPughClass(points: 7), .b)
        XCTAssertEqual(ChildPughClass(points: 9), .b)
        XCTAssertEqual(ChildPughClass(points: 10), .c)
        XCTAssertEqual(ChildPughClass.c.range, "10–15")
        XCTAssertNil(PatientLabs.childPughPoints(bilirubin: 2, albumin: 3, inr: 1.2, ascites: nil, encephalopathy: .absent).total)
    }

    // MARK: Liver, all three with the reading

    func testLiverScores() {
        let x = LiverInput(sex: .male, bilirubin: 2.5, sodium: 130, inr: 1.6, creatinine: 1.4, albumin: 2.9,
                           ascites: .slight, encephalopathy: .absent)
        let r = PatientLabs.liver(x)
        XCTAssertEqual(r.meld3, 23)
        XCTAssertEqual(r.meld3Exact ?? 0, 23.140104, accuracy: 1e-5)
        XCTAssertEqual(r.meldInitial, 18)
        XCTAssertEqual(r.meldNa, 23)
        XCTAssertEqual(r.points.bilirubin, 2)
        XCTAssertEqual(r.points.albumin, 2)
        XCTAssertEqual(r.points.inr, 1)
        XCTAssertEqual(r.points.ascites, 2)
        XCTAssertEqual(r.points.encephalopathy, 1)
        XCTAssertEqual(r.childPugh, 8)
        XCTAssertEqual(r.childPughClass, .b)
        XCTAssertTrue(r.missing.isEmpty)
        XCTAssertTrue(r.adjustments.isEmpty)
        XCTAssertEqual(r.interpretation.first, "Child-Turcotte-Pugh class B (7–9 points). " + PatientLabs.ctpReading)
        XCTAssertTrue(r.interpretation.contains(PatientLabs.meldReading))
        XCTAssertTrue(r.interpretation.contains(PatientLabs.decompensatedReading), "class B")
        XCTAssertEqual(r.interpretation.last, PatientLabs.calculatorReading)
        XCTAssertFalse(r.interpretation.contains(PatientLabs.emergencyReading))
        for line in r.interpretation {
            XCTAssertTrue(line.hasSuffix(")."), "each reading ends with its source: " + line)
        }

        var compensated = x
        compensated.ascites = .absent
        compensated.bilirubin = 1.2
        compensated.emergency = true
        let a = PatientLabs.liver(compensated)
        XCTAssertEqual(a.childPughClass, .a)
        XCTAssertFalse(a.interpretation.contains(PatientLabs.decompensatedReading))
        XCTAssertTrue(a.interpretation.contains(PatientLabs.emergencyReading))

        // Missing inputs: each score lists its own.
        let partial = PatientLabs.liver(LiverInput(bilirubin: 2.5, inr: 1.6, creatinine: 1.4))
        XCTAssertNil(partial.meld3)
        XCTAssertEqual(partial.missingMeld3, ["sex", "sodium", "albumin"])
        XCTAssertNil(partial.meldNa)
        XCTAssertEqual(partial.missingMeldNa, ["sodium"])
        XCTAssertNil(partial.childPugh)
        XCTAssertEqual(partial.missingChildPugh, ["albumin", "ascites", "encephalopathy"])
        XCTAssertEqual(partial.missing, ["sex", "sodium", "albumin", "ascites", "encephalopathy"])
        XCTAssertEqual(partial.points.bilirubin, 2, "points shown as soon as the input is in")
        XCTAssertTrue(partial.interpretation.isEmpty)

        // Dialysis: creatinine not needed, and counted as 3.0 (MELD 3.0) and 4.0 (MELD-Na).
        let dialysis = PatientLabs.liver(LiverInput(sex: .male, bilirubin: 2, sodium: 135, inr: 1.3, albumin: 3, dialysis: true))
        XCTAssertEqual(dialysis.meld3, 25)
        XCTAssertEqual(dialysis.meldNa, 26)
        XCTAssertFalse(dialysis.missing.contains("creatinine"))
        XCTAssertEqual(dialysis.adjustments.first, "Dialysis: creatinine counted as 3.0 for MELD 3.0 and 4.0 for MELD-Na.")
        let capped = PatientLabs.liver(LiverInput(sex: .male, bilirubin: 30, sodium: 122, inr: 4, creatinine: 4.5, albumin: 1.2))
        XCTAssertEqual(capped.meld3, 40)
        XCTAssertEqual(capped.meldNa, 40)
        XCTAssertTrue(capped.adjustments.contains("Sodium under 125 counted as 125."))
        XCTAssertTrue(capped.adjustments.contains("Albumin under 1.5 counted as 1.5 for MELD 3.0."))
        XCTAssertTrue(capped.adjustments.contains("MELD 3.0 over 40 is reported as 40, the OPTN maximum."))
        XCTAssertTrue(capped.adjustments.contains("Creatinine counted as 3.0 for MELD 3.0 and 4.0 for MELD-Na, their caps."))

        // From the record: sex, the labs and the urgency.
        var rec = PatientRecord()
        rec.sex = .female
        rec.urgency = .emergency
        rec.labs = ["tbili": 3.4, "na": 128, "inr": 1.9, "cr": 1.6, "albumin": 2.6]
        let fromRecord = PatientLabs.liver(LiverInput(record: rec, ascites: .slight, encephalopathy: .grade1to2))
        XCTAssertEqual(fromRecord.meld3Exact ?? 0, 29.608257, accuracy: 1e-5)
        XCTAssertEqual(fromRecord.meld3, 30)
        XCTAssertEqual(fromRecord.meldInitial, 23)
        XCTAssertEqual(fromRecord.meldNa, 28)
        XCTAssertEqual(fromRecord.childPugh, 12)
        XCTAssertEqual(fromRecord.childPughClass, .c)
        XCTAssertTrue(fromRecord.interpretation.contains(PatientLabs.emergencyReading))
    }

    // MARK: Right heart catheterization

    func testRightHeartNormal() {
        let r = PatientLabs.rightHeart(RightHeartInput(ra: 5, pasp: 25, padp: 10, pcwp: 9, co: 5.0, bsa: 1.9))
        XCTAssertEqual(r.mpap ?? 0, 15, accuracy: 1e-9, "(25 + 2 × 10) / 3")
        XCTAssertTrue(r.mpapEstimated)
        XCTAssertTrue(r.notes.contains(PatientLabs.mpapEstimateNote))
        XCTAssertEqual(r.tpg ?? 0, 6, accuracy: 1e-9)
        XCTAssertEqual(r.dpg ?? 0, 1, accuracy: 1e-9)
        XCTAssertEqual(r.pvr ?? 0, 1.2, accuracy: 1e-9)
        XCTAssertEqual(r.papi ?? 0, 3.0, accuracy: 1e-9)
        XCTAssertEqual(r.ci ?? 0, 2.631579, accuracy: 1e-5)
        XCTAssertEqual(r.pvri ?? 0, 2.28, accuracy: 1e-9)
        XCTAssertEqual(r.ph, .noPH)
        XCTAssertEqual(r.phText, "No pulmonary hypertension at rest: mPAP 20 mmHg or less (2022 ESC/ERS).")
        XCTAssertTrue(r.papiBelow.isEmpty)
        let near = PatientLabs.rightHeart(RightHeartInput(ra: 5, pasp: 33, padp: 14, pcwp: 9, co: 5.0, bsa: 1.9))
        XCTAssertTrue(near.phText?.hasSuffix("confirm with a measured mean.") ?? false, "an estimate of about 20 mmHg is flagged")
        XCTAssertTrue(r.missing.isEmpty)
    }

    func testRightHeartCombinedPreAndPostCapillary() {
        let r = PatientLabs.rightHeart(RightHeartInput(ra: 12, pasp: 60, padp: 28, mpap: 40, pcwp: 22, co: 4.0, bsa: 2.0))
        XCTAssertEqual(r.mpap ?? 0, 40, accuracy: 1e-9)
        XCTAssertFalse(r.mpapEstimated, "measured mean used")
        XCTAssertEqual(r.tpg ?? 0, 18, accuracy: 1e-9)
        XCTAssertEqual(r.dpg ?? 0, 6, accuracy: 1e-9)
        XCTAssertEqual(r.pvr ?? 0, 4.5, accuracy: 1e-9)
        XCTAssertEqual(r.papi ?? 0, 2.666667, accuracy: 1e-5)
        XCTAssertEqual(r.ci ?? 0, 2.0, accuracy: 1e-9)
        XCTAssertEqual(r.pvri ?? 0, 9.0, accuracy: 1e-9)
        XCTAssertEqual(r.ph, .combined)
        XCTAssertEqual(r.ph?.short, "CpcPH")
        XCTAssertFalse(r.notes.contains(PatientLabs.severePVRNote), "PVR 4.5")
        let severe = PatientLabs.rightHeart(RightHeartInput(ra: 14, pasp: 80, padp: 35, mpap: 50, pcwp: 20, co: 5.0))
        XCTAssertEqual(severe.pvr ?? 0, 6.0, accuracy: 1e-9)
        XCTAssertEqual(severe.ph, .combined)
        XCTAssertTrue(severe.notes.contains(PatientLabs.severePVRNote), "PVR over 5 WU")
        XCTAssertNil(severe.ci, "no BSA, no indexed values")
        XCTAssertNil(severe.pvri)
    }

    func testRightHeartClasses() {
        func ph(_ x: RightHeartInput) -> PHHemodynamics? { PatientLabs.rightHeart(x).ph }
        XCTAssertEqual(ph(RightHeartInput(ra: 8, pasp: 70, padp: 30, mpap: 45, pcwp: 10, co: 4)), .preCapillary)
        XCTAssertEqual(PatientLabs.rightHeart(RightHeartInput(ra: 8, pasp: 70, padp: 30, mpap: 45, pcwp: 10, co: 4)).pvr ?? 0, 8.75, accuracy: 1e-9)
        XCTAssertEqual(ph(RightHeartInput(ra: 10, pasp: 45, padp: 22, mpap: 30, pcwp: 22, co: 5)), .isolatedPostCapillary)
        XCTAssertEqual(ph(RightHeartInput(ra: 6, pasp: 35, padp: 18, mpap: 24, pcwp: 12, co: 7)), .unclassified)
        // The edges: mPAP 20 is not PH; PAWP 15 is "15 or less"; PVR 2 is "2 or less".
        XCTAssertEqual(ph(RightHeartInput(pasp: 32, padp: 14, pcwp: 10)), .noPH, "estimated mPAP exactly 20, no output needed")
        XCTAssertEqual(ph(RightHeartInput(mpap: 30, pcwp: 15, co: 5)), .preCapillary, "PAWP 15, PVR 3")
        XCTAssertEqual(ph(RightHeartInput(mpap: 30, pcwp: 20, co: 5)), .isolatedPostCapillary, "PVR exactly 2")
        XCTAssertNil(ph(RightHeartInput(mpap: 30, pcwp: 20)), "PH, but no cardiac output to separate the classes")
    }

    func testPAPIAndGuards() {
        let p = PatientLabs.rightHeart(RightHeartInput(ra: 10, pasp: 30, padp: 21))
        XCTAssertEqual(p.papi ?? 0, 0.9, accuracy: 1e-9)
        XCTAssertEqual(p.papiBelow.map(\.id), ["inferior-mi", "lvad-morine", "lvad-kang"], "0.9 or less meets all three")
        XCTAssertNil(p.ph)
        XCTAssertEqual(p.missing, ["PCWP", "cardiac output"])
        let mid = PatientLabs.rightHeart(RightHeartInput(ra: 10, pasp: 40, padp: 21))
        XCTAssertEqual(mid.papi ?? 0, 1.9, accuracy: 1e-9)
        XCTAssertEqual(mid.papiBelow.map(\.id), ["lvad-kang"], "under 2.0, not under 1.85")
        XCTAssertEqual(PatientLabs.papiThresholds.map(\.cutoff), [0.9, 1.85, 2.0])
        XCTAssertTrue(PatientLabs.papiThresholds[0].text.hasSuffix("(Korabathina 2012)."))

        // Divide-by-zero guards: RA 0 and cardiac output 0 give no PAPI or PVR.
        let zero = PatientLabs.rightHeart(RightHeartInput(ra: 0, pasp: 50, padp: 25, pcwp: 18, co: 0))
        XCTAssertNil(zero.papi)
        XCTAssertNil(zero.pvr)
        XCTAssertNil(zero.ph, "mPAP over 20 but no PVR")
        XCTAssertEqual(zero.tpg ?? 0, 15.333333, accuracy: 1e-5)
        XCTAssertEqual(zero.dpg ?? 0, 7, accuracy: 1e-9)
        XCTAssertEqual(zero.missing, ["cardiac output"])
        XCTAssertTrue(zero.notes.contains("PAPI needs an RA pressure above 0 mmHg."))
        let noBSA = PatientLabs.rightHeart(RightHeartInput(co: 5, bsa: 0))
        XCTAssertNil(noBSA.ci)

        // Systolic below diastolic: no estimate and no PAPI.
        let swapped = PatientLabs.rightHeart(RightHeartInput(ra: 8, pasp: 20, padp: 30, pcwp: 10, co: 5))
        XCTAssertNil(swapped.mpap)
        XCTAssertNil(swapped.papi)
        XCTAssertTrue(swapped.notes.contains("PA systolic is below PA diastolic: check the values."))

        let empty = PatientLabs.rightHeart(RightHeartInput())
        XCTAssertNil(empty.mpap)
        XCTAssertNil(empty.tpg)
        XCTAssertNil(empty.dpg)
        XCTAssertNil(empty.pvr)
        XCTAssertNil(empty.papi)
        XCTAssertNil(empty.ph)
        XCTAssertEqual(empty.missing, ["RA", "PA systolic", "PA diastolic", "PCWP", "cardiac output"])
    }
}
