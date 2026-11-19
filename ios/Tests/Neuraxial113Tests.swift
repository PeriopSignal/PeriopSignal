import XCTest
@testable import PeriopSignal

/// 1.13 (Ben, Nov 19, after an outside review): "Blocks on anticoagulants". Every hold interval in reference.json is pinned here
/// by hand, so a typing slip in the data fails a test and a deliberate edit has to be made in two places. The tool starts with
/// no dose and no kidney row chosen and shows a prompt in place of a time until they are, and the "avoid" answer for the
/// parenteral direct thrombin inhibitors rests on a flag in the data rather than one word in a sentence.
final class Neuraxial113Tests: XCTestCase {

    // MARK: Helpers

    private func bundled() throws -> ReferenceBundle {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reference", withExtension: "json"), "reference.json is bundled with the tests")
        return try ReferenceLoader.decode(try Data(contentsOf: url))
    }

    private func drugs() throws -> [NeuraxialDrug] {
        try XCTUnwrap(try bundled().neuraxial).allDrugs
    }

    private func drug(_ id: String, file: StaticString = #filePath, line: UInt = #line) throws -> NeuraxialDrug {
        try XCTUnwrap(try drugs().first { $0.id == id }, "no drug \(id)", file: file, line: line)
    }

    private func tier(_ drugID: String, _ tierID: String, file: StaticString = #filePath, line: UInt = #line) throws -> NeuraxialTier {
        try XCTUnwrap(try drug(drugID, file: file, line: line).tiers.first { $0.id == tierID }, "no tier \(drugID)/\(tierID)", file: file, line: line)
    }

    private let last = Date(timeIntervalSince1970: 1_700_000_000)

    private func plainTier(id: String = "t", holdHours: Double? = nil, holdText: String? = nil, avoid: Bool? = nil, renal: [RenalRule]? = nil) -> NeuraxialTier {
        NeuraxialTier(id: id, label: id, holdHours: holdHours, restartHours: nil, holdText: holdText, restartText: nil, catheter: nil, level: nil,
                      renal: renal, renalNote: nil, removalHours: nil, afterRemovalHours: nil, inrRule: nil, avoid: avoid)
    }

    // MARK: The numbers, pinned

    /// One hold interval as it stands in reference.json on Nov 19, 2026 (ASRA fifth edition). A row without `kidney` is the
    /// tier's own `holdHours`; a row with `kidney` is that kidney row's hours. `avoid` is true where the answer is to avoid the block.
    private struct Pin {
        let drug: String
        let tier: String
        let kidney: String?
        let hours: Double?
        let elderly: Double?
        let avoid: Bool
        init(_ drug: String, _ tier: String, kidney: String? = nil, hours: Double?, elderly: Double? = nil, avoid: Bool = false) {
            self.drug = drug; self.tier = tier; self.kidney = kidney; self.hours = hours; self.elderly = elderly; self.avoid = avoid
        }
        var key: String { "\(drug)/\(tier)/\(kidney ?? "-")" }
    }

    private static let pins: [Pin] = [
        // Heparins
        Pin("ufh-sc", "low", hours: 6),
        Pin("ufh-sc", "high1", hours: 12),
        Pin("ufh-sc", "high2", hours: 24),
        Pin("ufh-iv", "iv", hours: 6),
        Pin("lmwh", "low", hours: 12),
        Pin("lmwh", "high", hours: 24),
        // Oral Anticoagulants
        Pin("warfarin", "w", hours: 120),
        Pin("apixaban", "high", hours: 72),
        Pin("apixaban", "low", hours: 36),
        Pin("rivaroxaban", "high", hours: 72),
        Pin("rivaroxaban", "low", hours: 24),
        Pin("rivaroxaban", "low", kidney: "CrCl 30 mL/min or more", hours: 24),
        Pin("rivaroxaban", "low", kidney: "CrCl below 30 mL/min", hours: 30),
        Pin("edoxaban", "high", hours: 72),
        Pin("dabigatran", "high", hours: 72),
        Pin("dabigatran", "high", kidney: "CrCl 50 mL/min or more", hours: 72),
        Pin("dabigatran", "high", kidney: "CrCl 30–49 mL/min", hours: 120),
        Pin("dabigatran", "high", kidney: "CrCl below 30 mL/min", hours: nil, avoid: true),
        Pin("dabigatran", "low", hours: 48),
        Pin("dabigatran", "low", kidney: "CrCl 30 mL/min or more", hours: 48),
        Pin("dabigatran", "low", kidney: "CrCl below 30 mL/min", hours: nil, avoid: true),
        // Parenteral Anticoagulants
        Pin("fondaparinux", "low", hours: 36),
        Pin("fondaparinux", "low", kidney: "Normal renal function", hours: 36, elderly: 42),
        Pin("fondaparinux", "low", kidney: "CrCl 30–50 mL/min", hours: 58),
        Pin("fondaparinux", "low", kidney: "CrCl below 30 mL/min", hours: nil, avoid: true),
        Pin("fondaparinux", "high", hours: 70),
        Pin("fondaparinux", "high", kidney: "Normal renal function", hours: 70, elderly: 105),
        Pin("fondaparinux", "high", kidney: "CrCl 30–50 mL/min (no separate interval given: consider a calibrated anti-Xa)", hours: 70, elderly: 105),
        Pin("fondaparinux", "high", kidney: "CrCl below 30 mL/min", hours: nil, avoid: true),
        Pin("dti", "any", hours: nil, avoid: true),
        Pin("thrombolytic", "any", hours: 48),
        // Antiplatelet Drugs
        Pin("aspirin", "any", hours: 0),
        Pin("clopidogrel", "any", hours: 168),
        Pin("prasugrel", "any", hours: 240),
        Pin("ticagrelor", "any", hours: 120),
        Pin("cangrelor", "any", hours: 3),
        Pin("gp2b3a", "abciximab", hours: 48),
        Pin("gp2b3a", "small", hours: 8),
        Pin("cilostazol", "any", hours: 48),
        Pin("herbal", "any", hours: 0),
    ]

