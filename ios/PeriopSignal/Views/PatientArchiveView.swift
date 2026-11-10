import LocalAuthentication
import SwiftUI

/// Face ID, Touch ID or the passcode for the case archive (LocalAuthentication); off unless turned on.
enum ArchiveLock {
    static var available: Bool { LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) }

    /// "Face ID or passcode".
    static var label: String {
        let c = LAContext()
        _ = c.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch c.biometryType {
        case .faceID: return "Face ID or passcode"
        case .touchID: return "Touch ID or passcode"
        default: return "Passcode"
        }
    }

    static func unlock(_ reason: String) async -> Bool {
        let c = LAContext()
        c.localizedFallbackTitle = "Use Passcode"
        guard c.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return false }
        return (try? await c.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

/// Ended cases' summaries, by date: read, copy or share one, swipe to delete, or delete all. Each keeps the date only
/// (no time or room) and is deleted after the retention period chosen here.
struct PatientArchiveView: View {
    var archive: PatientArchive
    /// The summary open (kept by the caller, so it survives the sheet being rebuilt).
    @Binding var path: [UUID]
    /// Screenshot runs: open the newest summary.
    var opensFirst = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var unlocked = false
    @State private var confirmDeleteAll = false

    private var locked: Bool { archive.lockEnabled && !unlocked }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if locked { lockedView } else { list }
            }
            .background(FeedBackground())
            .navigationTitle("Case Archive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.fontWeight(.semibold) }
            }
            .navigationDestination(for: UUID.self) { id in
                if let e = archive.entries.first(where: { $0.id == id }) {
                    PatientArchiveDetail(entry: e, retentionDays: archive.retentionDays) {
                        archive.delete(id)
                        path.removeAll()
                    }
                } else {
                    Text("This summary has been deleted.").font(PS.sys(size: 15)).foregroundStyle(PS.fg3)
                }
            }
        }
        .task {
            archive.prune()
            if archive.lockEnabled { unlocked = await ArchiveLock.unlock("Open the case archive") }
            if opensFirst {
                // Pushed once the sheet has settled (never behind the lock).
                try? await Task.sleep(nanoseconds: 700_000_000)
                if !locked, let first = archive.byDay.first?.entries.first { path = [first.id] }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Locked again when the app leaves the screen; past-due summaries go when it comes back.
            if phase == .background && archive.lockEnabled {
                unlocked = false
                path.removeAll()
            }
            if phase == .active { archive.prune() }
        }
        .confirmationDialog("Delete every summary?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) {
                withAnimation(.snappy) { archive.deleteAll() }
                Haptics.success()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All \(archive.entries.count) archived summaries are removed from this phone. This can't be undone.")
        }
    }

    // MARK: Locked

    private var lockedView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(PS.sys(size: 30, weight: .semibold))
                .foregroundStyle(PS.action)
                .frame(width: 64, height: 64)
                .background(PS.action.opacity(0.12), in: Circle())
            Text("The case archive is locked").font(PS.serif(size: 22)).foregroundStyle(PS.fg)
            Text("Unlock with " + ArchiveLock.label + ".")
                .font(PS.sys(size: 14)).foregroundStyle(PS.fg2)
            Button {
                Task { unlocked = await ArchiveLock.unlock("Open the case archive") }
            } label: { Label("Unlock", systemImage: "faceid").frame(maxWidth: .infinity) }
                .buttonStyle(BigButtonStyle(prominent: true, color: PS.action))
                .padding(.horizontal, 40)
            Spacer()
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: List

    private var list: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Summaries of the cases you ended, kept on this phone with the date only: no time and no room.")
                        .font(PS.sys(size: 13.5)).foregroundStyle(PS.fg2).fixedSize(horizontal: false, vertical: true)
                    Text("Delete after").font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg2)
                    Picker("Delete after", selection: Binding(get: { archive.retentionDays }, set: { d in withAnimation(.snappy) { archive.setRetention(d) } })) {
                        ForEach(PatientArchive.retentionChoices, id: \.self) { Text(PatientArchive.retentionLabel($0)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text("A summary is deleted at the first midnight after this period, since only its date is kept.")
                        .font(PS.sys(size: 12)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
                Toggle(isOn: Binding(get: { archive.lockEnabled }, set: { setLock($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lock with " + ArchiveLock.label).font(PS.sys(size: 15)).foregroundStyle(PS.fg)
                        Text(ArchiveLock.available || archive.lockEnabled ? "Asked each time the archive opens." : "Set a passcode on this iPhone to use the lock.")
                            .font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
                    }
                }
                .tint(PS.action)
                .disabled(!ArchiveLock.available && !archive.lockEnabled)
            }
            .listRowBackground(PS.surface)

            if archive.entries.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No summaries").font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(PS.fg)
                        Text("End a case from the ⋯ menu at the top of My Patient and its handoff is kept here.")
                            .font(PS.sys(size: 13.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(PS.surface)
            }

            ForEach(archive.byDay) { group in
                Section {
                    ForEach(group.entries) { e in
                        NavigationLink(value: e.id) { row(e) }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    withAnimation(.snappy) { archive.delete(e.id) }
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                } header: {
                    Text(PatientArchiveWriter.label(group.day)).font(PS.mono(size: 11)).foregroundStyle(PS.fg3)
                }
                .listRowBackground(PS.surface)
            }

            if !archive.entries.isEmpty {
                Section {
                    Button(role: .destructive) { confirmDeleteAll = true } label: {
                        Label("Delete All", systemImage: "trash").font(PS.sys(size: 15, weight: .semibold))
                    }
                    .tint(PS.red)
                } footer: {
                    Text("Kept on this phone only: not backed up, and never sent anywhere unless you copy or share a summary.")
                        .font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
                }
                .listRowBackground(PS.surface)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func row(_ e: PatientArchiveEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(e.procedure).font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(PS.fg).lineLimit(2)
            if !e.oneLiner.isEmpty {
                Text(e.oneLiner).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg2).lineLimit(1)
            }
            Text(PatientArchiveDetail.keptText(e, retentionDays: archive.retentionDays))
                .font(PS.sys(size: 11.5)).foregroundStyle(PS.fg3)
        }
        .padding(.vertical, 3)
    }

    private func setLock(_ on: Bool) {
        if on {
            // Check it works before relying on it.
            Task {
                if await ArchiveLock.unlock("Lock the case archive") {
                    archive.setLock(true)
                    unlocked = true
                }
            }
        } else {
            archive.setLock(false)
        }
    }
}

/// One archived summary, read-only: the procedure line, then the full handoff to copy or share.
struct PatientArchiveDetail: View {
    var entry: PatientArchiveEntry
    var retentionDays: Int
    var onDelete: () -> Void
    @State private var sharing = false
    @State private var copied = false
    @State private var confirmDelete = false

    /// "Kept through Fri 6 Nov": the last day before the summary is deleted.
    nonisolated static func keptText(_ e: PatientArchiveEntry, retentionDays: Int, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let end = e.expires(retentionDays: retentionDays, calendar: calendar),
              let last = calendar.date(byAdding: .day, value: -1, to: end) else { return "" }
        return "Kept through " + PatientArchiveWriter.label(PatientArchiveWriter.day(last, calendar: calendar), now: now, calendar: calendar).lowercasedTodayYesterday
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: PatientArchiveWriter.label(entry.day))
                    Text(entry.procedure).font(PS.serif(size: 22)).foregroundStyle(PS.fg).fixedSize(horizontal: false, vertical: true)
                    Text(Self.keptText(entry, retentionDays: retentionDays)).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3)
                }
                Text(entry.text)
                    .font(PS.sys(size: 14.5))
                    .foregroundStyle(PS.fg)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
                HStack(spacing: 10) {
                    Button { sharing = true } label: { Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }
                        .buttonStyle(BigButtonStyle(prominent: true, color: PS.action))
                    Button { UIPasteboard.general.string = entry.text; copied.toggle() } label: { Label("Copy", systemImage: "doc.on.doc").frame(maxWidth: .infinity) }
                        .buttonStyle(BigButtonStyle(prominent: false))
                }
                EvidenceNote("Share only through channels your institution approves for patient information.", title: "Approved channels only")
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Delete Summary", systemImage: "trash").foregroundStyle(PS.red)
                }
                .buttonStyle(GhostButtonStyle())
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(FeedBackground())
        .navigationTitle("Summary")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: copied)
        .sheet(isPresented: $sharing) {
            ShareSheet(items: [entry.text]).presentationDetents([.medium, .large])
        }
        .confirmationDialog("Delete this summary?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Summary", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private extension String {
    /// "Kept through today" rather than "Kept through Today".
    var lowercasedTodayYesterday: String { self == "Today" || self == "Yesterday" ? lowercased() : self }
}
