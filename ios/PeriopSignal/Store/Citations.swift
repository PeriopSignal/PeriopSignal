import Foundation

/// Citation formats built from the Crossref record the feed carries (`citation`), with a web-page
/// citation as the fallback for FDA notices, society pages and conference reports.
extension Post {
    var doi: String? {
        if let d = citation?.doi, !d.isEmpty { return d }
        if let r = url.range(of: #"doi\.org/(10\.\S+)$"#, options: [.regularExpression, .caseInsensitive]) {
            return String(url[r]).replacingOccurrences(of: #"^.*doi\.org/"#, with: "", options: .regularExpression)
        }
        return nil
    }

    var hasBibliographicRecord: Bool { citation != nil }

    /// Short "Peltan ID, et al." style author line for the deep dive header.
    var authorLine: String {
        guard let c = citation, !c.authors.isEmpty else {
            return firstAuthor.isEmpty ? "" : "\(firstAuthor) et al."
        }
        let a = c.authors
        if a.count == 1 { return a[0] }
        if a.count == 2 { return a[0] + " and " + a[1] }
        return a[0] + ", et al."
    }

    /// AMA 11th edition style. Up to six authors; seven or more lists the first three then "et al".
    var amaCitation: String {
        guard let c = citation else { return fallbackCitation }
        var authors: String
        if c.authors.count > 6 {
            authors = c.authors.prefix(3).joined(separator: ", ") + ", et al"
        } else {
            authors = c.authors.joined(separator: ", ")
        }
        if !authors.isEmpty && !authors.hasSuffix(".") { authors += "." }
        var s = authors.isEmpty ? "" : authors + " "
        var title = c.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.hasSuffix(".") && !title.hasSuffix("?") { title += "." }
        s += title
        if let j = c.journal, !j.isEmpty { s += " " + j + "." }
        var ref = ""
        if let y = c.year { ref += String(y) }
        if let v = c.volume, !v.isEmpty {
            ref += ";" + v
            if let i = c.issue, !i.isEmpty { ref += "(" + i + ")" }
        }
        if let p = c.pages, !p.isEmpty { ref += ":" + p }
        if !ref.isEmpty { s += " " + ref + "." }
        if let d = c.doi, !d.isEmpty { s += " doi:" + d }
        return s
    }

    /// For posts without a journal record: the source page, with the access date.
    var fallbackCitation: String {
        let source = journal.isEmpty ? "Periop Signal" : journal
        let accessed = PSDate.long.string(from: Date())
        var t = (title ?? headline).trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.hasSuffix(".") && !t.hasSuffix("?") { t += "." }
        return "\(source). \(t) Published \(PSDate.display(date, long: true)). Accessed \(accessed). \(url)"
    }

    /// RIS record (EndNote, Zotero, Mendeley, Papers).
    var risRecord: String {
        var lines: [String] = []
        if let c = citation {
            lines.append("TY  - JOUR")
            for a in c.authors {
                // "Peltan ID" -> "Peltan, ID" (RIS wants family, given)
                lines.append("AU  - " + Self.familyGiven(a, initialsSeparator: ""))
            }
            lines.append("TI  - " + c.title)
            if let j = c.journal, !j.isEmpty { lines.append("T2  - " + j); lines.append("JO  - " + j) }
            if let y = c.year { lines.append("PY  - \(y)") }
            if let v = c.volume, !v.isEmpty { lines.append("VL  - " + v) }
            if let i = c.issue, !i.isEmpty { lines.append("IS  - " + i) }
            if let p = c.pages, !p.isEmpty {
                let parts = p.split(separator: "-", maxSplits: 1).map(String.init)
                lines.append("SP  - " + (parts.first ?? p))
                if parts.count == 2 { lines.append("EP  - " + parts[1]) }
            }
            if let d = c.doi, !d.isEmpty { lines.append("DO  - " + d) }
        } else {
            lines.append("TY  - ELEC")
            lines.append("TI  - " + (title ?? headline))
            if !journal.isEmpty { lines.append("PB  - " + journal) }
            lines.append("PY  - " + String(date.prefix(4)))
            lines.append("DA  - " + date.replacingOccurrences(of: "-", with: "/"))
        }
        lines.append("UR  - " + url)
        lines.append("N1  - Periop Signal: " + siteLink.absoluteString)
        lines.append("ER  - ")
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// BibTeX entry, keyed by first author and year.
    var bibtex: String {
        let c = citation
        let firstFamily = (c?.authors.first ?? firstAuthor).split(separator: " ").first.map(String.init) ?? "periopsignal"
        let yearStr = c?.year.map { String($0) } ?? String(date.prefix(4))
        let key = (firstFamily + yearStr).lowercased().filter { $0.isLetter || $0.isNumber }
        func field(_ k: String, _ v: String?) -> String? {
            guard let v, !v.isEmpty else { return nil }
            return "  \(k) = {\(v)}"
        }
        var fields: [String] = []
        if let c {
            let authors = c.authors.map { Self.familyGiven($0, initialsSeparator: ". ", trailing: ".") }
            fields = [field("author", authors.joined(separator: " and ")), field("title", c.title), field("journal", c.journal), field("year", yearStr),
                      field("volume", c.volume), field("number", c.issue), field("pages", c.pages?.replacingOccurrences(of: "-", with: "--")), field("doi", c.doi), field("url", url)].compactMap { $0 }
            return "@article{\(key),\n" + fields.joined(separator: ",\n") + "\n}\n"
        }
        fields = [field("title", title ?? headline), field("howpublished", journal), field("year", yearStr), field("url", url), field("note", "Accessed " + PSDate.long.string(from: Date()))].compactMap { $0 }
        return "@misc{\(key),\n" + fields.joined(separator: ",\n") + "\n}\n"
    }

    /// "Peltan ID" -> "Peltan, ID" (RIS) or "Peltan, I. D." (BibTeX); group authors pass through.
    static func familyGiven(_ a: String, initialsSeparator: String, trailing: String = "") -> String {
        guard let space = a.lastIndex(of: " "), a.range(of: #"^\S+ [A-Z]{1,4}$"#, options: .regularExpression) != nil else { return a }
        let family = String(a[..<space])
        let initials = a[a.index(after: space)...].map { String($0) }.joined(separator: initialsSeparator)
        return family + ", " + initials + trailing
    }

    /// Writes the RIS record to a temporary file for the share sheet (opens in reference managers).
    func risFileURL() -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("citations", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(id + ".ris")
        do {
            try risRecord.write(to: file, atomically: true, encoding: .utf8)
            return file
        } catch {
            return nil
        }
    }
}
