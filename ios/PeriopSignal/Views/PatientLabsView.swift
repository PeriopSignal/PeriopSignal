import SwiftUI

// MARK: - Labs: typed into the fishbone (1.11, Ben's note 1), the ⊕ sections (cardiac, liver with MELD & Child-Turcotte-Pugh,
// thyroid), type & screen and the infectious results
//
// The page opens on Ben's figures (image4, Nov 9): the BMP (Na | Cl | BUN over K | HCO₃ | Cr, glucose at the point), the
// CBC (WBC < Hb over Hct > Plt), the coagulation figure (PT over PTT, INR at the point, fibrinogen beside it), the hepatic
// figure (Ca | AST, protein | ALT, albumin | alk phos, bilirubin at the point) with Mg and PO₄ beside it, then GFR, HbA1c
// and lactate as plain slots. Each slot is a number field in the fishbone geometry: a tap puts the number pad on it and
// Next walks the figures in PatientLabs.slotOrder. An empty slot shows the catalog's reference range as a faint hint
// (Q20: the app's sourced ranges, never Ben's where they differ); values outside the range are bold red with L or H, as
// everywhere. A "List" toggle shows the 1.10 table instead (and the table comes by itself at the accessibility text
// sizes). The tab card (PreopLabsCard) and the briefs (FishboneFigure) draw the same figures from the same geometry.
// Ranges and the scores' arithmetic and sources are in PatientLabs.

extension PatientEditorView {

    @ViewBuilder var labsEditor: some View {
        PreopLabsFigures(chain: chain)
        typeScreenGroup
        infectiousGroup
        infectiousLabsSection
        pregnancySection
        labSection("cardiac", "Cardiac labs", PatientLabs.tests(.cardiac))
        if r.labSections.contains("liver") {
            liverGroup
        } else {
            labAdd("liver", "Liver (MELD & CTP)")
        }
        labSection("thyroid", "Thyroid", PatientLabs.tests(.thyroid))
        EvidenceNote("Reference ranges are typical adult ranges (ABIM Laboratory Test Reference Ranges, 2026; INR from MedlinePlus; GFR under 60 as KDIGO's decreased GFR); your laboratory's own ranges may differ. The range inside an empty slot is the one the value is flagged against. Natriuretic peptides and troponin are read as the 2024 AHA/ACC perioperative guideline reads them.")
    }

    @ViewBuilder private func labSection(_ id: String, _ add: String, _ tests: [LabTest]) -> some View {
        if labSectionShown(id, tests) {
            PatientGroup(title: tests.first?.group.title) { labRows(tests, section: id) }
        } else {
            labAdd(id, add)
        }
    }

    private func labSectionShown(_ id: String, _ tests: [LabTest]) -> Bool {
        r.labSections.contains(id) || tests.contains(where: { r.labs[$0.key] != nil })
    }

    static let liverKeys = ["tbili", "albumin", "inr", "cr", "na"]

    /// The lab fields on screen, top to bottom: the order Previous and Next walk ("main.na", "liver.inr"). The main
    /// labs are the figures' slots (PatientLabs.slotOrder), or the table's rows when the list is showing.
    var labFieldOrder: [String] {
        var ids = PreopLabsFigures.mainFieldOrder().map { "main." + $0 }
        if infectiousLabsShown { ids += PatientLabs.tests(.infectious).map { "infectious." + $0.key } }
        let cardiac = PatientLabs.tests(.cardiac)
        if labSectionShown("cardiac", cardiac) { ids += cardiac.map { "cardiac." + $0.key } }
        if r.labSections.contains("liver") { ids += Self.liverKeys.map { "liver." + $0 } }
        let thyroid = PatientLabs.tests(.thyroid)
        if labSectionShown("thyroid", thyroid) { ids += thyroid.map { "thyroid." + $0.key } }
        return ids
    }

    /// 1.11 (P1-7): a quiet "+ Name" link, in the action colour, in place of the ⊕ buttons.
    private func labAdd(_ id: String, _ title: String) -> some View {
        LabsQuietLink(title: title) {
            withAnimation(.snappy) { patient.update(discrete: true) { _ = $0.labSections.insert(id) } }
        }
    }

    @ViewBuilder func labRows(_ tests: [LabTest], section: String, estimate: LabValue? = nil) -> some View {
        ForEach(Array(tests.enumerated()), id: \.element.id) { i, t in
            LabFieldRow(test: t, sex: r.sex, troponin99: r.labs["troponin99"], value: entry(\.labs, t.key), chain: chain(section + "." + t.key),
                        estimate: estimate?.key == t.key ? estimate : nil)
            if i < tests.count - 1 { Hairline().padding(.leading, 14) }
        }
    }

    // MARK: Type and screen (1.8.3; the status chips 1.11), infectious results (1.8.3)

    /// Not sent · Sent · Resulted on one line; the ABO/Rh, antibody screen and crossmatch rows open under Resulted (and
    /// stay open while a result is recorded, whatever chip is tapped: PatientTypeScreen.effectiveStatus).
    @ViewBuilder private var typeScreenGroup: some View {
        let ts = r.typeScreen
        PatientGroup(title: "Type & screen") {
            PatientChipRow(label: nil) {
                PatientChoice(options: TypeScreenStatus.allCases.map { (id: $0.rawValue, label: $0.label) },
                              selection: Binding(get: { patient.record.typeScreen.effectiveStatus?.rawValue },
                                                 set: { v in patient.update { $0.typeScreen.setStatus(v.flatMap { TypeScreenStatus(rawValue: $0) }) } }))
            }
            if ts.effectiveStatus == .resulted {
                Hairline().padding(.leading, 14)
                PatientChipRow(label: "ABO/Rh") {
                    PatientChoice(options: PatientTypeScreen.types.map { (id: $0, label: PatientTypeScreen.display($0)) },
                                  selection: Binding(get: { patient.record.typeScreen.type }, set: { v in patient.update { $0.typeScreen.type = v } }))
                }
                Hairline().padding(.leading, 14)
                PatientChipRow(label: "Antibody screen") {
                    PatientChoice(options: LabResult.allCases.map { (id: $0.rawValue, label: $0.label) },
                                  selection: Binding(get: { patient.record.typeScreen.screen?.rawValue },
                                                     set: { v in patient.update { $0.typeScreen.screen = v.flatMap { LabResult(rawValue: $0) } } }),
                                  tint: PS.red)
                }
                if ts.screen == .positive || !ts.antibodyText.isEmpty {
                    LabInlineText(label: "Antibody", prompt: "e.g. anti-K",
                                  text: Binding(get: { patient.record.typeScreen.antibody }, set: { v in patient.update { $0.typeScreen.antibody = v } }))
                }
                Hairline().padding(.leading, 14)
                BloodStepperRow(label: "Crossmatched", unit: "units", step: 1, limit: Double(PatientTypeScreen.unitLimit),
                                value: Binding(get: { patient.record.typeScreen.crossmatched.map { Double($0) } },
                                               set: { v in patient.update { $0.typeScreen.crossmatched = v.map { Int($0.rounded()) }.flatMap { $0 > 0 ? $0 : nil } } }))
            }
            // 1.12 (Ben): the blood bank's expiration, once the type and screen is sent or resulted; entered by hand.
            if ts.effectiveStatus == .sent || ts.effectiveStatus == .resulted {
                Hairline().padding(.leading, 14)
                TypeScreenExpiresRow()
            }
        }
        // Screenshot runs: -ps.patient.scroll labs-results.
        .id("labs-results")
    }

