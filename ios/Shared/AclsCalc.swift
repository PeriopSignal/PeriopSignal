import Foundation

// MARK: - ACLS code timer
//
// A code is a clock started when the tool opens and a log of what was done, stamped in ms since the start.
// Counts, the last time of each action, the CPR cycle, the drug timers and the prompts are all read back from
// that log, so removing a mistaken entry corrects everything that depends on it. The content (doses, energies,
// prompts, trees, checklists) is reference.json "acls" (AclsData). The website runs the same rules
// (src/reference-logic.js, R.acls); the unit tests mirror each other.

struct AclsEntry: Hashable, Identifiable {
    var id = UUID()
    /// Milliseconds since the start of the code.
    var t: Double
    /// The action, rhythm check or checklist item ("epi", "vf", "chk:causes:hypoxia"); nil for notes.
    var action: String?
    var text: String
}

struct AclsState: Hashable {
    /// Seconds since 1970 when the code started.
    var startedAt: Double
    var mode: String
    var patient: String
    /// Kilograms, for the child doses.
    var weight: Double?
    var log: [AclsEntry] = []
    /// Decision path per "mode:patient".
    var path: [String: [String]] = [:]

    init(startedAt: Double, mode: String = "arrest", patient: String = "adult") {
        self.startedAt = startedAt
        self.mode = mode
        self.patient = patient == "child" ? "child" : "adult"
    }

    mutating func add(_ t: Double, _ action: String?, _ text: String) {
        log.append(AclsEntry(t: max(0, t), action: action, text: text))
        log.sort { $0.t < $1.t }
    }

    mutating func remove(_ e: AclsEntry) { log.removeAll { $0.id == e.id } }
}

struct AclsDose: Hashable {
    var text: String
    var amount: Double?
    var unit: String?
    var volume: Double?
    var needsWeight = false
    var capped = false
}

struct AclsEnergy: Hashable {
    var text: String
    var joules: Int?
    var needsWeight = false
}

struct AclsTimerState: Hashable {
    /// "wait", "due" or "overdue".
    var state: String
    var since: Double
    var remaining: Double
}

struct AclsPromptNow: Hashable, Identifiable {
    var id: String
    var level: String
    var text: String
    var action: String?
    var alert: Bool
}

struct AclsDeadlineNow: Hashable, Identifiable {
    var id: String
    var label: String
    var remaining: Double
}

enum AclsCalc {
    /// 75000 → "1:15"; 3725000 → "1:02:05"; negative values keep their sign.
    static func clock(_ ms: Double) -> String {
        let neg = ms < 0
        let s = Int((Swift.abs(ms) / 1000).rounded(.down))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        let body = h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
        return (neg ? "-" : "") + body
    }

