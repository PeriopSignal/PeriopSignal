import SwiftUI

/// What the rooms bar has open. Kept outside the view, like a received patient (PatientInbox), so a sheet survives the
/// tab being rebuilt and a screenshot launch reaches the bar that is on screen.
@MainActor
@Observable
final class PatientRoomsUI {
    static let shared = PatientRoomsUI()

    struct Archive: Identifiable {
        let id = UUID()
        /// Screenshot runs: open on the newest summary.
        var opensFirst = false
    }

    var editingRoom = false
    /// The archive sheet; an item, so what it opens on is never read stale.
    var archive: Archive?
    /// The summary open in the archive.
    var archivePath: [UUID] = []
    var confirmEnd = false
    /// Screenshot runs: the launch's presentation has been asked for (once, whichever copy of the bar asks), and its
    /// sheet has appeared.
    @ObservationIgnored var asked = false
    @ObservationIgnored var shown = false

    #if DEBUG
    /// Screenshot runs: opens the room sheet, the archive (on its newest summary) or the end-case dialog, and asks
    /// again when a sheet asked for while the tab was still settling did not appear.
    func openForScreenshot(_ o: String) async {
        for attempt in 0..<3 {
            if attempt > 0 {
                editingRoom = false
                archive = nil
                confirmEnd = false
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            shown = false
            PatientTrace.hit("try")
            switch o {
            case "room": editingRoom = true
            case "archive": archive = Archive()
            case "archive-entry": archive = Archive(opensFirst: true)
            default:
                confirmEnd = true
                return   // a dialog can't say when it has appeared
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if shown { return }
        }
    }
    #endif
}

/// The top of My Patient in one row of chips: a chip for each room the anesthesiologist covers, labelled by room
/// ("OR 12", "EP 3", or "Case 2" without one) over a short procedure line, to switch between in one tap; the current
/// chip highlighted, with small Call and Text icons when its room has a phone; and + to add a case. A chip's context
/// menu and the ⋯ menu hold the room and phone, End case (with Next Patient in the same room) and the case archive.
struct PatientRoomsBar: View {
    @Environment(PatientStore.self) private var patient
    @Environment(\.openURL) private var openURL
    /// The room (or "Case 2") just ended, for the banner.
    @State private var ended: String?

    private var ui: PatientRoomsUI { PatientRoomsUI.shared }
    private var current: PatientCase { patient.currentCase }

    var body: some View {
        @Bindable var ui = PatientRoomsUI.shared
        PatientTrace.hit("rb")
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                chipStrip
                menu
            }
            .frame(minHeight: 44)
            if let ended { endedBanner(ended) }
        }
        .sheet(isPresented: $ui.editingRoom) {
            PatientRoomSheet()
                .environment(patient)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .onAppear { ui.shown = true; PatientTrace.hit("roomShown") }
        }
        .sheet(item: $ui.archive, onDismiss: { ui.archivePath = [] }) { s in
            PatientArchiveView(archive: patient.archive, path: $ui.archivePath, opensFirst: s.opensFirst)
                .presentationDragIndicator(.visible)
                .onAppear { ui.shown = true }
        }
        .confirmationDialog("End \(current.label)?", isPresented: $ui.confirmEnd, titleVisibility: .visible) {
            if current.record.isEmpty {
                Button("Remove Case", role: .destructive) { end(keepSummary: false) }
            } else {
                // The usual turnover: keep the summary and start the next patient in the same room and phone.
                if hasRoom { Button("Next Patient in \(current.room)") { end(keepSummary: true, nextInRoom: true) } }
                Button("End Case & Keep Summary") { end(keepSummary: true) }
                Button("End Without a Summary", role: .destructive) { end(keepSummary: false) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(current.record.isEmpty
                 ? "Nothing has been entered, so no summary is kept."
                 : "The handoff is kept in the case archive on this phone with the date only (no time or room) for \(PatientArchive.retentionLabel(patient.archive.retentionDays)), then deleted. The case is removed"
                   + (hasRoom ? "; Next Patient opens an empty case in \(current.room) with the same phone." : "."))
        }
        .task { await openForScreenshot() }
    }

    // MARK: Chips

    /// The cases, then +, in one row that scrolls sideways; the current case is kept in view.
    private var chipStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(patient.cases) { c in chip(c).id(c.id) }
                    addChip
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 1)
            }
            .onAppear {
                let id = current.id
                DispatchQueue.main.async { proxy.scrollTo(id, anchor: .center) }
            }
            .onChange(of: patient.currentCase.id) { _, id in
                withAnimation(.snappy) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    /// One case: the room (or "Case 2") over its first procedure. The current one is highlighted and, with a room
    /// phone, carries Call and Text.
    private func chip(_ c: PatientCase) -> some View {
        let on = c.id == current.id
        let call = on ? PatientPhone.callURL(c.roomPhone) : nil
        let text = on ? PatientPhone.textURL(c.roomPhone) : nil
        return HStack(spacing: 4) {
            Button { select(c) } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(c.label)
                        .font(PS.sys(size: 13.5, weight: .semibold))
                        .foregroundStyle(on ? PS.fg : PS.fg2)
                    Text(c.detail.isEmpty ? "New case" : c.detail)
                        .font(PS.sys(size: 11))
                        .foregroundStyle(PS.fg3)
                }
                .lineLimit(1)
                .frame(minWidth: 50, maxWidth: 116, alignment: .leading)
                .padding(.leading, 10)
                .padding(.trailing, call == nil && text == nil ? 10 : 2)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(c.label + (c.detail.isEmpty ? "" : ", " + c.detail))
            .accessibilityAddTraits(on ? .isSelected : [])
            .accessibilityHint(on ? "Touch and hold for the room, phone and End case" : "Opens this case")
            if let call {
                contactIcon("phone.fill", tint: PS.green, url: call)
                    .accessibilityLabel("Call \(c.label)")
            }
            if let text {
                contactIcon("message.fill", tint: PS.accent2, url: text)
                    .accessibilityLabel("Text \(c.label)")
            }
        }
        .padding(.trailing, call == nil && text == nil ? 0 : 5)
        .background(on ? PS.accent2.opacity(0.16) : PS.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(on ? PS.accent2 : Color.clear, lineWidth: 1.5))
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contextMenu { chipMenu(c) }
    }