    @ViewBuilder private var infectiousGroup: some View {
        let options = LabResult.allCases.map { (id: $0.rawValue, label: $0.label) }
        PatientGroup(title: "Infectious results", note: "A positive MRSA, COVID-19 or C. difficile result, or an Other result read as VRE, also ticks its item under History › Infectious; a Staph aureus screen does not. Negative or pending adds nothing, and an item a result added goes again if the result changes.") {
            ForEach(LabResults.infectious) { t in
                PatientChipRow(label: t.label) {
                    PatientChoice(options: options,
                                  selection: Binding(get: { patient.record.infections.results[t.id]?.rawValue },
                                                     set: { v in patient.update { LabResults.set(t.id, v.flatMap { LabResult(rawValue: $0) }, in: &$0) } }))
                }
                Hairline().padding(.leading, 14)
            }
            ForEach(r.infections.other) { o in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        CapTextField(prompt: "Other test, e.g. VRE", text: Binding(get: { patient.record.infections.other.first { $0.id == o.id }?.name ?? "" },
                                                                         set: { v in patient.update { r in LabResults.edit(&r) { x in
                                                                             if let i = x.other.firstIndex(where: { $0.id == o.id }) { x.other[i].name = v } } } }))
                            .font(PS.sys(size: 14.5, weight: .medium))
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(PS.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        Button {
                            Haptics.light()
                            patient.update(discrete: true) { r in LabResults.edit(&r) { x in x.other.removeAll { $0.id == o.id } } }
                        } label: { Image(systemName: "xmark.circle.fill").font(PS.sys(size: 18)).foregroundStyle(PS.fg3) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove this result")
                    }
                    PatientChoice(options: options,
                                  selection: Binding(get: { patient.record.infections.other.first { $0.id == o.id }?.result?.rawValue },
                                                     set: { v in patient.update { r in LabResults.edit(&r) { x in
                                                         if let i = x.other.firstIndex(where: { $0.id == o.id }) { x.other[i].result = v.flatMap { LabResult(rawValue: $0) } } } } }))
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                Hairline().padding(.leading, 14)
            }
            LabsQuietLink(title: "Other result") {
                patient.update(discrete: true) { $0.infections.other.append(PatientInfectiousOther()) }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
        }
    }

    // MARK: Infectious labs and the pregnancy test (1.12, Ben's note 12)

    /// The "+ Infectious labs" box is open once the link was tapped or any of its results is recorded.
    var infectiousLabsShown: Bool {
        r.labSections.contains("infectious") || r.moreLabs.hasInfectious || r.labs["vanc"] != nil
    }

    private var negativeOption: [(id: String, label: String)] { [(id: "neg", label: "Negative")] }

    /// Urinalysis (Negative, or the findings), blood cultures (Negative, or what is known) and the vancomycin level. They sit
    /// with the infectious results above; a urinalysis finding or a culture that is not negative is read by the next team
    /// (bold red in the summaries), so it is typed here as it was reported.
    @ViewBuilder private var infectiousLabsSection: some View {
        if infectiousLabsShown {
            PatientGroup(title: "Infectious labs", note: "Urinalysis and blood cultures are Negative or what was reported; a finding, or a culture that is not negative, shows in bold red in the summaries. The vancomycin level has no reference range here: the target depends on the indication.") {
                PatientChipRow(label: "Urinalysis") {
                    PatientChoice(options: negativeOption,
                                  selection: Binding(get: { patient.record.moreLabs.uaNegative ? "neg" : nil },
                                                     set: { v in patient.update { $0.moreLabs.setUrinalysisNegative(v != nil) } }))
                }
                PatientChipRow(label: nil) {
                    PatientChips(options: PatientMoreLabs.urinalysisFindings.map { PatientFlag($0.id, $0.label) },
                                 selection: Binding(get: { patient.record.moreLabs.uaFindings },
                                                    set: { v in patient.update { r in
                                                        r.moreLabs.uaFindings = v
                                                        if !v.isEmpty { r.moreLabs.uaNegative = false }
                                                    } }))
                }
                LabInlineText(label: "Findings", prompt: "e.g. cloudy, trace protein",
                              text: Binding(get: { patient.record.moreLabs.uaText }, set: { v in patient.update { $0.moreLabs.setUrinalysisText(v) } }))
                Hairline().padding(.leading, 14)
                PatientChipRow(label: "Blood cultures") {
                    PatientChoice(options: negativeOption,
                                  selection: Binding(get: { patient.record.moreLabs.bloodCxNegative ? "neg" : nil },
                                                     set: { v in patient.update { $0.moreLabs.setBloodCulturesNegative(v != nil) } }))
                }
                LabInlineText(label: "Result", prompt: "e.g. GPC in clusters, 1 of 2 bottles",
                              text: Binding(get: { patient.record.moreLabs.bloodCxText }, set: { v in patient.update { $0.moreLabs.setBloodCulturesText(v) } }))
                Hairline().padding(.leading, 14)
                labRows(PatientLabs.tests(.infectious), section: "infectious")
            }
            .id("labs-infectious")
        } else {
            labAdd("infectious", "Infectious labs")
        }
    }

    /// "+ Pregnancy test": a Negative chip and/or an hCG value; shown for a woman and when the sex is not set.
    @ViewBuilder private var pregnancySection: some View {
        if PatientMoreLabs.showsPregnancy(r.sex) {
            if r.labSections.contains("pregnancy") || r.moreLabs.hasPregnancy || r.labs["hcg"] != nil {
                PatientGroup(title: "Pregnancy test", note: "Negative, and/or the hCG value as reported. A number is kept as a lab; words such as <5 stay as typed. No reference range is shown: it depends on the assay and the setting.") {
                    PatientChipRow(label: "Result") {
                        PatientChoice(options: negativeOption,
                                      selection: Binding(get: { patient.record.moreLabs.pregnancyNegative ? "neg" : nil },
                                                         set: { v in patient.update { $0.moreLabs.pregnancyNegative = v != nil } }))
                    }
                    HCGField()
                }
                .id("labs-pregnancy")
            } else {
                labAdd("pregnancy", "Pregnancy test")
            }
        }
    }

    // MARK: Liver

    @ViewBuilder private var liverGroup: some View {
        let res = PatientLabs.liver(LiverInput(record: r, dialysis: r.dialysis, ascites: r.ascites, encephalopathy: r.encephalopathy))
        PatientGroup(title: "Liver function testing (MELD & CTP)") {
            labRows(Self.liverKeys.compactMap { PatientLabs.test($0) }, section: "liver")
            Hairline().padding(.leading, 14)
            PatientChipRow(label: "Ascites") {
                PatientChoice(options: LiverAscites.allCases.map { (id: $0.rawValue, label: $0.label) },
                              selection: Binding(get: { patient.record.ascites?.rawValue }, set: { v in patient.update { $0.ascites = v.flatMap { LiverAscites(rawValue: $0) } } }))
            }
            PatientChipRow(label: "Encephalopathy") {
                PatientChoice(options: LiverEncephalopathy.allCases.map { (id: $0.rawValue, label: $0.label) },
                              selection: Binding(get: { patient.record.encephalopathy?.rawValue }, set: { v in patient.update { $0.encephalopathy = v.flatMap { LiverEncephalopathy(rawValue: $0) } } }))
            }
            toggleRow("Dialysis", "Twice or more in the past week, or CVVHD for 24 h: creatinine counts as the cap", bind(\.dialysis))
        }
        HStack(spacing: 10) {
            scoreTile("MELD 3.0", res.meld3.map(String.init), alert: (res.meld3 ?? 0) >= 15)
            scoreTile("MELD-Na", res.meldNa.map(String.init), alert: (res.meldNa ?? 0) >= 15)
            scoreTile("Child-Pugh", res.childPughClass.map { "\($0.rawValue) · \(res.childPugh ?? 0)" }, alert: res.childPughClass.map { $0 != .a } ?? false)
        }
        if !res.missing.isEmpty {
            Text("Still needed: " + res.missing.joined(separator: ", ") + ".").font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).padding(.horizontal, 4)
        }
        if !res.interpretation.isEmpty || !res.adjustments.isEmpty {
            EvidenceDisclosure {
                ForEach(res.adjustments + res.interpretation, id: \.self) { t in
                    Text(t).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
                }
                Text("MELD 3.0: Kim WR et al., Gastroenterology 2021 (the OPTN allocation score since July 2023). MELD-Na: the OPTN 2016 formula. Child-Turcotte-Pugh: Pugh RN et al., Br J Surg 1973, with the FDA and AASLD-IDSA cut-offs.")
                    .font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func scoreTile(_ title: String, _ value: String?, alert: Bool) -> some View {
        VStack(spacing: 4) {
            Text(title).font(PS.mono(size: 9.5, weight: .semibold)).textCase(.uppercase).foregroundStyle(PS.fg3).lineLimit(1).minimumScaleFactor(0.8)
            Text(value ?? "—").font(PS.sys(size: 22, weight: .bold, design: .rounded)).foregroundStyle(value == nil ? PS.fg3 : (alert ? PS.red : PS.fg))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Right heart catheterization results

    @ViewBuilder var rhcResults: some View {
        let h = r.rhc
        let res = PatientLabs.rightHeart(RightHeartInput(ra: h.ra, pasp: h.pasp, padp: h.padp, mpap: h.pam, pcwp: h.pcwp, co: h.co, bsa: r.bsa))
        let rows: [(String, String?, Bool)] = [
            ("Mean PA" + (res.mpapEstimated ? " (estimated)" : ""), res.mpap.map { NumText.short($0, places: 0) + " mmHg" }, (res.mpap ?? 0) > 20),
            ("Transpulmonary gradient", res.tpg.map { NumText.short($0, places: 0) + " mmHg" }, false),
            ("Diastolic pressure gradient", res.dpg.map { NumText.short($0, places: 0) + " mmHg" }, false),
            ("PVR", res.pvr.map { NumText.short($0, places: 1) + " WU" }, (res.pvr ?? 0) > 2),
            ("PAPI", res.papi.map { NumText.short($0, places: 2) }, !res.papiBelow.isEmpty),
            ("Cardiac index", res.ci.map { NumText.short($0, places: 2) + " L/min/m²" }, (res.ci ?? 9) < 2.2),
        ]
        if rows.contains(where: { $0.1 != nil }) {
            PatientGroup(title: "Calculated") {
                ForEach(Array(rows.filter { $0.1 != nil }.enumerated()), id: \.offset) { i, row in
                    HStack {
                        Text(row.0).font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg)
                        Spacer()
                        Text(row.1 ?? "").font(PS.sys(size: 15, weight: row.2 ? .bold : .semibold, design: .monospaced)).foregroundStyle(row.2 ? PS.red : PS.fg)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                }
                if let t = res.phText {
                    Text(t).font(PS.sys(size: 13.5, weight: .semibold)).foregroundStyle(res.ph?.isPH == true ? PS.red : PS.fg2)
                        .fixedSize(horizontal: false, vertical: true).padding(14)
                }
            }
            if !res.notes.isEmpty || !res.papiBelow.isEmpty {
                EvidenceDisclosure {
                    ForEach(res.papiBelow.map(\.text) + res.notes, id: \.self) { t in
                        Text(t).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Definitions: 2022 ESC/ERS pulmonary hypertension guideline (Humbert M et al., Eur Heart J 2022). Mean PA estimated as (PASP + 2 × PADP)/3 when not measured.")
                        .font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        if !res.missing.isEmpty && rows.contains(where: { $0.1 != nil }) {
            Text("For the rest: " + res.missing.joined(separator: ", ") + ".").font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).padding(.horizontal, 4)
        }
    }
}

// MARK: - The figures on the page

/// The tab card asks the page to open with the keyboard on one slot (PreopLabsCard): the slot's field id ("main.k"),
/// taken once by the page when it appears, in the figures or the table. The card notes the request as its link fires,
/// and the page's view is built only on the render pass after that, so the request is there before the page appears.
/// Screenshot runs stand in for the card's tap with -ps.labs.slot main.k (debug builds), which leaves the same request
/// at launch.
@MainActor
enum LabSlotFocusRequest {
    /// How long a tap's request waits for its page. The push starts in the same gesture, so an older request never
    /// opened a page, and must not put the keyboard on a later visit (another patient's page, perhaps).
    static let life: TimeInterval = 5

    /// The request a tap left, and when.
    private static var tapped: (id: String, at: Date)?
    /// The one a screenshot run leaves at launch, which waits for its page however slow the launch.
    private static var seeded: String? = launchRequest()

    static var pending: String? {
        get { tapped?.id ?? seeded }
        set {
            seeded = nil
            tapped = newValue.map { (id: $0, at: Date()) }
        }
    }

    /// When a tap left the request; nil with none, and for a screenshot run's.
    static var noted: Date? { tapped?.at }

    /// The request, once: nothing stays pending after the page has appeared, whatever the page shows.
    static func take(now: Date = Date()) -> String? {
        defer { pending = nil }
        if let t = tapped, now.timeIntervalSince(t.at) > life { return nil }
        return pending
    }

    /// The slot a screenshot run's -ps.labs.slot asks for; nil in a plain launch.
    nonisolated static func launchRequest() -> String? {
        let s = LaunchSeed.string("ps.labs.slot")
        return s.isEmpty ? nil : s
    }
}

/// One slot request as the page works through it. The page tries a few times, because a push can drop the first, but
/// only until the keyboard has been anywhere: once the focus is found on a field (the slot asked for, or one the user
/// tapped), or a keyboard has come up at all, the request is over. So Done, or a tap on Other results, is never
/// answered by the keyboard coming back to the slot.
struct LabSlotFocusAttempt: Equatable {
    /// The field id still to focus; nil with no request, or once it is over.
    private(set) var request: String?

    /// How long after a try the page looks whether the focus held.
    static let settleTime: TimeInterval = 0.35
    /// When the page tries, in seconds after it appears.
    static let tries: [TimeInterval] = [0.5, 1.4, 3.0]

    var isLive: Bool { request != nil }

    /// The page appeared with this request: kept only when it names a field the page shows now.
    mutating func begin(_ id: String?, fields: [String]) {
        request = id.flatMap { fields.contains($0) ? $0 : nil }
    }

    /// A try's turn: true when it may put the keyboard on `id`. A focus found on any field ends the request.
    mutating func shouldFocus(_ id: String, focus: String?) -> Bool {
        guard request == id else { return false }
        guard focus == nil else {
            request = nil
            return false
        }
        return true
    }

    /// A moment after a try: the focus held (or the user has put it elsewhere), so the request is over.
    mutating func settle(focus: String?) {
        if focus != nil { request = nil }
    }

    /// A keyboard came up (for the slot, or for a field outside the Previous / Next chain: Other results, the
    /// quick-add bar), the user switched between the figures and the table, or the page went away.
    mutating func end() { request = nil }
}

/// The Labs group: the figures with their slots (or the table, with List on or at an accessibility text size), the
/// Drawn row and the Other results field.
struct PreopLabsFigures: View {
    @Environment(PatientStore.self) private var patient
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The List toggle, remembered on this phone (screenshot runs pass -ps.labs.list 1).
    @AppStorage(PreopLabsFigures.listKey) private var listPref = false
    /// The page's Previous / Next chain, by field id.
    var chain: (String) -> PatientFieldChain
    /// The tab card's slot request, while the page still works on it.
    @State private var slotAttempt = LabSlotFocusAttempt()

    static let listKey = "ps.labs.list"

    private var r: PatientRecord { patient.record }
    /// The accessibility sizes always get the table: the figures' slots are fixed-size boxes.
    private var forcedList: Bool { typeSize.isAccessibilitySize }
    /// The toggle, a screenshot run's -ps.labs.list 1, or the accessibility sizes: the same reading as listMode(), so
    /// the Previous / Next order always follows what is on the screen.
    private var list: Bool { listPref || Self.listSeeded() || forcedList }

    /// What the page shows now, for the Previous / Next order worked out outside this view (PatientEditorView's
    /// labFieldOrder): the remembered toggle, a screenshot run's -ps.labs.list 1, or an accessibility text size.
    @MainActor static func listMode() -> Bool {
        UserDefaults.standard.bool(forKey: listKey) || listSeeded()
            || UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory
    }

    /// A screenshot run's -ps.labs.list 1 (debug builds; false otherwise).
    nonisolated static func listSeeded() -> Bool { LaunchSeed.bool(listKey) }

    /// The main labs in the order Next walks them: the figures' slots, or the table's rows (the main table, then the
    /// hepatic enzymes, which the table lists after it).
    @MainActor static func mainFieldOrder() -> [String] { mainFieldOrder(list: listMode()) }

    /// The same, for the table (list) or the figures: the keys whose fields the Labs group shows.
    nonisolated static func mainFieldOrder(list: Bool) -> [String] {
        list ? PatientLabs.entryOrder(.main).map(\.key) + PatientLabs.tests(.liver).map(\.key) : PatientLabs.slotOrder
    }

    /// The field ids the group shows, as the chain names them ("main.k").
    nonisolated static func mainFieldIDs(list: Bool) -> [String] { mainFieldOrder(list: list).map { "main." + $0 } }

    /// Where the page scrolls to for a field the tab card asked for ("main.k"): the field's own slot or row.
    nonisolated static func revealID(_ field: String) -> String { "labfield." + field }

    /// Where the requested field is put before its keyboard comes up: a third of the way down the page, which is clear
    /// of the number pad and its Previous / Next / Done bar on every phone. (Run 491: with the table on, the keyboard
    /// opened on Potassium with the row left under that bar.)
    nonisolated static var revealAnchor: UnitPoint { UnitPoint(x: 0.5, y: 1.0 / 3) }

    var body: some View {
        let sum = PatientLabs.summary(r)
        // The reader is for the tab card's slot request only: it scrolls the page this group sits in.
        ScrollViewReader { proxy in
            // The ⓘ explains the Hb ↔ Hct estimate, only while one is shown.
            PatientGroup(title: "Labs", note: sum.estimate == nil ? nil : PatientLabs.estimateCaption) {
                if list {
                    rows(PatientLabs.entryOrder(.main), estimate: sum.estimate)
                    Hairline().padding(.leading, 14)
                    rows(PatientLabs.tests(.liver))
                } else {
                    figures(sum)
                }
                Hairline().padding(.leading, 14)
                LabsDrawnRow().id("labsdrawn")
                PatientTextField(label: "Other results", prompt: "Endocrine, rheumatological, lipids, etc.",
                                 text: Binding(get: { patient.record.labNotes }, set: { v in patient.update { $0.labNotes = v } }))
            }
            // Opened from a slot on the tab card. On the group, not on the figures: the table's rows carry the same
            // field ids, and the request is taken whichever of the two the page shows, so none is left for a later visit.
            .onAppear { focusRequestedSlot(proxy) }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                if slotAttempt.isLive { slotAttempt.end() }
            }
            .onDisappear { slotAttempt.end() }
        }
        if !forcedList {
            HStack {
                Spacer(minLength: 0)
                Button {
                    Haptics.light()
                    slotAttempt.end()
                    withAnimation(.snappy) { listPref.toggle() }
                } label: {
                    Label(list ? "Figures" : "List", systemImage: list ? "square.grid.3x1.below.line.grid.1x2" : "list.bullet")
                        .font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.action)
                }
                .buttonStyle(.plain)
                .accessibilityHint(list ? "Shows the labs as fishbone figures" : "Shows the labs as a table")
            }
            .padding(.horizontal, 4).padding(.top, -8)
        }
    }

    private func value(_ key: String) -> Binding<Double?> {
        Binding(get: { patient.record.labs[key] }, set: { v in patient.update { $0.labs[key] = v } })
    }

    @ViewBuilder private func rows(_ tests: [LabTest], estimate: LabValue? = nil) -> some View {
        ForEach(Array(tests.enumerated()), id: \.element.id) { i, t in
            LabFieldRow(test: t, sex: r.sex, troponin99: r.labs["troponin99"], value: value(t.key), chain: chain("main." + t.key),
                        estimate: estimate?.key == t.key ? estimate : nil)
                .id(Self.revealID("main." + t.key))
            if i < tests.count - 1 { Hairline().padding(.leading, 14) }
        }
    }

    @ViewBuilder private func slot(_ key: String, _ sum: LabSummary) -> some View {
        if let t = PatientLabs.test(key) {
            LabSlot(test: t, sex: r.sex, troponin99: r.labs["troponin99"], value: value(key), chain: chain("main." + key),
                    estimate: sum.estimate?.key == key ? sum.estimate : nil)
                .id(Self.revealID("main." + key))
        }
    }

    @ViewBuilder private func figures(_ sum: LabSummary) -> some View {
        let g = FishboneGeometry.page
        VStack(alignment: .leading, spacing: 18) {
            FishboneBMP(g: g) { slot($0, sum) }
            FishboneCBC(g: g) { slot($0, sum) }
            FishboneCoags(g: g, fibrinogen: true) { slot($0, sum) }
            HStack(alignment: .top, spacing: 22) {
                FishboneHepatic(g: g) { slot($0, sum) }
                VStack(spacing: 8) {
                    ForEach(PatientLabs.mineralOrder, id: \.self) { slot($0, sum) }
                }
            }
            // Screenshot runs: -ps.patient.scroll labs-hepatic.
            .id("labs-hepatic")
            HStack(spacing: 22) {
                ForEach(PatientLabs.otherSlotOrder, id: \.self) { slot($0, sum) }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The keyboard goes to the slot the tab card asked for once the page has settled, and again a little later in case
    /// the push dropped the first; never once the focus has been on a field or a keyboard has come up
    /// (LabSlotFocusAttempt), so it is not pulled back after Done or from a field the user has tapped. The page is
    /// scrolled to the field first, and only while the request is still live, so the page never moves under a user who
    /// has started typing or has put the keyboard away.
    private func focusRequestedSlot(_ proxy: ScrollViewProxy) {
        var attempt = LabSlotFocusAttempt()
        attempt.begin(LabSlotFocusRequest.take(), fields: Self.mainFieldIDs(list: list))
        slotAttempt = attempt
        guard let id = attempt.request else { return }
        let reveal = { proxy.scrollTo(Self.revealID(id), anchor: Self.revealAnchor) }
        // As the page comes in, then with each try: a field already there is not moved again.
        DispatchQueue.main.async { if slotAttempt.request == id { reveal() } }
        for delay in LabSlotFocusAttempt.tries {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let c = chain(id)
                guard slotAttempt.shouldFocus(id, focus: c.focus.wrappedValue) else { return }
                reveal()
                c.focusHere()
                DispatchQueue.main.asyncAfter(deadline: .now() + LabSlotFocusAttempt.settleTime) {
                    slotAttempt.settle(focus: chain(id).focus.wrappedValue)
                }
            }
        }
        #if DEBUG
        // A screenshot run's -ps.labs.slot only (nobody is typing): again from scratch, in case a slow launch's push
        // dropped the keyboard while the focus still reads as set (as PatientEditorView does for -ps.patient.focus).
        if LabSlotFocusRequest.launchRequest() == id {
            for delay in [4.5, 6.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    let c = chain(id)
                    c.focus.wrappedValue = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { c.focusHere() }
                }
            }
        }
        #endif
    }
}

/// One slot of a figure: the value in 15-pt mono in a PS.surface2 box, its short name beneath, the catalog's range as a
/// faint hint while empty (PatientLabs.slotHint), a 44-pt hit area. Abnormal values bold red with L or H; the hemoglobin
/// or hematocrit estimated from the other shows in italic with "~" and "est." under it, never saved. Focus comes from
/// the page's chain (Previous / Next) or the slot's own. VoiceOver reads "Sodium, 138, range 136 to 145".
struct LabSlot: View {
    var test: LabTest
    var sex: PatientSex?
    var troponin99: Double? = nil
    @Binding var value: Double?
    var chain: PatientFieldChain? = nil
    var estimate: LabValue? = nil
    var g: FishboneGeometry = .page
    /// False for a value the catalog's range does not apply to (an arterial range on a venous gas, 1.12): never flagged,
    /// no range hint.
    var ranged = true
    @State private var text = ""
    @FocusState private var focused: Bool

    private var flag: LabFlag { ranged ? (value.map { PatientLabs.flag(test.key, $0, sex: sex, troponin99: troponin99) } ?? .normal) : .normal }
    private var isFocused: Bool { chain.map { $0.focus.wrappedValue == $0.id } ?? focused }
    private var hint: String? { ranged ? PatientLabs.slotHint(test.key, sex: sex) : nil }

    /// "Sodium, 138, range 136 to 145"; "Hemoglobin, empty, range 12 to 16"; "Hematocrit, estimated 38".
    static func accessibilityText(_ test: LabTest, value: Double?, sex: PatientSex?, flag: LabFlag = .normal, estimate: LabValue? = nil) -> String {
        var parts = [test.label]
        if let v = value {
            parts.append(test.format(v) + (flag.isAbnormal ? (flag == .low ? ", low" : ", high") : ""))
        } else if let e = estimate {
            parts.append("estimated " + e.text)
        } else {
            parts.append("empty")
        }
        if let range = test.rangeText(for: sex) {
            parts.append("range " + range.replacingOccurrences(of: "–", with: " to ") + (test.unit.isEmpty ? "" : " " + test.unit))
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                if text.isEmpty && !isFocused {
                    if let e = estimate {
                        Text("~" + e.text).font(PS.sys(size: 13, weight: .semibold, design: .monospaced)).italic().foregroundStyle(PS.fg3)
                    } else if let hint {
                        Text(hint).font(PS.sys(size: 9.5)).foregroundStyle(PS.fg3).lineLimit(1).minimumScaleFactor(0.75).padding(.horizontal, 3)
                    } else {
                        Text("—").font(PS.sys(size: 13, design: .monospaced)).foregroundStyle(PS.fg3)
                    }
                }
                HStack(spacing: 1) {
                    // 1.12: an out-of-range value is bold red with no H or L beside it (its accessibility label says low or high).
                    TextField("", text: $text)
                        .modifier(PatientFieldFocus(chain: chain, local: $focused))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .font(PS.sys(size: 15, weight: flag.isAbnormal ? .bold : .semibold, design: .monospaced))
                        .foregroundStyle(flag.isAbnormal ? PS.red : PS.fg)
                        .accessibilityLabel(Self.accessibilityText(test, value: value, sex: sex, flag: flag, estimate: value == nil ? estimate : nil))
                }
                .padding(.horizontal, 3)
            }
            .frame(width: g.cellWidth, height: g.boxHeight)
            .background(PS.surface2, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(isFocused ? PS.action : Color.clear, lineWidth: 1.5))
            Text(value == nil && estimate != nil ? test.short + " est." : test.short)
                .font(PS.sys(size: 9.5)).foregroundStyle(PS.fg3).lineLimit(1).minimumScaleFactor(0.8)
                .accessibilityHidden(true)
        }
        .frame(width: g.cellWidth, height: g.cellHeight)
        .contentShape(Rectangle())
        .onTapGesture { if let chain { chain.focusHere() } else { focused = true } }
        .onAppear { text = value.map { test.format($0) } ?? "" }
        // A change from elsewhere (Undo, quick add): show it, unless the text being typed already reads as it.
        .onChange(of: text) { _, t in
            let v = Double(t.replacingOccurrences(of: ",", with: "."))
            if v != value { value = v }
        }
        .onChange(of: value) { _, v in
            if Double(text.replacingOccurrences(of: ",", with: ".")) != v { text = v.map { test.format($0) } ?? "" }
        }
    }
}

// MARK: Type & screen: when it expires

/// "+ Expires" on the Type & screen group once it is Sent or Resulted (1.12, Ben: "add expiration day and time option to type
/// and screen"). It opens a date and time picker in place and collapses to "Expires 11/14/26 23:59 · Change" with a way to
/// clear it, the way the intraoperative lab set's "Drawn 06:30 · Change" does (LabsDrawnRow). Entered by hand: the validity
/// period is the blood bank's, so nothing here is calculated from the draw time or any rule. Once the time has passed it reads
/// "Expired 11/14/26 23:59" in red; nothing else happens (no notification, no countdown).
struct TypeScreenExpiresRow: View {
    @Environment(PatientStore.self) private var patient
    @State private var editing = false
    @State private var draft = Date()

    static let fontSize: CGFloat = 12.5

    private var ts: PatientTypeScreen { patient.record.typeScreen }

    var body: some View {
        if ts.effectiveStatus == .sent || ts.effectiveStatus == .resulted {
            VStack(alignment: .leading, spacing: 6) {
                if let e = ts.expires {
                    let expired = ts.isExpired()
                    HStack(spacing: 8) {
                        Image(systemName: "clock").font(PS.sys(size: Self.fontSize - 1, weight: .semibold)).foregroundStyle(expired ? PS.red : PS.fg3)
                            .accessibilityHidden(true)
                        Text((expired ? "Expired " : "Expires ") + PatientSummary.time(e))
                            .font(PS.sys(size: Self.fontSize, weight: expired ? .semibold : .regular)).foregroundStyle(expired ? PS.red : PS.fg2)
                        Button { withAnimation(.snappy) { editing.toggle() } } label: {
                            Text(editing ? "Done" : "Change").font(PS.sys(size: Self.fontSize, weight: .semibold)).foregroundStyle(PS.action)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(editing ? "Done" : "Change when the type and screen expires")
                        Spacer(minLength: 6)
                        Button { editing = false; patient.update(discrete: true) { $0.typeScreen.expires = nil } } label: {
                            Image(systemName: "xmark.circle.fill").font(PS.sys(size: Self.fontSize + 1)).foregroundStyle(PS.fg3)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear when the type and screen expires")
                    }
                    if editing {
                        DatePicker("Type and screen expires", selection: Binding(get: { e }, set: { v in patient.update { $0.typeScreen.expires = v } }),
                                   displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                    }
                } else if editing {
                    DatePicker("Type and screen expires", selection: $draft, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                    HStack(spacing: 14) {
                        Button { patient.update(discrete: true) { $0.typeScreen.expires = draft }; withAnimation(.snappy) { editing = false } } label: {
                            Text("Set").font(PS.sys(size: Self.fontSize, weight: .semibold)).foregroundStyle(PS.action)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Set when the type and screen expires")
                        Button { withAnimation(.snappy) { editing = false } } label: {
                            Text("Cancel").font(PS.sys(size: Self.fontSize)).foregroundStyle(PS.fg2)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    LabsQuietLink(title: "Expires") { draft = Date(); withAnimation(.snappy) { editing = true } }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 6)
        }
    }
}

/// A quiet "+ Name" link (P1-7, the add look that opens in place): "+" in the action colour, the name in PS.fg2.
struct LabsQuietLink: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            // The same drawing as the other quiet links (QuietLinkRow, PreopQuietLink): one look for "opens in place".
            HStack(spacing: 8) {
                Image(systemName: "plus").font(PS.sys(size: 11, weight: .bold)).foregroundStyle(PS.action).frame(width: 14)
                Text(title).font(PS.sys(size: 13.5, weight: .semibold)).foregroundStyle(PS.fg2)
            }
            .padding(.horizontal, 4).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add " + title.lowercased())
    }
}

// MARK: - The fishbone geometry the page, the tab card and the briefs share

/// One geometry for the figures: a cell's width, its total height (the value and its name) and the value box's height.
/// `page` is the input slot (60 × 44 with a 30-pt box, a 44-pt hit area); `small` the brief's and the tab card's
/// display cell (40 × 30).
struct FishboneGeometry {
    var cellWidth: CGFloat
    var cellHeight: CGFloat
    var boxHeight: CGFloat

    static let page = FishboneGeometry(cellWidth: 60, cellHeight: 44, boxHeight: 30)
    static let small = FishboneGeometry(cellWidth: 40, cellHeight: 30, boxHeight: 30)

    var wedgeSize: CGSize { CGSize(width: 12, height: cellHeight - 4) }
    var ruleHeight: CGFloat { cellHeight - 6 }
}

/// A "<" or ">" for the fishbone: a wedge whose point is on the left or the right.
struct FishboneWedge: Shape {
    var pointsLeft: Bool
    func path(in rect: CGRect) -> Path {
        var p = Path()
        if pointsLeft {
            p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        } else {
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        return p
    }
}

/// A "∨" under the hepatic figure: the two columns meet at the bilirubin's point.
struct FishboneWedgeDown: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return p
    }
}

/// The "/" between the blood gas's values (pH / PaCO₂ / PaO₂ / HCO₃).
struct FishboneSlash: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return p
    }
}

/// The rules and wedges, in the brief's tokens: PS.line2 rules, PS.fg3 bones.
enum FishboneBones {
    static func vRule(_ g: FishboneGeometry) -> some View { Rectangle().fill(PS.line2).frame(width: 1, height: g.ruleHeight) }
    static func hRule(_ width: CGFloat) -> some View { Rectangle().fill(PS.line2).frame(width: width, height: 1) }
    static func wedge(_ g: FishboneGeometry, pointsLeft: Bool) -> some View {
        FishboneWedge(pointsLeft: pointsLeft).stroke(PS.fg3, lineWidth: 1).frame(width: g.wedgeSize.width, height: g.wedgeSize.height)
    }
}

/// The BMP: Na | Cl | BUN over K | HCO₃ | Cr, the glucose at the point.
struct FishboneBMP<Cell: View>: View {
    var g: FishboneGeometry
    @ViewBuilder var cell: (String) -> Cell

    var body: some View {
        HStack(spacing: 3) {
            VStack(spacing: 0) {
                HStack(spacing: 0) { cell("na"); FishboneBones.vRule(g); cell("cl"); FishboneBones.vRule(g); cell("bun") }
                FishboneBones.hRule(g.cellWidth * 3 + 2)
                HStack(spacing: 0) { cell("k"); FishboneBones.vRule(g); cell("hco3"); FishboneBones.vRule(g); cell("cr") }
            }
            FishboneBones.wedge(g, pointsLeft: false)
            cell("glucose")
        }
    }
}

/// The CBC: WBC < Hb over Hct > Plt.
struct FishboneCBC<Cell: View>: View {
    var g: FishboneGeometry
    @ViewBuilder var cell: (String) -> Cell

    var body: some View {
        HStack(spacing: 0) {
            cell("wbc")
            FishboneBones.wedge(g, pointsLeft: true)
            VStack(spacing: 0) {
                cell("hb")
                FishboneBones.hRule(g.cellWidth)
                cell("hct")
            }
            FishboneBones.wedge(g, pointsLeft: false)
            cell("plt")
        }
    }
}

/// Coagulation, as Ben drew it: PT over PTT, the INR at the point; the fibrinogen beside it when asked for.
struct FishboneCoags<Cell: View>: View {
    var g: FishboneGeometry
    var fibrinogen: Bool
    @ViewBuilder var cell: (String) -> Cell

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                cell("pt")
                FishboneBones.hRule(g.cellWidth)
                cell("ptt")
            }
            FishboneBones.wedge(g, pointsLeft: false)
            cell("inr")
            if fibrinogen {
                Spacer().frame(width: 10)
                FishboneBones.vRule(g)
                Spacer().frame(width: 10)
                cell("fibrinogen")
            }
        }
    }
}

/// The hepatic figure: Ca | AST, protein | ALT, albumin | alk phos, the bilirubin at the point below.
struct FishboneHepatic<Cell: View>: View {
    var g: FishboneGeometry
    @ViewBuilder var cell: (String) -> Cell

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) { cell("ca"); FishboneBones.vRule(g); cell("ast") }
            FishboneBones.hRule(g.cellWidth * 2 + 1)
            HStack(spacing: 0) { cell("protein"); FishboneBones.vRule(g); cell("alt") }
            FishboneBones.hRule(g.cellWidth * 2 + 1)
            HStack(spacing: 0) { cell("albumin"); FishboneBones.vRule(g); cell("alp") }
            FishboneWedgeDown().stroke(PS.fg3, lineWidth: 1).frame(width: g.cellWidth * 2 + 1, height: 10).padding(.vertical, 2)
            cell("tbili")
        }
    }
}

/// The blood gas: pH / PaCO₂ / PaO₂ / HCO₃.
struct FishboneABG<Cell: View>: View {
    var g: FishboneGeometry
    @ViewBuilder var cell: (String) -> Cell

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(IntraopLabs.abgSlash.enumerated()), id: \.element) { i, key in
                if i > 0 { FishboneSlash().stroke(PS.fg3, lineWidth: 1).frame(width: 10, height: g.cellHeight - 10) }
                cell(key)
            }
        }
    }
}

// MARK: - The table's row

/// One lab: label, the value typed, the unit and the range; out of range shows bold red with L or H.
struct LabFieldRow: View {
    var test: LabTest
    var sex: PatientSex?
    var troponin99: Double?
    @Binding var value: Double?
    /// Its place in the page's Previous / Next order.
    var chain: PatientFieldChain? = nil
    /// Hemoglobin or hematocrit estimated from the other, shown while this one is empty (never saved).
    var estimate: LabValue? = nil
    /// False for a value the catalog's range does not apply to (an arterial range on a venous gas, 1.12): never flagged.
    /// The range line follows the `test` given (a venous gas passes a copy without a range).
    var ranged = true
    @State private var text = ""
    @FocusState private var focused: Bool