    /// A number as JavaScript's String() prints it for these values: 0.18, 1.8, 90, 0.01.
    static func num(_ v: Double) -> String {
        if v == v.rounded() && Swift.abs(v) < 1e15 { return String(Int(v)) }
        var s = String(format: "%.6f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    /// Rounds a dose sensibly: 2 decimals below 1, 1 below 10, whole above.
    static func round(_ v: Double) -> Double {
        let p: Double = v < 1 ? 100 : v < 10 ? 10 : 1
        return (v * p).rounded() / p
    }

    static func count(_ s: AclsState, _ id: String) -> Int { s.log.filter { $0.action == id }.count }

    static func last(_ s: AclsState, _ id: String) -> Double? { s.log.last { $0.action == id }?.t }

    /// The rhythm of the last rhythm check ("shockable", "nonshockable", "rosc"), or nil.
    static func rhythm(_ s: AclsState, _ d: AclsData) -> String? {
        for e in s.log.reversed() {
            if let id = e.action, let r = d.actions[id]?.rhythm { return r }
        }
        return nil
    }

    static func kg(_ s: AclsState) -> Double? { s.patient == "child" ? s.weight.flatMap { $0 > 0 ? $0 : nil } : nil }

    /// The spec for this patient: a child never falls back to the adult dose.
    static func spec(_ a: AclsAction?, _ patient: String) -> AclsSpec? {
        guard let a else { return nil }
        return patient == "child" ? a.child : a.adult
    }

    static func maxDoses(_ a: AclsAction, _ s: AclsState) -> Int { spec(a, s.patient)?.maxDoses ?? Int.max }

    /// The dose for the nth administration (0-based): fixed for adults, per kg with a cap for children.
    static func dose(_ a: AclsAction, _ s: AclsState, _ n: Int) -> AclsDose? {
        guard var d = spec(a, s.patient) else { return nil }
        if let list = d.doses, !list.isEmpty { d = d.merged(list[min(n, list.count - 1)]) }
        let route = d.route.map { " " + $0 } ?? ""
        let unit = d.unit ?? ""
        if let text = d.text, d.dose == nil, d.perKg == nil { return AclsDose(text: text, amount: nil, unit: d.unit) }
        if let perKg = d.perKg {
            let per = "\(num(perKg)) \(unit)/kg"
            guard let w = kg(s) else {
                return AclsDose(text: per + route + (d.max.map { " (max \(num($0)) \(unit))" } ?? ""), amount: nil, unit: d.unit, needsWeight: true)
            }
            var amount = perKg * w, capped = false, floored = false
            if let mx = d.max, amount > mx { amount = mx; capped = true }
            if let mn = d.min, amount < mn { amount = mn; floored = true }
            amount = round(amount)
            var text = "\(num(amount)) \(unit)\(route)"
            var vol: Double?
            if let c = d.conc {
                vol = round(amount / c.value)
                text += " · \(num(vol!)) mL of \(num(c.value)) \(c.unit)"
            }
            text += capped ? " (the maximum)" : floored ? " (the minimum)" : " (\(per))"
            return AclsDose(text: text, amount: amount, unit: d.unit, volume: vol, capped: capped)
        }
        guard let amount = d.dose else { return nil }
        var text = "\(num(amount)) \(unit)\(route)"
        if let c = d.conc { text += " · \(num(round(amount / c.value))) mL of \(num(c.value)) \(c.unit)" }
        return AclsDose(text: text, amount: amount, unit: d.unit)
    }

    /// Shock energy for the nth shock (0-based): the adult text, or J/kg by shock number for a child.
    static func energy(_ a: AclsAction, _ s: AclsState, _ n: Int) -> AclsEnergy? {
        guard let e = spec(a, s.patient) else { return nil }
        if let seq = e.perKgSeq, !seq.isEmpty {
            let later = n >= seq.count
            let per = later ? (e.thenPerKg ?? seq.last!) : seq[n]
            let atLeast = later && e.thenAtLeast == true ? "≥ " : ""
            guard let w = kg(s) else {
                let upTo = later && e.maxPerKg != nil ? " (up to \(num(e.maxPerKg!)) J/kg\(e.capText.map { " " + $0 } ?? ""))" : ""
                return AclsEnergy(text: "\(atLeast)\(num(per)) J/kg\(upTo)", joules: nil, needsWeight: true)
            }
            // maxJ: the adult ceiling ("or the adult dose, whichever is lower"), so a large child never reads above it
            let raw = Int((per * w).rounded())
            if let cap = e.maxJ, raw > Int(cap) {
                return AclsEnergy(text: "\(Int(cap)) J, the adult dose (\(num(per)) J/kg would be \(raw) J)", joules: Int(cap))
            }
            var upTo = ""
            if later, let mpk = e.maxPerKg {
                let up = Int((mpk * w).rounded())
                if let cap = e.maxJ, up > Int(cap) { upTo = ", up to \(Int(cap)) J (the adult dose)" } else { upTo = ", up to \(up) J" }
            }
            return AclsEnergy(text: "\(atLeast)\(raw) J (\(num(per)) J/kg)\(upTo)", joules: raw)
        }
        return AclsEnergy(text: e.text ?? "", joules: e.joules.map { Int($0) })
    }

    /// Seconds since the start of the current CPR cycle (the last cycle-resetting entry, else the start).
    static func cycle(_ s: AclsState, _ d: AclsData, _ t: Double) -> (from: Double, elapsed: Double) {
        var from = 0.0
        for e in s.log.reversed() where e.t <= t {
            if let id = e.action, d.actions[id]?.cycleReset == true { from = e.t; break }
        }
        return (from, (t - from) / 1000)
    }

    /// A repeatable action's state: next in n s, due, or overdue (seconds since the last dose).
    static func timer(_ a: AclsAction?, _ s: AclsState, _ id: String, _ t: Double) -> AclsTimerState? {
        guard let a, let rep = a.repeats, let lastT = last(s, id) else { return nil }
        if spec(a, s.patient)?.noRepeat == true { return nil }   // e.g. a child's atropine: "may repeat once", no interval printed
        let since = (t - lastT) / 1000
        if since < rep.min { return AclsTimerState(state: "wait", since: since, remaining: rep.min - since) }
        if let mx = rep.max, since >= mx { return AclsTimerState(state: "overdue", since: since, remaining: 0) }
        return AclsTimerState(state: "due", since: since, remaining: 0)
    }

    static func cmp(_ v: Double, _ op: String, _ n: Double) -> Bool {
        switch op {
        case ">=": return v >= n
        case ">": return v > n
        case "<=": return v <= n
        case "<": return v < n
        case "==": return v == n
        default: return false
        }
    }

    /// Whether every condition of a prompt holds.
    static func holds(_ conds: [AclsCond]?, _ s: AclsState, _ d: AclsData, _ t: Double) -> Bool {
        for k in conds ?? [] {
            if let p = k.patient, p != s.patient { return false }
            if let r = k.rhythm, rhythm(s, d) != r { return false }
            if let id = k.done, count(s, id) == 0 { return false }
            if let id = k.not, count(s, id) > 0 { return false }
            if let ids = k.notAny, ids.contains(where: { count(s, $0) > 0 }) { return false }
            if let c = k.count, !cmp(Double(count(s, c.id)), c.op, c.n) { return false }
            if let c = k.countAny, !cmp(Double(c.ids.reduce(0) { $0 + count(s, $1) }), c.op, c.n) { return false }
            if let c = k.countSince {
                let from = last(s, c.sinceId)
                let v = s.log.filter { $0.action == c.id && (from == nil || $0.t > from!) }.count
                if !cmp(Double(v), c.op, c.n) { return false }
            }
            if let c = k.since {
                guard let l = last(s, c.id), cmp((t - l) / 1000, c.op, c.n) else { return false }
            }
            if let c = k.elapsed, !cmp(t / 1000, c.op, c.sec) { return false }
            if let c = k.cycle, !cmp(cycle(s, d, t).elapsed, c.op, c.sec) { return false }
            if k.weight == true && kg(s) == nil { return false }
        }
        return true
    }

    /// Fills {dose:id}, {energy:id}, {count:id} and {next:id} in a prompt's text.
    static func fill(_ text: String, _ s: AclsState, _ d: AclsData) -> String {
        let pattern = try! NSRegularExpression(pattern: "\\{(dose|energy|count|next):([a-z0-9-]+)\\}")
        let ns = text as NSString
        var out = ""
        var cursor = 0
        for m in pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
            let kind = ns.substring(with: m.range(at: 1)), id = ns.substring(with: m.range(at: 2))
            if let a = d.actions[id] {
                let n = count(s, id)
                switch kind {
                case "dose": out += dose(a, s, n)?.text ?? ""
                case "energy": out += energy(a, s, n)?.text ?? ""
                case "next": out += String(n + 1)
                default: out += String(n)
                }
            }
            cursor = m.range.location + m.range.length
        }
        out += ns.substring(from: cursor)
        return out
    }

    static func mode(_ s: AclsState, _ d: AclsData) -> AclsMode? { d.modes.first { $0.id == s.mode } }

    /// The prompts that apply now, in the mode's order.
    static func prompts(_ s: AclsState, _ d: AclsData, _ t: Double) -> [AclsPromptNow] {
        guard let m = mode(s, d) else { return [] }
        var out: [AclsPromptNow] = []
        for p in m.prompts ?? [] {
            if let pt = p.patient, pt != s.patient { continue }
            if !holds(p.when, s, d, t) { continue }
            if let id = p.action, let a = d.actions[id], count(s, id) >= maxDoses(a, s) { continue }
            out.append(AclsPromptNow(id: p.id, level: p.level ?? "info", text: fill(p.text, s, d), action: p.action, alert: p.alert ?? false))
        }
        return out
    }

    /// Deadlines still open; remaining (s) turns negative once passed.
    static func deadlines(_ s: AclsState, _ d: AclsData, _ t: Double) -> [AclsDeadlineNow] {
        (mode(s, d)?.deadlines ?? []).filter { dl in !(dl.until.map { count(s, $0) > 0 } ?? false) }
            .map { AclsDeadlineNow(id: $0.id, label: $0.label, remaining: $0.sec - t / 1000) }
    }

    /// The decision tree of a tree mode for this patient: the path chosen so far and the current node.
    static func tree(_ s: AclsState, _ d: AclsData) -> (tree: AclsTree, path: [String], node: AclsNode, nodeId: String)? {
        guard let m = mode(s, d), let tr = m.tree?[s.patient] ?? m.tree?["all"] else { return nil }
        let path = (s.path[m.id + ":" + s.patient] ?? []).filter { tr.nodes[$0] != nil }
        let cur = path.last ?? tr.start
        guard let node = tr.nodes[cur] else { return nil }
        return (tr, path, node, cur)
    }

    static func choose(_ s: inout AclsState, _ d: AclsData, _ t: Double, next: String, label: String) {
        guard let m = mode(s, d), let tr = tree(s, d) else { return }
        let key = m.id + ":" + s.patient
        s.path[key] = (s.path[key] ?? []) + [next]
        s.add(t, nil, "\(m.short ?? m.name): \(tr.node.q ?? "") \(label)")
    }

    static func back(_ s: inout AclsState, _ d: AclsData) {
        guard let m = mode(s, d) else { return }
        let key = m.id + ":" + s.patient
        if var p = s.path[key], !p.isEmpty { p.removeLast(); s.path[key] = p }
    }

    /// The text logged for an action: "Epinephrine 1 mg IV/IO (dose 2)", "Shock 3: 200 J". `joules` is the
    /// energy typed for this shock; a child's computed energy is used when none is typed.
    static func entryText(_ a: AclsAction, _ s: AclsState, _ n: Int, joules: Double? = nil) -> String {
        switch a.kind {
        case "shock":
            let j: Int? = (joules ?? 0) > 0 ? Int(joules!) : energy(a, s, n)?.joules
            return "\(a.label) \(n + 1)" + (j.map { ": \($0) J" } ?? "")
        case "drug":
            let ds = dose(a, s, n), sp = spec(a, s.patient)
            var amount = ""
            if let ds, let amt = ds.amount { amount = " \(num(amt)) \(ds.unit ?? "")" + (sp?.route.map { " " + $0 } ?? "") }
            return a.label + amount + (n > 0 ? " (dose \(n + 1))" : "")
        default:
            return a.log ?? a.label
        }
    }

    /// The log as text for the record: one line per entry with clock time and code time.
    static func logText(_ s: AclsState, wall: (Double) -> String) -> String {
        let who = s.patient == "child" ? "child" + (kg(s).map { ", \(num($0)) kg" } ?? "") : "adult"
        var lines = ["Code log (\(who)), started \(wall(s.startedAt * 1000))"]
        for e in s.log { lines.append("\(wall(s.startedAt * 1000 + e.t))  +\(clock(e.t))  \(e.text)") }
        return lines.joined(separator: "\n")
    }
}
