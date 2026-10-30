import SwiftUI

/// "When is the stomach ready?" — what was taken and when, in; the earliest elective start, out
/// (ASA 2017 fasting guideline with the 2023 update).
struct FastingView: View {
    var onOpen: (URL) -> Void
    var onOpenCard: () -> Void

    struct Intake: Identifiable {
        let id: String
        let label: String
        let hours: Double
        let detail: String
    }
    static let intakes: [Intake] = [
        Intake(id: "clear", label: "Clear liquids", hours: 2, detail: "Water, pulp-free juice, carbonated drinks, clear tea, black coffee"),
        Intake(id: "carb", label: "Carbohydrate drink", hours: 2, detail: "Adults: encouraged up to 400 mL until 2 h before (2023)"),
        Intake(id: "breast", label: "Breast milk", hours: 4, detail: ""),
        Intake(id: "formula", label: "Infant formula", hours: 6, detail: ""),
        Intake(id: "milk", label: "Non-human milk", hours: 6, detail: "Empties like a solid; the amount matters"),
        Intake(id: "light", label: "Light meal", hours: 6, detail: "Toast and clear liquids"),
        Intake(id: "heavy", label: "Fried or fatty food, meat", hours: 8, detail: "Additional time, 8 hours or more"),
        Intake(id: "gum", label: "Chewing gum", hours: 0, detail: "Does not delay or cancel; remove before any sedative"),
    ]
    static let conditions: [String] = [
        "Pregnancy or labor", "Obesity", "Diabetes", "Hiatal hernia or uncontrolled reflux", "Achalasia, stricture or Zenker diverticulum",
        "Previous gastric surgery", "Gastroparesis", "Opioid use", "Ileus, obstruction or acute abdomen", "Emergency procedure",
        "Enteral tube feeding", "Potentially difficult airway",
    ]

    @State private var taken: [String: Date] = [:]
    @State private var flags: Set<String> = []
    @State private var now = Date()

    private var earliest: (date: Date, because: Intake)? {
        var best: (Date, Intake)?
        for i in Self.intakes {
            guard let t = taken[i.id] else { continue }
            let ready = t.addingTimeInterval(i.hours * 3600)
            if best == nil || ready > best!.0 { best = (ready, i) }
        }
        return best.map { ($0.0, $0.1) }
    }

    var body: some View {
        ToolScroll {
            VStack(alignment: .leading, spacing: 18) {
                result
                intakeCard
                conditionsCard
                footer
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 30)
        }
        .background(FeedBackground())
        .scrollContentBackground(.hidden)
        .navigationTitle("Fasting")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Reset") { withAnimation(.snappy) { taken = [:]; flags = [] } }.disabled(taken.isEmpty && flags.isEmpty)
            }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    private var result: some View {
        let e = earliest
        let ready = e.map { $0.date <= now } ?? false
        let tone: Color = !flags.isEmpty ? PS.accent : (e == nil ? PS.fg3 : (ready ? PS.green : PS.accent2))
        return VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Earliest elective start", color: tone)
            if let e {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(Self.when.string(from: e.date)).font(PS.serif(size: 30, weight: .semibold)).foregroundStyle(PS.fg)
                    Text(ready ? "now" : NeuraxialCalc.countdown(to: e.date, from: now)).font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(tone)
                }
                Text(e.because.hours == 0 ? "Gum does not set a time; remove it before any sedative." : "\(NeuraxialCalc.fmtHours(e.because.hours)) after the \(e.because.label.lowercased()) at \(Self.clock.string(from: taken[e.because.id] ?? e.date)).")
                    .font(PS.sys(size: 14)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
                if !ready, e.date.addingTimeInterval(-2 * 3600) > now {
                    Text("Clear liquids are fine until \(Self.clock.string(from: e.date.addingTimeInterval(-2 * 3600))).").font(PS.sys(size: 13)).foregroundStyle(PS.fg2)
                }
            } else {
                Text("Enter What Was Taken").font(PS.serif(size: 24, weight: .semibold)).foregroundStyle(PS.fg3)
            }
            if !flags.isEmpty {
                Text("The guideline is written for healthy patients: with \(flags.count == 1 ? "this condition" : "these conditions") its times do not apply as written — plan for delayed emptying.")
                    .font(PS.sys(size: 13.5)).foregroundStyle(PS.accent).fixedSize(horizontal: false, vertical: true)
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
    }

    private var intakeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "What was taken, and when").padding(.leading, 2)
            VStack(spacing: 0) {
                ForEach(Array(Self.intakes.enumerated()), id: \.element.id) { i, intake in
                    let on = taken[intake.id] != nil
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            Button {
                                Haptics.light()
                                withAnimation(.snappy) { if on { taken[intake.id] = nil } else { taken[intake.id] = Date().addingTimeInterval(-3600) } }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: on ? "checkmark.circle.fill" : "circle").font(PS.sys(size: 20)).foregroundStyle(on ? PS.accent : PS.fg3)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(intake.label).font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg)
                                        if !intake.detail.isEmpty { Text(intake.detail).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true) }
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Spacer(minLength: 0)
                            Text(intake.hours == 0 ? "—" : NeuraxialCalc.fmtHours(intake.hours)).font(PS.mono(size: 11, weight: .semibold)).foregroundStyle(PS.fg3)
                        }
                        if on {
                            DatePicker("Time", selection: Binding(get: { taken[intake.id] ?? Date() }, set: { taken[intake.id] = $0 }), in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                                .labelsHidden().datePickerStyle(.compact).tint(PS.accent)
                                .padding(.leading, 30)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    if i < Self.intakes.count - 1 { Hairline().padding(.leading, 16) }
                }
            }
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        }
    }

    private var conditionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "Anything that slows emptying?").padding(.leading, 2)
            FlowLayout(spacing: 8) {
                ForEach(Self.conditions, id: \.self) { c in
                    let on = flags.contains(c)
                    Button {
                        Haptics.light()
                        withAnimation(.snappy) { if on { flags.remove(c) } else { flags.insert(c) } }
                    } label: {
                        Text(c)
                            .font(PS.sys(size: 13, weight: .medium))
                            .padding(.horizontal, 11).padding(.vertical, 7)
                            .background(on ? PS.accent.opacity(0.15) : PS.surface, in: Capsule())
                            .overlay(Capsule().stroke(on ? PS.accent.opacity(0.7) : PS.line2, lineWidth: 1))
                            .foregroundStyle(on ? PS.accent : PS.fg2)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Hairline()
            HStack(spacing: 10) {
                Button(action: onOpenCard) { Label("Guideline card", systemImage: "tablecells") }.buttonStyle(GhostButtonStyle())
                if let url = URL(string: "https://doi.org/10.1097/ALN.0000000000004381") {
                    Button { onOpen(url) } label: { Label("Guideline ↗", systemImage: "doc.text") }.buttonStyle(GhostButtonStyle())
                }
            }
            Text("ASA practice guidelines for preoperative fasting (2017, updated 2023): minimum times for healthy patients of all ages having elective procedures under general anesthesia, regional anesthesia or procedural sedation; not for labor. Meeting the times does not guarantee an empty stomach. Children's clear liquids: as close to 2 h before as possible.")
                .font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
        }
    }

    private static let when: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "EEE d MMM, HH:mm"; return f
    }()
    private static let clock: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "HH:mm"; return f
    }()
}
