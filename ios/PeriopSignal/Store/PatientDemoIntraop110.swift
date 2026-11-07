import Foundation

// A made-up patient for the 1.10 Intraoperative tab screenshots (-ps.patient demo-intraop110): the airway course of Ben's
// example (notes-img2: "Oxygen on arrival: Room air. Mask ventilation DIFFICULT: Beard. Intubation easy: video laryngoscope,
// grade 1; 8.0 cuffed ETT (23 cm). Remains intubated."), a drip with its unit, lab sets with their times, a SLIC, and a saved
// "Flexible scope" and Han mask grade (retired in 1.10) that must load and stay out of the text.

extension PatientDemo {
    static var intraop110: PatientRecord {
        var r = PatientDemo.briefs
        r.setProcedures(PlannedProcedure.parse("Aortic valve replacement and supracoronary ascending aorta replacement"))
        r.anesthetic = ["ga"]
        r.currentAirway = "natural"
        r.oxygen = PatientOxygen(device: "ra")
        r.mask = "difficult"
        // A trailing space, as a typed note can have: the course reads "Beard." and never "Beard .".
        r.maskNote = "Beard "
        r.maskGrade = 3
        r.intubation = "easy"
        r.airwayDevice = "Video laryngoscope"
        r.laryngoscopyGrade = "1"
        r.attempts = nil
        r.tube = "8.0 cuffed ETT (23 cm)"
        r.airwayAtEnd = "intubated"
        r.airwayFollowUp = ["told"]
        r.devices = ["18g R forearm", "R radial art line 20g", "RIJ SLIC 9 Fr", "swan RIJ 8.5 Fr introducer"]
            .flatMap { PatientDevices.parse($0)?.devices(placedIntraop: true) ?? [] }
        r.infusions = [PatientInfusion(drug: "Norepinephrine", rate: "0.05 mcg/kg/min"), PatientInfusion(drug: "Insulin", rate: "4 units/h")]
        r.medsGiven = "Tranexamic acid 1 g load then 400 mg/h; methylprednisolone 500 mg"
        r.fluids = ["crystalloid": 1000, "prbc": 2, "plasma": 2, "cellSaver": 450, "ebl": 600, "uop": 350]
        r.regional = []
        r.events = ""
        r.intraopLabs = [IntraopLabSet(time: PatientDemo.today(10, 40), values: ["ph": 7.38, "hb": 15.5, "k": 4.9, "na": 138, "ica": 1.16, "lactate": 1.1]),
                         IntraopLabSet(time: PatientDemo.today(9, 15), values: ["inr": 1.3, "act": 512])]
        r.labsDrawn = PatientDemo.today(6, 30)
        r.considerations = []
        r.considerationsNote = ""
        return r
    }
}