    private func contactIcon(_ icon: String, tint: Color, url: URL) -> some View {
        Button {
            Haptics.light()
            openURL(url)
        } label: {
            Image(systemName: icon)
                .font(PS.sys(size: 11.5, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.15), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var addChip: some View {
        Button { addCase() } label: {
            Image(systemName: "plus")
                .font(PS.sys(size: 14, weight: .semibold))
                .foregroundStyle(PS.accent2)
                .frame(width: 40, height: 40)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(PS.line2, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!patient.canAddCase)
        .opacity(patient.canAddCase ? 1 : 0.4)
        .accessibilityLabel("Add another case")
    }

    // MARK: Menus

    /// "OR 12 · 216-555-0112", or the case and "no room set": the menus' heading.
    private func roomHeading(_ c: PatientCase) -> String {
        let phone = c.roomPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        return c.hasRoom ? c.room + (phone.isEmpty ? " · no phone" : " · " + phone) : c.label + " · no room set"
    }

    private var archiveTitle: String {
        patient.archive.entries.isEmpty ? "Case Archive" : "Case Archive (\(patient.archive.entries.count))"
    }

    /// A chip's context menu: its room and phone, and what can be done with the case.
    @ViewBuilder private func chipMenu(_ c: PatientCase) -> some View {
        Section(roomHeading(c)) {
            if c.id != current.id {
                Button { select(c) } label: { Label("Open \(c.label)", systemImage: "arrow.right.circle") }
            }
            Button { afterMenu(c) { ui.editingRoom = true } } label: { Label(c.hasRoom ? "Room & Phone" : "Set Room & Phone", systemImage: "pencil") }
            if let call = PatientPhone.callURL(c.roomPhone) {
                Button { openURL(call) } label: { Label("Call", systemImage: "phone") }
            }
            if let text = PatientPhone.textURL(c.roomPhone) {
                Button { openURL(text) } label: { Label("Text", systemImage: "message") }
            }
            Button { afterMenu(c) { ui.confirmEnd = true } } label: { Label("End Case…", systemImage: "checkmark.circle") }
        }
        Button { afterMenu(nil) { ui.archive = PatientRoomsUI.Archive() } } label: { Label(archiveTitle, systemImage: "archivebox") }
    }

    /// The current case's room and phone, Add case, End case and the archive.
    private var menu: some View {
        Menu {
            Section(roomHeading(current)) {
                Button { ui.editingRoom = true } label: { Label(current.hasRoom ? "Room & Phone" : "Set Room & Phone", systemImage: "pencil") }
                Button { ui.confirmEnd = true } label: { Label("End Case…", systemImage: "checkmark.circle") }
                if patient.canAddCase {
                    Button { addCase() } label: { Label("Add Case", systemImage: "plus") }
                }
            }
            Button { ui.archive = PatientRoomsUI.Archive() } label: { Label(archiveTitle, systemImage: "archivebox") }
        } label: {
            Image(systemName: "ellipsis")
                .font(PS.sys(size: 15, weight: .bold))
                .foregroundStyle(PS.fg2)
                .frame(width: 34, height: 40)
                .background(PS.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Case actions")
        .accessibilityHint("Room and phone, end the case, add a case, case archive")
    }

    private func endedBanner(_ label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "archivebox.fill").font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.green)
            Text("\(label) ended").font(PS.sys(size: 13.5, weight: .semibold)).foregroundStyle(PS.fg)
            Spacer(minLength: 6)
            if !patient.archive.entries.isEmpty {
                Button("Archive") { ui.archive = PatientRoomsUI.Archive() }
                    .buttonStyle(CapsuleButtonStyle(prominent: false))
            }
            Button { withAnimation(.snappy) { ended = nil } } label: {
                Image(systemName: "xmark").font(PS.sys(size: 11, weight: .bold)).foregroundStyle(PS.fg3).frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(PS.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Actions

    private func select(_ c: PatientCase) {
        guard c.id != current.id else { return }
        Haptics.light()
        withAnimation(.snappy) {
            ended = nil
            patient.selectCase(c.id)
        }
    }

    private func addCase() {
        Haptics.light()
        withAnimation(.snappy) {
            ended = nil
            patient.addCase()
        }
        ui.editingRoom = true
    }

    /// From a chip's context menu: opens that case, then presents a sheet or dialog once the menu has closed (one
    /// asked for while the menu is still closing can be dropped).
    private func afterMenu(_ c: PatientCase?, _ present: @escaping () -> Void) {
        if let c, c.id != current.id { select(c) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { present() }
    }

    private var hasRoom: Bool { !current.room.trimmingCharacters(in: .whitespaces).isEmpty }

    private func end(keepSummary: Bool, nextInRoom: Bool = false) {
        let label = current.label
        let kept = patient.endCase(keepSummary: keepSummary, nextInRoom: nextInRoom) != nil
        Haptics.success()
        withAnimation(.snappy) { ended = kept ? label : nil }
    }

    /// Screenshot runs: -ps.patient.open room | archive | archive-entry | end-case.
    private func openForScreenshot() async {
        #if DEBUG
        let o = LaunchSeed.string("ps.patient.open")
        guard ["room", "archive", "archive-entry", "end-case"].contains(o) else { return }
        // A presentation asked for before the tab has settled can be dropped, so wait until it has; then the shared
        // state asks (and asks again if need be), whichever copy of the bar is on screen.
        PatientTrace.hit("rbTask")
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        let ui = PatientRoomsUI.shared
        if Task.isCancelled { PatientTrace.hit("rbTaskX") }
        guard !Task.isCancelled, !ui.asked else { return }
        ui.asked = true
        Task { @MainActor in await PatientRoomsUI.shared.openForScreenshot(o) }
        #endif
    }
}

/// The current case's room and phone, typed or picked from the rooms saved on this phone, so each room's number is
/// typed once. Rooms are hospital details, kept apart from the patient.
struct PatientRoomSheet: View {
    @Environment(PatientStore.self) private var patient
    @Environment(\.dismiss) private var dismiss
    @State private var room = ""
    @State private var phone = ""
    @State private var remember = true
    /// The phone a saved room filled in; a phone typed by hand is never replaced.
    @State private var filledPhone: String?
    @FocusState private var focus: Field?

    private enum Field { case room, phone }

    private var directory: PatientRoomDirectory { patient.rooms }
    private var trimmedRoom: String { room.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PatientGroup(title: patient.currentCase.hasRoom ? "This case" : patient.currentCase.label) {
                        field("Room") {
                            TextField("e.g. OR 12, CVOR 3, EP 2", text: $room)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .submitLabel(.next)
                                .focused($focus, equals: .room)
                                .onSubmit { focus = .phone }
                        }
                        Hairline().padding(.leading, 14)
                        field("Room phone") {
                            TextField("e.g. 216-555-0112", text: $phone)
                                .keyboardType(.phonePad)
                                .textContentType(.telephoneNumber)
                                .focused($focus, equals: .phone)
                        }
                        Hairline().padding(.leading, 14)
                        Toggle(isOn: $remember) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Save to my rooms").font(PS.sys(size: 15)).foregroundStyle(PS.fg)
                                Text("Type a room's phone once; pick the room next time.").font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
                            }
                        }
                        .tint(PS.accent)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                    }
                    savedRooms
                    EvidenceNote("A room and its phone are hospital details, not patient details: never a patient's name, record number or bed. They stay on this phone and are not backed up. Call and Text open the Phone and Messages apps; send patient information only through channels your institution approves.", title: "Hospital details only")
                        .padding(.horizontal, 2)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(FeedBackground())
            .navigationTitle("Room & Phone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { save() }.fontWeight(.semibold) }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { Keyboard.dismiss() }
                }
            }
        }
        .onAppear {
            room = patient.currentCase.room
            phone = patient.currentCase.roomPhone
        }
        .onChange(of: room) { _, new in
            // A saved room fills its phone, unless one was typed.
            let auto = filledPhone != nil && phone == filledPhone
            if let saved = directory.room(named: new) {
                if phone.isEmpty || auto {
                    phone = saved.phone
                    filledPhone = saved.phone
                }
            } else if auto {
                phone = ""
                filledPhone = nil
            }
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg2)
            content()
                .font(PS.sys(size: 16))
                .foregroundStyle(PS.fg)
                .padding(10)
                .background(PS.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    @ViewBuilder private var savedRooms: some View {
        let exact = directory.room(named: room)
        let list = directory.matches(exact == nil ? room : "")
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "My rooms").padding(.leading, 2)
            if directory.rooms.isEmpty {
                Text("Rooms you save appear here with their phones.")
                    .font(PS.sys(size: 13.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, r in
                        savedRow(r, on: exact?.id == r.id)
                        if i < list.count - 1 { Hairline().padding(.leading, 14) }
                    }
                    if list.isEmpty {
                        Text("No saved room matches; Done saves this one.")
                            .font(PS.sys(size: 13)).foregroundStyle(PS.fg3)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 4)
                .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
            }
        }
    }

    private func savedRow(_ r: PatientRoom, on: Bool) -> some View {
        HStack(spacing: 12) {
            Button {
                Haptics.light()
                room = r.name
                phone = r.phone
                filledPhone = r.phone
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: on ? "checkmark.circle.fill" : "door.left.hand.closed")
                        .font(PS.sys(size: 14, weight: .semibold))
                        .foregroundStyle(on ? PS.green : PS.fg3)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.name).font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(PS.fg)
                        Text(r.phone.isEmpty ? "No phone saved" : r.phone).font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3)
                    }
                    Spacer(minLength: 6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Use \(r.name)" + (r.phone.isEmpty ? "" : ", \(r.phone)"))
            Button {
                Haptics.light()
                withAnimation(.snappy) { directory.remove(r.id) }
            } label: {
                Image(systemName: "trash").font(PS.sys(size: 13.5, weight: .semibold)).foregroundStyle(PS.fg3)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(r.name) from my rooms")
        }
        .padding(.leading, 14).padding(.trailing, 8).padding(.vertical, 8)
    }

    private func save() {
        patient.setRoom(room, phone: phone, remember: remember && !trimmedRoom.isEmpty)
        Haptics.success()
        dismiss()
    }
}
