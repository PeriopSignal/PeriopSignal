import Foundation

// MARK: - Massive transfusion tally
//
// Each tap is an entry with its time; the ratio, the calcium and lab prompts and the fibrinogen estimate are read back
// from the entries and reference.json "mtp" (MtpData), so removing a mistaken tap corrects them all. A tally tap is not
// a verified dose. The tally lives on the phone (MtpStore) and holds no patient details.

struct MtpEntry: Codable, Equatable, Identifiable {
    var id = UUID()
    var time: Date
    /// MtpData.Product id, or "calcium", "txa", "labs".
    var product: String
    var qty: Double = 1
    /// The calcium salt ("chloride", "gluconate") or the TXA context.
    var detail: String?
    /// The My Patient case it was also added to, so removing it removes it there too.
    var caseID: UUID?
}

struct MtpState: Codable, Equatable {
    var started: Date
    var entries: [MtpEntry] = []
    /// Units per platelet dose, for the ratio (4–6).
    var plateletUnits: Double
    /// Single-donor units per cryo pool.
    var cryoPool: Double
    var txaContext = "trauma"
    var injury: Date?
    /// Also add products to the open My Patient case (off unless switched on).
    var addToCase = false
    /// The latest values typed in, for the prompts (not stored as labs anywhere else).
    var ica: Double?
    /// When `ica` was typed in.
    var icaTime: Date?
    var fibrinogen: Double?
    var fibtem: Double?
    var tegFF: Double?
    /// "rotem" or "teg": which viscoelastic fields the screen shows.
    var vha = "rotem"
    var extemCa5: Double?
    var extemLi30: Double?
    var rtegMa: Double?
    var rtegLy30: Double?
    var potassium: Double?
    var inr: Double?

    init(started: Date, data: MtpData) {
        self.started = started
        plateletUnits = data.plateletUnits.default
        cryoPool = data.cryoPool.default
        addToCase = data.addToCaseDefault ?? false
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        started = (try? c.decodeIfPresent(Date.self, forKey: .started)) ?? Date()
        entries = (try? c.decodeIfPresent([MtpEntry].self, forKey: .entries)) ?? []
        plateletUnits = (try? c.decodeIfPresent(Double.self, forKey: .plateletUnits)) ?? 6
        cryoPool = (try? c.decodeIfPresent(Double.self, forKey: .cryoPool)) ?? 5
        txaContext = (try? c.decodeIfPresent(String.self, forKey: .txaContext)) ?? "trauma"
        injury = try? c.decodeIfPresent(Date.self, forKey: .injury)
        addToCase = (try? c.decodeIfPresent(Bool.self, forKey: .addToCase)) ?? false
        ica = try? c.decodeIfPresent(Double.self, forKey: .ica)
        icaTime = try? c.decodeIfPresent(Date.self, forKey: .icaTime)
        fibrinogen = try? c.decodeIfPresent(Double.self, forKey: .fibrinogen)
        fibtem = try? c.decodeIfPresent(Double.self, forKey: .fibtem)
        tegFF = try? c.decodeIfPresent(Double.self, forKey: .tegFF)
        vha = (try? c.decodeIfPresent(String.self, forKey: .vha)) ?? "rotem"
        extemCa5 = try? c.decodeIfPresent(Double.self, forKey: .extemCa5)
        extemLi30 = try? c.decodeIfPresent(Double.self, forKey: .extemLi30)
        rtegMa = try? c.decodeIfPresent(Double.self, forKey: .rtegMa)
        rtegLy30 = try? c.decodeIfPresent(Double.self, forKey: .rtegLy30)
        potassium = try? c.decodeIfPresent(Double.self, forKey: .potassium)
        inr = try? c.decodeIfPresent(Double.self, forKey: .inr)
    }

    @discardableResult
    mutating func add(_ product: String, qty: Double = 1, detail: String? = nil, at t: Date, caseID: UUID? = nil) -> MtpEntry {
        let e = MtpEntry(time: t, product: product, qty: qty, detail: detail, caseID: caseID)
        entries.append(e)
        entries.sort { $0.time < $1.time }
        return e
    }

