import SwiftUI

#if DEBUG
// MARK: - The style gallery (1.11, Ben's Q8: the before/after of the colour and chip grammar)
//
// One page with every chip and link variant of My Patient, so the CI's light and dark shots (788–790) show the whole
// grammar at once: the three colour roles (PS.accent for the tab bar's selection only, PS.action for anything that does
// something, PS.red for clinical alerts), the four chip looks (ChipStyle), the Yes/No pills, the quiet link and its
// collapsed row, the add chip and the filled row, the summary lines, the headings and the jump chips. Debug builds only:
// -ps.screen gallery; -ps.gallery.scroll links|lines|headings|buttons brings a part below the first screen to the top,
// so the shots cover the whole page.

struct PatientStyleGallery: View {
    @State private var asa: String? = "3"
    @State private var sex: String? = "male"
    @State private var anesthetic: Set<String> = ["ga", "regional"]
    @State private var presets: Set<String> = ["exam"]
    @State private var answer: Bool? = nil
    @State private var answerNo: Bool? = false
    @State private var answerYes: Bool? = true

    /// The variants on the page, by name; the tests check that every ChipStyle is among them.
    static let variants = ["tokens", "choice", "toggle", "preset", "add", "yesno", "quietlink", "collapsed", "addchip", "filledrow", "filledrow-alert",
                           "line", "line-marks", "line-alert", "section-title", "card-header", "caption", "jump", "buttons"]

    /// The page's parts in order, by the name -ps.gallery.scroll takes.
    static let sections = ["tokens", "chips", "links", "lines", "headings", "buttons"]

    /// Which variants each part draws; together they are every variant, each once.
    static let sectionVariants: [String: [String]] = [
        "tokens": ["tokens"],
        "chips": ["choice", "toggle", "preset", "add", "yesno"],
        "links": ["quietlink", "collapsed", "addchip", "filledrow", "filledrow-alert"],
        "lines": ["line", "line-marks", "line-alert"],
        "headings": ["section-title", "card-header", "caption", "jump"],
        "buttons": ["buttons"],
    ]

    /// Screenshot runs: the part -ps.gallery.scroll names, or nil for the top of the page (no name, or not a part).
    static func scrollTarget(_ name: String) -> String? { sections.contains(name) ? name : nil }

