import Foundation

// MARK: - Prosthetic valve library (1.12, note 4)
//
// A DRAFT LIST FOR BEN TO EDIT. Every row below is one line of plain data: position, kind, name (and, for a few
// models, the sizes that model comes in). To add, rename or remove a valve, edit the `rows` list only; nothing else in
// the app needs to change. A row's name is a manufacturer's product name as it is sold; the library says nothing about
// a valve beyond its name, and nothing about its haemodynamics, MRI conditions or the sizes of a model that is not
// listed with sizes of its own.
//
// The picker (ValveLibraryPicker) offers a valve and a size; choosing writes text into the field it sits beside, as if
// it had been typed ("23 mm Magna Ease"), so everything that reads that field is unchanged and free text still works.
//
// Sizes: a row with `sizes: nil` offers the generic surgical row (19 to 33 mm, odd numbers) and a typed size; a row
// with `sizes: []` (rings, clips, devices whose sizes this list does not state) offers a typed size only; a row with
// its own sizes offers those (SAPIEN 3: 20, 23, 26, 29; Evolut: 23, 26, 29, 34, as Ben wrote them).

/// The valve a prosthesis or repair is in.
enum ValvePosition: String, CaseIterable, Hashable, Identifiable {
    case aortic, mitral, tricuspid, pulmonic

    var id: String { rawValue }
    var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// What kind of prosthesis or repair.
enum ValveKind: String, CaseIterable, Hashable, Identifiable {
    case bioprosthetic, mechanical, transcatheter, repair

    var id: String { rawValue }

    /// The heading in the picker.
    var label: String {
        switch self {
        case .bioprosthetic: return "Surgical bioprosthetic"
        case .mechanical: return "Mechanical"
        case .transcatheter: return "Transcatheter"
        case .repair: return "Repair: ring / clip"
        }
    }

    /// The word written in the history's prosthesis text ("bioprosthetic 23 mm Magna Ease").
    var word: String {
        switch self {
        case .bioprosthetic: return "bioprosthetic"
        case .mechanical: return "mechanical"
        case .transcatheter: return "transcatheter"
        case .repair: return "repair"
        }
    }

    /// The echo's own kind chip (EchoValve.prostheses) for this kind.
    var echoKind: String {
        switch self {
        case .bioprosthetic: return "Bioprosthetic"
        case .mechanical: return "Mechanical"
        case .transcatheter: return "Transcatheter"
        case .repair: return "Repair or ring"
        }
    }

    /// The kind an echo valve's kind chip names ("Bioprosthetic", "Repair or ring"); nil for empty or free text.
    static func fromEcho(_ kind: String) -> ValveKind? {
        allCases.first { $0.echoKind.caseInsensitiveCompare(kind.trimmingCharacters(in: .whitespaces)) == .orderedSame }
    }
}

/// One line of the library.
struct ValveRow: Hashable, Identifiable {
    var position: ValvePosition
    var kind: ValveKind
    /// As the manufacturer names it; "" for the row that stands for a valve not on the list (the kind and the size only).
    var name: String
    /// nil: the generic surgical sizes; []: a typed size only; otherwise this model's own sizes, in mm.
    var sizes: [Int]?

    var id: String { position.rawValue + "|" + kind.rawValue + "|" + name }

    /// What the picker calls the row.
    var title: String { name.isEmpty ? "Model not listed" : name }

    init(_ position: ValvePosition, _ kind: ValveKind, _ name: String, sizes: [Int]? = nil) {
        self.position = position
        self.kind = kind
        self.name = name
        self.sizes = sizes
    }
}

/// What a choice in the picker writes.
struct ValveChoice: Hashable {
    var row: ValveRow
    /// "23 mm", "27", "" for none, as chosen or typed.
    var size: String

    /// The detail as the echo's prosthesis-details field holds it ("23 mm Magna Ease"); the kind is the chip beside it.
    var detail: String { ValveLibrary.detail(row, size: size) }

    /// The text for the history's prosthesis field ("bioprosthetic 23 mm Magna Ease"): the kind first, as it is typed there
    /// ("mechanical 23 mm").
    var historyText: String { [row.kind.word, detail].filter { !$0.isEmpty }.joined(separator: " ") }
}

enum ValveLibrary {
    /// The generic surgical sizes, mm.
    static let genericSizes = [19, 21, 23, 25, 27, 29, 31, 33]

