import Foundation

#if DEBUG
/// Helper A's demo patients for the 1.12 screenshots (-ps.patient <seed>). Start from an existing demo
/// (PatientDemo.record, PatientDemo.cardiac ...) and change what the shot needs.
///
///   demo-112-labs-preop  a woman with the preop labs on the Labs page and in the Preprocedure Summary: CMP, Heme and Other
///                        values (some abnormal), a pregnancy test, a urinalysis, blood cultures, a vancomycin level, and two
///                        extras chosen under "+ Add other input data into Handoff" (albumin, WBC)
///   demo-112-labs-abg    the same, with intraop sets: an ABG at 08:03 and coags (platelets, INR, fibrinogen, ACT, a ROTEM)
///   demo-112-labs-vbg    the same, the newest set a VBG at 10:40
///   demo-112-labs-svo2   the same, the newest set an SvO₂ (PA) sample at 10:40, with two intraop extras chosen
///   demo-112-labs-male   a man: no pregnancy test offered or shown
enum PatientDemo112Labs {
    static func record(_ seed: String) -> PatientRecord? {
        switch seed {
        case "demo-112-labs-preop": return preop
        case "demo-112-labs-abg": return withSets([abgSet, coagSet])
        case "demo-112-labs-vbg": return withSets([abgSet, coagSet, vbgSet])
        case "demo-112-labs-svo2": return svo2
        case "demo-112-labs-male":
            var r = preop
            r.sex = .male
            return r
        default: return nil
        }
    }

    /// A woman for the labs shots; the briefs demo gives her a history, a procedure and a case, and the labs are set here.
    static var preop: PatientRecord {
        var r = PatientDemo.briefs
        r.ageYears = 52
        r.sex = .female
        r.labs = ["na": 138, "k": 4.1, "cl": 102, "hco3": 24, "bun": 24, "cr": 1.3, "gfr": 52, "ast": 55, "alt": 30, "glucose": 142,
                  "hb": 10.9, "hct": 33, "wbc": 11.8, "plt": 210, "pt": 12.1, "ptt": 31, "inr": 1.0, "fibrinogen": 310,
                  "lactate": 1.4, "tsh": 5.2, "ft4": 1.1, "tbili": 0.8, "albumin": 3.1, "ca": 8.1, "vanc": 18.4]
        r.labsDrawn = PatientDemo.today(6, 30)
        r.typeScreen = PatientTypeScreen(type: "A+", screen: .negative, crossmatched: 2)
        r.infections = PatientInfections(results: ["mrsa": .negative, "staph": .negative, "covid": .negative])
        r.labSections = ["infectious", "pregnancy", "thyroid"]
        var more = PatientMoreLabs()
        more.pregnancyNegative = true
        more.hcgText = "<5"
        more.uaNegative = true
        more.bloodCxNegative = true
        r.moreLabs = more
        r.labNotes = ""
        // The briefs demo carries a set of its own; the labs shots choose theirs (withSets).
        r.intraopLabs = []
        r.handoffExtras = ["preop:albumin", "preop:wbc"]
        r.preopSummaryOn = true
        return r
    }

    private static var abgSet: IntraopLabSet {
        IntraopLabSet(time: PatientDemo.today(8, 3),
                      values: ["ph": 7.43, "paco2": 43, "pao2": 146, "hco3a": 28, "be": 4, "lactate": 1.0, "hb": 9, "k": 4.3, "na": 132,
                               "ica": 1.07, "glucose": 164])
    }

    private static var coagSet: IntraopLabSet {
        IntraopLabSet(time: PatientDemo.today(9, 15), values: ["inr": 1.6, "plt": 98, "fibrinogen": 180, "act": 512],
                      viscoelastic: "EXTEM CT 92 s, A10 38 mm")
    }

    private static var vbgSet: IntraopLabSet {
        IntraopLabSet(time: PatientDemo.today(10, 40), values: ["ph": 7.31, "paco2": 51, "pao2": 38, "hco3a": 25, "lactate": 2.4, "k": 4.9, "glucose": 188],
                      gasType: .vbg)
    }

    private static func withSets(_ sets: [IntraopLabSet]) -> PatientRecord {
        var r = preop
        r.intraopLabs = sets
        return r
    }

    private static var svo2: PatientRecord {
        var r = withSets([abgSet, coagSet,
                          IntraopLabSet(time: PatientDemo.today(10, 40),
                                        values: ["so2v": 64, "ph": 7.33, "paco2": 46, "pao2": 36, "hco3a": 24, "lactate": 1.9, "k": 4.4, "glucose": 171],
                                        gasType: .svo2)])
        r.handoffExtras += ["intraop:k", "intraop:glucose"]
        return r
    }
}
#endif
