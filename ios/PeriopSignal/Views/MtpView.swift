import SwiftUI

// MARK: - Massive transfusion: tally, ratio, calcium and lab prompts
//
// Reference → Emergency. One tap per product; the ratio against 1:1:1, the calcium prompt (with the first citrated unit,
// then every 4), the lab prompt (every 4 RBC or 30 min), fibrinogen, 4F-PCC and TXA are read from the tally and
// reference.json "mtp" (MtpCalc). The tally is kept on this phone until End, with no patient details; it can also add
// the products to the open My Patient case. A draft until signed off in the review doc.

/// The running tally, kept on this phone between launches until End (no patient details).
enum MtpSaved {
    private static let key = "ps.mtp.v1"

    static func load() -> MtpState? {
        #if DEBUG
        if PatientTips.launch == .screenshot { return nil }
        #endif
        guard let d = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(MtpState.self, from: d)
    }

    static func save(_ s: MtpState?) {
        if let s, let d = try? JSONEncoder().encode(s) { UserDefaults.standard.set(d, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }
}

struct MtpView: View {
    var onOpen: (URL) -> Void
    @Environment(ReferenceStore.self) private var refs
    @Environment(PatientStore.self) private var patient
    @State private var state: MtpState? = MtpSaved.load()
    @State private var confirmEnd = false
    @State private var tableOpen = false
    @State private var pccWeight: Double?

    var body: some View {
        Group {
            if let d = refs.mtp {
                ToolScroll {
                    TimelineView(.periodic(from: .now, by: 10)) { ctx in
                        VStack(alignment: .leading, spacing: 18) {
                            ToolHeader(eyebrow: "Emergency", title: "Massive Transfusion",
                                       summary: "Tap each product as it goes up: the ratio, calcium and labs follow.", infoSummary: false, tint: PS.accent)
                            DraftBanner(section: "mtp")
                            if (patient.record.ageYears ?? 18) < 18 {
                                Label("All defaults are for adults: children are at high risk of low calcium and magnesium and high potassium.", systemImage: "exclamationmark.triangle.fill")
                                    .font(PS.sys(size: 13.5, weight: .semibold)).foregroundStyle(PS.red).fixedSize(horizontal: false, vertical: true)
                            }
                            if let s = state {
                                running(s, d, now: ctx.date)
                            } else {
                                Button {
                                    Haptics.success()
                                    withAnimation(.snappy) { state = MtpState(started: Date(), data: d) }
                                } label: { Label("Start MTP", systemImage: "drop.fill").frame(maxWidth: .infinity) }
                                .buttonStyle(BigButtonStyle(prominent: true))
                            }
                            footer(d)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                        .padding(.bottom, 30)
                    }
                }
            } else {
                ContentUnavailableView("Not available offline yet", systemImage: "wifi.slash", description: Text("This tool arrives with the next refresh."))
            }
        }
        .background(FeedBackground())
        .scrollContentBackground(.hidden)
        .navigationTitle("MTP")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("End") { confirmEnd = true }.disabled(state == nil)
            }
        }
        .confirmationDialog("End this MTP?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End and clear the tally", role: .destructive) { withAnimation(.snappy) { state = nil } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The tally is removed from this phone. Anything added to the My Patient case stays there.")
        }
        .sheet(isPresented: $tableOpen) {
            if let d = refs.mtp { MtpTableSheet(data: d, onOpen: onOpen) }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        #if DEBUG
        // Screenshot runs: -ps.mtp.seed 1 starts a made-up tally once the content has loaded.
        .task(id: refs.mtp != nil) {
            if LaunchSeed.bool("ps.mtp.seed"), state == nil, let d = refs.mtp { state = MtpDemo.state(d) }
        }
        #endif
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: state) { _, s in MtpSaved.save(s) }
    }

    // MARK: Running

    /// The newest measured iCa: typed here, or the newest intraoperative ABG in the open My Patient case.
    private func measuredIca(_ s: MtpState) -> MtpCalc.IcaReading? {
        MtpCalc.latestIca(s, caseLabs: patient.record.intraopLabs)
    }

    private func calcium(_ s: MtpState, _ d: MtpData) -> MtpCalc.CalciumStatus {
        MtpCalc.calcium(s, data: d, measured: measuredIca(s))
    }

    @ViewBuilder private func running(_ s: MtpState, _ d: MtpData, now: Date) -> some View {
        let ca = calcium(s, d)
        summary(s, d, now: now)
        if ca.due || ca.action == .check { calciumDue(s, d, ca) }
        tally(s, d)
        if !ca.due && ca.action != .check { calciumLine(d, ca) }
        labsCard(s, d, now: now)
        txaCard(s, d, now: now)
        settings(s, d)
        logCard(s, d)
    }

    private func summary(_ s: MtpState, _ d: MtpData, now: Date) -> some View {
        let ratio = MtpCalc.ratio(s, data: d)
        return ToolCard(tint: PS.accent) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: "MTP since \(ClockText.time(s.started))", color: PS.accent)
                Spacer()
                Text(Self.elapsed(from: s.started, to: now)).font(PS.mono(size: 13, weight: .semibold)).foregroundStyle(PS.fg2)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(ratio.text ?? "—").font(PS.serif(size: 30, weight: .semibold)).foregroundStyle(PS.fg)
                Text("RBC : plasma : platelets · target \(d.ratio.target)").font(PS.sys(size: 13)).foregroundStyle(PS.fg2)
            }
            Text("RBC \(MtpCalc.one(ratio.rbc)) · plasma \(MtpCalc.one(ratio.plasma)) · platelets \(MtpCalc.one(MtpCalc.total(s, "platelets"))) dose\(MtpCalc.total(s, "platelets") == 1 ? "" : "s") (\(MtpCalc.one(ratio.plateletUnits)) units)")
                .font(PS.sys(size: 13.5)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
            let cryo = MtpCalc.total(s, "cryo"), wb = MtpCalc.total(s, "wholeBlood")
            if cryo > 0 || wb > 0 {
                Text([cryo > 0 ? "cryo \(MtpCalc.one(cryo)) pool\(cryo == 1 ? "" : "s") (≥\(MtpCalc.grams(MtpCalc.cryoFibrinogenGrams(s, data: d))) g fibrinogen)" : nil,
                      wb > 0 ? "whole blood \(MtpCalc.one(wb)) (in the ratio as RBC + plasma)" : nil].compactMap { $0 }.joined(separator: " · "))
                    .font(PS.sys(size: 13.5)).foregroundStyle(PS.fg2)
            }
        }
    }

    // MARK: Tally

    private func tally(_ s: MtpState, _ d: MtpData) -> some View {
        let blood = d.products.filter(\.citrated)
        let factors = d.products.filter { !$0.citrated }
        return VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Tap as it goes up · hold to take one back").padding(.leading, 2)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(blood) { p in tallyButton(p, s, big: true) }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(factors) { p in tallyButton(p, s, big: false) }
            }
        }
    }

    private func tallyButton(_ p: MtpData.Product, _ s: MtpState, big: Bool) -> some View {
        let n = MtpCalc.total(s, p.id)
        let step = p.step ?? 1
        return Button { add(p, qty: step) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(p.name).font(PS.sys(size: big ? 15 : 12.5, weight: .semibold)).foregroundStyle(PS.fg).lineLimit(1).minimumScaleFactor(0.8)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(MtpCalc.one(n)).font(big ? PS.serif(size: 30, weight: .semibold) : PS.sys(size: 18, weight: .semibold)).foregroundStyle(PS.fg)
                    Text(p.unit + (n == 1 || ["g", "IU", "mg", "mL"].contains(p.unit) ? "" : "s")).font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
                    Spacer(minLength: 0)
                    Image(systemName: "plus").font(PS.sys(size: big ? 15 : 12, weight: .bold)).foregroundStyle(PS.accent)
                }
            }
            .padding(big ? 14 : 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PS.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(PS.line2, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if n > 0 { Button(role: .destructive) { removeLast(p.id) } label: { Label("Take one back", systemImage: "minus") } }
            if let note = p.note { Text(note) }
        }
        .accessibilityLabel("\(p.name), \(MtpCalc.one(n)) \(p.unit)")
        .accessibilityHint("Adds \(MtpCalc.one(step)) \(p.unit)")
    }

    private func add(_ p: MtpData.Product, qty: Double) {
        Haptics.light()
        guard var s = state else { return }
        var caseID: UUID?
        if s.addToCase, let key = p.caseKey {
            caseID = patient.book.currentID
            patient.update(discrete: true) { $0.fluids[key, default: 0] += qty }
        }
        withAnimation(.snappy) {
            s.add(p.id, qty: qty, at: Date(), caseID: caseID)
            state = s
        }
    }

    private func removeLast(_ product: String) {
        guard var s = state, let e = MtpCalc.last(s, product) else { return }
        remove(e, from: &s)
        withAnimation(.snappy) { state = s }
    }

    /// Removes a tap; one that was also added to the current My Patient case comes off it too.
    private func remove(_ e: MtpEntry, from s: inout MtpState) {
        if let cid = e.caseID, cid == patient.book.currentID, let key = refs.mtp?.product(e.product)?.caseKey {
            patient.update(discrete: true) { r in
                let v = max(0, (r.fluids[key] ?? 0) - e.qty)
                r.fluids[key] = v == 0 ? nil : v
            }
        }
        s.remove(e.id)
    }

    private func log(_ product: String, detail: String? = nil) {
        Haptics.light()
        guard var s = state else { return }
        withAnimation(.snappy) {
            s.add(product, detail: detail, at: Date())
            state = s
        }
    }

    // MARK: Calcium

    private func calciumDue(_ s: MtpState, _ d: MtpData, _ ca: MtpCalc.CalciumStatus) -> some View {
        ToolCard(tint: ca.action == .check ? PS.accent : PS.red) {
            Eyebrow(text: Self.calciumHeading(ca, d), color: ca.action == .check ? PS.accent : PS.red)
            if ca.action == .check {
                Text("Send an iCa: \(MtpCalc.one(Double(d.calcium.everyUnits))) citrated units since the last one was at target.")
                    .font(PS.serif(size: 19)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(d.calcium.dose).font(PS.serif(size: 19)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
                Text(d.calcium.chloride).font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.accent)
                HStack(spacing: 10) {
                    Button("CaCl₂ given") { log("calcium", detail: "chloride") }.buttonStyle(CapsuleButtonStyle(prominent: true))
                    Button("Gluconate given") { log("calcium", detail: "gluconate") }.buttonStyle(CapsuleButtonStyle(prominent: false))
                }
            }
            icaRow(s, d)
        }
    }

    /// "iCa 0.85 at 14:02: urgent", "Calcium with the first unit", "Calcium: 4 units since the last dose".
    static func calciumHeading(_ ca: MtpCalc.CalciumStatus, _ d: MtpData) -> String {
        if let r = ca.reading {
            let at = "iCa \(String(format: "%.2f", r.value)) at \(ClockText.time(r.time))" + (r.fromCase ? " (My Patient)" : "")
            switch ca.action {
            case .urgent: return at + ": urgent"
            case .give: return at + ": give calcium"
            default: return at + ": at target"
            }
        }
        return ca.firstDose ? "Calcium with the first unit" : "Calcium: \(MtpCalc.one(ca.since)) units since the last dose"
    }

    private func calciumLine(_ d: MtpData, _ ca: MtpCalc.CalciumStatus) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "drop.triangle").foregroundStyle(PS.fg3)
            Text(ca.reading != nil
                 ? Self.calciumHeading(ca, d) + "; send another after \(MtpCalc.one(ca.untilNext)) more unit\(ca.untilNext == 1 ? "" : "s")."
                 : (ca.firstDose ? "Calcium comes with the first citrated unit." : "Calcium after \(MtpCalc.one(ca.untilNext)) more unit\(ca.untilNext == 1 ? "" : "s")."))
                .font(PS.sys(size: 13.5)).foregroundStyle(PS.fg2)
            Spacer()
            Button("Given") { log("calcium") }.font(PS.sys(size: 13, weight: .semibold))
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder private func icaRow(_ s: MtpState, _ d: MtpData) -> some View {
        HStack(spacing: 10) {
            Text("iCa").font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.fg)
            UnitField(prompt: "mmol/L", unit: "mmol/L", value: Binding(get: { state?.ica }, set: { v in state?.ica = v; state?.icaTime = v == nil ? nil : Date() }), width: 80)
            Spacer()
        }
        if let r = measuredIca(s), r.fromCase {
            Text("Newest from My Patient's ABG: \(String(format: "%.2f", r.value)) at \(ClockText.time(r.time))").font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2)
        }
        switch MtpCalc.ica(measuredIca(s)?.value, data: d) {
        case .urgent?: Text("Below \(MtpCalc.one(d.calcium.icaUrgent)): urgent.").font(PS.sys(size: 13.5, weight: .bold)).foregroundStyle(PS.red)
        case .give?: Text("Below \(MtpCalc.one(d.calcium.icaGive)): give calcium.").font(PS.sys(size: 13.5, weight: .semibold)).foregroundStyle(PS.accent)
        default: EmptyView()
        }
    }

    private func binding(_ kp: WritableKeyPath<MtpState, Double?>) -> Binding<Double?> {
        Binding(get: { state?[keyPath: kp] }, set: { v in state?[keyPath: kp] = v })
    }

    // MARK: Labs

    private func labsCard(_ s: MtpState, _ d: MtpData, now: Date) -> some View {
        let l = MtpCalc.labs(s, data: d, now: now)
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Labs", info: d.labs.text + " " + d.fibrinogen.note)
            ToolCard(tint: l.due ? PS.accent : nil) {
                HStack {
                    Text(l.due ? "Send labs" : "Next labs \(ClockText.relative(MtpCalc.labsDueAt(s, data: d), now: now))")
                        .font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(l.due ? PS.accent : PS.fg)
                    Spacer()
                    Button("Sent") { log("labs") }.buttonStyle(CapsuleButtonStyle(prominent: l.due))
                }
                Text("\(MtpCalc.one(l.rbcSince)) RBC since the last set").font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3)
                if !calcium(s, d).due && calcium(s, d).action != .check { icaRow(s, d) }
                labField("Fibrinogen (Clauss)", "g/L", \.fibrinogen)
                labField("FIBTEM CA5", "mm", \.fibtem)
                labField("TEG FF MA", "mm", \.tegFF)
                if MtpCalc.fibrinogenLow(s, data: d) {
                    Text(d.fibrinogen.text + " At least \(MtpCalc.one(MtpCalc.cryoUnits(forGrams: 3, data: d))) single-donor units for 3 g (\(MtpCalc.one((MtpCalc.cryoUnits(forGrams: 3, data: d) / s.cryoPool).rounded(.up))) of your \(MtpCalc.one(s.cryoPool))-unit pools).")
                        .font(PS.sys(size: 13.5, weight: .semibold)).foregroundStyle(PS.accent).fixedSize(horizontal: false, vertical: true)
                }
                labField("Potassium", "mmol/L", \.potassium)
                if MtpCalc.potassiumHigh(s, data: d) {
                    Text("K⁺ above \(MtpCalc.one(d.labs.kHigh)).").font(PS.sys(size: 13.5, weight: .semibold)).foregroundStyle(PS.red)
                }
                labField("INR (warfarin reversal)", "", \.inr)
                pccRow(s, d)
            }
        }
    }

    private func labField(_ label: String, _ unit: String, _ kp: WritableKeyPath<MtpState, Double?>) -> some View {
        HStack {
            Text(label).font(PS.sys(size: 14)).foregroundStyle(PS.fg)
            Spacer()
            UnitField(prompt: "—", unit: unit, value: binding(kp), width: 70)
        }
    }

    @ViewBuilder private func pccRow(_ s: MtpState, _ d: MtpData) -> some View {
        if let inr = s.inr, inr >= 2 {
            let w = patient.record.weightKg ?? pccWeight
            if w == nil {
                HStack {
                    Text("Weight for 4F-PCC").font(PS.sys(size: 14)).foregroundStyle(PS.fg)
                    Spacer()
                    UnitField(prompt: "kg", unit: "kg", value: $pccWeight, width: 70)
                }
            }
            if let dose = MtpCalc.pcc(inr: inr, weightKg: w, data: d) {
                Text("4F-PCC \(CaseTimerEngine.grouped(dose.iu)) IU (\(MtpCalc.one(dose.iuPerKg)) IU/kg × \(MtpCalc.one(dose.dosingKg)) kg\(dose.capped ? ", capped at \(MtpCalc.one(d.pcc.capKg)) kg" : ""))")
                    .font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(PS.fg)
                Text(d.pcc.text).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
                Text(d.pcc.boxed).font(PS.sys(size: 12.5, weight: .semibold)).foregroundStyle(PS.accent).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: TXA

    private func txaCard(_ s: MtpState, _ d: MtpData, now: Date) -> some View {
        let ctx = d.txa.contexts.first { $0.id == s.txaContext } ?? d.txa.contexts[0]
        let late = MtpCalc.txaLate(s, data: d, now: now)
        let given = s.entries.filter { $0.product == "txa" }
        return VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "Tranexamic acid").padding(.leading, 2)
            ToolCard {
                ChoiceChips(options: d.txa.contexts.map { (id: $0.id, label: $0.name) }, selected: s.txaContext) { id in
                    state?.txaContext = id
                }
                Text(ctx.text).font(PS.sys(size: 14)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
                if ctx.maxHoursFromInjury != nil {
                    DatePicker("Injury", selection: Binding(get: { s.injury ?? s.started }, set: { state?.injury = $0 }),
                               in: ...Date(), displayedComponents: [.hourAndMinute])
                        .font(PS.sys(size: 14)).tint(PS.accent)
                }
                if late, let msg = ctx.late {
                    Label(msg, systemImage: "exclamationmark.triangle.fill").font(PS.sys(size: 13.5, weight: .semibold)).foregroundStyle(PS.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    if !given.isEmpty {
                        Text("Given " + given.map { ClockText.time($0.time) }.joined(separator: ", ")).font(PS.sys(size: 13)).foregroundStyle(PS.fg2)
                    }
                    Spacer()
                    Button(late ? "Given anyway" : "TXA given") { log("txa", detail: s.txaContext) }
                        .buttonStyle(CapsuleButtonStyle(prominent: !late, color: late ? PS.red : PS.accent))
                }
            }
        }
    }

    // MARK: Settings

    private func settings(_ s: MtpState, _ d: MtpData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Your blood bank", info: d.plateletUnits.note ?? "")
            ToolCard {
                Stepper(value: Binding(get: { s.plateletUnits }, set: { state?.plateletUnits = $0 }), in: d.plateletUnits.min...d.plateletUnits.max, step: 1) {
                    Text("A platelet dose counts as \(MtpCalc.one(s.plateletUnits)) units").font(PS.sys(size: 14)).foregroundStyle(PS.fg)
                }
                Stepper(value: Binding(get: { s.cryoPool }, set: { state?.cryoPool = $0 }), in: d.cryoPool.min...d.cryoPool.max, step: 1) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cryo pool: \(MtpCalc.one(s.cryoPool)) units").font(PS.sys(size: 14)).foregroundStyle(PS.fg)
                        Text("≥\(MtpCalc.grams(s.cryoPool * (d.cryoPool.mgPerUnit ?? 150) / 1000)) g fibrinogen per pool").font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
                    }
                }
                if let n = d.cryoPool.note { InfoCaptionText(text: n, font: PS.sys(size: 12)) }
                Toggle(isOn: Binding(get: { s.addToCase }, set: { state?.addToCase = $0 })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Also add to the My Patient case").font(PS.sys(size: 14)).foregroundStyle(PS.fg)
                        Text("Taps are not verified doses; taking one back takes it off the case too.").font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
                    }
                }
                .tint(PS.accent)
            }
        }
    }

    // MARK: Log

    @ViewBuilder private func logCard(_ s: MtpState, _ d: MtpData) -> some View {
        if !s.entries.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(s.entries.reversed()) { e in
                        HStack {
                            Text("\(ClockText.time(e.time))  \(Self.name(e, d))").font(PS.mono(size: 12, weight: .medium)).foregroundStyle(PS.fg2)
                            Spacer()
                            Button(role: .destructive) {
                                guard var st = state else { return }
                                remove(e, from: &st)
                                withAnimation(.snappy) { state = st }
                            } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).tint(PS.fg3)
                            .accessibilityLabel("Remove " + Self.name(e, d))
                        }
                    }
                }
                .padding(.top, 6)
            } label: {
                Text("Log (\(s.entries.count))").font(PS.sys(size: 13.5, weight: .semibold)).foregroundStyle(PS.fg2)
            }
            .tint(PS.fg3)
        }
    }

    static func name(_ e: MtpEntry, _ d: MtpData) -> String {
        switch e.product {
        case "calcium": return "Calcium" + (e.detail.map { " (\($0))" } ?? "")
        case "txa": return "TXA" + (e.detail.map { " (\($0))" } ?? "")
        case "labs": return "Labs sent"
        default:
            let p = d.product(e.product)
            return "\(p?.name ?? e.product) \(MtpCalc.one(e.qty)) \(p?.unit ?? "")"
        }
    }

    // MARK: Footer

    private func footer(_ d: MtpData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Hairline()
            HStack(spacing: 10) {
                Button { tableOpen = true } label: { Label("Targets & calcium salts", systemImage: "tablecells") }.buttonStyle(GhostButtonStyle())
                if let s = d.sources.first(where: { $0.id == "rossaint2023" }), let url = URL(string: s.url) {
                    Button { onOpen(url) } label: { Label("Guideline ↗", systemImage: "doc.text") }.buttonStyle(GhostButtonStyle())
                }
            }
            EvidenceDisclosure {
                ForEach(d.cautions, id: \.self) { c in
                    Text("• " + c).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                }
                Text(d.calcium.rule + " " + d.calcium.icaNote + " " + d.ratio.note)
                    .font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
                EvidenceLinks(sources: d.sources, onOpen: onOpen)
            }
        }
    }

    static func elapsed(from a: Date, to b: Date) -> String {
        let m = max(0, Int(b.timeIntervalSince(a) / 60))
        return String(format: "%d:%02d", m / 60, m % 60)
    }
}

