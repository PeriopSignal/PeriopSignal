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
        if !res.suggestions.isEmpty {
            PatientGroup(title: "In the record: confirm", note: nil) {
                ForEach(Array(res.suggestions.enumerated()), id: \.element.item.id) { i, s in
                    teeRow(s.item, result: res, why: s.why)
                    if i < res.suggestions.count - 1 { Hairline().padding(.leading, 14) }
                }
            }
        }
        let suggested = Set(res.suggestions.map(\.item.id))
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
            PatientTextField(label: "Notes", prompt: "Last endoscopy, GI advice, probe size, plan", text: Binding(get: { patient.record.teeScreen.notes }, set: { v in patient.update { $0.teeScreen.notes = v } }))
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

    /// One item: its label and detail, then Yes/No, or "In the record" when a structured field already shows it.
    private func teeRow(_ it: TEEItem, result: TEEResult, why: String?) -> some View {
        let fromRecord = PatientTEE.fromRecord(r)[it.id]
        let answer = r.teeScreen.answer(it.id)
        let tint = it.level == .absolute ? PS.red : PS.accent
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(it.label).font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
                    if let d = it.detail { Text(d).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 6)
                if fromRecord == nil {
                    YesNoPills(no: answer == false || (answer == nil && r.teeScreen.reviewed), yes: answer == true,
                               onNo: { withAnimation(.snappy) { patient.update(discrete: true) { $0.teeScreen.set(it.id, answer == false ? nil : false) } } },
                               onYes: { withAnimation(.snappy) { patient.update(discrete: true) { $0.teeScreen.set(it.id, answer == true ? nil : true) } } })
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
            if result.findings.isEmpty {
                Text(result.reviewed ? "Every item asked; none applies." : "Answer the questions below, or confirm what the record suggests.")
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