    mutating func remove(_ id: UUID) { entries.removeAll { $0.id == id } }
}

enum MtpCalc {
    static func total(_ s: MtpState, _ product: String) -> Double {
        s.entries.filter { $0.product == product }.map(\.qty).reduce(0, +)
    }

    /// Citrated units given after `since` (all of them when nil): every RBC, plasma, platelet dose, cryo pool (as 1)
    /// and whole blood tap; not cell saver or factor concentrates.
    static func citrated(_ s: MtpState, data d: MtpData, after since: Date?) -> Double {
        let ids = Set(d.products.filter(\.citrated).map(\.id))
        return s.entries.filter { ids.contains($0.product) && (since == nil || $0.time > since!) }.map(\.qty).reduce(0, +)
    }

    static func last(_ s: MtpState, _ product: String) -> MtpEntry? { s.entries.last { $0.product == product } }

    // MARK: Ratio

    struct Ratio: Hashable {
        var rbc: Double
        var plasma: Double
        /// Platelet doses × units per dose.
        var plateletUnits: Double
        /// "1 : 0.8 : 1", normalized to RBC; nil before any RBC.
        var text: String?
    }

    /// RBC : plasma : platelets. A product with `ratioAs` (whole blood: 1 RBC + 1 plasma, signed off in the review doc)
    /// adds to those lines.
    static func ratio(_ s: MtpState, data d: MtpData) -> Ratio {
        var rbc = total(s, "prbc"), plasma = total(s, "plasma")
        let plt = total(s, "platelets") * s.plateletUnits
        for p in d.products {
            guard let parts = p.ratioAs, !parts.isEmpty else { continue }
            let n = total(s, p.id)
            if parts.contains("prbc") { rbc += n }
            if parts.contains("plasma") { plasma += n }
        }
        let text: String? = rbc > 0 ? "1 : \(one(plasma / rbc)) : \(one(plt / rbc))" : nil
        return Ratio(rbc: rbc, plasma: plasma, plateletUnits: plt, text: text)
    }

    // MARK: Calcium

    /// A measured ionized calcium and when it was drawn: typed in on the MTP screen, or the newest ABG in My Patient.
    struct IcaReading: Hashable {
        var value: Double
        var time: Date
        /// From My Patient's intraoperative labs rather than typed here.
        var fromCase = false
    }

    /// What the calcium card asks for.
    enum CalciumAction: Hashable {
        /// Nothing due.
        case none
        /// Give calcium: empirically by the unit count (no iCa since the last dose), or a measured iCa below 1.1.
        case give
        /// A measured iCa below 0.9.
        case urgent
        /// The measured iCa was at target, and 4 more citrated units have gone in since: send another.
        case check
    }

    struct CalciumStatus: Hashable {
        var action: CalciumAction = .none
        /// The measured iCa the decision used (drawn after the last calcium dose), if any.
        var reading: IcaReading?
        /// Give or urgent.
        var due: Bool { action == .give || action == .urgent }
        /// Citrated units since the last logged dose (or since the start).
        var since: Double
        /// Units left before the next prompt; 0 when due.
        var untilNext: Double
        var firstDose: Bool
    }