    /// Every tier and every kidney row in the file, as the keys the pins use.
    private func bundleKeys() throws -> [String] {
        var keys: [String] = []
        for d in try drugs() {
            for t in d.tiers {
                keys.append("\(d.id)/\(t.id)/-")
                for r in t.renal ?? [] { keys.append("\(d.id)/\(t.id)/\(r.label)") }
            }
        }
        return keys
    }

    func testEveryHoldIntervalInTheFileIsPinned() throws {
        let keys = Self.pins.map(\.key)
        XCTAssertEqual(Set(keys).count, keys.count, "a row is pinned twice")
        XCTAssertEqual(Set(try bundleKeys()), Set(keys), "a tier or kidney row was added, removed or renamed in reference.json: pin it here on purpose")
        for p in Self.pins {
            let t = try tier(p.drug, p.tier)
            if let label = p.kidney {
                let r = try XCTUnwrap(t.renal?.first { $0.label == label }, p.key)
                XCTAssertEqual(r.hours, p.hours, "\(p.key) hours")
                XCTAssertEqual(r.elderlyHours, p.elderly, "\(p.key) elderly hours")
            } else {
                XCTAssertEqual(t.holdHours, p.hours, "\(p.key) hours")
            }
        }
    }

    /// The same numbers through the calculation, so what the screen shows (hours, and avoid) matches the pins too.
    func testPinnedAnswersFollowTheNumbers() throws {
        for p in Self.pins {
            let t = try tier(p.drug, p.tier)
            if let label = p.kidney {
                let i = try XCTUnwrap(t.renal?.firstIndex { $0.label == label }, p.key)
                let a = NeuraxialCalc.answer(tier: t, renalIndex: i, elderly: false, lastDose: last)
                XCTAssertEqual(a.hours, p.hours, "\(p.key) answer hours")
                XCTAssertEqual(a.avoid, p.avoid, "\(p.key) avoid")
                XCTAssertEqual(a.earliest, p.hours.map { last.addingTimeInterval($0 * 3600) }, "\(p.key) earliest")
                if let e = p.elderly {
                    let old = NeuraxialCalc.answer(tier: t, renalIndex: i, elderly: true, lastDose: last)
                    XCTAssertEqual(old.hours, e, "\(p.key) elderly answer hours")
                }
            } else if (t.renal ?? []).isEmpty {
                let a = NeuraxialCalc.answer(tier: t, renalIndex: nil, elderly: false, lastDose: last)
                XCTAssertEqual(a.hours, p.hours, "\(p.key) answer hours")
                XCTAssertEqual(a.avoid, p.avoid, "\(p.key) avoid")
            }
        }
    }

    // MARK: Nothing is chosen for the user

    func testMultiTierDrugStartsWithNoDoseAndNoAnswer() throws {
        let lmwh = try drug("lmwh")
        var s = NeuraxialSelection()
        XCTAssertEqual(s.stage(drug: nil), .chooseDrug)
        s.selectDrug(lmwh)
        XCTAssertNil(s.tierID)
        XCTAssertNil(s.tier(in: lmwh))
        XCTAssertEqual(s.stage(drug: lmwh), .chooseDose)
        XCTAssertNil(s.answer(drug: lmwh, lastDose: last), "no time before the dose is chosen")
        XCTAssertEqual(NeuraxialSelection.prompt(for: s.stage(drug: lmwh)), "Choose the dose")
        s.selectTier(try XCTUnwrap(lmwh.tiers.first { $0.id == "low" }))
        XCTAssertEqual(s.stage(drug: lmwh), .ready)
        XCTAssertEqual(s.answer(drug: lmwh, lastDose: last)?.hours, 12)
        s.selectTier(try XCTUnwrap(lmwh.tiers.first { $0.id == "high" }))
        XCTAssertEqual(s.answer(drug: lmwh, lastDose: last)?.hours, 24)
    }

