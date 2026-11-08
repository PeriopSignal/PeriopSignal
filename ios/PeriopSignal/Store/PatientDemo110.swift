import Foundation

// A made-up patient for the 1.10 echo and past-surgery screenshots (-ps.patient demo-echo110, shots 520–539): a 71-year-old
// man with a degenerated bioprosthetic aortic valve and an ascending aneurysm, for a redo AVR with supracoronary ascending
// aorta replacement; the intraoperative TEE has a pre-bypass and a post-bypass exam as Ben's notes-img3 shows.

extension PatientDemo {
    static var echo110: PatientRecord {
        var r = PatientRecord()
        r.ageYears = 71; r.sex = .male; r.heightCm = 176; r.weightKg = 84
        r.setProcedures(PlannedProcedure.parse("AVR with supracoronary ascending aorta replacement"))
        r.urgency = .elective
        r.problems = ["htn", "hld"]
        r.surgeries = [PatientSurgery(name: "Appendectomy", date: PatientMonthYear(year: 1998))]
        PastSurgeryNote.add("AVR", PatientMonthYear(month: 6, year: 2015), to: &r)

        var echo = PatientEcho()
        echo.study = "TTE"; echo.date = PatientMonthYear(month: 9, year: 2026)
        echo.lv = .normal; echo.lvef = 63; echo.lvSize = .dilated
        echo.rv = .normal; echo.rvSize = .normal
        echo.mitral = EchoValve(regurgitation: .mild, stenosis: .normal)
        echo.tricuspid = EchoValve(regurgitation: .trivial, stenosis: .normal)
        echo.aortic = EchoValve(regurgitation: .moderate, stenosis: .severe, prosthesis: "Bioprosthetic", prosthesisDetail: "23 mm Perimount, 2015")
        echo.aorta = "Sinus 4.0 cm, ascending 4.4 cm"
        r.echoFindings = echo

        var pre = PatientEcho()
        pre.study = "TEE"
        pre.lv = .normal; pre.lvef = 60; pre.lvSize = .dilated
        pre.rv = .normal; pre.rvSize = .normal
        pre.mitral = EchoValve(regurgitation: .mild, stenosis: .normal)
        pre.tricuspid = EchoValve(regurgitation: .trivial, stenosis: .normal)
        pre.aortic = EchoValve(regurgitation: .moderate, stenosis: .severe, prosthesis: "Bioprosthetic", prosthesisDetail: "23 mm Perimount",
                               notes: "Thickened, restricted leaflets; mean gradient 48 mmHg")
        pre.aorta = "Sinus 4.0 cm, ascending 4.5 cm"
        r.intraopEcho = pre

        var post = PatientEcho()
        post.lv = .normal; post.lvef = 60
        post.rv = .normal
        post.mitral = EchoValve(regurgitation: .mild, stenosis: .normal)
        post.tricuspid = EchoValve(regurgitation: .trivial, stenosis: .normal)
        post.aortic = EchoValve(regurgitation: .normal, stenosis: .normal, prosthesis: "Bioprosthetic", prosthesisDetail: "29 Magna",
                                notes: "Well seated, no paravalvular leak")
        r.intraopEchoPost = post
        return r
    }

    /// The same case before bypass: the pre-bypass exam only, so the page offers the post-bypass one.
    /// The same case with the degenerated valve's severe aortic stenosis recorded under History (-ps.patient
    /// demo-echo110-as, shots 598–599): for the planned AVR the guideline's "evaluate for valve intervention" note is
    /// not shown (review 1.10, second pass).
    static var echo110Severe: PatientRecord {
        var r = echo110
        r.hx.valves["aortic"] = PatientValve(stenosis: true, stenosisGrade: "severe", regurgitation: true, regurgitationGrade: "moderate",
                                             prosthetic: true, prosthesis: "Bioprosthetic")
        PatientHistoryDetails.sync(&r)
        return r
    }

    static var echo110Pre: PatientRecord {
        var r = echo110
        r.intraopEchoPost = PatientEcho()
        return r
    }
}