    /// The calcium prompt, from the measured iCa when there is one (review doc, MTP row 9: "base the calcium prompt on
    /// the measured iCa from the ABG, not a fixed threshold alone"):
    /// - an iCa drawn since the last calcium dose decides: below 0.9 urgent, below 1.1 give; at or above 1.1 nothing,
    ///   until 4 more citrated units have gone in since it was drawn, then "send iCa";
    /// - with no iCa since the last dose, the JTS rule: with the first citrated unit, then after every 4 units.
    static func calcium(_ s: MtpState, data d: MtpData, measured: IcaReading? = nil) -> CalciumStatus {
        let lastCa = last(s, "calcium")?.time
        let since = citrated(s, data: d, after: lastCa)
        let every = Double(d.calcium.everyUnits)
        if let r = measured, r.time > (lastCa ?? .distantPast) {
            var st = CalciumStatus(reading: r, since: since, untilNext: 0, firstDose: lastCa == nil)
            if r.value < d.calcium.icaUrgent { st.action = .urgent; return st }
            if r.value < d.calcium.icaGive { st.action = .give; return st }
            let afterDraw = citrated(s, data: d, after: r.time)
            st.untilNext = max(0, every - afterDraw)
            st.action = afterDraw >= every ? .check : .none
            return st
        }
        if lastCa == nil {
            return CalciumStatus(action: since >= 1 ? .give : .none, since: since, untilNext: since >= 1 ? 0 : 1, firstDose: true)
        }
        return CalciumStatus(action: since >= every ? .give : .none, since: since, untilNext: max(0, every - since), firstDose: false)
    }

    /// The newer of the iCa typed in here and the newest in My Patient's intraoperative labs.
    static func latestIca(_ s: MtpState, caseLabs: [IntraopLabSet]) -> IcaReading? {
        var best: IcaReading?
        if let v = s.ica, let t = s.icaTime { best = IcaReading(value: v, time: t) }
        for set in caseLabs {
            guard let v = set.values["ica"], let t = set.time else { continue }
            if best == nil || t > best!.time { best = IcaReading(value: v, time: t, fromCase: true) }
        }
        return best
    }

    enum IcaLevel: Hashable { case normal, give, urgent }

    static func ica(_ v: Double?, data d: MtpData) -> IcaLevel? {
        guard let v else { return nil }
        if v < d.calcium.icaUrgent { return .urgent }
        if v < d.calcium.icaGive { return .give }
        return .normal
    }

    // MARK: Labs

    struct LabStatus: Hashable {
        var due: Bool
        var rbcSince: Double
        var minutesSince: Double
    }

    /// After every 4 RBC units since labs were last sent, or at least every 30 min.
    static func labs(_ s: MtpState, data d: MtpData, now: Date) -> LabStatus {
        let lastLabs = last(s, "labs")?.time
        let rbcSince = s.entries.filter { $0.product == "prbc" && (lastLabs == nil || $0.time > lastLabs!) }.map(\.qty).reduce(0, +)
        let minutes = now.timeIntervalSince(lastLabs ?? s.started) / 60
        let due = rbcSince >= Double(d.labs.everyRbc) || minutes >= d.labs.everyMinutes
        return LabStatus(due: due, rbcSince: rbcSince, minutesSince: minutes)
    }

    static func labsDueAt(_ s: MtpState, data d: MtpData) -> Date {
        (last(s, "labs")?.time ?? s.started).addingTimeInterval(d.labs.everyMinutes * 60)
    }

    static func potassiumHigh(_ s: MtpState, data d: MtpData) -> Bool { (s.potassium ?? 0) > d.labs.kHigh }

    // MARK: Fibrinogen

    /// Fibrinogen in the cryo given, at the Circular's minimum per unit (g).
    static func cryoFibrinogenGrams(_ s: MtpState, data d: MtpData) -> Double {
        total(s, "cryo") * s.cryoPool * (d.cryoPool.mgPerUnit ?? 150) / 1000
    }

    /// Single-donor units for a fibrinogen dose (g), at the minimum per unit.
    static func cryoUnits(forGrams g: Double, data d: MtpData) -> Double {
        let mg = d.cryoPool.mgPerUnit ?? 150
        return (g * 1000 / mg).rounded(.up)
    }

    static func fibrinogenLow(_ s: MtpState, data d: MtpData) -> Bool {
        if let v = s.fibrinogen, v <= d.fibrinogen.clauss { return true }
        if let v = s.fibtem, v < d.fibrinogen.fibtem { return true }
        if let v = s.tegFF, v < d.fibrinogen.tegFF { return true }
        return false
    }