    private var flag: LabFlag { ranged ? (value.map { PatientLabs.flag(test.key, $0, sex: sex, troponin99: troponin99) } ?? .normal) : .normal }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                // One line, shrunk a little where a narrow row needs it: "Hemoglobin" broke mid-word at 375 pt under a
                // system page's item indent (review 1.10).
                Text(test.label).font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg)
                    .lineLimit(1).minimumScaleFactor(0.75)
                if let range = test.rangeText(for: sex) {
                    Text(range + (test.unit.isEmpty ? "" : " " + test.unit)).font(PS.sys(size: 11)).foregroundStyle(PS.fg3)
                }
                if value == nil, let e = estimate {
                    Text("Est. ~" + e.text + (e.key == "hct" ? " (3 × Hb)" : " (Hct ÷ 3)"))
                        .font(PS.sys(size: 11, weight: .medium)).italic().foregroundStyle(PS.fg3)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 6)
            // 1.12: an out-of-range value is bold red with no H or L beside it.
            TextField(value == nil ? (estimate.map { "~" + $0.text } ?? "—") : "—", text: $text)
                .modifier(PatientFieldFocus(chain: chain, local: $focused))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(PS.sys(size: 16, weight: flag.isAbnormal ? .bold : .medium, design: .monospaced))
                .foregroundStyle(flag.isAbnormal ? PS.red : PS.fg)
                // VoiceOver cannot see that the value is red: it says "low" or "high" (1.12).
                .accessibilityLabel(flag.isAbnormal ? test.label + ", " + flag.word : test.label)
                // Gives up a little width to the label on a narrow row; 84 wherever there is room.
                .frame(minWidth: 64, maxWidth: 84)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(PS.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .onChange(of: text) { _, t in
                    let v = Double(t.replacingOccurrences(of: ",", with: "."))
                    if v != value { value = v }
                }
            Text(test.unit).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).frame(width: 54, alignment: .leading).lineLimit(2).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { if let chain { chain.focusHere() } else { focused = true } }
        .onAppear { text = value.map { test.format($0) } ?? "" }
        // A change from elsewhere (Undo, a preset): show it, unless the text being typed already reads as it ("1."
        // while typing 1.5 stays as typed).
        .onChange(of: value) { _, v in
            if Double(text.replacingOccurrences(of: ",", with: ".")) != v { text = v.map { test.format($0) } ?? "" }
        }
    }
}

