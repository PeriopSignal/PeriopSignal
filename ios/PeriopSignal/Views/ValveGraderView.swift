import SwiftUI

/// Measurements in, the ASE grade out: pick the lesion, enter what you measured, tick the signs.
struct ValveGraderView: View {
    @Environment(PatientStore.self) private var myPatient
    var onOpen: (URL) -> Void
    var onOpenTable: () -> Void

    /// DEBUG screenshots: -ps.vg.lesion mr opens on that lesion.
    @State private var lesion: ValveLesion = ValveLesion(rawValue: LaunchSeed.string("ps.vg.lesion")) ?? .as_
    /// DEBUG screenshots: -ps.vg.texts "vmax=3.3;lvotd=2.0" types those values in (1.12).
    @State private var texts: [String: String] = ValveGraderView.seededTexts()
    @State private var signs: Set<String> = []

    private static func seededTexts() -> [String: String] {
        #if DEBUG
        var out: [String: String] = [:]
        for pair in LaunchSeed.string("ps.vg.texts").split(separator: ";") {
            let kv = pair.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if kv.count == 2 { out[kv[0]] = kv[1] }
        }
        return out
        #else
        return [:]
        #endif
    }

    /// What was typed and ticked (1.12: calculated values are not in it, so an empty page still reads as empty).
    private var input: ValveInput {
        var i = ValveInput()
        for (k, v) in texts {
            if let d = Double(v.replacingOccurrences(of: ",", with: ".")), d > 0 { i.numbers[k] = d }
        }
        i.signs = signs
        return i
    }
    /// What the open patient gives (1.12): the BSA from the recorded height and weight, the LVEF from the recorded echo.
    private var context: ValveGrading.Context { ValveGrading.Context(myPatient.record) }
    /// The fields that can be calculated from the others and are empty (1.12, Ben's note 9). A field that holds text which
    /// is not a number yet is not empty.
    private var calculation: ValveGrading.Calculation {
        let occupied = Set(texts.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }.keys)
        return ValveGrading.calculate(lesion, typed: input.numbers, occupied: occupied, context: context)
    }
    /// The reading grades the value shown, typed or calculated.
    private var reading: ValveReading { ValveGrading.read(lesion, ValveGrading.graded(input, with: calculation)) }
    private var params: [ValveParam] { ValveGrading.params(for: lesion) }

    var body: some View {
        ToolScroll {
            VStack(alignment: .leading, spacing: 18) {
                picker
                result
                if let g = reading.overall { PatientEchoSaveBar(label: g.label + " " + lesion.short, isSaved: { $0.grade(for: lesion) == EchoGrade(g) }, save: { $0.apply(lesion, g) }) }
                numbers
                if params.contains(where: \.isSign) { signsCard }
                footer
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 30)
        }
        .background(FeedBackground())
        .scrollContentBackground(.hidden)
        .navigationTitle("ASE Valve Severity Grading")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { Keyboard.dismiss() }
            }
        }
    }

    private var picker: some View {
        HStack(spacing: 10) {
            Picker("Lesion", selection: $lesion) {
                ForEach(ValveLesion.allCases) { l in Text(l.short).tag(l) }
            }
            .pickerStyle(.segmented)
            .onChange(of: lesion) { _, _ in texts = [:]; signs = [] }
            if !(texts.isEmpty && signs.isEmpty) {
                Button {
                    Haptics.light()
                    withAnimation(.snappy) { texts = [:]; signs = [] }
                } label: { Image(systemName: "arrow.counterclockwise") }
                    .font(PS.sys(size: 14, weight: .semibold))
                    .foregroundStyle(PS.fg2)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear the measurements")
            }
        }
    }

    private var result: some View {
        let r = reading
        let tone: Color = {
            switch r.overall {
            case .severe?: return PS.accent
            case .moderate?: return PS.accent2
            case .mild?: return PS.green
            case nil: return input.isEmpty ? PS.fg3 : PS.accent2
            }
        }()
        return VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: lesion.name, color: tone)
            Text(r.headline.titleCased).font(PS.serif(size: 24, weight: .semibold)).foregroundStyle(input.isEmpty ? PS.fg3 : PS.fg).fixedSize(horizontal: false, vertical: true)
                .promptHeadline(r.overall == nil && r.headline.hasPrefix("Enter "))
            Text(r.explanation).font(PS.sys(size: 14)).foregroundStyle(PS.fg2).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
            if !r.lines.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(r.lines) { line in
                        HStack(spacing: 4) {
                            if let g = line.grade { Circle().fill(color(g)).frame(width: 6, height: 6) }
                            Text("\(line.label): \(line.text)").font(PS.sys(size: 11.5, weight: .medium)).foregroundStyle(PS.fg2)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(PS.surface2, in: Capsule())
                    }
                }
            }
            ForEach(Array(r.cautions.enumerated()), id: \.offset) { _, c in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").font(PS.sys(size: 11)).foregroundStyle(PS.accent)
                    Text(c).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: PS.cardRadius, topTrailingRadius: PS.cardRadius)
                .fill(tone.opacity(0.9)).frame(height: 3)
                .clipShape(RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        }
        .animation(.snappy, value: r)
    }

    private func color(_ g: ValveGrade) -> Color {
        switch g {
        case .mild: return PS.green
        case .moderate: return PS.accent2
        case .severe: return PS.accent
        }
    }

    private var numbers: some View {
        let list = params.filter { !$0.isSign }
        let calc = calculation
        return VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "Measurements").padding(.leading, 2)
            if let line = Self.patientLine(calc, context: context) {
                Text(line).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).padding(.leading, 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, p in
                    let typedValue = texts[p.id].flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
                    // 1.12: a calculated value stands in a field that is empty; typing in it replaces it, clearing brings it back.
                    let calculated: ValveGrading.Calculated? = (texts[p.id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty ? calc.values[p.id] : nil
                    let grade = (typedValue ?? calculated?.value).flatMap { p.grade($0) }
                    VStack(alignment: .leading, spacing: 3) {
                        if p.id == "lvotd" {
                            Text("Optional: the empty fields above are calculated from these.")
                                .font(PS.sys(size: 11.5, weight: .semibold)).foregroundStyle(PS.fg3)
                                .padding(.bottom, 4)
                        }
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.label).font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg)
                                if let h = p.hint { Text(h).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true) }
                                if let c = calculated {
                                    Text(c.caption).font(PS.sys(size: 11.5, weight: .medium)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Spacer(minLength: 6)
                            if let g = grade { Circle().fill(color(g)).frame(width: 8, height: 8) }
                            FocusBox { f in
                                TextField(calculated == nil ? "—" : "", text: Binding(get: { texts[p.id] ?? "" }, set: { texts[p.id] = $0 }))
                                    .keyboardType(.decimalPad)
                                    .focused(f)
                                    .multilineTextAlignment(.trailing)
                                    .font(PS.sys(size: 17, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(PS.fg)
                                    .padding(.horizontal, 6).padding(.vertical, 5)
                                    .overlay(alignment: .trailing) {
                                        // The calculated value, in a quieter ink; out of the way of the cursor while the field is being typed in.
                                        if let c = calculated, !f.wrappedValue {
                                            Text(c.text)
                                                .font(PS.sys(size: 17, weight: .semibold, design: .monospaced)).foregroundStyle(PS.fg3)
                                                .padding(.trailing, 6)
                                                .allowsHitTesting(false)
                                                .accessibilityLabel("\(c.text), " + c.caption)
                                        }
                                    }
                                    .background(PS.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                                .frame(width: 78)
                            Text(p.unit).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).frame(width: 46, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    if i < list.count - 1 { Hairline().padding(.leading, 14) }
                }
            }
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
            ForEach(Array(calc.notes.enumerated()), id: \.offset) { _, n in
                Text(n).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).padding(.leading, 2).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// "Indexed values use BSA 2.13 m² from My Patient." when a value was indexed or the LVEF taken from the patient.
    static func patientLine(_ calc: ValveGrading.Calculation, context c: ValveGrading.Context) -> String? {
        var used: [String] = []
        if let b = c.bsa, calc.values["avai"] != nil || calc.values["svi"] != nil { used.append("BSA " + String(format: "%.2f", b) + " m²") }
        if calc.values["lvef"] != nil, let e = c.lvef { used.append("LVEF " + NumText.short(e) + "%") }
        return used.isEmpty ? nil : used.joined(separator: " and ") + " from My Patient."
    }

    private var signsCard: some View {
        let list = params.filter(\.isSign)
        return VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "Signs").padding(.leading, 2)
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, p in
                    let on = signs.contains(p.id)
                    Button {
                        Haptics.light()
                        withAnimation(.snappy) { if on { signs.remove(p.id) } else { signs.insert(p.id) } }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: on ? "checkmark.circle.fill" : "circle").font(PS.sys(size: 19)).foregroundStyle(on ? PS.accent : PS.fg3)
                                .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 5 }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.label).font(PS.sys(size: 14, weight: .medium)).foregroundStyle(PS.fg).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                                if let h = p.hint { Text(h).font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true) }
                            }
                            Spacer(minLength: 0)
                            if case .sign(let g) = p.kind, g != .moderate { Text(g.label).font(PS.mono(size: 9.5, weight: .semibold)).foregroundStyle(color(g)) }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if i < list.count - 1 { Hairline().padding(.leading, 14) }
                }
            }
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Hairline()
            HStack(spacing: 10) {
                Button(action: onOpenTable) { Label("Grading tables", systemImage: "tablecells") }.buttonStyle(GhostButtonStyle())
                if let url = URL(string: "https://www.asecho.org/guideline/native-valvular-regurgitation-by-echo") {
                    Button { onOpen(url) } label: { Label("ASE ↗", systemImage: "doc.text") }.buttonStyle(GhostButtonStyle())
                }
            }
            EvidenceDisclosure {
                Text("Source: \(lesion.source). The reading integrates the signs the way the documents describe and sets aside what you leave blank; it is a second pair of eyes on the numbers, not a report. Loading conditions in the operating room usually under-read regurgitation.")
                    .font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
