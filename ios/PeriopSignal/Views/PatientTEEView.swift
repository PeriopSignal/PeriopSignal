import SwiftUI

// MARK: - TEE screen
//
// The workup page behind Assessment → Cardiac evaluation → TEE screen (and the prompt when a TEE is likely): what the
// record already shows, what it hints at to confirm, and the rest of the ASE/SCA list as Yes/No questions. The model,
// classes and sources are in PatientTEE (Shared).

extension PatientEditorView {

    /// The row in the cardiac evaluation that opens the screen.
    var teeLinkRow: some View {
        let res = PatientTEE.evaluate(r)
        let icon: String
        switch res.level {
        case .absolute, .relative: icon = "exclamationmark.triangle"
        case .none: icon = res.reviewed ? "checkmark.shield" : "plus.circle"
        }
        return linkRow("TEE screen", PatientTEE.status(r), icon: icon, value: .workup("tee"))
    }

    @ViewBuilder var teeScreenEditor: some View {
        let res = PatientTEE.evaluate(r)
        TEEResultCard(result: res)
        // Asked first (1.9, Ben): difficulty swallowing (the checklist's Dysphagia), a previous EGD and a previous TEE.
        PatientGroup(title: "Ask first") {
            if let swallow = swallowItem {
                teeRow(swallow, result: res, why: res.suggestions.first { $0.item.id == "dysphagia" }?.why)
                Hairline().padding(.leading, 14)
            }
            teePreviousRow("Previous EGD?", answer: \.teeScreen.previousEGD)
            if r.teeScreen.previousEGD == true {
                PatientTextField(label: "EGD date", prompt: "MM/YYYY", text: bind(\.teeScreen.egdDate))
                PatientTextField(label: "EGD findings", prompt: "Normal, esophagitis, stricture, varices…", text: bind(\.teeScreen.egdFindings))
            }
            Hairline().padding(.leading, 14)
            teePreviousRow("Previous TEE?", answer: \.teeScreen.previousTEE)
            if r.teeScreen.previousTEE == true {
                PatientTextField(label: "TEE date", prompt: "MM/YYYY", text: bind(\.teeScreen.teeDate))
            }
        }
        let others = res.suggestions.filter { $0.item.id != "dysphagia" }
        if !others.isEmpty {
            PatientGroup(title: "In the record: confirm", note: nil) {
                ForEach(Array(others.enumerated()), id: \.element.item.id) { i, s in
                    teeRow(s.item, result: res, why: s.why)
                    if i < others.count - 1 { Hairline().padding(.leading, 14) }
                }
            }
            .id("tee-confirm")
        }
        let suggested = Set(res.suggestions.map(\.item.id)).union(["dysphagia"])
        let absolute = PatientTEE.items.filter { $0.level == .absolute && !suggested.contains($0.id) }
        let relative = PatientTEE.items.filter { $0.level == .relative && !suggested.contains($0.id) }
        PatientGroup(title: "Absolute contraindications") {
            ForEach(Array(absolute.enumerated()), id: \.element.id) { i, it in
                teeRow(it, result: res, why: nil)
                if i < absolute.count - 1 { Hairline().padding(.leading, 14) }
            }
        }
        PatientGroup(title: "Relative contraindications") {
            ForEach(Array(relative.enumerated()), id: \.element.id) { i, it in
                teeRow(it, result: res, why: nil)
                if i < relative.count - 1 { Hairline().padding(.leading, 14) }
            }
        }
        PatientGroup(title: nil) {
            toggleRow("Asked about every item", "Anything not answered Yes counts as No", Binding(get: { patient.record.teeScreen.reviewed }, set: { v in patient.update { $0.teeScreen.reviewed = v } }))
            PatientTextField(label: "Notes", prompt: "GI advice, probe size, plan", text: Binding(get: { patient.record.teeScreen.notes }, set: { v in patient.update { $0.teeScreen.notes = v } }))
        }
        if !res.findings.isEmpty {
            PatientGroup(title: "Precautions") {
                adviceList("If the benefit outweighs the risk", PatientTEE.precautions, tint: res.level == .absolute ? PS.red : PS.accent)
            }
        }
        EvidenceDisclosure {
            ForEach(Array(PatientTEE.evidence.enumerated()), id: \.offset) { _, p in
                Text(p).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
            }
            Text("Sources").font(PS.sys(size: 12, weight: .semibold)).foregroundStyle(PS.fg2).padding(.top, 2)
            ForEach(TEESource.allCases, id: \.self) { s in
                Text(s.citation).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    /// The checklist's Dysphagia, asked in Ben's words.
    private var swallowItem: TEEItem? {
        guard var it = PatientTEE.item("dysphagia") else { return nil }
        it.label = "Difficulty swallowing?"
        return it
    }

    /// Previous EGD or TEE: No and Yes; a second tap on the same answer clears it. What was typed under Yes is kept.
    private func teePreviousRow(_ title: String, answer: WritableKeyPath<PatientRecord, Bool?>) -> some View {
        let a = r[keyPath: answer]
        return HStack(spacing: 10) {
            Text(title).font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg)
            Spacer(minLength: 6)
            YesNoPills(no: a == false, yes: a == true,
                       onNo: { withAnimation(.snappy) { patient.update(discrete: true) { $0[keyPath: answer] = false } } },
                       onYes: { withAnimation(.snappy) { patient.update(discrete: true) { $0[keyPath: answer] = true } } },
                       onClear: { withAnimation(.snappy) { patient.update(discrete: true) { $0[keyPath: answer] = nil } } })
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    /// One item: its label and detail, then Yes/No, or "In the record" when a structured field already shows it.
    private func teeRow(_ it: TEEItem, result: TEEResult, why: String?) -> some View {
        let fromRecord = PatientTEE.fromRecord(r)[it.id]
        let answer = r.teeScreen.answer(it.id)
        let tint = it.level == .absolute ? PS.red : PS.accent
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                TEEItemTitle(item: it)
                Spacer(minLength: 6)
                if fromRecord == nil {
                    YesNoPills(no: answer == false || (answer == nil && r.teeScreen.reviewed), yes: answer == true,
                               onNo: { withAnimation(.snappy) { patient.update(discrete: true) { $0.teeScreen.set(it.id, false) } } },
                               onYes: { withAnimation(.snappy) { patient.update(discrete: true) { $0.teeScreen.set(it.id, true) } } },
                               // A No shown only because the screen was reviewed (no answer yet) is set as an answer first, as before.
                               onClear: { withAnimation(.snappy) { patient.update(discrete: true) { $0.teeScreen.set(it.id, answer == nil ? false : nil) } } })
                } else {
                    Label("In the record", systemImage: "checkmark.circle.fill")
                        .font(PS.sys(size: 12.5, weight: .semibold)).foregroundStyle(tint)
                        .labelStyle(.titleAndIcon)
                }
            }
            if let fromRecord {
                Text(fromRecord.joined(separator: "; ")).font(PS.sys(size: 12)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
            }
            if let why {
                Text(why).font(PS.sys(size: 12)).foregroundStyle(PS.accent2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }
}

/// An item's label, with its definition behind an ⓘ at the end of the label (1.8.1). Captions that say how an item is
/// graded stay in view: Zenker's (Ben, Nov 2) and, like it, the ones that say a class rests on survey opinion or on
/// severity. Dysphagia's "Now or in the past" stays in view too: it sets the question's scope (review 1.8.1 row 33).
struct TEEItemTitle: View {
    var item: TEEItem
    @State private var open = LaunchSeed.bool("ps.evidence.open")

    /// The items whose caption is about the grading, so it stays in view.
    static let gradingCaptions: Set<String> = ["diverticulum", "esophagectomy", "te-fistula", "motility"]
    /// The items whose caption sets the question's scope, so it stays in view.
    static let scopeCaptions: Set<String> = ["dysphagia"]

    var body: some View {
        InfoTitle(caption: item.detail, collapsible: !Self.gradingCaptions.union(Self.scopeCaptions).contains(item.id), open: $open, captionFont: PS.sys(size: 12), spacing: 2) {
            Text(item.label).font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The result at the top: the class in words, and each contraindication with where it was found and its source.
struct TEEResultCard: View {
    var result: TEEResult

    private var color: Color {
        switch result.level {
        case .absolute: return PS.red
        case .relative: return PS.accent
        case .none: return result.reviewed ? PS.green : PS.fg3
        }
    }

    private var title: String {
        switch result.level {
        case .absolute: return "Absolute contraindication to the probe"
        case .relative: return "Relative contraindication to the probe"
        case .none: return result.reviewed ? "No contraindication recorded" : "Not screened yet"
        }
    }

    private var icon: String {
        switch result.level {
        case .absolute: return "xmark.octagon.fill"
        case .relative: return "exclamationmark.triangle.fill"
        case .none: return result.reviewed ? "checkmark.shield.fill" : "circle.dashed"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(PS.sys(size: 18, weight: .semibold)).foregroundStyle(color)
                Text(title).font(PS.sys(size: 16.5, weight: .bold)).foregroundStyle(result.level == .none ? PS.fg : color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if result.findings.isEmpty && result.reviewed {
                Text("Every item asked; none applies.")
                    .font(PS.sys(size: 13)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(result.findings, id: \.item.id) { f in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(f.item.label).font(PS.sys(size: 14.5, weight: .semibold))
                            .foregroundStyle(f.item.level == .absolute ? PS.red : PS.fg)
                        Text(f.item.level == .absolute ? "Absolute" : "Relative")
                            .font(PS.sys(size: 11, weight: .bold))
                            .foregroundStyle(f.item.level == .absolute ? PS.red : PS.accent)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background((f.item.level == .absolute ? PS.red : PS.accent).opacity(0.12), in: Capsule())
                    }
                    Text(f.from.joined(separator: "; ") + " · " + f.item.source.short)
                        .font(PS.sys(size: 12)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous).stroke(result.level == .none ? Color.clear : color.opacity(0.5), lineWidth: 1.5))
        .accessibilityElement(children: .combine)
    }
}