/// The hCG as typed (1.12): a number is saved as the lab `hcg`, anything else ("<5") stays as typed
/// (PatientMoreLabs.setHCG). The text is kept here while it is typed, so "5." is not rewritten to "5" under the cursor.
struct HCGField: View {
    @Environment(PatientStore.self) private var patient
    @State private var text = ""

    private var stored: String { PatientMoreLabs.hcgField(patient.record) }

    private func number(_ s: String) -> Double? { Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) }

    var body: some View {
        HStack(spacing: 10) {
            Text("hCG").font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg2)
            TextField("e.g. 12 mIU/mL, or <5", text: $text)
                .font(PS.sys(size: 15))
                .foregroundStyle(PS.fg)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(PS.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityLabel("hCG value")
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .onAppear { text = stored }
        .onChange(of: text) { _, t in
            if t != stored { patient.update { PatientMoreLabs.setHCG(t, in: &$0) } }
        }
        // A change from elsewhere (Undo): show it, unless the text being typed already reads as it.
        .onChange(of: stored) { _, s in
            if s != text, !(number(text) != nil && number(text) == number(s)) { text = s }
        }
    }
}

/// A one-line text entry inside a lab group ("Antibody: anti-K").
struct LabInlineText: View {
    var label: String
    var prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Text(label).font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg2)
            TextField(prompt, text: $text)
                .font(PS.sys(size: 15))
                .foregroundStyle(PS.fg)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(PS.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }
}
