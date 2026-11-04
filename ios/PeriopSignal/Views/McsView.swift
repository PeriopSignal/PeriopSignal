import SwiftUI

// MARK: - Mechanical support: LVAD, Impella, ECMO, IABP, ProtekDuo
//
// Reference → Cardiothoracic. "Which device?" (preselected from the lines and devices in My Patient), then that device's
// short run of questions, each with what to look at behind it; the numbers, each tagged with how firm it is (Mfr, per
// your team, review, verify, G), sit behind "Device numbers". Reference only. reference.json "mcs", a draft until
// signed off in the review doc.

struct McsView: View {
    var onOpen: (URL) -> Void
    @Environment(ReferenceStore.self) private var refs
    @Environment(PatientStore.self) private var patient
    @Environment(TipCenter.self) private var tips
    @State private var device: String?
    @State private var openQuestions: Set<Int> = []
    @State private var tableOpen = false

    var body: some View {
        Group {
            if let d = refs.mcs {
                ToolScroll {
                    VStack(alignment: .leading, spacing: 18) {
                        ToolHeader(eyebrow: "Cardiothoracic", title: "Mechanical Support",
                                   summary: "Pick the device: a few questions to run through, with the numbers behind each.",
                                   tint: Topics.info("cardiacSurgery").fg)
                        DraftBanner(section: "mcs")
                        Text("Which device?").font(PS.serif(size: 18)).foregroundStyle(PS.fg)
                        ChoiceChips(options: d.devices.map { (id: $0.id, label: $0.name) }, selected: device) { id in
                            withAnimation(.snappy) { device = id; openQuestions = [] }
                        }
                        if let id = device, let dev = d.devices.first(where: { $0.id == id }) {
                            deviceCard(dev, d)
                        }
                        footer(d)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 30)
                }
                .sheet(isPresented: $tableOpen) {
                    if let id = device, let dev = d.devices.first(where: { $0.id == id }) {
                        McsTableSheet(device: dev, data: d, onOpen: onOpen)
                    }
                }
                .onAppear { if device == nil { device = preselect(d) } }
            } else {
                ContentUnavailableView("Not available offline yet", systemImage: "wifi.slash", description: Text("This tool arrives with the next refresh."))
            }
        }
        .background(FeedBackground())
        .scrollContentBackground(.hidden)
        .navigationTitle("Mechanical Support")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: device != nil && refs.mcs != nil) {
            // The first visit, once a device's questions are on screen: one tip at the questions.
            guard device != nil, refs.mcs != nil else { return }
            try? await Task.sleep(nanoseconds: 700_000_000)
            withAnimation(.easeOut(duration: 0.25)) { _ = tips.offer(.mcs) }
        }
    }

    /// The device in the current My Patient case, if one is recorded (a screenshot run may name one: -ps.mcs.device).
    private func preselect(_ d: McsData) -> String? {
        #if DEBUG
        let forced = LaunchSeed.string("ps.mcs.device")
        if !forced.isEmpty { return forced }
        #endif
        let kinds = Set(patient.record.devices.filter { !$0.removed }.map(\.kind.rawValue))
        return d.devices.first { dev in (dev.deviceKinds ?? []).contains { kinds.contains($0) } }?.id
    }

    private func deviceCard(_ dev: McsData.Device, _ d: McsData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: dev.detail ?? dev.name)
                Spacer()
                Text("\(dev.questions.count) questions").font(PS.mono(size: 11, weight: .semibold)).foregroundStyle(PS.fg3)
            }
            .padding(.horizontal, 2)
            VStack(spacing: 0) {
                ForEach(Array(dev.questions.enumerated()), id: \.offset) { i, q in
                    let open = openQuestions.contains(i)
                    Button {
                        Haptics.light()
                        withAnimation(.snappy) { if open { openQuestions.remove(i) } else { openQuestions.insert(i) } }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("\(i + 1)").font(PS.mono(size: 12, weight: .bold)).foregroundStyle(PS.accent)
                                Text(q.q).font(PS.sys(size: 15.5, weight: .semibold)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                Image(systemName: open ? "chevron.up" : "chevron.down").font(PS.sys(size: 11, weight: .semibold)).foregroundStyle(PS.fg3)
                            }
                            if open {
                                Text(q.look).font(PS.sys(size: 14)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
                                    .padding(.leading, 22)
                                    .transition(.opacity)
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(open ? "Hides what to look at" : "Shows what to look at")
                    if i < dev.questions.count - 1 { Hairline().padding(.leading, 38) }
                }
            }
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
            .tipFrame(TipSet.mcs.steps[0].target, in: tips)
            if let call = dev.call {
                Label(call, systemImage: "phone.arrow.up.right").font(PS.sys(size: 13.5, weight: .semibold)).foregroundStyle(PS.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Button { tableOpen = true } label: { Label("Device numbers", systemImage: "tablecells") }.buttonStyle(GhostButtonStyle())
                if let s = d.sources(dev.sources ?? []).first, let url = URL(string: s.url) {
                    Button { onOpen(url) } label: { Label("Guideline ↗", systemImage: "doc.text") }.buttonStyle(GhostButtonStyle())
                }
            }
        }
    }

    private func footer(_ d: McsData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Hairline()
            EvidenceDisclosure {
                ForEach(d.cautions, id: \.self) { c in
                    Text("• " + c).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                }
                Text(d.legend).font(PS.sys(size: 12)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                EvidenceLinks(sources: device.flatMap { id in d.devices.first { $0.id == id } }.map { d.sources($0.sources ?? []) } ?? d.sources, onOpen: onOpen)
            }
        }
    }
}

/// One device's numbers, each with its flag.
struct McsTableSheet: View {
    var device: McsData.Device
    var data: McsData
    var onOpen: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    FlagTable(rows: device.rows)
                    Text(data.legend).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                    EvidenceLinks(sources: data.sources(device.sources ?? []), onOpen: onOpen)
                }
                .padding(20)
            }
            .background(FeedBackground())
            .navigationTitle(device.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.large])
    }
}