    // The list. Position, kind, name; sizes only where the model's own are certain.
    static let rows: [ValveRow] = [
        // Aortic
        ValveRow(.aortic, .bioprosthetic, "Perimount"),
        ValveRow(.aortic, .bioprosthetic, "Magna Ease"),
        ValveRow(.aortic, .bioprosthetic, "Inspiris Resilia"),
        ValveRow(.aortic, .bioprosthetic, "Mosaic"),
        ValveRow(.aortic, .bioprosthetic, "Hancock II"),
        ValveRow(.aortic, .bioprosthetic, "Avalus"),
        ValveRow(.aortic, .bioprosthetic, "Epic"),
        ValveRow(.aortic, .bioprosthetic, "Trifecta"),
        ValveRow(.aortic, .bioprosthetic, "Perceval (sutureless)"),
        ValveRow(.aortic, .bioprosthetic, "Intuity (rapid deployment)"),
        ValveRow(.aortic, .bioprosthetic, "Freestyle (stentless)"),
        ValveRow(.aortic, .bioprosthetic, ""),
        ValveRow(.aortic, .mechanical, "St. Jude Regent"),
        ValveRow(.aortic, .mechanical, "St. Jude Masters"),
        ValveRow(.aortic, .mechanical, "On-X"),
        ValveRow(.aortic, .mechanical, "ATS Open Pivot"),
        ValveRow(.aortic, .mechanical, "CarboMedics"),
        ValveRow(.aortic, .mechanical, "Medtronic Hall"),
        ValveRow(.aortic, .mechanical, ""),
        ValveRow(.aortic, .transcatheter, "SAPIEN 3", sizes: [20, 23, 26, 29]),
        ValveRow(.aortic, .transcatheter, "SAPIEN 3 Ultra", sizes: [20, 23, 26, 29]),
        ValveRow(.aortic, .transcatheter, "Evolut R", sizes: [23, 26, 29, 34]),
        ValveRow(.aortic, .transcatheter, "Evolut PRO", sizes: [23, 26, 29, 34]),
        ValveRow(.aortic, .transcatheter, "Evolut FX", sizes: [23, 26, 29, 34]),
        ValveRow(.aortic, .transcatheter, "Navitor", sizes: []),
        ValveRow(.aortic, .transcatheter, "", sizes: []),
        // Mitral
        ValveRow(.mitral, .bioprosthetic, "Perimount Magna Mitral Ease"),
        ValveRow(.mitral, .bioprosthetic, "Mosaic"),
        ValveRow(.mitral, .bioprosthetic, "Hancock II"),
        ValveRow(.mitral, .bioprosthetic, "Epic"),
        ValveRow(.mitral, .bioprosthetic, ""),
        ValveRow(.mitral, .mechanical, "St. Jude Masters"),
        ValveRow(.mitral, .mechanical, "On-X"),
        ValveRow(.mitral, .mechanical, "ATS Open Pivot"),
        ValveRow(.mitral, .mechanical, "CarboMedics"),
        ValveRow(.mitral, .mechanical, ""),
        ValveRow(.mitral, .transcatheter, "SAPIEN 3 (valve-in-valve)", sizes: [20, 23, 26, 29]),
        ValveRow(.mitral, .transcatheter, "", sizes: []),
        ValveRow(.mitral, .repair, "Physio II ring", sizes: []),
        ValveRow(.mitral, .repair, "Physio ring", sizes: []),
        ValveRow(.mitral, .repair, "Cosgrove-Edwards band", sizes: []),
        ValveRow(.mitral, .repair, "Memo 3D ring", sizes: []),
        ValveRow(.mitral, .repair, "Profile 3D ring", sizes: []),
        ValveRow(.mitral, .repair, "CG Future ring", sizes: []),
        ValveRow(.mitral, .repair, "MitraClip", sizes: []),
        ValveRow(.mitral, .repair, "PASCAL", sizes: []),
        ValveRow(.mitral, .repair, "", sizes: []),
        // Tricuspid
        ValveRow(.tricuspid, .bioprosthetic, "Mosaic"),
        ValveRow(.tricuspid, .bioprosthetic, "Hancock II"),
        ValveRow(.tricuspid, .bioprosthetic, "Epic"),
        ValveRow(.tricuspid, .bioprosthetic, ""),
        ValveRow(.tricuspid, .mechanical, ""),
        ValveRow(.tricuspid, .transcatheter, "EVOQUE", sizes: []),
        ValveRow(.tricuspid, .transcatheter, "", sizes: []),
        ValveRow(.tricuspid, .repair, "Contour 3D ring", sizes: []),
        ValveRow(.tricuspid, .repair, "MC3 ring", sizes: []),
        ValveRow(.tricuspid, .repair, "Tri-Ad band", sizes: []),
        ValveRow(.tricuspid, .repair, "TriClip", sizes: []),
        ValveRow(.tricuspid, .repair, "PASCAL", sizes: []),
        ValveRow(.tricuspid, .repair, "", sizes: []),
        // Pulmonic
        ValveRow(.pulmonic, .bioprosthetic, ""),
        ValveRow(.pulmonic, .transcatheter, "Melody", sizes: []),
        ValveRow(.pulmonic, .transcatheter, "Harmony", sizes: []),
        ValveRow(.pulmonic, .transcatheter, "SAPIEN 3", sizes: []),
        ValveRow(.pulmonic, .transcatheter, "", sizes: []),
    ]

    /// The kinds with at least one row at a position, in the order of ValveKind.
    static func kinds(at position: ValvePosition) -> [ValveKind] {
        ValveKind.allCases.filter { k in rows.contains { $0.position == position && $0.kind == k } }
    }

    static func rows(at position: ValvePosition, _ kind: ValveKind) -> [ValveRow] {
        rows.filter { $0.position == position && $0.kind == kind }
    }

    /// The sizes the picker offers for a row, in mm (empty: type one).
    static func sizes(for row: ValveRow) -> [Int] {
        guard let own = row.sizes else { return genericSizes }
        return own
    }

    /// "23" or "23 mm" or "23mm" → "23 mm"; any other text (a size with letters, "27/29") as typed, trimmed.
    static func sizeText(_ typed: String) -> String {
        let t = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "" }
        let digits = t.lowercased().replacingOccurrences(of: "mm", with: "").trimmingCharacters(in: .whitespaces)
        if let n = Double(digits), n > 0, n < 100 { return NumText.short(n) + " mm" }
        return t
    }

    /// "23 mm Magna Ease" (the size, then the model); a row with no model gives the size alone, and with neither, "".
    static func detail(_ row: ValveRow, size: String) -> String {
        [sizeText(size), row.name].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// The valve a history or echo field belongs to ("aortic", "mitral", ...), as a position.
    static func position(_ valve: String) -> ValvePosition? { ValvePosition(rawValue: valve.lowercased()) }
}
