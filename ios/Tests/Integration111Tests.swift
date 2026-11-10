import XCTest
@testable import PeriopSignal

/// 1.11 integration: the pieces the five branches share.
final class Integration111Tests: XCTestCase {
    private func drips(_ r: PatientRecord) -> String? {
        HandoffWriter.shortText(r).components(separatedBy: "\n").first { $0.hasPrefix("Drips: ") }
    }

    // MARK: The short handoff's drips follow the intraoperative list

    func testShortHandoffDripsForARecordWithOnlyPreopDripsReadAsIn110() {
        var r = PatientRecord()
        r.homeInfusions = [PatientInfusion(drug: "Epinephrine", rate: "0.05 mcg/kg/min"), PatientInfusion(drug: "Norepinephrine", rate: "0.1 mcg/kg/min")]
        XCTAssertEqual(drips(r), "Drips: Epinephrine at 0.05 mcg/kg/min; Norepinephrine at 0.1 mcg/kg/min")
    }

    func testShortHandoffDripsForARecordWithOnlyRoomDripsReadAsIn110() {
        var r = PatientRecord()
        r.infusions = [PatientInfusion(drug: "Phenylephrine", rate: "0.3 mcg/kg/min"), PatientInfusion(drug: "Propofol", rate: "50 mcg/kg/min")]
        XCTAssertEqual(drips(r), "Drips: Phenylephrine at 0.3 mcg/kg/min; Propofol at 50 mcg/kg/min")
    }

    func testA110CarryOverIsListedOnceWithTheRoomRate() {
        var r = PatientRecord()
        r.homeInfusions = [PatientInfusion(drug: "Norepinephrine", rate: "0.1 mcg/kg/min")]
        r.infusions = [PatientInfusion(drug: "norepinephrine", rate: "0.06 mcg/kg/min")]
        XCTAssertEqual(drips(r), "Drips: Norepinephrine at 0.06 mcg/kg/min")
    }

    func testChangingOnePreopDripInTheRoomKeepsTheOthersInTheShortHandoff() {
        var r = PatientRecord()
        r.homeInfusions = [PatientInfusion(drug: "Epinephrine", rate: "0.05 mcg/kg/min"), PatientInfusion(drug: "Norepinephrine", rate: "0.1 mcg/kg/min")]
        IntraopInfusionList.setRate(r.homeInfusions[0].id, "0.08 mcg/kg/min", in: &r)
        XCTAssertEqual(drips(r), "Drips: Epinephrine at 0.08 mcg/kg/min; Norepinephrine at 0.1 mcg/kg/min")
    }

    func testAPreopDripRemovedInTheRoomLeavesTheShortHandoffsDrips() {
        var r = PatientRecord()
        r.homeInfusions = [PatientInfusion(drug: "Epinephrine", rate: "0.05 mcg/kg/min"), PatientInfusion(drug: "Norepinephrine", rate: "0.1 mcg/kg/min")]
        IntraopInfusionList.remove(r.homeInfusions[0].id, in: &r)
        XCTAssertEqual(drips(r), "Drips: Norepinephrine at 0.1 mcg/kg/min")
        IntraopInfusionList.remove(r.homeInfusions[1].id, in: &r)
        XCTAssertNil(drips(r))
        // The preop record and the full handoff's "running before the case" line keep them.
        XCTAssertEqual(r.homeInfusions.count, 2)
    }

    func testARoomDripIsListedAfterThePreopDrips() {
        var r = PatientRecord()
        r.homeInfusions = [PatientInfusion(drug: "Norepinephrine", rate: "0.1 mcg/kg/min")]
        r.infusions = [PatientInfusion(drug: "Vasopressin", rate: "2 units/h")]
        XCTAssertEqual(drips(r), "Drips: Norepinephrine at 0.1 mcg/kg/min; Vasopressin at 2 units/h")
    }

    /// A drip typed in the room (or carried over in 1.10) is merged with the preop drip of the same drug. Deleting it must
    /// not bring the preop drip back at its preop rate.
    func testARoomEntryMergedWithAPreopDripStaysRemoved() {
        var r = PatientRecord()
        r.homeInfusions = [PatientInfusion(drug: "Norepinephrine", rate: "0.05 mcg/kg/min")]
        r.infusions = [PatientInfusion(drug: "norepinephrine", rate: "0.1 mcg/kg/min"), PatientInfusion(drug: "Vasopressin", rate: "2 units/h")]
        XCTAssertEqual(IntraopInfusionList.rows(r).map(\.rate), ["0.1 mcg/kg/min", "2 units/h"])
        XCTAssertEqual(IntraopInfusionList.mergedPreopDrip(of: r.infusions[0].id, in: r), r.homeInfusions[0].id)
        XCTAssertNil(IntraopInfusionList.mergedPreopDrip(of: r.infusions[1].id, in: r), "a room drip of another drug")
        IntraopInfusionList.remove(r.infusions[0].id, in: &r)
        XCTAssertEqual(IntraopInfusionList.rows(r).map(\.text), ["Vasopressin at 2 units/h"], "the preop drip does not come back")
        XCTAssertEqual(drips(r), "Drips: Vasopressin at 2 units/h")
        XCTAssertEqual(r.homeInfusions.map(\.rate), ["0.05 mcg/kg/min"], "the preop record keeps it")
        // A room drip with no preop twin is simply removed.
        let before = r.infusions.count
        IntraopInfusionList.remove(r.infusions.first { $0.drug == "Vasopressin" }!.id, in: &r)
        XCTAssertEqual(r.infusions.count, before - 1)
        XCTAssertNil(drips(r))
    }

    func testTheRowTextMatchesTheInfusionText() {
        let i = PatientInfusion(drug: "Insulin", rate: "")
        var r = PatientRecord()
        r.homeInfusions = [i]
        XCTAssertEqual(IntraopInfusionList.rows(r).map(\.text), [i.text])
    }

    // MARK: Presets share the preset chip look

    func testThePresetLookIsAGreenOutlineThenAGreenFillWithACheck() {
        let off = ChipStyle.preset.look(on: false), on = ChipStyle.preset.look(on: true)
        XCTAssertEqual(off.edge, .green); XCTAssertNil(off.mark); XCTAssertEqual(off.fill, .neutral)
        XCTAssertEqual(on.fill, .green); XCTAssertEqual(on.mark, "checkmark")
    }

    // MARK: Age → Height → Weight keyboard chain

    func testTheSizeFieldsStepInOrderAndStopAtTheEnds() {
        let order = PreopDemographicsBox.sizeOrder
        XCTAssertEqual(order, ["age", "height", "weight"])
        XCTAssertEqual(PreopNumberCell.neighbour(of: "age", in: order, step: 1), "height")
        XCTAssertEqual(PreopNumberCell.neighbour(of: "height", in: order, step: 1), "weight")
        XCTAssertNil(PreopNumberCell.neighbour(of: "weight", in: order, step: 1))
        XCTAssertEqual(PreopNumberCell.neighbour(of: "weight", in: order, step: -1), "height")
        XCTAssertNil(PreopNumberCell.neighbour(of: "age", in: order, step: -1))
        XCTAssertNil(PreopNumberCell.neighbour(of: "pulse", in: order, step: 1))
    }
}
