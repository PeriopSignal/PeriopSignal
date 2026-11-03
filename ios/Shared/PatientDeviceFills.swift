import Foundation

// MARK: - The history on the diagram (1.9)
//
// Entries on the system pages that are devices or access in the patient: a dialysis fistula or catheter with its typed
// location (Renal), a chest tube in place (Respiratory), an implanted pacemaker or ICD (Cardiovascular). Each is
// drawn on the diagram while its source holds, as a fill (PatientCrossFill): added once, remembered by its source's
// key in PatientRecord.fills.devices, and taken off only if it is still there when the source goes.

enum PatientDeviceFills {
    static func apply(before: PatientRecord, after r: inout PatientRecord) {
    }
}