    // MARK: Viscoelastic (TACTIC, beyond fibrinogen)

    struct VhaPrompt: Hashable, Identifiable {
        /// "platelets", "coagulopathy", "fibrinolysis".
        var id: String
        var text: String
        /// Information only: no product suggested (coagulopathy).
        var info: Bool
    }

    /// Platelets low (EXTEM − FIBTEM CA5 <30 mm, or rTEG MA − FF MA <46 mm), coagulopathy likely (EXTEM CA5 <41 mm or
    /// rTEG MA <64 mm, information only) and hyperfibrinolysis (EXTEM LI30 <85% or rTEG LY30 >10%), from whichever
    /// device's values are entered.
    static func vhaPrompts(_ s: MtpState, data d: MtpData) -> [VhaPrompt] {
        guard let v = d.viscoelastic else { return [] }
        var out: [VhaPrompt] = []
        let plateletsLow = (s.extemCa5.flatMap { e in s.fibtem.map { e - $0 < v.rotem.extemMinusFibtemCa5 } } ?? false)
            || (s.rtegMa.flatMap { m in s.tegFF.map { m - $0 < v.teg.rtegMinusFfMa } } ?? false)
        if plateletsLow { out.append(VhaPrompt(id: "platelets", text: v.platelets, info: false)) }
        if (s.extemCa5.map { $0 < v.rotem.extemCa5 } ?? false) || (s.rtegMa.map { $0 < v.teg.rtegMa } ?? false) {
            out.append(VhaPrompt(id: "coagulopathy", text: v.coagulopathy, info: true))
        }
        if (s.extemLi30.map { $0 < v.rotem.extemLi30 } ?? false) || (s.rtegLy30.map { $0 > v.teg.rtegLy30 } ?? false) {
            out.append(VhaPrompt(id: "fibrinolysis", text: v.fibrinolysis, info: false))
        }
        return out
    }

    // MARK: 4F-PCC (vitamin K antagonist reversal)

    struct PccDose: Hashable {
        var iuPerKg: Double
        var dosingKg: Double
        var capped: Bool
        var iu: Double
    }

    /// The label's band for the INR, on a dosing weight capped at 100 kg; nil under INR 2 or without a weight.
    static func pcc(inr: Double?, weightKg: Double?, data d: MtpData) -> PccDose? {
        guard let inr, let w = weightKg, w > 0 else { return nil }
        guard let band = d.pcc.bands.first(where: { b in
            guard inr >= b.from else { return false }
            guard let to = b.to else { return true }
            return (b.toInclusive ?? false) ? inr <= to : inr < to
        }) else { return nil }
        let kg = min(w, d.pcc.capKg)
        return PccDose(iuPerKg: band.iuPerKg, dosingKg: kg, capped: w > d.pcc.capKg, iu: (band.iuPerKg * kg / 10).rounded() * 10)
    }

    // MARK: TXA

    /// Hours since injury when a trauma context has an injury time.
    static func hoursSinceInjury(_ s: MtpState, now: Date) -> Double? {
        s.injury.map { now.timeIntervalSince($0) / 3600 }
    }

    static func txaLate(_ s: MtpState, data d: MtpData, now: Date) -> Bool {
        guard let ctx = d.txa.contexts.first(where: { $0.id == s.txaContext }), let max = ctx.maxHoursFromInjury,
              let h = hoursSinceInjury(s, now: now) else { return false }
        return h > max
    }

    /// Grams of fibrinogen to two places, trailing zeros dropped ("0.75", "1.5", "3").
    static func grams(_ v: Double) -> String {
        let r = (v * 100).rounded() / 100
        if r == r.rounded() { return String(Int(r)) }
        return String(format: (r * 10) == (r * 10).rounded() ? "%.1f" : "%.2f", r)
    }

    static func one(_ v: Double) -> String {
        let r = (v * 10).rounded() / 10
        return r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)
    }
}
