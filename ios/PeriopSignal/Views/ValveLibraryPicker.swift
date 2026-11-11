import SwiftUI

// MARK: - The valve library's picker (1.12, note 4)
//
// "Library" beside a prosthesis field opens this sheet: the valves of ValveLibrary, grouped by position and kind, then a
// size. Choosing writes text into the field as if it had been typed; the field stays free text. The list is a draft
// for Ben to edit in ValveLibrary.swift.

/// The "Library" control that sits beside a prosthesis field.
struct ValveLibraryButton: View {
    /// The valve the field belongs to; nil lists every position.
    var position: ValvePosition?
    /// Only this kind's valves (the echo's kind chip is chosen); nil lists every kind.
    var kind: ValveKind? = nil
    var onChoose: (ValveChoice) -> Void
    @State private var open = false

    var body: some View {
        Button {
            Haptics.light()
            open = true
        } label: {
            Label("Library", systemImage: "books.vertical")
                .font(PS.sys(size: 14, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 11).frame(minHeight: 40)
                .background(PS.action.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(PS.action)
        .accessibilityLabel(position.map { "Valve library, " + $0.label.lowercased() } ?? "Valve library")
        .accessibilityHint("Choose a valve and size to write into the field")
        .sheet(isPresented: $open) {
            ValveLibraryPicker(position: position, kind: kind) { choice in
                onChoose(choice)
                open = false
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        #if DEBUG
        // Screenshot runs: -ps.valve.library <position> opens that position's picker once the page is up.
        .task {
            guard let p = position, LaunchSeed.string("ps.valve.library") == p.rawValue else { return }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            open = true
        }
        #endif
    }
}

/// The sheet: positions and kinds as headings, a valve per row; a valve opens its sizes.
struct ValveLibraryPicker: View {
    var position: ValvePosition?
    var kind: ValveKind? = nil
    var onChoose: (ValveChoice) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var path: [ValveRow] = []

    private var positions: [ValvePosition] { position.map { [$0] } ?? ValvePosition.allCases }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(positions) { p in
                    ForEach(ValveLibrary.kinds(at: p).filter { kind == nil || $0 == kind }) { k in
                        Section {
                            ForEach(ValveLibrary.rows(at: p, k)) { row in
                                NavigationLink(value: row) {
                                    Text(row.title)
                                        .font(PS.sys(size: 16))
                                        .foregroundStyle(row.name.isEmpty ? PS.fg2 : PS.fg)
                                }
                                .listRowBackground(PS.surface)
                            }
                        } header: {
                            Text(p.label + " · " + k.label)
                                .font(PS.sys(size: 13, weight: .semibold))
                                .foregroundStyle(PS.fg2)
                                .textCase(nil)
                        }
                    }
                }
                Section {
                    Text("A draft list of common valves. It only writes text into the field; the field can still be typed in.")
                        .font(PS.sys(size: 12.5))
                        .foregroundStyle(PS.fg3)
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(PS.bg)
            .navigationTitle(position.map { $0.label + " valve" } ?? "Valve library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .navigationDestination(for: ValveRow.self) { row in
                ValveSizePage(row: row, onChoose: onChoose)
            }
        }
        #if DEBUG
        // Screenshot runs: -ps.valve.library.row "<name>" also opens that valve's sizes.
        .task {
            let want = LaunchSeed.string("ps.valve.library.row")
            guard !want.isEmpty, path.isEmpty else { return }
            try? await Task.sleep(nanoseconds: 800_000_000)
            if let row = ValveLibrary.rows.first(where: { r in positions.contains(r.position) && r.title == want }) { path = [row] }
        }
        #endif
    }
}

/// A valve's sizes: its own, the generic row, or a typed one.
struct ValveSizePage: View {
    var row: ValveRow
    var onChoose: (ValveChoice) -> Void
    @State private var typed = ""
    @FocusState private var focused: Bool

    private var sizes: [Int] { ValveLibrary.sizes(for: row) }
    private let columns = [GridItem(.adaptive(minimum: 74), spacing: 8)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(row.position.label + " · " + row.kind.label)
                    .font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg2)
                if !sizes.isEmpty {
                    Text("Size").font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg2)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                        ForEach(sizes, id: \.self) { s in
                            Button {
                                Haptics.light()
                                onChoose(ValveChoice(row: row, size: String(s)))
                            } label: {
                                Text("\(s) mm")
                                    .font(PS.sys(size: 15, weight: .semibold))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(PS.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(PS.fg)
                            .accessibilityLabel("\(s) millimetres")
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(sizes.isEmpty ? "Size (optional)" : "Another size").font(PS.sys(size: 13, weight: .semibold)).foregroundStyle(PS.fg2)
                    TextField("e.g. 27", text: $typed)
                        .focused($focused)
                        .font(PS.sys(size: 15)).foregroundStyle(PS.fg)
                        .padding(10)
                        .background(PS.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .submitLabel(.done)
                        .onSubmit { choose() }
                }
                Button {
                    Haptics.light()
                    choose()
                } label: {
                    Text(typed.trimmingCharacters(in: .whitespaces).isEmpty ? "Use without a size" : "Use this size")
                        .font(PS.sys(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(PS.action.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(PS.action)
            }
            .padding(16)
        }
        .background(PS.bg)
        .navigationTitle(row.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func choose() {
        onChoose(ValveChoice(row: row, size: typed))
    }
}