    private let asaChips = ["1", "2", "3", "4", "5", "6"].map { ChipChoice($0, PatientRules.roman(Int($0)!)) }
    private let sexChips = [ChipChoice("male", "Male"), ChipChoice("female", "Female")]
    private let presetChips = [ChipChoice("exam", "Exam normal"), ChipChoice("echo", "Echo normal"), ChipChoice("none", "None")]
    private let addChips = [ChipChoice("ecg", "ECG"), ChipChoice("echo", "Echo"), ChipChoice("lhc", "Left heart cath")]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Style gallery").font(PS.sys(size: 22, weight: .bold)).foregroundStyle(PS.fg)
                        Text("1.11: red means a clinical alert, blue means tap me, the brand red stays on the tab bar; one chip grammar.")
                            .font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).fixedSize(horizontal: false, vertical: true)
                    }
                    tokens.id("tokens")
                    chips.id("chips")
                    links.id("links")
                    lines.id("lines")
                    headings.id("headings")
                    buttons.id("buttons")
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .task {
                // Screenshot runs: asked for a few times, since the first frames come before the page has its height.
                guard let to = Self.scrollTarget(LaunchSeed.string("ps.gallery.scroll")) else { return }
                for _ in 0..<8 {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    proxy.scrollTo(to, anchor: .top)
                }
            }
        }
        .background(PS.bg.ignoresSafeArea())
        .modifier(DebugContentWidth())
    }

    // MARK: Tokens

    private var tokens: some View {
        group("Colour roles") {
            HStack(spacing: 10) {
                swatch(PS.accent, "Selection", "tab bar")
                swatch(PS.action, "Action", "tap me")
                swatch(PS.red, "Alert", "clinical")
                swatch(PS.green, "Preset", "normal")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
    }

    private func swatch(_ c: Color, _ name: String, _ use: String) -> some View {
        VStack(spacing: 5) {
            Circle().fill(c).frame(width: 28, height: 28)
            Text(name).font(PS.sys(size: 11.5, weight: .semibold)).foregroundStyle(PS.fg)
            Text(use).font(PS.sys(size: 10.5)).foregroundStyle(PS.fg3)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Chips

    private var chips: some View {
        group("Chips: one grammar") {
            PatientChipRow(label: "Choice · ink") {
                PatientChoice(choices: asaChips, selection: $asa)
            }
            PatientChipRow(label: "Sex") { PatientChoice(choices: sexChips, selection: $sex) }
            Hairline().padding(.leading, 14)
            PatientChipRow(label: "Toggle · ✓") {
                ChipSet(options: PatientPreop110.anesthetics, style: .toggle, isOn: { anesthetic.contains($0) },
                        tap: { id in if anesthetic.contains(id) { anesthetic.remove(id) } else { anesthetic.insert(id) } })
            }
            Hairline().padding(.leading, 14)
            PatientChipRow(label: "Preset · green") {
                ChipSet(options: presetChips, style: .preset, isOn: { presets.contains($0) },
                        tap: { id in if presets.contains(id) { presets.remove(id) } else { presets.insert(id) } })
            }
            Hairline().padding(.leading, 14)
            PatientChipRow(label: "Add · opens a page") {
                ChipSet(options: addChips, style: .add, isOn: { _ in false }, tap: { _ in })
            }
            Hairline().padding(.leading, 14)
            yesNo("Unanswered", $answer)
            yesNo("Answered No", $answerNo)
            yesNo("Answered Yes", $answerYes)
        }
    }

    private func yesNo(_ title: String, _ value: Binding<Bool?>) -> some View {
        HStack {
            Text(title).font(PS.sys(size: 14.5, weight: .medium)).foregroundStyle(PS.fg)
            Spacer(minLength: 6)
            YesNoPills(no: value.wrappedValue == false, yes: value.wrappedValue == true,
                       onNo: { value.wrappedValue = false }, onYes: { value.wrappedValue = true }, onClear: { value.wrappedValue = nil })
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    // MARK: Links and rows

    private var links: some View {
        group("Links and rows: three add looks") {
            // A — the quiet link that opens in place, and the row it collapses to.
            HStack(spacing: 8) {
                Image(systemName: "plus").font(PS.sys(size: 11, weight: .bold)).foregroundStyle(PS.action).frame(width: 14)
                Text("Add preoperative vitals").font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.fg2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            collapsed("Urgency: Elective", alert: false)
            collapsed("Urgency: Emergency", alert: true)
            Hairline().padding(.leading, 14)
            // B — the add chip that opens a page, and the filled row it becomes.
            HStack(spacing: 8) {
                PreopAddChip(title: "Stress test")
                PreopAddChip(title: "Echo")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            PreopFilledRow(title: "ECG", summary: "Normal sinus rhythm; LBBB", icon: "waveform.path.ecg")
                .padding(.horizontal, 14).padding(.vertical, 6)
            PreopFilledRow(title: "TEE screening", summary: "Relative contraindication: previous upper GI surgery, dysphagia", icon: "exclamationmark.triangle", alert: true,
                           caution: "Caution: carotid stenosis over 70% recorded")
                .padding(.horizontal, 14).padding(.vertical, 6)
        }
    }

    private func collapsed(_ title: String, alert: Bool) -> some View {
        HStack(spacing: 6) {
            Text(title).font(PS.sys(size: 14.5, weight: .semibold)).foregroundStyle(alert ? PS.red : PS.fg)
            Text("·").font(PS.sys(size: 14.5)).foregroundStyle(PS.fg3)
            Text("Change").font(PS.sys(size: 14, weight: .semibold)).foregroundStyle(PS.action)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    // MARK: Summary lines

    private var lines: some View {
        group("Summary lines") {
            VStack(alignment: .leading, spacing: 10) {
                PatientLineText(line: PatientSummary.Line("Current airway", "Own airway"))
                PatientLineText(line: PatientSummary.Line("Labs", "Hb 12.8 L · Hct ~38 (est.) · Plt 210 · K 5.9 H", marks: ["Hb 12.8 L", "K 5.9 H"]))
                PatientLineText(line: PatientSummary.Line("Difficult mask ventilation", "2 of 5 predictors", alert: true))
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
    }

    // MARK: Headings

    private var headings: some View {
        VStack(alignment: .leading, spacing: 8) {
            PreopSectionTitle(text: "Planned Procedure & Anesthetic", info: "Elective: can be delayed up to a year (2024 AHA/ACC).")
            VStack(alignment: .leading, spacing: 9) {
                PatientCardHeader(title: "Airway Examination", icon: "mouth")
                Text("Mallampati, difficult-airway signs, teeth").font(PS.sys(size: 13.5)).foregroundStyle(PS.fg3)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
            PatientGroup(title: "Allergies", note: "A caption only where a section has several boxes; never the title again.") {
                Text("No known allergies").font(PS.sys(size: 14.5)).foregroundStyle(PS.fg).padding(.horizontal, 14).padding(.vertical, 10)
            }
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "Jump bar")
                HStack(spacing: 8) {
                    PatientJumpChip(title: "Procedure")
                    PatientJumpChip(title: "Demographics", current: true)
                    PatientJumpChip(title: "Exam & Workup")
                }
            }
            .padding(.top, 6)
        }
    }

    // MARK: Buttons

    private var buttons: some View {
        group("Buttons") {
            HStack(spacing: 10) {
                Button("Add 3") {}.buttonStyle(CapsuleButtonStyle(color: PS.action))
                Button("Change") {}.buttonStyle(CapsuleButtonStyle(prominent: false))
                Button("Deep dive →") {}.buttonStyle(TextButtonStyle(color: PS.action))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
    }

    // PatientGroup stores its content closure, so the builder it is handed has to escape.
    private func group<C: View>(_ title: String, @ViewBuilder _ content: @escaping () -> C) -> some View {
        PatientGroup(title: title) { content() }
    }
}
#endif