    func testKidneyRowIsNotChosenForTheUser() throws {
        let rivaroxaban = try drug("rivaroxaban")
        var s = NeuraxialSelection()
        s.selectDrug(rivaroxaban)
        XCTAssertEqual(s.stage(drug: rivaroxaban), .chooseDose)
        // The high dose has no kidney rows: ready as soon as it is chosen.
        s.selectTier(try XCTUnwrap(rivaroxaban.tiers.first { $0.id == "high" }))
        XCTAssertEqual(s.stage(drug: rivaroxaban), .ready)
        XCTAssertEqual(s.answer(drug: rivaroxaban, lastDose: last)?.hours, 72)
        // The low dose has kidney rows: no answer until one is chosen.
        s.selectTier(try XCTUnwrap(rivaroxaban.tiers.first { $0.id == "low" }))
        XCTAssertNil(s.renalIndex)
        XCTAssertEqual(s.stage(drug: rivaroxaban), .chooseKidney)
        XCTAssertNil(s.answer(drug: rivaroxaban, lastDose: last), "no time before kidney function is chosen")
        XCTAssertEqual(NeuraxialSelection.prompt(for: s.stage(drug: rivaroxaban)), "Choose kidney function")
        s.selectRenal(1)
        XCTAssertEqual(s.stage(drug: rivaroxaban), .ready)
        XCTAssertEqual(s.answer(drug: rivaroxaban, lastDose: last)?.hours, 30)
        s.selectRenal(0)
        XCTAssertEqual(s.answer(drug: rivaroxaban, lastDose: last)?.hours, 24)
        // A row number that is not in the list is not a choice.
        s.selectRenal(7)
        XCTAssertEqual(s.stage(drug: rivaroxaban), .chooseKidney)
        XCTAssertNil(s.answer(drug: rivaroxaban, lastDose: last))
    }

    func testChangingTheDoseClearsTheKidneyRow() throws {
        let dabigatran = try drug("dabigatran")
        var s = NeuraxialSelection()
        s.selectDrug(dabigatran)
        s.selectTier(try XCTUnwrap(dabigatran.tiers.first { $0.id == "high" }))
        s.selectRenal(1)
        XCTAssertEqual(s.answer(drug: dabigatran, lastDose: last)?.hours, 120)
        s.selectTier(try XCTUnwrap(dabigatran.tiers.first { $0.id == "low" }))
        XCTAssertNil(s.renalIndex)
        XCTAssertEqual(s.stage(drug: dabigatran), .chooseKidney)
    }

    func testSingleTierDrugWithNoKidneyRowsAnswersAtOnce() throws {
        for id in ["edoxaban", "warfarin", "dti", "aspirin"] {
            let d = try drug(id)
            XCTAssertEqual(d.tiers.count, 1, id)
            XCTAssertTrue((d.tiers[0].renal ?? []).isEmpty, id)
            var s = NeuraxialSelection()
            s.selectDrug(d)
            XCTAssertEqual(s.tierID, d.tiers[0].id, "\(id): its one tier is chosen for it")
            XCTAssertEqual(s.stage(drug: d), .ready, id)
            XCTAssertNotNil(s.answer(drug: d, lastDose: last), id)
        }
        let edoxaban = try drug("edoxaban")
        var s = NeuraxialSelection()
        s.selectDrug(edoxaban)
        XCTAssertEqual(s.answer(drug: edoxaban, lastDose: last)?.hours, 72)
    }

    func testChangingTheDrugClearsDoseKidneyRowAndElderly() throws {
        let fonda = try drug("fondaparinux")
        var s = NeuraxialSelection()
        s.selectDrug(fonda)
        s.selectTier(try XCTUnwrap(fonda.tiers.first { $0.id == "low" }))
        s.selectRenal(0)
        s.elderly = true
        XCTAssertEqual(s.answer(drug: fonda, lastDose: last)?.hours, 42)
        // To a drug with two tiers: nothing carried over.
        let lmwh = try drug("lmwh")
        s.selectDrug(lmwh)
        XCTAssertEqual(s.drugID, "lmwh")
        XCTAssertNil(s.tierID)
        XCTAssertNil(s.renalIndex)
        XCTAssertFalse(s.elderly)
        XCTAssertEqual(s.stage(drug: lmwh), .chooseDose)
        // Back to the same drug: also a fresh start.
        s.selectDrug(fonda)
        XCTAssertNil(s.tierID)
        XCTAssertNil(s.renalIndex)
        XCTAssertEqual(s.stage(drug: fonda), .chooseDose)
        // To a drug with one tier: that tier, no kidney row, no elderly.
        s.elderly = true
        s.selectDrug(try drug("edoxaban"))
        XCTAssertEqual(s.tierID, "high")
        XCTAssertNil(s.renalIndex)
        XCTAssertFalse(s.elderly)
    }

