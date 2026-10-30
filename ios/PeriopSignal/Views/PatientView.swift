import SwiftUI

/// My Patient: a short history and physical, the assessment, the airway, the intraoperative course and the plan for
/// one patient, read top to bottom like a preanesthetic note. Each card opens its editor; the tools it prompts open
/// already filled in. Kept on this phone only until Clear (with Undo); Generate Handoff writes it up as text.
struct PatientView: View {
    @Environment(PatientStore.self) private var patient
    @State private var path = NavigationPath()
    @State private var webLink: WebLink?
    @State private var showHandoff = false
    @State private var confirmClear = false
    @State private var handoff = PatientHandoff()

    private var r: PatientRecord { patient.record }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if patient.canUndo { undoBanner }
                        if patient.isEmpty {
                            emptyCard
                        } else {
                            summaryCard
                            jumpBar(proxy)
                        }
                        historyCard.id(PatientEditor.history)
                        assessmentCard.id(PatientEditor.assessment)
                        airwayCard.id(PatientEditor.airway)
                        intraopCard.id(PatientEditor.intraop)
                        planCard.id(PatientEditor.plan)
                        handoffButton
                        Text("Kept on this phone only, with no name or record number, until you clear it. Not backed up or sent anywhere.")
                            .font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineSpacing(1.5)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 2)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
            .background(FeedBackground())
            .scrollContentBackground(.hidden)
            .navigationTitle("My Patient")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if patient.canUndo {
                        Button { withAnimation(.snappy) { patient.undoClear() } } label: { Label("Undo Clear", systemImage: "arrow.uturn.backward") }
                    } else {
                        Button(role: .destructive) { confirmClear = true } label: { Label("Clear Patient", systemImage: "trash") }
                            .disabled(patient.isEmpty)
                    }
                }
            }
            .confirmationDialog("Clear this patient?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear Patient", role: .destructive) { withAnimation(.snappy) { patient.clear() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Everything on this tab is removed from the phone. You can undo it right after.")
            }
            .navigationDestination(for: PatientEditor.self) { e in
                PatientEditorView(editor: e, onOpenRoute: { open($0) })
            }
            .navigationDestination(for: RefRoute.self) { route in
                RefDestination(route: route, push: { path.append($0) }, openURL: { webLink = WebLink(url: $0) }, path: nil, handoff: handoff)
            }
        }
        .environment(handoff)
        .task { await openForScreenshot() }
        .fullScreenCover(item: $webLink) { link in
            SafariView(url: link.url).ignoresSafeArea()
        }
        .sheet(isPresented: $showHandoff) {
            HandoffSheet(full: HandoffWriter.text(r), short: HandoffWriter.shortText(r))
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private func open(_ key: String) {
        if let route = RefRoute(key: key) { path.append(route) }
    }

    /// Screenshot runs: -ps.patient.open history | medications | assessment | airway | intraop | plan | handoff | score:rcri.
    private func openForScreenshot() async {
        #if DEBUG
        let o = LaunchSeed.string("ps.patient.open")
        switch o {
        case "details": path.append(PatientEditor.details)
        case "history": path.append(PatientEditor.history)
        case "medications": path.append(PatientEditor.medications)
        case "assessment": path.append(PatientEditor.assessment)
        case "airway": path.append(PatientEditor.airway)
        case "intraop": path.append(PatientEditor.intraop)
        case "plan": path.append(PatientEditor.plan)
        case "handoff":
            // A sheet asked for before the tab is on screen can be dropped, so wait a moment.
            try? await Task.sleep(nanoseconds: 800_000_000)
            showHandoff = true
        default: if let route = RefRoute(key: o) { path.append(route) }
        }
        #endif
    }

    // MARK: Top

    private var undoBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "trash").font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg3)
            Text("Patient cleared").font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.fg)
            Spacer()
            Button("Undo") { withAnimation(.snappy) { patient.undoClear() } }
                .buttonStyle(CapsuleButtonStyle())
        }
        .padding(12)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(PS.line2, lineWidth: 1))
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "One patient at a time", color: PS.accent)
            Text("Start with the patient's age, sex, height and weight.")
                .font(PS.serif(size: 22)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
            Text("They fill in the calculators for you, and the rest of the tab builds a short history and physical, the intraoperative course and a handoff.")
                .font(PS.sys(size: 14)).foregroundStyle(PS.fg2).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
            Text("Everything stays on this phone. Don't enter names, record numbers or dates of birth.")
                .font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
            NavigationLink(value: PatientEditor.details) {
                Label("Add patient details", systemImage: "plus")
            }
            .buttonStyle(CapsuleButtonStyle())
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
    }

    private var summaryCard: some View {
        NavigationLink(value: PatientEditor.details) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Eyebrow(text: r.urgency?.label ?? "Patient", color: r.emergency ? PS.accent : PS.fg3)
                    Spacer()
                    Image(systemName: "chevron.right").font(PS.sys(size: 12, weight: .semibold)).foregroundStyle(PS.fg3)
                }
                Text(r.person.isEmpty ? "Patient" : r.person)
                    .font(PS.serif(size: 26)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
                if !r.procedure.isEmpty {
                    Text(r.procedure).font(PS.sys(size: 15, weight: .medium)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
                }
                let sizeLine = PatientSummary.bodyLine(r)
                if !sizeLine.isEmpty { Text(sizeLine).font(PS.sys(size: 13.5)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true) }
                WrapLayout(spacing: 6) {
                    if let asa = PatientRules.asaText(r) { badge(asa, PS.accent) }
                    else if let s = PatientRules.asaSuggestion(r) { badge("Suggested " + s.label, PS.fg3) }
                    if let m = PatientSummary.metsText(r) { badge(m, r.mets == "lt4" ? PS.accent : PS.green) }
                    if !r.anesthetic.isEmpty { badge(PatientSummary.anestheticText(r), PS.accent2) }
                    if r.nkda { badge("NKDA", PS.green) } else if !r.allergies.isEmpty { badge("Allergies", PS.accent) }
                }
                if let v = PatientSummary.vitalsLine(r) { Text(v).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3) }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(PS.sys(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func jumpBar(_ proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach([PatientEditor.history, .assessment, .airway, .intraop, .plan], id: \.self) { e in
                    Button { withAnimation(.snappy) { proxy.scrollTo(e, anchor: .top) } } label: {
                        Text(e.title)
                            .font(PS.sys(size: 13.5, weight: .semibold))
                            .foregroundStyle(PS.fg2)
                            .padding(.horizontal, 13).padding(.vertical, 7)
                            .background(PS.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Section cards

    private var historyCard: some View {
        PatientSectionCard(editor: .history, lines: PatientSummary.historyLines(r), empty: "Problems by system, medications, allergies, anesthesia history, NPO and labs.")
    }

    private var assessmentCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            PatientSectionCard(editor: .assessment, lines: PatientSummary.assessmentLines(r), empty: "ASA class, functional capacity and the risk scores.")
            let prompts = PatientRules.prompts(r)
            if !prompts.isEmpty && !patient.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(prompts.enumerated()), id: \.element.id) { i, p in
                        Button { open(p.route) } label: { promptRow(p) }
                            .buttonStyle(.plain)
                        if i < prompts.count - 1 { Hairline().padding(.leading, 44) }
                    }
                }
                .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
            }
        }
    }

    private func promptRow(_ p: PatientPrompt) -> some View {
        HStack(spacing: 12) {
            Image(systemName: p.done == nil ? "circle.dashed" : "checkmark.circle.fill")
                .font(PS.sys(size: 17, weight: .semibold))
                .foregroundStyle(p.done == nil ? PS.accent : PS.green)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.done ?? p.title).font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
                Text(p.done == nil ? p.why : p.title).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Text(p.done == nil ? "Open" : "Review").font(PS.sys(size: 12.5, weight: .semibold)).foregroundStyle(PS.accent)
            Image(systemName: "chevron.right").font(PS.sys(size: 11, weight: .semibold)).foregroundStyle(PS.fg3)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private var airwayCard: some View {
        NavigationLink(value: PatientEditor.airway) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader(.airway)
                    let lines = PatientSummary.airwayLines(r)
                    if lines.isEmpty {
                        Text("Mallampati, difficult-airway signs, teeth and the examination.").font(PS.sys(size: 13.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, l in summaryLine(l) }
                    }
                }
                if let m = r.mallampati {
                    VStack(spacing: 4) {
                        MallampatiDrawing(mclass: m).frame(width: 64, height: 64)
                        Text(PatientRules.roman(m)).font(PS.mono(size: 11, weight: .bold)).foregroundStyle(PS.fg2)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var intraopCard: some View {
        PatientSectionCard(editor: .intraop, lines: PatientSummary.intraopLines(r), empty: "Airway course, lines, blocks, infusions, fluids and blood, events and echo.")
    }

    private var planCard: some View {
        PatientSectionCard(editor: .plan, lines: PatientSummary.planLines(r), empty: "Disposition, pain plan and what the next team should do.")
    }

    private func sectionHeader(_ e: PatientEditor) -> some View {
        HStack(spacing: 8) {
            Image(systemName: e.icon).font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.accent)
            Text(e.title).font(PS.sys(size: 16, weight: .semibold)).foregroundStyle(PS.fg)
            Spacer()
            Image(systemName: "chevron.right").font(PS.sys(size: 12, weight: .semibold)).foregroundStyle(PS.fg3)
        }
    }

    private func summaryLine(_ l: PatientSummary.Line) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if let k = l.label { Text(k).font(PS.sys(size: 11.5, weight: .semibold)).foregroundStyle(l.alert ? PS.accent : PS.fg3) }
            Text(l.text).font(PS.sys(size: 14)).foregroundStyle(l.alert ? PS.accent : PS.fg).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var handoffButton: some View {
        Button { showHandoff = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.left.arrow.right.square").font(PS.sys(size: 17, weight: .semibold))
                Text("Generate Handoff").font(PS.sys(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundStyle(PS.accentFg)
            .background(patient.isEmpty ? PS.fg3 : PS.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(patient.isEmpty)
        .padding(.top, 4)
    }
}

/// A section of the note: its header, then its lines (or what it holds, while empty). Opens the section's editor.
struct PatientSectionCard: View {
    var editor: PatientEditor
    var lines: [PatientSummary.Line]
    var empty: String

    var body: some View {
        NavigationLink(value: editor) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Image(systemName: editor.icon).font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.accent)
                    Text(editor.title).font(PS.sys(size: 16, weight: .semibold)).foregroundStyle(PS.fg)
                    Spacer()
                    Image(systemName: "chevron.right").font(PS.sys(size: 12, weight: .semibold)).foregroundStyle(PS.fg3)
                }
                if lines.isEmpty {
                    Text(empty).font(PS.sys(size: 13.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                        VStack(alignment: .leading, spacing: 1) {
                            if let k = l.label { Text(k).font(PS.sys(size: 11.5, weight: .semibold)).foregroundStyle(l.alert ? PS.accent : PS.fg3) }
                            Text(l.text).font(PS.sys(size: 14)).foregroundStyle(l.alert ? PS.accent : PS.fg).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The handoff as text, short or full: read, copy or share the one shown.
struct HandoffSheet: View {
    var full: String
    var short: String
    /// "full" or "short"; the last one used is kept.
    @AppStorage("ps.handoff.format") private var format = "full"
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var text: String { format == "short" ? short : full }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Handoff", selection: $format) {
                        Text("Short").tag("short")
                        Text("Full").tag("full")
                    }
                    .pickerStyle(.segmented)
                    Text(text)
                        .font(PS.sys(size: 14.5))
                        .foregroundStyle(PS.fg)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
                    Text("Share only through channels your institution approves for patient information.")
                        .font(PS.sys(size: 12)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(text: "Handing over")
                        ForEach(Array(HandoffWriter.steps.enumerated()), id: \.offset) { i, step in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("\(i + 1)").font(PS.mono(size: 12, weight: .bold)).foregroundStyle(PS.accent).frame(width: 16, alignment: .leading)
                                Text(step).font(PS.sys(size: 13.5)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Text("From the HATRICC handoff protocol (Lane-Fall MB, et al. Implement Sci 2021). In a PACU, anesthesia often reports alone.")
                            .font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
                }
                .padding(20)
            }
            .background(FeedBackground())
            .navigationTitle("Handoff")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { UIPasteboard.general.string = text; copied.toggle() } label: { Label("Copy", systemImage: "doc.on.doc") }
                    ShareLink(item: text) { Label("Share", systemImage: "square.and.arrow.up") }
                }
            }
            .sensoryFeedback(.success, trigger: copied)
        }
    }
}
