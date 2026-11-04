import XCTest
@testable import PeriopSignal

/// The TEE checklist's esophageal and gastric operations keep up with the larger procedure list (1.8.3).
final class TEEProcedures183Tests: XCTestCase {
    /// Every id the checklist names is in the procedure list, so a renamed or mistyped id can't drop out silently.
    func testChecklistIDsAreInTheProcedureList() {
        for id in PatientTEE.esophagectomyIDs.union(PatientTEE.upperGIIDs).sorted() {
            XCTAssertNotNil(ProcedureCatalog.byID(id), id)
        }
    }

    private func item(_ id: String) -> String? {
        PatientTEE.surgeryItem(PatientSurgery(name: ProcedureCatalog.byID(id)?.name ?? id, procedureID: id))
    }

    func testNewEsophagealAndGastricOperationsFlagTheChecklist() {
        XCTAssertEqual(item("colon-interposition"), "esophagectomy", "an esophageal replacement follows an esophagectomy")
        XCTAssertEqual(item("conduit-takedown"), "esophagectomy", "a conduit takedown follows an esophagectomy")
        XCTAssertEqual(PatientTEE.surgeryItem(PatientSurgery(name: "esophagectomy takedown")), "esophagectomy")
        for id in ["esophageal-diversion", "esophageal-diverticulum", "esophageal-perforation", "esophageal-enucleation", "tif", "oagb",
                   "bypass-reversal", "sleeve-conversion", "gastric-band-removal-open", "lap-gastrojejunostomy-revision", "pyloroplasty",
                   "peds-gastrostomy-fundoplication", "tep-voice", "surgical-cystgastrostomy"] {
            XCTAssertEqual(item(id), "gi-surgery", id)
        }
    }

    func testOperationsLeftOutStayOut() {
        for id in ["gastric-stimulator", "perforated-ulcer", "bleeding-ulcer", "gastrostomy-closure", "choledochoduodenostomy"] {
            XCTAssertNil(item(id), id)
        }
    }
}