    /// Over the whole file: no drug answers before the user has made the choices it needs.
    func testNoBundledDrugAnswersBeforeItsChoicesAreMade() throws {
        for d in try drugs() {
            var s = NeuraxialSelection()
            s.selectDrug(d)
            if d.tiers.count > 1 {
                XCTAssertEqual(s.stage(drug: d), .chooseDose, d.id)
                XCTAssertNil(s.answer(drug: d, lastDose: last), d.id)
            }
            for t in d.tiers {
                s.selectDrug(d)
                s.selectTier(t)
                if let rules = t.renal, !rules.isEmpty {
                    XCTAssertEqual(s.stage(drug: d), .chooseKidney, "\(d.id)/\(t.id)")
                    XCTAssertNil(s.answer(drug: d, lastDose: last), "\(d.id)/\(t.id)")
                    for i in rules.indices {
                        s.selectRenal(i)
                        XCTAssertNotNil(s.answer(drug: d, lastDose: last), "\(d.id)/\(t.id)/\(i)")
                    }
                } else {
                    XCTAssertEqual(s.stage(drug: d), .ready, "\(d.id)/\(t.id)")
                }
            }
        }
    }

    func testPromptsOnlyWhileAChoiceIsMissing() {
        XCTAssertNil(NeuraxialSelection.prompt(for: .chooseDrug))
        XCTAssertEqual(NeuraxialSelection.prompt(for: .chooseDose), "Choose the dose")
        XCTAssertEqual(NeuraxialSelection.prompt(for: .chooseKidney), "Choose kidney function")
        XCTAssertNil(NeuraxialSelection.prompt(for: .ready))
    }

    // MARK: The "avoid" flag

    func testBundledThrombinInhibitorRowCarriesTheAvoidFlag() throws {
        let t = try tier("dti", "any")
        XCTAssertEqual(t.avoid, true)
        XCTAssertNil(t.holdHours)
        let a = NeuraxialCalc.answer(tier: t, renalIndex: nil, elderly: false, lastDose: last)
        XCTAssertTrue(a.avoid)
        XCTAssertNil(a.earliest)
        // No other tier in the file is flagged: the flag marks only the rows that say to avoid the block.
        for d in try drugs() {
            for x in d.tiers where !(d.id == "dti" && x.id == "any") { XCTAssertNil(x.avoid, "\(d.id)/\(x.id)") }
        }
    }

    func testAvoidFlagWinsAndTheWordIsTheFallback() {
        // Flag present: it decides, whatever the sentence says.
        XCTAssertTrue(NeuraxialCalc.answer(tier: plainTier(holdText: "Not for this one", avoid: true), renalIndex: nil, elderly: false, lastDose: last).avoid)
        XCTAssertFalse(NeuraxialCalc.answer(tier: plainTier(holdText: "ASRA suggests against it", avoid: false), renalIndex: nil, elderly: false, lastDose: last).avoid)
        // Flag missing (older data): the word "against" in the hold text, as before.
        XCTAssertTrue(NeuraxialCalc.answer(tier: plainTier(holdText: "ASRA suggests against it"), renalIndex: nil, elderly: false, lastDose: last).avoid)
        XCTAssertFalse(NeuraxialCalc.answer(tier: plainTier(holdText: "Not specified"), renalIndex: nil, elderly: false, lastDose: last).avoid)
        XCTAssertFalse(NeuraxialCalc.answer(tier: plainTier(), renalIndex: nil, elderly: false, lastDose: last).avoid)
    }

    func testOlderDataWithoutTheFlagStillDecodesAndAvoids() throws {
        let json = """
        {"id": "any", "label": "Any dose", "holdHours": null, "restartHours": null,
         "holdText": "ASRA suggests against neuraxial techniques while on a parenteral direct thrombin inhibitor",
         "catheter": "Not recommended", "restartText": "Not specified"}
        """
        let t = try JSONDecoder().decode(NeuraxialTier.self, from: Data(json.utf8))
        XCTAssertNil(t.avoid)
        XCTAssertTrue(NeuraxialCalc.answer(tier: t, renalIndex: nil, elderly: false, lastDose: last).avoid)
        let flagged = json.replacingOccurrences(of: "\"holdHours\": null,", with: "\"holdHours\": null, \"avoid\": true,")
        let withFlag = try JSONDecoder().decode(NeuraxialTier.self, from: Data(flagged.utf8))
        XCTAssertEqual(withFlag.avoid, true)
    }
}
