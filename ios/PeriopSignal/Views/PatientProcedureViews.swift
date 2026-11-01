import SwiftUI

// MARK: - Planned procedures (1.6): picked from the procedure list or typed, with the side asked when the procedure
// has one. The list's procedures fill the risk-score inputs (PatientRecord.setProcedures).

private let sideOptions: [(id: String, label: String)] = [(id: "left", label: "Left"), (id: "right", label: "Right"), (id: "bilateral", label: "Bilateral")]

/// One planned procedure: its name, the side when it has one, details, and remove.
struct PlannedProcedureRow: View {
    @Binding var item: PlannedProcedure
    /// The caption under a typed procedure.
    var typedCaption = "Typed: not used for the risk-score inputs"
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    if item.catalogID == nil {
                        TextField("Procedure", text: $item.name)
                            .font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(PS.fg)
                    } else {
                        Text(item.title)
                            .font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(PS.fg)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(caption).font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
                }
                Spacer(minLength: 4)
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash").foregroundStyle(PS.fg3) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(item.title)")
            }
            if item.catalog?.lateral == true {
                if item.needsSide {
                    Label("Which side?", systemImage: "exclamationmark.circle.fill")
                        .font(PS.sys(size: 12.5, weight: .semibold)).foregroundStyle(PS.red)
                }
                PatientChoice(options: sideOptions, selection: $item.side, tint: item.needsSide ? PS.red : PS.accent)
            }
            TextField("Details, e.g. ×3, possible open", text: $item.detail)
                .font(PS.sys(size: 13.5)).foregroundStyle(PS.fg2)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var caption: String {
        guard let p = item.catalog else { return typedCaption }
        return p.specialty
    }
}

/// Search the procedure list by name or abbreviation ("lap chole", "L TKA", "CABG x3 + AVR"); several procedures
/// and a side typed together are read in one go. Anything else can be added as typed.
struct ProcedureSearchField: View {
    var prompt = "Add a procedure, e.g. lap chole, L TKA"
    /// The caption of the "add as typed" row.
    var typedCaption = "Not in the list: the risk-score inputs stay as set"
    var onAdd: ([PlannedProcedure]) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    private var query: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Everything the text names, when it names more than a single list search would show (several procedures, a
    /// side or details).
    private var reading: [PlannedProcedure] {
        guard query.count >= 2 else { return [] }
        let items = PlannedProcedure.parse(query)
        guard items.contains(where: { $0.catalogID != nil }) else { return [] }
        let simple = items.count == 1 && items[0].side == nil && items[0].detail.isEmpty
        return simple ? [] : items
    }

    private var results: [Procedure] {
        guard query.count >= 2 else { return [] }
        return ProcedureCatalog.search(query, limit: 6)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(PS.sys(size: 14)).foregroundStyle(PS.fg3)
                TextField(prompt, text: $text)
                    .focused($focused)
                    .font(PS.sys(size: 15)).foregroundStyle(PS.fg)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .onSubmit(addBest)
                if !text.isEmpty {
                    Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(PS.fg3) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear")
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            if !reading.isEmpty {
                Hairline().padding(.leading, 14)
                suggestion(reading.map(\.text).joined(separator: " + "), caption: reading.count > 1 ? "Add all \(reading.count)" : "Add", strong: true) { add(reading) }
            }
            ForEach(results) { p in
                Hairline().padding(.leading, 14)
                suggestion(p.name, caption: p.specialty + (p.lateral ? " · asks the side" : "")) { add([PlannedProcedure(p)]) }
            }
            if query.count >= 2 {
                Hairline().padding(.leading, 14)
                suggestion("Add “\(query)” as typed", caption: typedCaption, typed: true) {
                    add([PlannedProcedure(name: query)])
                }
            }
        }
    }

    private func suggestion(_ title: String, caption: String, strong: Bool = false, typed: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(PS.sys(size: 14.5, weight: strong ? .semibold : .regular)).foregroundStyle(typed ? PS.fg2 : PS.fg)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(caption).font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
                }
                Spacer(minLength: 4)
                Image(systemName: "plus.circle").font(PS.sys(size: 16)).foregroundStyle(PS.accent)
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func addBest() {
        if !reading.isEmpty { add(reading) }
        else if let p = results.first { add([PlannedProcedure(p)]) }
        else if !query.isEmpty { add([PlannedProcedure(name: query)]) }
    }

    private func add(_ items: [PlannedProcedure]) {
        guard !items.isEmpty else { return }
        Haptics.light()
        withAnimation(.snappy) { onAdd(items) }
        text = ""
    }
}
