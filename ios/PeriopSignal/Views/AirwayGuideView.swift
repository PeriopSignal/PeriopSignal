import SwiftUI

/// The ASA 2022 difficult-airway algorithm as a guide: answer the assessment questions for the
/// plan, then run the attempt-by-attempt checklist in the room.
struct AirwayGuideView: View {
    var onOpen: (URL) -> Void
    var onOpenCard: () -> Void

    @State private var suspected = false
    @State private var ventilation = false
    @State private var aspiration = false
    @State private var apnea = false
    @State private var invasive = false
    @State private var uncooperative = false
    @State private var attempts = 0
    @State private var maskOK = true
    @State private var cannotVentilate = false
    @State private var done: Set<String> = []

    private enum Plan { case routine, prepared, awake }
    private var plan: Plan {
        guard suspected else { return .routine }
        let predictors = ventilation || aspiration || apnea || invasive
        if predictors && !uncooperative { return .awake }
        return .prepared
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                assessment
                planCard
                inRoom
                if cannotVentilate { cicv }
                footer
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 30)
        }
        .background(FeedBackground())
        .scrollContentBackground(.hidden)
        .navigationTitle("Difficult Airway")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Reset") {
                    withAnimation(.snappy) { suspected = false; ventilation = false; aspiration = false; apnea = false; invasive = false; uncooperative = false; attempts = 0; maskOK = true; cannotVentilate = false; done = [] }
                }
            }
        }
    }

    // MARK: Assessment

    private var assessment: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "Before you start").padding(.leading, 2)
            VStack(spacing: 0) {
                question("Difficult laryngoscopy or intubation suspected?", "Several features together: mouth opening, upper-lip bite, Mallampati, thyromental distance, neck mobility, history", $suspected)
                Hairline().padding(.leading, 16)
                question("Difficult mask or supraglottic ventilation?", nil, $ventilation)
                Hairline().padding(.leading, 16)
                question("Increased aspiration risk?", nil, $aspiration)
                Hairline().padding(.leading, 16)
                question("Rapid desaturation or intolerance of apnea?", "Obesity, pregnancy, children, critical illness, low reserve", $apnea)
                Hairline().padding(.leading, 16)
                question("Emergency invasive airway would be difficult?", "Neck anatomy, prior surgery or radiation, obesity", $invasive)
                Hairline().padding(.leading, 16)
                question("Awake technique not feasible?", "Uncooperative patient, small child", $uncooperative)
            }
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        }
    }

    private func question(_ title: String, _ detail: String?, _ on: Binding<Bool>) -> some View {
        Toggle(isOn: on) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
                if let d = detail { Text(d).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true) }
            }
        }
        .tint(PS.accent)
        .padding(.horizontal, 16).padding(.vertical, 11)
    }

    // MARK: Plan

    private var planCard: some View {
        let (title, tone, steps): (String, Color, [String]) = {
            switch plan {
            case .awake:
                return ("Awake Intubation", PS.accent, [
                    "Explain the plan and the risks; antisialagogue; topicalize well, sedation light enough to keep breathing and cooperation.",
                    "Oxygen throughout — high-flow nasal or a nasal cannula under the mask.",
                    "Choose the device you know best (flexible scope, videolaryngoscope, or both); a second skilled clinician present.",
                    "Double set-up: surgical or invasive airway ready" + (invasive ? " — the invasive route is itself expected to be difficult, so have the surgeon in the room." : "."),
                    "If the awake attempt fails and the case cannot wait or the patient is unstable: post-induction pathway with the invasive airway prepared.",
                ])
            case .prepared:
                return ("Intubate After Induction, Prepared for Failure", PS.accent2, [
                    uncooperative ? "Awake technique not feasible: induce with spontaneous ventilation maintained where possible (inhalational in children)." : "No independent predictor of failed rescue: induction is reasonable with rescue devices open.",
                    "Position, preoxygenate, apneic oxygenation; videolaryngoscope, supraglottic airway and flexible scope in the room; bougie and stylet ready.",
                    "Time-out: name the primary and backup airway managers; an observer calls time, attempts and saturation.",
                    "Plan the wake-up: short-acting drugs or rocuronium with sugammadex drawn up (16 mg/kg for immediate reversal).",
                    "Invasive airway kit opened, not just available.",
                ])
            case .routine:
                return ("Routine Airway, Cart Available", PS.green, [
                    "Standard equipment in the room; the difficult-airway cart immediately available.",
                    "Preoxygenate and keep oxygen flowing; capnography to confirm ventilation.",
                    "Reassess if the first laryngoscopy surprises you — the attempt counter below applies to every patient.",
                ])
            }
        }()
        return VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "The plan", color: tone)
            Text(title).font(PS.serif(size: 24, weight: .semibold)).foregroundStyle(PS.fg)
            if plan == .awake {
                Text("Difficult intubation is suspected together with " + awakeReasons + ".").font(PS.sys(size: 13.5)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
            }
            checklistBlock(steps, key: "plan", title: "Plan Checklist", tint: tone)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: PS.cardRadius, topTrailingRadius: PS.cardRadius)
                .fill(tone.opacity(0.9)).frame(height: 3)
                .clipShape(RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        }
        .animation(.snappy, value: suspected)
    }

    private var awakeReasons: String {
        var r: [String] = []
        if ventilation { r.append("difficult ventilation") }
        if aspiration { r.append("aspiration risk") }
        if apnea { r.append("intolerance of apnea") }
        if invasive { r.append("a difficult invasive airway") }
        return r.joined(separator: ", ")
    }

    // MARK: In the room

    private var inRoom: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "In the room: attempt by attempt").padding(.leading, 2)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(attemptsTitle).font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(attempts >= 4 ? PS.accent : PS.fg)
                        Text(attemptsDetail).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Text("\(attempts)").font(PS.serif(size: 34, weight: .semibold)).foregroundStyle(attempts >= 3 ? PS.accent : PS.fg)
                }
                HStack(spacing: 10) {
                    Button {
                        Haptics.light()
                        withAnimation(.snappy) { attempts += 1 }
                    } label: { Text("Attempt failed") }.buttonStyle(CapsuleButtonStyle(prominent: true))
                    Button {
                        Haptics.light()
                        withAnimation(.snappy) { attempts = max(0, attempts - 1) }
                    } label: { Text("Undo") }.buttonStyle(GhostButtonStyle()).disabled(attempts == 0)
                }
                Hairline()
                Toggle(isOn: $maskOK) {
                    Text("Mask or supraglottic ventilation adequate after the last attempt").font(PS.sys(size: 14, weight: .medium)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
                }
                .tint(PS.green)
                checklistBlock([
                    "Change something before trying again: position, relaxation, blade or device, a bougie, an adjunct — not the same move twice.",
                    "Combine devices when one struggles: videolaryngoscope with a flexible scope, or intubate through the supraglottic airway.",
                    "Provide and test mask ventilation after every attempt; keep oxygen on throughout.",
                    "Each attempt, decide: wake the patient and restore breathing, or carry on? Non-invasive next, or invasive?",
                ], key: "room", title: "Before Every Attempt", tint: PS.accent2)
                if !maskOK {
                    Button {
                        Haptics.light()
                        withAnimation(.snappy) { cannotVentilate = true }
                    } label: { Label("Cannot ventilate — open the emergency pathway", systemImage: "exclamationmark.triangle.fill") }
                    .buttonStyle(CapsuleButtonStyle(prominent: true, color: PS.accent, onColor: PS.accentFg))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        }
    }

    private var attemptsTitle: String {
        switch attempts {
        case 0: return "No attempts yet"
        case 1, 2: return "Attempt \(attempts) failed"
        case 3: return "Three attempts: one more, by the most skilled person present"
        default: return "Stop attempting — rescue, wake, or invasive airway"
        }
    }
    private var attemptsDetail: String {
        switch attempts {
        case 0: return "Count every laryngoscopy, supraglottic placement and mask rescue; the limit is three of any class, plus one by a more skilled clinician (3 + 1)."
        case 1, 2: return "Call for help now if you have not; the observer tracks time and saturation."
        case 3: return "Only a clinician with greater skill makes the fourth; otherwise wake the patient or move to rescue."
        default: return "Further attempts cause injury and swelling. Oxygenate by whatever works; wake the patient if feasible, or proceed to the invasive airway."
        }
    }

    // MARK: Cannot ventilate

    private var cicv: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cannot Intubate, Cannot Ventilate").font(PS.serif(size: 20, weight: .semibold)).foregroundStyle(PS.accent)
            checklistBlock([
                "Call for help: a second anesthesiologist, a surgeon, the invasive airway kit opened now; start the clock.",
                "Optimize oxygenation: two-hand mask with an oral and nasal airway, a supraglottic airway (a different size or type), and a final look with the videolaryngoscope only if it does not cost oxygenation.",
                "Functional obstruction (laryngospasm, light anesthesia)? Deepen and relax. Anatomic? Devices.",
                "When non-invasive options have failed or are failing: emergency invasive airway without further delay — surgical cricothyrotomy, or needle cricothyrotomy with a pressure-regulated jet device, or large-bore cannula, by the most experienced person present, with an alternative ready if it fails.",
                "Start ECMO when appropriate and available; rigid bronchoscopy in adults where a team exists.",
                "Afterwards: document the difficulty, tell the patient, registry or letter and alert bracelet.",
            ], key: "cicv", title: "Emergency Checklist", tint: PS.accent)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PS.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous).stroke(PS.accent.opacity(0.4), lineWidth: 1))
    }

    /// A pilot-style checklist: progress and reset on top, numbered boxes to tick in any order.
    private func checklistBlock(_ items: [String], key: String, title: String, tint: Color) -> some View {
        let ids = items.indices.map { "\(key)-\($0)" }
        let count = ids.filter { done.contains($0) }.count
        return VStack(alignment: .leading, spacing: 4) {
            ChecklistProgress(done: count, total: items.count, tint: tint, title: title) {
                for id in ids { done.remove(id) }
            }
            .padding(.bottom, 4)
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                let id = ids[i]
                ChecklistItemRow(number: i + 1, text: item, done: done.contains(id), tint: tint, size: 14) {
                    if done.contains(id) { done.remove(id) } else { done.insert(id) }
                }
                if i < items.count - 1 { Hairline().padding(.leading, 38) }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Hairline()
            HStack(spacing: 10) {
                Button(action: onOpenCard) { Label("Full algorithm", systemImage: "tablecells") }.buttonStyle(GhostButtonStyle())
                if let url = URL(string: "https://doi.org/10.1097/ALN.0000000000004002") {
                    Button { onOpen(url) } label: { Label("Guideline ↗", systemImage: "doc.text") }.buttonStyle(GhostButtonStyle())
                }
            }
            Text("A guide through the 2022 ASA practice guideline's decision points, in Periop Signal's words; the ASA infographics are the algorithm. Children: awake intubation is uncommon, inhalational induction with spontaneous breathing is usual, and the attempt limit is the primary manager's attempts plus one by the backup.")
                .font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
        }
    }
}