/// The lab targets and the calcium salts, behind "Targets & calcium salts".
struct MtpTableSheet: View {
    var data: MtpData
    var onOpen: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Eyebrow(text: "Lab targets").padding(.leading, 2)
                    FlagTable(rows: data.targets.map { [$0[0], $0.count > 1 ? $0[1] : "", $0.count > 2 ? $0[2] : ""] })
                    Eyebrow(text: "Calcium salts").padding(.leading, 2)
                    FlagTable(rows: data.calcium.salts.map { [$0[0], $0.dropFirst().joined(separator: " · "), ""] })
                    Text(data.calcium.fastNote).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3)
                    EvidenceLinks(sources: data.sources, onOpen: onOpen)
                }
                .padding(20)
            }
            .background(FeedBackground())
            .navigationTitle("MTP Targets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.large])
    }
}

#if DEBUG
enum MtpDemo {
    /// 25 minutes in: 6 RBC, 5 plasma, 1 platelet dose, 1 cryo pool, one calcium after the first unit.
    static func state(_ d: MtpData, now: Date = Date()) -> MtpState {
        var s = MtpState(started: now.addingTimeInterval(-25 * 60), data: d)
        var t = now.addingTimeInterval(-24 * 60)
        func tap(_ p: String, _ detail: String? = nil) { s.add(p, detail: detail, at: t); t = t.addingTimeInterval(110) }
        tap("prbc"); tap("calcium", "chloride"); tap("plasma"); tap("prbc"); tap("plasma"); tap("prbc"); tap("labs")
        tap("plasma"); tap("prbc"); tap("platelets"); tap("prbc"); tap("plasma"); tap("cryo"); tap("prbc"); tap("plasma")
        s.ica = 1.08
        s.icaTime = now.addingTimeInterval(-4 * 60)
        s.injury = now.addingTimeInterval(-70 * 60)
        return s
    }
}
#endif
