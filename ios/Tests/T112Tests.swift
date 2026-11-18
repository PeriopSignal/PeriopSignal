import XCTest
@testable import PeriopSignal

/// 1.12 follow-up (Ben, Nov 18): cardiopulmonary test findings typed into the text bars (CardioText).
///
/// The tables below are GENERATED from SP/cardiotext/tables.py, the Python model the reader was written in (cardio.py), so the Swift
/// reader and the model cannot drift: every "yes" line names the exact fields it must give and nothing else; every "no" line gives no
/// study finding and, unless it says a study was not done, leaves the line exactly as it is for the readers that follow (no mask).
final class T112Tests: XCTestCase {
    private var now: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 8))! }

    /// The codes of what a line gives ("echo.lvef=35"), sorted.
    private func codes(_ line: String, page: CardioStudy? = nil) -> [String] {
        CardioText.read(line, page: page, now: now).findings.compactMap { CardioText.code($0) }.sorted()
    }

    private func codes(_ q: QuickAddReading) -> [String] {
        q.findings.compactMap { CardioText.code($0) }.sorted()
    }

    private func yes(_ table: [(String, [String])]) {
        for item in table { XCTAssertEqual(codes(item.0), item.1.sorted(), item.0) }
    }

    private func no(_ table: [(String, Bool)]) {
        for item in table {
            let r = CardioText.read(item.0, page: nil, now: now)
            XCTAssertEqual(r.findings.compactMap { CardioText.code($0) }, [], item.0)
            XCTAssertEqual(!r.masks.isEmpty, item.1, "masks of: " + item.0)
        }
    }

    // MARK: The tables (generated)

    private static let yesEcho: [(String, [String])] = [
        ("TTE 6/26 EF 35%, mod MR, RV nl", ["echo.date=06/2026", "echo.study=TTE", "echo.lvef=35", "echo.valve.mitral.regurgitation=moderate", "echo.rv=normal"]),
        ("echo EF 55%", ["echo.lvef=55"]),
        ("TTE: EF 30-35%, severe LV dysfunction", ["echo.study=TTE", "echo.lvef=32.5", "echo.lv=severe"]),
        ("echocardiogram: LVEF 45", ["echo.lvef=45"]),
        ("TEE 2024 EF of 55", ["echo.study=TEE", "echo.date=2024", "echo.lvef=55"]),
        ("echo EF ~40", ["echo.lvef=40"]),
        ("TTE June 2026: nl LV fxn, RV fxn mod reduced", ["echo.study=TTE", "echo.date=06/2026", "echo.lv=normal", "echo.rv=moderate"]),
        ("echo: LVSF mod reduced", ["echo.lv=moderate"]),
        ("TTE: mildly reduced LV systolic function", ["echo.study=TTE", "echo.lv=mild"]),
        ("echo: preserved LV function", ["echo.lv=normal"]),
        ("echo: RV nl", ["echo.rv=normal"]),
        ("echo: nl RV", ["echo.rv=normal"]),
        ("echo: RV nl size", ["echo.rvSize=normal"]),
        ("echo: LV dilated", ["echo.lvSize=dilated"]),
        ("echo: dilated RV", ["echo.rvSize=dilated"]),
        ("echo: dil LV", ["echo.lvSize=dilated"]),
        ("echo: LV normal size", ["echo.lvSize=normal"]),
        ("echo: RV enlarged", ["echo.rvSize=dilated"]),
        ("TTE: severe RV dysfunction", ["echo.study=TTE", "echo.rv=severe"]),
        ("echo: aorta intact", ["echo.aorta=intact"]),
        ("echo: aorta nl", ["echo.aorta=intact"]),
        ("echo: normal aorta", ["echo.aorta=intact"]),
        ("TTE: sev AS", ["echo.study=TTE", "echo.valve.aortic.stenosis=severe", "history.valve.aortic.stenosis=severe"]),
        ("TTE: triv TR", ["echo.study=TTE", "echo.valve.tricuspid.regurgitation=trivial"]),
        ("TTE: mild AI/AR", ["echo.study=TTE", "echo.valve.aortic.regurgitation=mild"]),
        ("mod MR on echo", ["echo.valve.mitral.regurgitation=moderate"]),
        ("EF 35% on TTE", ["echo.study=TTE", "echo.lvef=35"]),
        ("TTE showed EF 45%, mod-sev AS", ["echo.study=TTE", "echo.lvef=45", "echo.valve.aortic.stenosis=severe", "history.valve.aortic.stenosis=severe"]),
        ("echo: LVEF 35%, moderately reduced LV function, RV nl, mild MR", ["echo.lvef=35", "echo.lv=moderate", "echo.rv=normal", "echo.valve.mitral.regurgitation=mild"]),
        ("TEE: EF 55%, no MR, trace TR", ["echo.study=TEE", "echo.lvef=55", "echo.valve.tricuspid.regurgitation=trivial"]),
        ("TTE 6/26, EF 60%", ["echo.study=TTE", "echo.date=06/2026", "echo.lvef=60"]),
        ("TTE EF 35%, PCWP 18", ["echo.study=TTE", "echo.lvef=35"]),
        ("echo: LV fxn nl", ["echo.lv=normal"]),
        ("echo: RV fxn mod reduced", ["echo.rv=moderate"]),
        ("TTE: RV dysfxn mild", ["echo.study=TTE", "echo.rv=mild"]),
        ("2025 TTE: EF 50%", ["echo.study=TTE", "echo.date=2025", "echo.lvef=50"]),
        ("echo with EF 25%, severe MR and mild TR", ["echo.lvef=25", "echo.valve.mitral.regurgitation=severe", "echo.valve.tricuspid.regurgitation=mild"]),
        ("TTE: EF 55%, RVSP 45, LA mildly dilated, RV nl", ["echo.study=TTE", "echo.lvef=55", "echo.rv=normal"]),
    ]
    private static let yesLhc: [(String, [String])] = [
        ("LHC: LAD 90%, RCA 40%", ["lhc.stenosis.lad=90", "lhc.stenosis.rca=40"]),
        ("LHC 6/26 LM 50", ["lhc.date=06/2026", "lhc.stenosis.lm=50"]),
        ("left heart cath: 90% LAD, RCA occluded", ["lhc.stenosis.lad=90", "lhc.stenosis.rca=100"]),
        ("LHC pLAD 80%, mid RCA 70%", ["lhc.stenosis.lad=80", "lhc.stenosis.rca=70"]),
        ("LHC: prox LAD 70%, mid LAD 90%", ["lhc.stenosis.lad=90"]),
        ("LHC: CTO RCA", ["lhc.stenosis.rca=100"]),
        ("LHC: RCA CTO", ["lhc.stenosis.rca=100"]),
        ("LHC: right dominant, LAD 90%", ["lhc.dominance=right", "lhc.stenosis.lad=90"]),
        ("LHC: L dom", ["lhc.dominance=left"]),
        ("LHC: R dom, RCA 50%", ["lhc.dominance=right", "lhc.stenosis.rca=50"]),
        ("LHC: codominant", ["lhc.dominance=codominant"]),
        ("LHC: co-dominant", ["lhc.dominance=codominant"]),
        ("cath: LAD 90%", ["lhc.stenosis.lad=90"]),
        ("coronary angiogram: RCA 100%", ["lhc.stenosis.rca=100"]),
        ("LHC: Cx 60%", ["lhc.stenosis.lcx=60"]),
        ("LHC: circumflex 50%", ["lhc.stenosis.lcx=50"]),
        ("LHC: left main 40%", ["lhc.stenosis.lm=40"]),
        ("LHC: LMCA 30%", ["lhc.stenosis.lm=30"]),
        ("LHC: non-obstructive CAD", ["lhc.result=non-obstructive"]),
        ("LHC: no CAD", ["lhc.result=no-cad"]),
        ("LHC: normal coronaries", ["lhc.result=no-cad"]),
        ("cors: clean cors", ["lhc.result=no-cad"]),
        ("cors: LAD 70%, RCA 50%", ["lhc.stenosis.lad=70", "lhc.stenosis.rca=50"]),
        ("LHC 2019: PDA 70%", ["lhc.date=2019", "lhc.stenosis.pda=70"]),
        ("LHC: LM 50 LAD 90%", ["lhc.stenosis.lm=50", "lhc.stenosis.lad=90"]),
        ("LHC: LAD 100%", ["lhc.stenosis.lad=100"]),
        ("LAD 90% by cath", ["lhc.stenosis.lad=90"]),
        ("LHC LAD 90%, EF 35%", ["lhc.stenosis.lad=90"]),
        ("LHC: dLAD 60%, pRCA 80%", ["lhc.stenosis.lad=60", "lhc.stenosis.rca=80"]),
        ("left heart cath 06/2026: RCA 70%, LCx 40%, left dominant", ["lhc.date=06/2026", "lhc.stenosis.rca=70", "lhc.stenosis.lcx=40", "lhc.dominance=left"]),
        ("LHC: LAD stenosis 70%", ["lhc.stenosis.lad=70"]),
    ]
    private static let yesRhc: [(String, [String])] = [
        ("RHC: RA 12, PA 45/20/30, PCWP 18, CO 4.2", ["rhc.ra=12", "rhc.pasp=45", "rhc.padp=20", "rhc.pam=30", "rhc.pcwp=18", "rhc.co=4.2"]),
        ("RHC RAP 8, PAP 45/20 (30), wedge 18", ["rhc.ra=8", "rhc.pasp=45", "rhc.padp=20", "rhc.pam=30", "rhc.pcwp=18"]),
        ("RHC: PA 45/20 mean 30", ["rhc.pasp=45", "rhc.padp=20", "rhc.pam=30"]),
        ("right heart cath: mPAP 30, PCWP 15", ["rhc.pam=30", "rhc.pcwp=15"]),
        ("RHC: PASP 45, PADP 20", ["rhc.pasp=45", "rhc.padp=20"]),
        ("RHC 6/26: PA mean 30", ["rhc.date=06/2026", "rhc.pam=30"]),
        ("RHC: PAWP 18 mmHg, CO 4.2 L/min", ["rhc.pcwp=18", "rhc.co=4.2"]),
        ("swan numbers: RA 10, PA 50/25, PCWP 20, CO 3.8", ["rhc.ra=10", "rhc.pasp=50", "rhc.padp=25", "rhc.pcwp=20", "rhc.co=3.8"]),
        ("RHC: RA 12 mmHg", ["rhc.ra=12"]),
        ("RHC: CO 5", ["rhc.co=5"]),
        ("RHC: PCWP 12", ["rhc.pcwp=12"]),
        ("RHC: CI 2.1, PVR 4, CO 4.2", ["rhc.co=4.2"]),
        ("RHC: PA 60/30", ["rhc.pasp=60", "rhc.padp=30"]),
        ("RHC: PAP 25/10, RAP 4", ["rhc.pasp=25", "rhc.padp=10", "rhc.ra=4"]),
        ("RHC 2023: PCWP 22, mPAP 38", ["rhc.date=2023", "rhc.pcwp=22", "rhc.pam=38"]),
        ("RHC: right atrial pressure 9", ["rhc.ra=9"]),
        ("RHC: PA 45/20/30, wedge 18", ["rhc.pasp=45", "rhc.padp=20", "rhc.pam=30", "rhc.pcwp=18"]),
        ("RHC: cardiac output 4.8", ["rhc.co=4.8"]),
        ("RHC: RA 6 PA 30/12 PCWP 10 CO 5.5", ["rhc.ra=6", "rhc.pasp=30", "rhc.padp=12", "rhc.pcwp=10", "rhc.co=5.5"]),
        ("RHC: PA mean 28", ["rhc.pam=28"]),
        ("RHC: PADP 18", ["rhc.padp=18"]),
        ("RHC: pcwp 14, RAP 7", ["rhc.pcwp=14", "rhc.ra=7"]),
        ("RHC: PA 80/35, SvO2 62%", ["rhc.pasp=80", "rhc.padp=35"]),
        ("RHC: wedge 24, CO 3.1", ["rhc.pcwp=24", "rhc.co=3.1"]),
        ("RHC: RA 15, PA 70/30/45", ["rhc.ra=15", "rhc.pasp=70", "rhc.padp=30", "rhc.pam=45"]),
        ("RHC: PAWP 16", ["rhc.pcwp=16"]),
    ]
    private static let yesPft: [(String, [String])] = [
        ("PFTs: FEV1 1.8 L, FVC 3.1 L", ["pft.fev1=1.8", "pft.fvc=3.1"]),
        ("PFT FEV1 62%", ["pft.fev1Pct=62"]),
        ("spirometry FEV1 62% pred, FVC 78%", ["pft.fev1Pct=62", "pft.fvcPct=78"]),
        ("PFT: FEV1 1.8 L (62%)", ["pft.fev1=1.8", "pft.fev1Pct=62"]),
        ("PFT FEV1/FVC 0.55", ["pft.ratio=0.55"]),
        ("PFT FEV1/FVC 55%", ["pft.ratio=55"]),
        ("PFT ratio 0.55", ["pft.ratio=0.55"]),
        ("PFT ratio 55", ["pft.ratio=55"]),
        ("PFT: TLC 85%, DLCO 45%", ["pft.tlcPct=85", "pft.dlcoPct=45"]),
        ("PFT: FEV1 1.8", ["pft.fev1=1.8"]),
        ("PFT: FEV1 62", ["pft.fev1Pct=62"]),
        ("PFT 6/26: obstructive", ["pft.date=06/2026", "pft.pattern=obstruction"]),
        ("PFT: mod obstruction", ["pft.pattern=obstruction", "pft.severity=moderate"]),
        ("PFT: severe restrictive", ["pft.pattern=restriction", "pft.severity=severe"]),
        ("PFT: obs", ["pft.pattern=obstruction"]),
        ("PFT: mixed", ["pft.pattern=mixed"]),
        ("PFT: nonspecific", ["pft.pattern=nonspecific"]),
        ("normal PFTs", ["pft.pattern=normal"]),
        ("PFTs nl", ["pft.pattern=normal"]),
        ("PFT wnl", ["pft.pattern=normal"]),
        ("pulmonary function test: FEV1 45% pred, severe obstruction", ["pft.fev1Pct=45", "pft.pattern=obstruction", "pft.severity=severe"]),
        ("PFTs: FEV1 1.62 L (58%), FVC 2.9 L (78%), FEV1/FVC 0.56, TLC 104%, DLCO 61%", ["pft.fev1=1.62", "pft.fev1Pct=58", "pft.fvc=2.9", "pft.fvcPct=78", "pft.ratio=0.56", "pft.tlcPct=104", "pft.dlcoPct=61"]),
        ("spirometry: FVC 3.4 L", ["pft.fvc=3.4"]),
        ("PFT FVC 80%", ["pft.fvcPct=80"]),
        ("PFTs 2024: restriction", ["pft.date=2024", "pft.pattern=restriction"]),
        ("PFT: DLCO 45%", ["pft.dlcoPct=45"]),
        ("PFT: TLC 85%", ["pft.tlcPct=85"]),
        ("PFT FEV1 1.8 L, 62% pred", ["pft.fev1=1.8"]),
        ("PFT: moderately obstructive", ["pft.pattern=obstruction", "pft.severity=moderate"]),
        ("PFT: obstruction mild", ["pft.pattern=obstruction", "pft.severity=mild"]),
        ("PFT: GOLD 2, FEV1 55%", ["pft.fev1Pct=55"]),
    ]
    private static let yesCxr: [(String, [String])] = [
        ("CXR nl", ["cxr.result=normal"]),
        ("normal CXR", ["cxr.result=normal"]),
        ("CXR clear", ["cxr.result=normal"]),
        ("CXR: clear", ["cxr.result=normal"]),
        ("CXR NAD", ["cxr.result=normal"]),
        ("CXR: NACPD", ["cxr.result=normal"]),
        ("CXR: no acute cardiopulmonary process", ["cxr.result=normal"]),
        ("CXR: no acute disease", ["cxr.result=normal"]),
        ("CXR unremarkable", ["cxr.result=normal"]),
        ("CXR wnl", ["cxr.result=normal"]),
        ("chest x-ray normal", ["cxr.result=normal"]),
        ("chest xray: clear", ["cxr.result=normal"]),
        ("CXR: L pleural effusion", ["cxr.effusion=left,-"]),
        ("CXR: small R effusion", ["cxr.effusion=right,small"]),
        ("CXR: bilat effusions", ["cxr.effusion=bilateral,-"]),
        ("CXR: mod left effusion", ["cxr.effusion=left,moderate"]),
        ("chest x-ray: large right pleural eff", ["cxr.effusion=right,large"]),
        ("CXR: RLL infiltrate", ["cxr.findings=RLL infiltrate"]),
        ("CXR: cardiomegaly", ["cxr.findings=cardiomegaly"]),
        ("CXR: pulm edema", ["cxr.findings=pulm edema"]),
        ("CXR: hyperinflation", ["cxr.findings=hyperinflation"]),
        ("CXR: small L effusion, cardiomegaly", ["cxr.effusion=left,small", "cxr.findings=cardiomegaly"]),
        ("CXR PA/lat: nl", ["cxr.result=normal"]),
        ("chest film: bibasilar atelectasis", ["cxr.findings=bibasilar atelectasis"]),
        ("chest radiograph shows large left effusion", ["cxr.effusion=left,large"]),
        ("CXR: effusion", ["cxr.effusion=-,-"]),
        ("CXR: sm R pleural effusion", ["cxr.effusion=right,small"]),
        ("CXR: RLL infiltrate, hyperinflation", ["cxr.findings=RLL infiltrate; hyperinflation"]),
        ("CXR clear, no acute process", ["cxr.result=normal"]),
        ("CXR: lg b/l effusions", ["cxr.effusion=bilateral,large"]),
    ]
    private static let yesCarotid: [(String, [String])] = [
        ("carotid US: R ICA 70-99%, L ICA <50%", ["carotid.right.stenosis=ge70", "carotid.left.stenosis=lt50"]),
        ("carotid duplex R 60%, L 40%", ["carotid.right.stenosis=50-69", "carotid.left.stenosis=lt50"]),
        ("carotid US: RICA ≥70%", ["carotid.right.stenosis=ge70"]),
        ("carotid US: L ICA occluded, R ICA 50-69%", ["carotid.left.stenosis=occluded", "carotid.right.stenosis=50-69"]),
        ("carotid doppler: bilateral <50%", ["carotid.right.stenosis=lt50", "carotid.left.stenosis=lt50"]),
        ("carotid US: normal", ["carotid.right.stenosis=normal", "carotid.left.stenosis=normal"]),
        ("carotids normal", ["carotid.right.stenosis=normal", "carotid.left.stenosis=normal"]),
        ("carotid US R ICA near occlusion", ["carotid.right.stenosis=near"]),
        ("carotid US: L ICA string sign", ["carotid.left.stenosis=near"]),
        ("carotid US: R 100%", ["carotid.right.stenosis=occluded"]),
        ("carotid US: R vertebral antegrade, L vertebral reversed", ["carotid.right.vertebral=antegrade", "carotid.left.vertebral=reversed"]),
        ("carotid US: R ICA 60% PSV 230 EDV 80", ["carotid.right.stenosis=50-69", "carotid.right.psv=230", "carotid.right.edv=80"]),
        ("carotid US: right no significant stenosis", ["carotid.right.stenosis=normal"]),
        ("carotid US: 70% L ICA", ["carotid.left.stenosis=ge70"]),
        ("carotid US 5/26: R ICA >70%", ["carotid.date=05/2026", "carotid.right.stenosis=ge70"]),
        ("carotid US: L ICA 70%", ["carotid.left.stenosis=ge70"]),
        ("carotid US: right 40%, left 75%", ["carotid.right.stenosis=lt50", "carotid.left.stenosis=ge70"]),
        ("carotids: LICA 80%", ["carotid.left.stenosis=ge70"]),
        ("carotid duplex: bilat vertebral antegrade", ["carotid.right.vertebral=antegrade", "carotid.left.vertebral=antegrade"]),
        ("carotid US: L vertebral retrograde", ["carotid.left.vertebral=reversed"]),
        ("carotid US: R vertebral absent", ["carotid.right.vertebral=absent"]),
        ("carotid US: L vertebral partial reversal", ["carotid.left.vertebral=partial"]),
        ("carotid US: R ICA 50-69% PSV 180", ["carotid.right.stenosis=50-69", "carotid.right.psv=180"]),
        ("carotid US: L ICA 90% PSV 350 EDV 120", ["carotid.left.stenosis=ge70", "carotid.left.psv=350", "carotid.left.edv=120"]),
        ("carotid doppler 2024: both normal", ["carotid.date=2024", "carotid.right.stenosis=normal", "carotid.left.stenosis=normal"]),
        ("carotid US: R ICA occluded", ["carotid.right.stenosis=occluded"]),
        ("carotid US: left ICA 55%", ["carotid.left.stenosis=50-69"]),
        ("carotid ultrasound: R <50%, L 50-69%", ["carotid.right.stenosis=lt50", "carotid.left.stenosis=50-69"]),
        ("carotid US: b/l ICA 30%", ["carotid.right.stenosis=lt50", "carotid.left.stenosis=lt50"]),
        ("carotid US: L ICA near-occlusion", ["carotid.left.stenosis=near"]),
    ]
    private static let yesRadial: [(String, [String])] = [
        ("radial US: R radial 2.6 mm", ["radial.right.diameter=2.6"]),
        ("radial US: R radial 2.6 mm calcified, L radial 2.4 mm", ["radial.right.diameter=2.6", "radial.right.calcified=true", "radial.left.diameter=2.4"]),
        ("radial ultrasound: harvest left", ["radial.harvest=left"]),
        ("radial duplex: no harvest", ["radial.harvest=none"]),
        ("radial US harvest right", ["radial.harvest=right"]),
        ("radial US: L radial ulnar adequate", ["radial.left.ulnar=adequate"]),
        ("radial US: R ulnar inadequate", ["radial.right.ulnar=inadequate"]),
        ("radial US: R no calcification", ["radial.right.calcified=false"]),
        ("radial artery US: R 2.8 mm, L 2.5 mm", ["radial.right.diameter=2.8", "radial.left.diameter=2.5"]),
        ("radial US 6/26: R radial 2.6 mm, harvest left", ["radial.date=06/2026", "radial.right.diameter=2.6", "radial.harvest=left"]),
        ("radial US: left radial 2.2 mm calcified", ["radial.left.diameter=2.2", "radial.left.calcified=true"]),
        ("radial US: R radial 3 mm, no calcification, ulnar adequate", ["radial.right.diameter=3"]),
        ("radial US: L radial calcification", ["radial.left.calcified=true"]),
        ("radial US: right radial 2.9 mm ulnar adequate", ["radial.right.diameter=2.9", "radial.right.ulnar=adequate"]),
        ("radial US: L radial 2.4 mm ulnar inadequate", ["radial.left.diameter=2.4", "radial.left.ulnar=inadequate"]),
        ("radial duplex 2025: R radial 2.7 mm", ["radial.date=2025", "radial.right.diameter=2.7"]),
        ("radial US: R radial 2.6 mm; L radial 2.4 mm; harvest left", ["radial.right.diameter=2.6", "radial.left.diameter=2.4", "radial.harvest=left"]),
        ("radial ultrasound R 2.5 mm not calcified", ["radial.right.diameter=2.5", "radial.right.calcified=false"]),
        ("radial US: left 2.1 mm", ["radial.left.diameter=2.1"]),
        ("radial US: L ulnar adequate, R ulnar inadequate", ["radial.left.ulnar=adequate", "radial.right.ulnar=inadequate"]),
        ("radial US: harvest left, R radial 2.6 mm", ["radial.harvest=left", "radial.right.diameter=2.6"]),
        ("radial US: R radial 2.6mm", ["radial.right.diameter=2.6"]),
        ("radial US: R radial 1.9 mm calcified", ["radial.right.diameter=1.9", "radial.right.calcified=true"]),
        ("radial US: no harvest, L radial 2.0 mm", ["radial.harvest=none", "radial.left.diameter=2"]),
        ("radial US R radial 2.6 mm calcified ulnar adequate", ["radial.right.diameter=2.6", "radial.right.calcified=true", "radial.right.ulnar=adequate"]),
        ("radial US: L radial 3.1 mm", ["radial.left.diameter=3.1"]),
    ]
    private static let noShared: [(String, Bool)] = [
        ("EF 35%", false),
        ("needs echo", true),
        ("echo pending", true),
        ("no prior echo", true),
        ("TEE probe in", false),
        ("RA 96%", false),
        ("sat 94% on RA", false),
        ("RA on methotrexate", false),
        ("PA catheter placed", false),
        ("PA-C saw patient", false),
        ("TLC right IJ", false),
        ("PDA ligation as infant", false),
        ("CO2 24", false),
        ("LAD stent 2019", false),
        ("s/p cath 2019", false),
        ("cath lab", false),
        ("foley cath", false),
        ("cardiac cath scheduled Friday", false),
        ("PFTs not done", true),
        ("FEV1", false),
        ("CXR ordered", true),
        ("clear lungs", false),
        ("effusion", false),
        ("carotid bruit", false),
        ("s/p L CEA", false),
        ("R radial A-line", false),
        ("radial pulse 2+", false),
        ("90% on 2 L", false),
        ("LM 3/6 murmur", false),
        ("MR brain", false),
        ("mod MR", false),
        ("RV pacing", false),
        ("LV thrombus", false),
        ("PCWP", false),
        ("no echo", true),
        ("echo not done", true),
        ("TTE ordered", true),
        ("awaiting TTE", true),
        ("echo scheduled for Monday", true),
        ("will need echo", true),
        ("echo declined", true),
        ("refused TTE", true),
        ("unable to get echo", true),
        ("to get TTE", true),
        ("LHC ordered", false),
        ("LHC pending", false),
        ("needs LHC", false),
        ("RHC scheduled", false),
        ("PFTs pending", true),
        ("no PFTs", true),
        ("spirometry not done", true),
        ("CXR today", false),
        ("CXR pending", true),
        ("no CXR", true),
        ("carotid US pending", true),
        ("carotid US ordered", true),
        ("needs carotid US", true),
        ("radial US scheduled", true),
        ("radial US not done", true),
        ("stress echo EF 40%", false),
        ("exercise stress echo negative", false),
        ("bubble echo positive", false),
        ("RA 12", false),
        ("PA 45/20", false),
        ("PCWP 18", false),
        ("CO 4.2", false),
        ("LAD 90%", false),
        ("RCA 100%", false),
        ("FEV1 62%", false),
        ("DLCO 45%", false),
        ("TLC 85%", false),
        ("L ICA 70%", false),
        ("R radial 2.6 mm", false),
        ("harvest left", false),
        ("RV nl", false),
        ("nl LV fxn", false),
        ("sev AS", false),
        ("triv TR", false),
        ("LV dilated", false),
        ("obstructive", false),
        ("carotid stenosis 70%", false),
        ("carotid endarterectomy 2019", false),
        ("radial artery harvest 2015", false),
        ("s/p CABG with radial artery graft", false),
        ("on echo", false),
        ("by cath", false),
        ("TTE", false),
        ("LHC", false),
        ("RHC", false),
        ("PFTs", false),
        ("CXR", false),
        ("carotid US", false),
        ("radial US", false),
        ("echo lab", false),
        ("TEE screen done", false),
        ("cath", false),
        ("cors", false),
        ("carotids", false),
        ("no significant change from prior echo", false),
        ("echo EF not reported", false),
        ("TTE: EF 150%", false),
        ("swan cath", false),
        ("central cath", false),
        ("PA cath in place", false),
        ("cardiac cath lab Monday", false),
        ("PFTs ordered", true),
        ("spirometry scheduled", true),
        ("chest x-ray ordered", true),
        ("CXR to be done", true),
        ("carotid duplex needed", true),
        ("radial US to be done", true),
        ("echo needed", true),
        ("TTE: EF >55%", false),
        ("TTE EF <20%", false),
        ("history of echo", false),
        ("LHC: ", false),
        ("RHC:", false),
        ("echo?", false),
        ("for TEE", false),
        ("73M for TEE", false),
        ("for LHC", false),
        ("68M for LHC, LAD 90%", false),
        ("scheduled for TEE", false),
        ("for cardiac cath, LAD 90%", false),
        ("for RHC, PCWP 18", false),
        ("undergoing LHC", false),
        ("for cardioversion", false),
        ("for TEE/DCCV", false),
        ("for TTE, EF 35%", false),
    ]
    private static let noEcho: [(String, Bool)] = [
        ("TTE: EF 3%", false),
        ("TTE: EF 95%", false),
        ("echo: LVH", false),
        ("TTE: no RV dysfunction", false),
        ("TTE: possible RV dilation", false),
        ("echo: RV not dilated", false),
        ("TTE: mild-mod", false),
        ("echo: mod reduced", false),
        ("echo: LV mod", false),
        ("TTE: sev", false),
        ("TTE: normal", false),
        ("echo: nl", false),
        ("TTE: mildly dilated RV", false),
        ("echo: RV and LV nl", false),
        ("TTE: aorta dilated", false),
        ("TTE: aortic root 4.5 cm", false),
        ("TTE: diastolic dysfunction grade 2", false),
        ("TTE: RVSP 45", false),
        ("echo: LA dilated", false),
        ("TTE: wall motion abnormality", false),
        ("echo: gradient 40", false),
        ("echo: AVA 0.8", false),
        ("TTE: PS mild", false),
        ("echo: mild PR", false),
        ("TTE: no MR", false),
        ("TTE: possible severe AS", false),
        ("TTE: ?AS", false),
        ("echo: LV thrombus", false),
        ("TTE: pericardial effusion", false),
        ("echo: RV pacing wire", false),
        ("TTE: EF >55%", false),
        ("TTE EF <30%", false),
        ("echo: EF unchanged", false),
        ("echo: EF 35% vs 40%", false),
        ("TTE: no significant change", false),
        ("echo today", false),
        ("echo tomorrow", true),
        ("TEE tomorrow, severe AS", false),
        ("TTE 13/26", false),
        ("TTE 6/27 EF", false),
        ("EF 35%, mod MR, RV nl", false),
        ("echo: RA 12", false),
        ("TTE: PA 45/20", false),
        ("echo: LAD 90%", false),
        ("TTE: FEV1 62%", false),
    ]
    private static let noLhc: [(String, Bool)] = [
        ("LHC: EF 35%", false),
        ("LHC: LAD stent", false),
        ("LHC: DES to LAD", false),
        ("LHC: LIMA-LAD patent", false),
        ("LHC: SVG to RCA patent", false),
        ("LHC: OM1 90%", false),
        ("LHC: diagonal 70%", false),
        ("LHC: ramus 80%", false),
        ("LHC: PLV 70%", false),
        ("LHC: LAD 150%", false),
        ("LHC: LAD 2019", false),
        ("LHC: LAD 3 vessel", false),
        ("LHC: LAD 70-80%", false),
        ("LHC: LAD", false),
        ("LHC: no LAD stenosis", false),
        ("LHC: dominant", false),
        ("LHC: right", false),
        ("LHC: stent to RCA 2018", false),
        ("LHC: LAD 90 mm", false),
        ("LHC: no significant disease", false),
        ("LHC: possible LAD 90%", false),
        ("cath: EF 35%", false),
        ("cath: scheduled", false),
        ("cath: 2019", false),
        ("cath: normal", false),
        ("cors: normal", false),
        ("cath lab LAD 90%", false),
        ("foley cath LAD 90%", false),
        ("PA cath LAD 90%", false),
        ("LAD 90% by echo", false),
        ("LHC: RCA 70%, RCA 50%", false),
        ("LHC: LAD 90%, LAD 50%", false),
        ("coronary CT: LAD 90%", false),
        ("CTA coronary angiogram: LAD 90%", false),
        ("LHC: LM 3/6 murmur", false),
        ("LHC: PDA ligation", false),
        ("LHC: PDA closure as infant", false),
        ("RHC LAD 90%", false),
    ]
    private static let noRhc: [(String, Bool)] = [
        ("RHC: RA 96%", false),
        ("RHC: RA 90", false),
        ("RHC: RA 45", false),
        ("RHC: PA 45", false),
        ("RHC: PA 20/45", false),
        ("RHC: PA 200/20", false),
        ("RHC: PCWP 80", false),
        ("RHC: CO 25", false),
        ("RHC: CO 0.5", false),
        ("RHC: CO2 24", false),
        ("RHC: CI 2.1", false),
        ("RHC: PVR 4", false),
        ("RHC: SVR 1200", false),
        ("RHC: SvO2 62%", false),
        ("RHC: TPG 12", false),
        ("RHC: PA catheter placed", false),
        ("RHC: PA-C saw patient", false),
        ("RHC: RA on methotrexate", false),
        ("RHC: PA sat 62%", false),
        ("RHC: PA 45/20/90", false),
        ("RHC: mPAP 150", false),
        ("RHC: LAD 90%", false),
        ("RHC: EF 35%", false),
        ("RHC: PA 45/20/10", false),
        ("RHC: no PCWP", false),
        ("RHC: PCWP not obtained", false),
        ("RHC: PCWP unable", false),
        ("RHC: PA 4/2", false),
        ("RHC: PASP 5", false),
        ("RHC: PADP 90", false),
        ("RHC: wedge 10-12", false),
        ("swan cath RA 12", false),
        ("central cath RA 12", false),
        ("RHC: RA ?", false),
        ("RHC: possible PCWP 18", false),
        ("RHC tomorrow", false),
        ("RHC: elevated PCWP", false),
    ]
    private static let noPft: [(String, Bool)] = [
        ("PFT: FEV1", false),
        ("PFT: FEV1 predicted", false),
        ("PFT: FEV1 0.1", false),
        ("PFT: FEV1 200%", false),
        ("PFT: FVC 12 L", false),
        ("PFT: FEV1/FVC 1.2", false),
        ("PFT: FEV1/FVC 150", false),
        ("PFT: ratio 0", false),
        ("PFT: TLC right IJ", false),
        ("PFT: TLC 5.2 L", false),
        ("PFT: DLCO 45", false),
        ("PFT: DLCO adj", false),
        ("PFT: not obstructive", false),
        ("PFT: no restriction", false),
        ("PFT: possible obstruction", false),
        ("PFT: obs?", false),
        ("PFT: restr", false),
        ("PFT: GOLD 2", false),
        ("PFT: normal DLCO", false),
        ("PFT: bronchodilator response", false),
        ("PFT: poor effort", false),
        ("PFT: unable", false),
        ("PFT: FEV1 1.8 L vs 2.2 L", false),
        ("PFT: FEV1 >50%", false),
        ("PFT: FEV1 <30%", false),
        ("PFT: air trapping", false),
        ("PFT: low DLCO", false),
        ("PFT: severe", false),
        ("PFT: moderate", false),
        ("PFT: pattern", false),
        ("TTE: FEV1 62%", false),
        ("PFT: EF 35%", false),
        ("PFT: LAD 90%", false),
        ("PFT: asthma", false),
        ("PFT: COPD", false),
        ("PFT: nl DLCO", false),
        ("PFT: obstructive and restrictive", false),
    ]
    private static let noCxr: [(String, Bool)] = [
        ("CXR: HTN", false),
        ("CXR: DM2", false),
        ("CXR: then to OR", false),
        ("CXR: awaiting read", true),
        ("CXR: unchanged", false),
        ("CXR: no effusion", false),
        ("CXR: no pneumothorax", false),
        ("CXR: possible effusion", false),
        ("CXR: not clear", false),
        ("CXR: not normal", false),
        ("CXR: patient lying flat", false),
        ("CXR: portable at bedside", false),
        ("CXR: AP", false),
        ("CXR: pt c/o SOB", false),
        ("CXR: clear to auscultation", false),
        ("CXR in AM", true),
        ("CXR: ?", false),
        ("CXR: please review", false),
        ("CXR tomorrow clear", true),
        ("LHC: cardiomegaly", false),
        ("PFT: cardiomegaly", false),
        ("cardiomegaly", false),
        ("RLL infiltrate", false),
        ("pulm edema", false),
        ("hyperinflation", false),
        ("bibasilar atelectasis", false),
        ("small L effusion", false),
        ("bilat effusions", false),
        ("pleural effusion", false),
        ("large right pleural eff", false),
        ("NACPD", false),
        ("no acute process", false),
        ("unremarkable", false),
        ("wnl", false),
    ]
    private static let noCarotid: [(String, Bool)] = [
        ("carotid US: 70%", false),
        ("carotid US: <50%", false),
        ("carotid US: PSV 230", false),
        ("carotid US: EDV 80", false),
        ("carotid US: R vertebral", false),
        ("carotid US: antegrade", false),
        ("carotid US: R ICA", false),
        ("carotid US: R ICA 60-80%", false),
        ("carotid US: R ICA >60%", false),
        ("carotid US: R ICA <70%", false),
        ("carotid US: R ICA 150%", false),
        ("carotid US: R PSV 5000", false),
        ("carotid US: bruit R", false),
        ("carotid US: R CEA 2019", false),
        ("carotid US: s/p L CEA", false),
        ("carotid US: L stent", false),
        ("carotid US: R ICA mild", false),
        ("carotid US: no right stenosis", false),
        ("carotid US: possible R ICA 70%", false),
        ("carotid US: L ICA ?70%", false),
        ("carotid US: R vertebral partial", false),
        ("carotid US: L vertebral flow", false),
        ("carotid US: ECA 70%", false),
        ("carotid US: R CCA 60%", false),
        ("carotids: bruit", false),
        ("carotids: 2+", false),
        ("carotids tomorrow", true),
        ("carotid US: R ICA 45-65%", false),
        ("carotid US: R ICA 100-%", false),
        ("carotid US: bilateral PSV 200", false),
        ("radial US: R ICA 70%", false),
        ("carotid US: R 70/50", false),
        ("carotid US: R ICA 120%", false),
        ("carotid US: R vertebral 70%", false),
        ("carotid US: R ICA <60%", false),
        ("carotid US: right", false),
        ("carotid US: left", false),
    ]
    private static let noRadial: [(String, Bool)] = [
        ("radial US: 2.6 mm", false),
        ("radial US: calcified", false),
        ("radial US: ulnar adequate", false),
        ("radial US: R radial", false),
        ("radial US: R radial 9 mm", false),
        ("radial US: R radial 0.5 mm", false),
        ("radial US: harvest", false),
        ("radial US: harvest L", false),
        ("radial US: harvest both", false),
        ("radial US: R radial 26 mm", false),
        ("radial US: R radial A-line", false),
        ("radial US: radial pulse 2+", false),
        ("radial US: R ulnar OK", false),
        ("radial US: R ulnar borderline", false),
        ("radial US: no ulnar", false),
        ("radial US: possible calcification R", false),
        ("radial US: not harvested", false),
        ("radial US: L radial calcified?", false),
        ("radial US: RA 12", false),
        ("radial US: R ICA 70%", false),
        ("radial US: R radial 2.6 cm", false),
        ("radial US: R radial 2,6 mm", false),
        ("radial US: R radial mm", false),
        ("radial US tomorrow", true),
        ("radial US: bilateral 2.6 mm", false),
        ("radial art line R", false),
        ("radial artery harvest 2015", false),
        ("s/p radial cath 2019", false),
        ("radial pulse 2+, ulnar 2+", false),
        ("R radial 2.6 mm", false),
        ("L radial calcified", false),
        ("ulnar adequate", false),
        ("harvest right", false),
        ("no harvest", false),
        ("radial US: R harvest", false),
        ("radial US: Allen test normal", false),
        ("radial US: R radial 2.6 mm?", false),
        ("radial US: R radial >3 mm", false),
    ]
    private static let scenarios: [(String, String, [String])] = [
        ("EF 35, mod MR, RV nl", "echo", ["echo.lvef=35", "echo.valve.mitral.regurgitation=moderate", "echo.rv=normal"]),
        ("EF 35, mod MR, RV nl", "", []),
        ("EF 35, mod MR, RV nl", "lhc", []),
        ("LAD 90%, RCA 40%", "lhc", ["lhc.stenosis.lad=90", "lhc.stenosis.rca=40"]),
        ("RA 12, PA 45/20/30, PCWP 18, CO 4.2", "rhc", ["rhc.ra=12", "rhc.pasp=45", "rhc.padp=20", "rhc.pam=30", "rhc.pcwp=18", "rhc.co=4.2"]),
        ("FEV1 62%, TLC 85%", "pft", ["pft.fev1Pct=62", "pft.tlcPct=85"]),
        ("small L effusion", "cxr", ["cxr.effusion=left,small"]),
        ("R ICA 70-99%, L ICA <50%", "carotid", ["carotid.right.stenosis=ge70", "carotid.left.stenosis=lt50"]),
        ("R radial 2.6 mm, L radial 2.4 mm", "radial", ["radial.right.diameter=2.6", "radial.left.diameter=2.4"]),
        ("clean cors, right dominant", "lhc", ["lhc.result=no-cad", "lhc.dominance=right"]),
        ("EF 35. mod MR", "echo", ["echo.lvef=35", "echo.valve.mitral.regurgitation=moderate"]),
        ("EF 35, HTN, mod MR", "echo", ["echo.lvef=35"]),
        ("68M for AVR, EF 35%", "echo", []),
        ("TTE EF 35%", "lhc", ["echo.study=TTE", "echo.lvef=35"]),
        ("TTE EF 35%, HTN, mod MR", "", ["echo.study=TTE", "echo.lvef=35"]),
        ("TTE EF 35%. Mod MR", "", ["echo.study=TTE", "echo.lvef=35"]),
        ("TTE EF 35%\nmod MR", "", ["echo.study=TTE", "echo.lvef=35"]),
        ("TTE EF 35%, mod MR; LHC LAD 90%, RCA 40%; PFT FEV1 62%", "", ["echo.study=TTE", "echo.lvef=35", "echo.valve.mitral.regurgitation=moderate", "lhc.stenosis.lad=90", "lhc.stenosis.rca=40", "pft.fev1Pct=62"]),
        ("TTE EF 35%, mod MR, LHC LAD 90%", "", ["echo.study=TTE", "echo.lvef=35", "echo.valve.mitral.regurgitation=moderate", "lhc.stenosis.lad=90"]),
        ("LHC LAD 90%, RV nl", "", ["lhc.stenosis.lad=90"]),
        ("TTE EF 35%, RA 12", "", ["echo.study=TTE", "echo.lvef=35"]),
        ("RHC RA 12, EF 35%", "", ["rhc.ra=12"]),
        ("CXR: clear, RA 12", "", ["cxr.result=normal"]),
        ("TTE EF 35% yesterday, mod MR", "", ["echo.study=TTE", "echo.lvef=35", "echo.valve.mitral.regurgitation=moderate"]),
        ("TTE EF 35%, SOB, mod MR", "", ["echo.study=TTE", "echo.lvef=35"]),
        ("no echo, EF 35%", "", []),
        ("needs TTE, EF 35, RV nl", "echo", []),
        ("LHC ordered, LAD 90%", "", []),
        ("TTE: EF 150%", "", []),
        ("TTE: EF 150%, EF 35%", "", []),
        ("RHC: PCWP 80, PCWP 18", "", []),
        ("PFT: FEV1 200%, FEV1 1.8 L", "", []),
        ("LHC: LAD 150%, LAD 90%", "", []),
        ("TTE: EF 35%, EF 50%", "", []),
        ("TTE: EF 35%, EF 35%", "", ["echo.study=TTE", "echo.lvef=35"]),
        ("TTE: RV nl, RV fxn mod reduced", "", []),
        ("TTE: mod MR, severe MR", "", []),
        ("LHC: LAD 90%, LAD 50%", "", []),
        ("LHC: pLAD 90%, mid LAD 50%", "", ["lhc.stenosis.lad=90"]),
        ("RHC: PCWP 18, PCWP 12", "", []),
        ("PFT: FEV1 62%, FEV1 70%", "", []),
        ("CXR: small L effusion, large R effusion", "", []),
        ("carotid US: R ICA 70%, R ICA 40%", "", []),
        ("TTE 6/26: EF 35%; echo 2020: EF 50%", "", []),
        ("TTE 06/2026 EF 35%", "", ["echo.study=TTE", "echo.date=06/2026", "echo.lvef=35"]),
        ("TTE 2024 EF 35%", "", ["echo.study=TTE", "echo.date=2024", "echo.lvef=35"]),
        ("TTE June 2026 EF 35%", "", ["echo.study=TTE", "echo.date=06/2026", "echo.lvef=35"]),
        ("TTE 12/26 EF 35%", "", ["echo.study=TTE", "echo.lvef=35"]),
        ("TTE 6/19 EF 35%", "", ["echo.study=TTE", "echo.date=06/2019", "echo.lvef=35"]),
        ("6/26 TTE: EF 35%", "", ["echo.study=TTE", "echo.date=06/2026", "echo.lvef=35"]),
        ("TTE 2031 EF 35%", "", ["echo.study=TTE", "echo.lvef=35"]),
        ("RHC 3/2025: PCWP 18", "", ["rhc.date=03/2025", "rhc.pcwp=18"]),
        ("PFT 11/2026 FEV1 62%", "", ["pft.date=11/2026", "pft.fev1Pct=62"]),
        ("TTE 6/26", "", ["echo.study=TTE", "echo.date=06/2026"]),
        ("LHC 6/26", "", ["lhc.date=06/2026"]),
        ("CXR 6/26 clear", "", ["cxr.result=normal"]),
        ("cath 2019", "", []),
        ("carotids 2019", "", []),
        ("cors 6/26", "", []),
        ("CXR: clear, small L effusion", "", ["cxr.effusion=left,small"]),
        ("CXR: clear, cardiomegaly", "", ["cxr.findings=cardiomegaly"]),
        ("carotid US: normal, vertebral antegrade", "", ["carotid.right.stenosis=normal", "carotid.left.stenosis=normal"]),
        ("radial US: R radial 2.6 mm, calcified", "", ["radial.right.diameter=2.6"]),
        ("carotid US: R ICA 60%, PSV 230", "", ["carotid.right.stenosis=50-69"]),
        ("TTE: sev MR", "", ["echo.study=TTE", "echo.valve.mitral.regurgitation=severe", "history.valve.mitral.regurgitation=severe"]),
        ("TTE: mod-sev MR, mild TR", "", ["echo.study=TTE", "echo.valve.mitral.regurgitation=severe", "history.valve.mitral.regurgitation=severe", "echo.valve.tricuspid.regurgitation=mild"]),
        ("TTE: severe aortic stenosis", "", ["echo.study=TTE", "echo.valve.aortic.stenosis=severe"]),
        ("TTE: trace AS", "", []),
        ("TTE: PS mild, EF 55%", "", ["echo.study=TTE", "echo.lvef=55"]),
        ("carotid US: nl R, L 50-69%", "", []),
        ("carotid US: normal vertebrals", "", []),
        ("carotid US: R ICA 70-99% PSV 130-230", "", []),
        ("CXR clear except cardiomegaly", "", ["cxr.findings=clear except cardiomegaly"]),
        ("CXR: lungs clear, small L effusion", "", ["cxr.findings=lungs clear", "cxr.effusion=left,small"]),
        ("CXR: effusion resolved", "", []),
        ("CXR 6/26 clear vs 3/26 L effusion", "", []),
        ("CXR: R and L effusions", "", ["cxr.findings=R and L effusions"]),
        ("CXR: small L moderate R effusion", "", ["cxr.findings=small L moderate R effusion"]),
        ("CXR: probably clear", "", []),
        ("CXR: RLL infiltrate, resolved on repeat", "", []),
        ("CXR: w/o infiltrate", "", []),
        ("CXR: RUL mass 3 cm", "", ["cxr.findings=RUL mass 3 cm"]),
        ("CXR: LLL pna WBC 15 temp 38.5", "", ["cxr.findings=LLL pna WBC 15 temp 38.5"]),
        ("CXR: L effusion vs atelectasis", "", []),
        ("LHC: SVG-RCA occluded, LAD 70", "", []),
        ("LHC: LAD 70%-80%", "", []),
        ("LHC 3/26: 3VD, LAD 90 LCx 80 RCA 70", "", ["lhc.stenosis.lad=90", "lhc.stenosis.lcx=80", "lhc.stenosis.rca=70", "lhc.date=03/2026"]),
        ("PFT FEV1 1.8/62%, FVC 3.1/78%", "", []),
        ("PFT: FEV1:FVC 0.58", "", []),
        ("PFT: obs/restr", "", []),
        ("PFT: obstructive w/ mild restriction", "", []),
        ("PFTs normal except DLCO 60%", "", []),
        ("PFT: FEV1 2.9 (pred) 1.8 (actual)", "", []),
        ("radial US 6/26: no harvest L, harvest R", "", []),
        ("radial US 6/26: avoid harvest left", "", []),
        ("echo EF 25% now 40% after GDMT", "", []),
        ("echo 2024 EF 55, repeat 6/26 EF 35", "", []),
        ("TTE EF 40s", "", []),
        ("plan TTE, EF 35", "", []),
        ("RHC: CO 4.1 (TD), CO 4.3 (Fick)", "", []),
        ("tte ef 45%", "", ["echo.lvef=45", "echo.study=TTE"]),
        ("RHC: RV 40/8, RA 8, PA 38/18, PCWP 14", "", ["rhc.ra=8", "rhc.pasp=38", "rhc.padp=18", "rhc.pcwp=14"]),
        ("echo 6/26: EF 35%, grade 2 DD, mod MR, mod TR, RVSP 50", "", ["echo.lvef=35", "echo.valve.mitral.regurgitation=moderate", "echo.valve.tricuspid.regurgitation=moderate", "echo.date=06/2026"]),
        ("EF 35 (TTE 6/26)", "", ["echo.date=06/2026", "echo.study=TTE"]),
        ("PFT FEV1 1.2 ratio 0.50", "", []),
        ("radial US: L radial 2.6 mm non-calcified", "", []),
        ("carotid US: R ICA 80, L ICA 30", "", []),
        ("LHC: co-dom", "", []),
        ("TTE: The left ventricle is normal in size with severely reduced systolic function.", "", []),
        ("TTE: normal LV size, EF 35%", "", []),
        ("CXR: normal heart size, RLL pneumonia", "", ["cxr.findings=normal heart size; RLL pneumonia"]),
        ("CXR: left pleural effusion resolved", "", []),
        ("CXR: absence of pleural effusion", "", []),
        ("CXR: PA and lateral views demonstrate clear lungs without focal consolidation, effusion or pneumothorax.", "", []),
        ("CXR: small-to-moderate left effusion", "", ["cxr.findings=small-to-moderate left effusion"]),
        ("Chest x-ray: large left pleural effusion with mediastinal shift to the right", "", []),
        ("PFTs: RV/TLC 45%", "", []),
        ("Spirometry: FEV1:FVC 0.63", "", []),
        ("PFTs: FEV1 1,5 L", "", []),
        ("Spirometry: FEV1/FVC 1.5/2.4", "", []),
        ("PFTs: moderately severe obstruction", "", []),
        ("Carotid duplex: bilateral ICA 50-69% R and 70-99% L", "", []),
        ("Carotid duplex: R/L: <50%/50-69%", "", []),
        ("RHC: RA 12 cmH2O", "", []),
        ("TTE 11/18: EF 35%", "", ["echo.lvef=35", "echo.date=11/2018", "echo.study=TTE"]),
        ("Possible LHC for LAD 90%", "", []),
        ("Echo results pending: EF 35%", "", []),
        ("LHC: LAD 90% pre-PCI, 0% post-PCI", "", []),
        ("LHC: 90% LAD stenosis, 70% RCA stenosis", "", ["lhc.stenosis.lad=90", "lhc.stenosis.rca=70"]),
        ("LHC: 90% stenosis of the LAD", "", ["lhc.stenosis.lad=90"]),
        ("Carotid duplex: right ICA 50-69% stenosis, left ICA less than 50% stenosis.", "", ["carotid.right.stenosis=50-69"]),
        ("Carotid duplex: 50-69% stenosis of the right ICA", "", ["carotid.right.stenosis=50-69"]),
        ("RHC: PA 45/20 (mean 30), PCWP 18, CO 3.9 / CI 2.0", "", ["rhc.pasp=45", "rhc.padp=20", "rhc.pam=30", "rhc.pcwp=18", "rhc.co=3.9"]),
        ("RHC: RA 12, RV 48/10, PA 48/22 (32), PCW 20, CO 4.1, CI 2.0", "", ["rhc.ra=12", "rhc.pasp=48", "rhc.padp=22", "rhc.pam=32", "rhc.pcwp=20", "rhc.co=4.1"]),
        ("RHC: RA 8, PA 55/25 mean 35, PCWP 15, Fick CO 4.8 L/min", "", ["rhc.ra=8", "rhc.pasp=55", "rhc.padp=25", "rhc.pam=35", "rhc.pcwp=15", "rhc.co=4.8"]),
        ("Right heart catheterization: RA pressure 10 mmHg, PA pressure 60/30 mmHg with a mean of 42 mmHg, PCWP 12 mmHg, thermodilution cardiac output 5.1 L/min", "", ["rhc.ra=10"]),
        ("TTE: severe LV systolic dysfunction", "", ["echo.lv=severe", "echo.study=TTE"]),
        ("Echocardiogram 3/2026. LVEF approximately 30%. There is moderate mitral regurgitation.", "", ["echo.date=03/2026"]),
        ("TTE: EF 55%, mild MR and TR", "", ["echo.lvef=55", "echo.study=TTE"]),
        ("PFTs: FEV1 1.5 L, 52% predicted; FVC 2.4 L, 66% predicted; FEV1/FVC 63%", "", ["pft.fev1=1.5"]),
        ("Radial artery ultrasound: right radial artery diameter 2.6 mm, left 2.4 mm; no calcification; ulnar flow adequate bilaterally.", "", []),
        ("CXR: right-sided pleural effusion", "", ["cxr.effusion=right,-"]),
        ("CXR: no acute cardiopulmonary abnormality", "", []),
        ("LHC: three vessel disease with 80% LAD, 90% RCA, 70% LCx.", "", []),
        ("Swan numbers: CVP 12, PA 48/22/32, PCWP 20, CO 4.1", "", []),
        ("PFT: FEV1 1.8/62%", "", []),
        ("PFTs: FEV1 1,8 L", "", []),
        ("RHC: CO 4,2", "", []),
        ("PFT: FEV1:FVC 0.55", "", []),
        ("PFT: RV/TLC 45%", "", []),
        ("PFT: obstruction ruled out", "", []),
        ("PFT: obstructive vs restrictive", "", []),
        ("TTE: EF was 55%, now 35%", "", []),
        ("RHC: PCWP 18 -> 12 after diuresis", "", []),
        ("TTE: RV EF 35%", "", []),
        ("TTE: probably EF 35%", "", []),
        ("echo: EF 35 or 40", "", []),
        ("echo: EF 35% - 40%", "", []),
        ("echo to eval EF 35%", "", []),
        ("will echo, EF 35%", "", []),
        ("echo 11/18 EF 55%", "", ["echo.lvef=55", "echo.date=11/2018"]),
        ("TTE 6/15 EF 35%", "", ["echo.lvef=35", "echo.date=06/2015", "echo.study=TTE"]),
        ("echo 2019 EF 55%, 2026 EF 30%", "", []),
        ("carotid US 2019: R ICA 70%; 2025: R ICA 50-69%", "", []),
        ("CXR: R effusion, resolved", "", []),
        ("CXR: cannot exclude effusion", "", []),
        ("CXR: question of L effusion", "", []),
        ("CXR: normal heart size, R effusion", "", ["cxr.findings=normal heart size", "cxr.effusion=right,-"]),
        ("CXR: heart size normal, mod R effusion", "", ["cxr.findings=heart size normal", "cxr.effusion=right,moderate"]),
        ("CXR: R effusion vs atelectasis", "", []),
        ("CXR: R effusion, L pneumothorax", "", ["cxr.effusion=right,-", "cxr.findings=L pneumothorax"]),
        ("CXR: L effusion + R infiltrate", "", ["cxr.findings=L effusion + R infiltrate"]),
        ("cath to evaluate LAD 90% on CTA", "", []),
        ("cath postponed: LAD 90%", "", []),
        ("cath: SVG-RCA 100%", "", []),
        ("LHC: LAD 90%, LAD 50% post PCI", "", []),
        ("LHC: pre PCI LAD 90%, post PCI 0%", "", []),
        ("LHC: 70% LAD 50% RCA", "", []),
        ("LHC: 70% mid LAD 50% prox RCA", "", []),
        ("LHC: LM/LAD 70%", "", []),
        ("RHC: Fick CO 4.2, TD CO 5.1", "", []),
        ("RHC: CO 4.2, CO 3.9 post", "", []),
        ("RHC: PCWP 18 or 20", "", []),
        ("RHC: PCWP 15 or less", "", []),
        ("carotid US: R ICA 70% (2019), now 50%", "", []),
        ("carotid US: R ICA 70% pre-CEA", "", []),
        ("radial US: no harvest right", "", []),
        ("echo: AR mild MR mod", "", []),
        ("RHC: PA 25/10 (mean 15), RA 4, CO 5.2", "", ["rhc.pasp=25", "rhc.padp=10", "rhc.pam=15", "rhc.ra=4", "rhc.co=5.2"]),
        ("left and right heart cath: LAD 90%, PCWP 18", "", []),
        ("carotid US 6/26: normal bilaterally", "", ["carotid.right.stenosis=normal", "carotid.left.stenosis=normal", "carotid.date=06/2026"]),
        ("CXR: left sided effusion", "", ["cxr.effusion=left,-"]),
        ("CXR: lungs are clear bilaterally", "", ["cxr.findings=lungs are clear bilaterally"]),
        ("LHC via R radial, LAD 90%, RCA 40%", "", []),
        ("TTE: EF35%", "", []),
        ("echo: DD grade 2, EF 55%", "", []),
        ("TTE: EF 35%, TAPSE 12 mm, RV fxn mod reduced", "", ["echo.lvef=35", "echo.study=TTE"]),
        ("LHC: RCA chronic total occlusion", "", []),
        ("TTE: normal LV size", "", []),
        ("echo EF 25% -> 45% after CRT", "", []),
        ("TTE: LVEF 40%-45%", "", []),
        ("PFT: FEV1 1.8-2.0 L", "", []),
        ("CXR: normal heart size, small L effusion", "", ["cxr.findings=normal heart size", "cxr.effusion=left,small"]),
        ("CXR: normal heart size", "", ["cxr.findings=normal heart size"]),
        ("CXR: L effusion resolved", "", []),
        ("CXR: atelectasis vs effusion", "", []),
        ("Echo unavailable: EF 35%", "", []),
        ("RHC: CO 2.4 L/min/m2", "", []),
        ("Carotid US: bilateral ICA 40% R, 60% L", "", []),
        ("Cath 2019: 90% LAD s/p stent", "", []),
        ("TTE 6/12 EF 35%", "", ["echo.lvef=35", "echo.date=06/2012", "echo.study=TTE"]),
        ("echo 4/26: EF ~25%, severe LV systolic dysfunction, mod-severe MR", "", ["echo.lvef=25", "echo.lv=severe", "echo.valve.mitral.regurgitation=severe", "echo.date=04/2026"]),
        ("PFT 6/26: nl", "", ["pft.pattern=normal", "pft.date=06/2026"]),
        ("Pulmonary function testing 2025: FEV1 2.1L, FVC 3.0L, FEV1/FVC 70%", "", ["pft.fev1=2.1", "pft.fvc=3", "pft.ratio=70", "pft.date=2025"]),
        ("RHC: PA 52/24 (mean 35)", "", ["rhc.pasp=52", "rhc.padp=24", "rhc.pam=35"]),
        ("Carotid duplex: R ICA 60%, L ICA 30% stenosis", "", ["carotid.right.stenosis=50-69", "carotid.left.stenosis=lt50"]),
        ("LHC: LAD 60%, D1 70%, RCA 50%", "", ["lhc.stenosis.lad=60"]),
        ("Radial artery mapping: R radial 2.5 mm, L radial 2.2 mm, ulnar adequate bilaterally", "", []),
        ("CXR: negative", "", []),
        ("R/LHC 6/26: LAD 90%, PCWP 18, PA 45/20", "", ["lhc.stenosis.lad=90", "lhc.date=06/2026"]),
        ("CXR: pericardial effusion", "", ["cxr.findings=pericardial effusion"]),
        ("CXR: trace L effusion", "", ["cxr.findings=trace L effusion"]),
        ("CXR: massive R effusion", "", ["cxr.findings=massive R effusion"]),
        ("CXR: loculated effusion", "", ["cxr.findings=loculated effusion"]),
        ("CXR: mild effusion", "", ["cxr.findings=mild effusion"]),
        ("CXR: small to moderate L effusion", "", ["cxr.findings=small to moderate L effusion"]),
        ("TTE EF 35%, now on lasix", "", []),
        ("TTE EF 35%, mod MR with SAM, RV nl", "", ["echo.lvef=35", "echo.study=TTE"]),
        ("CXR: clear to auscultation", "", []),
        ("TTE 12/26 EF 35%", "", ["echo.lvef=35", "echo.study=TTE"]),
        ("TTE 2031 EF 35%", "", ["echo.lvef=35", "echo.study=TTE"]),
        ("CXR 6/26 clear", "", ["cxr.result=normal"]),
    ]

    // MARK: The tables, run

    func testEchoYes() { yes(Self.yesEcho) }
    func testLeftHeartCathYes() { yes(Self.yesLhc) }
    func testRightHeartCathYes() { yes(Self.yesRhc) }
    func testPFTYes() { yes(Self.yesPft) }
    func testChestXrayYes() { yes(Self.yesCxr) }
    func testCarotidYes() { yes(Self.yesCarotid) }
    func testRadialYes() { yes(Self.yesRadial) }

    func testSharedNoLinesReadNothing() { no(Self.noShared) }
    func testEchoNo() { no(Self.noEcho) }
    func testLeftHeartCathNo() { no(Self.noLhc) }
    func testRightHeartCathNo() { no(Self.noRhc) }
    func testPFTNo() { no(Self.noPft) }
    func testChestXrayNo() { no(Self.noCxr) }
    func testCarotidNo() { no(Self.noCarotid) }
    func testRadialNo() { no(Self.noRadial) }

    /// Runs end, numbers out of range, disagreement in one run, dates, the study's own page, three studies in one line.
    func testScenarios() {
        for item in Self.scenarios {
            XCTAssertEqual(codes(item.0, page: CardioStudy(rawValue: item.1)), item.2.sorted(), item.0 + (item.1.isEmpty ? "" : "  [page " + item.1 + "]"))
        }
    }

    func testEveryTableIsBigEnough() {
        XCTAssertGreaterThanOrEqual(Self.yesEcho.count, 25)
        XCTAssertGreaterThanOrEqual(Self.yesLhc.count, 25)
        XCTAssertGreaterThanOrEqual(Self.yesRhc.count, 25)
        XCTAssertGreaterThanOrEqual(Self.yesPft.count, 25)
        XCTAssertGreaterThanOrEqual(Self.yesCxr.count, 25)
        XCTAssertGreaterThanOrEqual(Self.yesCarotid.count, 25)
        XCTAssertGreaterThanOrEqual(Self.yesRadial.count, 25)
        for n in [Self.noEcho.count, Self.noLhc.count, Self.noRhc.count, Self.noPft.count, Self.noCxr.count, Self.noCarotid.count, Self.noRadial.count] {
            XCTAssertGreaterThanOrEqual(n + Self.noShared.count, 40)
        }
    }

    func testEveryPatternCompiles() {
        for rx in CardioText.allPatterns { XCTAssertNotNil(rx.re, rx.pattern) }
        XCTAssertTrue(QuickAdd.allPatterns.count > CardioText.allPatterns.count)
    }

    // MARK: Where it is read

    private func isCardio(_ f: PatientNoteFinding) -> Bool {
        if case .cardio = f.change { return true }
        if case .echoValve = f.change { return true }
        return false
    }

    func testThePreoperativeBarReadsAndTheIntraoperativeAndSummaryBarsDoNot() {
        let line = "TTE 6/26 EF 35%, mod MR, RV nl"
        let r = PatientRecord()
        let pre = QuickAdd.read(line, record: r, tab: .preop, now: now)
        XCTAssertEqual(codes(pre).filter { !$0.hasPrefix("history.") }, ["echo.date=06/2026", "echo.lvef=35", "echo.rv=normal", "echo.study=TTE", "echo.valve.mitral.regurgitation=moderate"])
        // The Intraoperative tab: these words are the intraoperative exam, as today.
        let intra = QuickAdd.read(line, record: r, tab: .intraop, now: now)
        XCTAssertFalse(intra.findings.contains(where: isCardio))
        // Summary & Handoff reads as the Preoperative tab does, but where the case is told.
        let summary = QuickAdd.read(line, record: r, tab: .preop, now: now, handoff: true)
        XCTAssertFalse(summary.findings.contains { if case .cardio = $0.change { return true }; return false })
        // An editor page that is not a study's reads behind a cue, as the tab does.
        XCTAssertEqual(PatientEditor.workup("surgeries").cardioStudy, nil)
        XCTAssertEqual(PatientEditor.history.cardioStudy, nil)
    }

    func testAStudysOwnPageNeedsNoCue() {
        let r = PatientRecord()
        let line = "EF 35, mod MR, RV nl"
        let none = QuickAdd.read(line, record: r, tab: .preop, now: now)
        XCTAssertFalse(none.findings.contains { if case .cardio = $0.change { return true }; return false }, "no cue, no page: history, as today")
        let page = QuickAdd.read(line, record: r, tab: .preop, now: now, cardioPage: .echo)
        XCTAssertEqual(codes(page).filter { !$0.hasPrefix("history.") }, ["echo.lvef=35", "echo.rv=normal", "echo.valve.mitral.regurgitation=moderate"])
        let ids: [String: CardioStudy] = ["echo": .echo, "lhc": .lhc, "rhc": .rhc, "pft": .pft, "cxr": .cxr, "carotid": .carotid, "radial": .radial]
        for (id, study) in ids { XCTAssertEqual(PatientEditor.workup(id).cardioStudy, study, id) }
        XCTAssertEqual(PatientEditor.intraopPart("echo").cardioStudy, nil, "the intraoperative echo is the case's exam")
        XCTAssertEqual(PatientEditor.workup("ecg").cardioStudy, nil)
        XCTAssertEqual(PatientEditor.workup("stress").cardioStudy, nil)
    }

    func testThePastedNoteReadsToo() {
        let note = "TTE 6/26: EF 35%, mod MR, RV nl.\nLHC: LAD 90%, RCA 40%, right dominant."
        let on = PatientNote.read(note, now: now, cardio: true)
        let got = on.findings.compactMap { CardioText.code($0) }
        for c in ["echo.lvef=35", "echo.rv=normal", "echo.study=TTE", "echo.date=06/2026", "lhc.stenosis.lad=90", "lhc.stenosis.rca=40", "lhc.dominance=right"] {
            XCTAssertTrue(got.contains(c), c)
        }
        let off = PatientNote.read(note, now: now)
        XCTAssertFalse(off.findings.contains { if case .cardio = $0.change { return true }; return false }, "the sheet opened from where the case is told reads none")
        // The same line on the sheet opened from a study's page needs no cue.
        let page = PatientNote.read("PA 45/20/30, PCWP 18", now: now, cardio: true, cardioPage: .rhc)
        XCTAssertEqual(page.findings.compactMap { CardioText.code($0) }.sorted(), ["rhc.padp=20", "rhc.pam=30", "rhc.pasp=45", "rhc.pcwp=18"])
    }

    func testTheSheetOpenedFromTheOperatingRoomFilesNone() {
        let note = PatientNote.read("TTE EF 35%, RV nl", now: now, cardio: true)
        XCTAssertTrue(note.findings.contains { if case .cardio = $0.change { return true }; return false })
        let routed = QuickAdd.forTab(note, tab: .intraop, record: PatientRecord(), now: now)
        XCTAssertFalse(routed.findings.contains(where: isCardio), "the preoperative studies are never filed from the OR")
    }

    // MARK: What is read is not read again

    func testWhatIsReadIsMaskedFromTheHistoryReader() {
        let r = PatientRecord()
        let rhc = QuickAdd.read("RHC: RA 12, PA 45/20/30, PCWP 18, CO 4.2", record: r, tab: .preop, now: now)
        XCTAssertEqual(codes(rhc), ["rhc.co=4.2", "rhc.padp=20", "rhc.pam=30", "rhc.pasp=45", "rhc.pcwp=18", "rhc.ra=12"])
        XCTAssertFalse(rhc.findings.contains { if case .vital = $0.change { return true }; return false }, "RA is the pressure here, not room air")
        XCTAssertTrue(rhc.ambiguous.isEmpty, "and is not asked about")
        XCTAssertTrue(rhc.unread.isEmpty)
        let lhc = QuickAdd.read("LHC: LAD 90%, RCA 40%, right dominant", record: r, tab: .preop, now: now)
        XCTAssertEqual(codes(lhc), ["lhc.dominance=right", "lhc.stenosis.lad=90", "lhc.stenosis.rca=40"])
        XCTAssertTrue(lhc.unread.isEmpty)
        let pft = QuickAdd.read("PFTs: FEV1 1.8 L (62%), FVC 3.1 L, TLC 85%, DLCO 45%, severe obstruction", record: r, tab: .preop, now: now)
        XCTAssertEqual(codes(pft), ["pft.dlcoPct=45", "pft.fev1=1.8", "pft.fev1Pct=62", "pft.fvc=3.1", "pft.pattern=obstruction", "pft.severity=severe", "pft.tlcPct=85"])
        XCTAssertTrue(pft.unread.isEmpty)
    }

    func testThreeStudiesInOneLineEachReadOnlyItsOwn() {
        let q = QuickAdd.read("TTE EF 35%, mod MR; LHC LAD 90%, RCA 40%; PFT FEV1 62%", record: PatientRecord(), tab: .preop, now: now)
        let got = codes(q)
        for c in ["echo.lvef=35", "echo.study=TTE", "echo.valve.mitral.regurgitation=moderate", "lhc.stenosis.lad=90", "lhc.stenosis.rca=40", "pft.fev1Pct=62"] {
            XCTAssertTrue(got.contains(c), c)
        }
        XCTAssertFalse(got.contains { $0.hasPrefix("rhc.") || $0.hasPrefix("cxr.") || $0.hasPrefix("carotid.") })
    }

    // MARK: Today's reading, unchanged

    func testOutsideARunEverythingIsReadAsToday() {
        let r = PatientRecord()
        func ids(_ line: String) -> Set<String> { Set(QuickAdd.read(line, record: r, tab: .preop, now: now).findings.map(\.id)) }
        // An EF with no echo cue stays history.
        XCTAssertTrue(ids("EF 35%").contains("problem:ef-moderate"))
        XCTAssertTrue(ids("EF 25%").contains("problem:ef-severe"))
        XCTAssertTrue(ids("HTN, EF 35%").contains("problem:ef-moderate"))
        // A lesion with no echo cue stays history.
        XCTAssertTrue(ids("mod MR").contains("problem:mr"))
        XCTAssertTrue(ids("severe AS").contains("problem:as"))
        XCTAssertFalse(ids("mod MR").contains("echo:mitral:regurgitation"))
        XCTAssertFalse(ids("severe AS").contains("echo:aortic:stenosis"))
        // Behind an echo cue it is the echo's as well, as today.
        XCTAssertTrue(ids("Echo: EF 55%, mild AS").contains("echo:aortic:stenosis"))
        XCTAssertTrue(ids("Echo: EF 55%, mild AS").contains("problem:as"))
        XCTAssertTrue(ids("TTE: severe AS").contains("echo:aortic:stenosis"))
        XCTAssertTrue(ids("TTE: severe AS").contains("problem:as"))
        // A low EF behind an echo cue still files its history item, as today.
        XCTAssertTrue(ids("TTE: EF 25%").contains("problem:ef-severe"))
        XCTAssertTrue(ids("TTE: EF 25%").contains("cardio:echo:lvef"))
        // A cath result in a word is the cath's, as today.
        XCTAssertTrue(ids("cath: normal coronaries").contains("lhc:result"))
        // A planned TEE or LHC is the procedure (the procedure catalog names them), not a study that was done: nothing is read, nothing masked.
        let plan = QuickAdd.read("73M for TEE", record: r, tab: .preop, now: now)
        XCTAssertEqual(plan.findings.first { $0.id == "procedure" }?.change, .procedure("TEE"))
        XCTAssertEqual(codes(QuickAdd.read("68M for LHC, LAD 90%", record: r, tab: .preop, now: now)), [])
        // The words of a study that was not done are masked and read nothing.
        let nd = QuickAdd.read("needs TTE", record: r, tab: .preop, now: now)
        XCTAssertTrue(nd.findings.isEmpty)
    }

    // MARK: Chips, statuses, apply, undo

    private func chip(_ q: QuickAddReading, _ record: PatientRecord, _ id: String) -> QuickAddChip? {
        QuickAdd.chips(q, record: record).first { $0.findings.contains { $0.id == id } }
    }

    func testTheChipsSayTheFieldAndTheValue() {
        let r = PatientRecord()
        let q = QuickAdd.read("TTE 6/26 EF 35%, RV nl; LHC LAD 90%; RHC PCWP 18; PFT FEV1 62%; CXR small L effusion; carotid US R ICA 70-99%", record: r, tab: .preop, now: now)
        XCTAssertEqual(chip(q, r, "cardio:echo:lvef")?.destination, "Echo")
        XCTAssertEqual(chip(q, r, "cardio:echo:lvef")?.value, "EF 35%")
        XCTAssertEqual(chip(q, r, "cardio:echo:rv")?.value, "RV function normal")
        XCTAssertEqual(chip(q, r, "cardio:echo:date")?.value, "Date 06/2026")
        XCTAssertEqual(chip(q, r, "cardio:lhc:stenosis.lad")?.destination, "LHC")
        XCTAssertEqual(chip(q, r, "cardio:lhc:stenosis.lad")?.value, "LAD 90%")
        XCTAssertEqual(chip(q, r, "cardio:rhc:pcwp")?.value, "PCWP 18 mmHg")
        XCTAssertEqual(chip(q, r, "cardio:pft:fev1Pct")?.value, "FEV1 62% predicted")
        XCTAssertEqual(chip(q, r, "cardio:cxr:effusion")?.destination, "CXR")
        XCTAssertEqual(chip(q, r, "cardio:cxr:effusion")?.value, "small left effusion")
        XCTAssertEqual(chip(q, r, "cardio:carotid:right.stenosis")?.value, "Right ICA ≥70%")
    }

    func testStatusesAgainstWhatTheStudyAlreadyHolds() {
        func status(_ line: String, _ id: String, _ r: PatientRecord) -> PatientNoteStatus? {
            let q = QuickAdd.read(line, record: r, tab: .preop, now: now)
            return q.findings.first { $0.id == id }.map { PatientNote.status($0, in: r) }
        }
        var r = PatientRecord()
        XCTAssertEqual(status("TTE EF 35%", "cardio:echo:lvef", r), .new)
        r.echoFindings.lvef = 35
        XCTAssertEqual(status("TTE EF 35%", "cardio:echo:lvef", r), .recorded)
        XCTAssertEqual(status("TTE EF 50%", "cardio:echo:lvef", r), .replaces("35%"))
        r.echoFindings.rv = .moderate
        XCTAssertEqual(status("TTE RV nl", "cardio:echo:rv", r), .replaces("moderately reduced"))
        r.echoFindings.date = PatientMonthYear(month: 6, year: 2026)
        XCTAssertEqual(status("TTE 6/26 EF 35%", "cardio:echo:date", r), .recorded)
        XCTAssertEqual(status("TTE 2026 EF 35%", "cardio:echo:date", r), .recorded)
        XCTAssertEqual(status("TTE 3/25 EF 35%", "cardio:echo:date", r), .replaces("06/2026"))
        r.lhc.stenosis["lad"] = 70
        XCTAssertEqual(status("LHC LAD 90%", "cardio:lhc:stenosis.lad", r), .replaces("70%"))
        XCTAssertEqual(status("LHC LAD 70%", "cardio:lhc:stenosis.lad", r), .recorded)
        XCTAssertEqual(status("LHC RCA 40%", "cardio:lhc:stenosis.rca", r), .new)
        r.chestXray = PatientChestXray(result: .normal)
        XCTAssertEqual(status("CXR small L effusion", "cardio:cxr:effusion", r), .replaces("normal"))
        XCTAssertEqual(status("CXR nl", "cardio:cxr:result", r), .recorded)
        r.chestXray = PatientChestXray(result: .effusion, side: .left, size: .small)
        XCTAssertEqual(status("CXR small L effusion", "cardio:cxr:effusion", r), .recorded)
        XCTAssertEqual(status("CXR large R effusion", "cardio:cxr:effusion", r), .replaces("small left effusion"))
        XCTAssertEqual(status("CXR nl", "cardio:cxr:result", r), .replaces("small left effusion"))
        r.carotid.right.stenosis = "50-69"
        XCTAssertEqual(status("carotid US R ICA 70-99%", "cardio:carotid:right.stenosis", r), .replaces("50–69%"))
        r.radial.right.calcified = false
        XCTAssertEqual(status("radial US R calcified", "cardio:radial:right.calcified", r), .replaces("not calcified"))
        r.pft.fev1 = 1.8
        XCTAssertEqual(status("PFT FEV1 1.8 L", "cardio:pft:fev1", r), .recorded)
    }

    func testApplyWritesExactlyTheFieldsAndNothingElse() {
        var r = PatientRecord()
        let before = r
        let reading = CardioText.read("TTE 6/26 EF 35%, mod MR, RV nl, LV dilated; LHC LAD 90%, RCA 40%, right dominant; RHC PCWP 18, CO 4.2; PFT FEV1 62%, obstructive; CXR small L effusion, cardiomegaly; carotid US R ICA 70-99% PSV 230; radial US L radial 2.4 mm, harvest left", page: nil, now: now)
        PatientNote.apply(reading.findings.map(\.change), to: &r)
        var e = PatientEcho()
        e.study = "TTE"; e.date = PatientMonthYear(month: 6, year: 2026); e.lvef = 35; e.rv = .normal; e.lvSize = .dilated
        e.mitral.regurgitation = .moderate
        XCTAssertEqual(r.echoFindings, e)
        var l = PatientLHC()
        l.stenosis = ["lad": 90, "rca": 40]; l.dominance = "right"
        XCTAssertEqual(r.lhc, l)
        var h = PatientRHC()
        h.pcwp = 18; h.co = 4.2
        XCTAssertEqual(r.rhc, h)
        var p = PatientPFT()
        p.fev1Pct = 62; p.pattern = "obstruction"
        XCTAssertEqual(r.pft, p)
        XCTAssertEqual(r.chestXray, PatientChestXray(result: .effusion, side: .left, size: .small, findings: "cardiomegaly"))
        var c = PatientCarotid()
        c.right.stenosis = "ge70"; c.right.psv = 230
        XCTAssertEqual(r.carotid, c)
        var d = PatientRadial()
        d.left.diameter = 2.4; d.harvest = "left"
        XCTAssertEqual(r.radial, d)
        // Nothing else in the record moved.
        var rest = r
        rest.echoFindings = before.echoFindings; rest.lhc = before.lhc; rest.rhc = before.rhc; rest.pft = before.pft
        rest.chestXray = before.chestXray; rest.carotid = before.carotid; rest.radial = before.radial
        XCTAssertEqual(rest, before)
    }

    @MainActor func testAddingIsOneUndoStep() {
        let store = PatientStore(url: nil)
        let before = store.record
        let q = QuickAdd.read("TTE 6/26 EF 35%, RV nl; LHC LAD 90%", record: before, tab: .preop, now: now)
        let chips = QuickAdd.chips(q, record: before).filter { $0.canAdd }
        XCTAssertFalse(chips.isEmpty)
        store.update(discrete: true) { PatientNote.apply(QuickAdd.changes(chips), to: &$0) }
        XCTAssertEqual(store.record.echoFindings.lvef, 35)
        XCTAssertEqual(store.record.lhc.stenosis["lad"], 90)
        store.undo()
        XCTAssertEqual(store.record.echoFindings, before.echoFindings)
        XCTAssertEqual(store.record.lhc, before.lhc)
        XCTAssertNil(store.record.echoFindings.lvef)
    }

    func testARecordSavedBeforeStillOpensAndTakesTheFindings() throws {
        let old = #"{"procedure":"AVR","echoFindings":{"lv":"mild","lvef":45,"study":"TTE"},"lhc":{"dominance":"left","stenosis":{"lad":50}},"pft":{"fev1":1.5}}"#
        var r = try JSONDecoder().decode(PatientRecord.self, from: Data(old.utf8))
        XCTAssertEqual(r.echoFindings.lvef, 45)
        let q = QuickAdd.read("TTE EF 35%; LHC LAD 90%", record: r, tab: .preop, now: now)
        let lvef = q.findings.first { $0.id == "cardio:echo:lvef" }
        XCTAssertEqual(lvef.map { PatientNote.status($0, in: r) }, .replaces("45%"), "never a silent overwrite")
        PatientNote.apply(q.findings.map(\.change), to: &r)
        XCTAssertEqual(r.echoFindings.lvef, 35)
        XCTAssertEqual(r.echoFindings.lv, .mild, "the other fields are left as they were")
        XCTAssertEqual(r.lhc.stenosis["lad"], 90)
        XCTAssertEqual(r.lhc.dominance, "left")
        XCTAssertEqual(r.pft.fev1, 1.5)
    }

    func testTheCathResultAbbreviationsTheAppLacked() {
        // "clean cors" and "normal cors" are a cath's result, read behind a cath cue.
        XCTAssertEqual(codes("cors: clean cors"), ["lhc.result=no-cad"])
        XCTAssertEqual(codes("LHC: normal cors"), ["lhc.result=no-cad"])
        XCTAssertEqual(codes("clean cors"), [], "with no cue it is not read")
        XCTAssertNil(PatientLHC.readResult("clean cors"))
    }
}
