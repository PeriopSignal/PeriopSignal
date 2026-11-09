import SwiftUI

// MARK: - The three "add" looks (1.11, P1-7)
//
// Ben's 1.11 layout review found ten ways to add something on the Preoperative tab. There are three now:
//   A. a quiet link, "+ Name": opens its controls in place and, once set, collapses to "Name: value · Change"
//      (urgency, risk-score inputs, vitals, code status, other conditions, last intake, current infusions, a flag);
//   B. a grey chip, "+ Name" (PreopAddChip): opens a page, and reads as a filled row (PreopFilledRow) once it holds data;
//   C. a card with a title row and ›: opens a page that carries a figure or a table (airway, labs, lines; the intraop links).
// This file holds A and the one-phrase empty hints the cards share (P1-9). The "+" is the action colour (PS.action, Q8):
// red is kept for clinical alerts.

/// Grammar A, empty: "+ Name", the "+" in the action colour and the label in the second text colour, flush left.
struct PreopQuietLink: View {
    var title: String
    /// What VoiceOver says the tap does ("Shows the code status choices").
    var hint: String? = nil
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            withAnimation(.snappy) { action() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(PS.sys(size: 11, weight: .bold)).foregroundStyle(PS.action).frame(width: 14)
                Text(title).font(PS.sys(size: 13.5, weight: .semibold)).foregroundStyle(PS.fg2)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(hint ?? "")
    }
}

/// Grammar A, set: "Name: value · Change" on one line; a tap on Change opens the controls again.
struct PreopQuietValueRow: View {
    var title: String
    var value: String
    var changeTitle = "Change"
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            withAnimation(.snappy) { action() }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                (Text(title + ": ").foregroundStyle(PS.fg3) + Text(value).foregroundStyle(PS.fg2))
                    .font(PS.sys(size: 13.5, weight: .semibold))
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Text("· " + changeTitle).font(PS.sys(size: 13.5, weight: .semibold)).foregroundStyle(PS.action).fixedSize()
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title + ": " + value)
        .accessibilityHint(changeTitle)
    }
}

/// A small "Hide" at the end of a row of controls a quiet link opened, while nothing in them is set.
struct PreopHideButton: View {
    var action: () -> Void
    var body: some View {
        Button("Hide") { withAnimation(.snappy) { action() } }
            .font(PS.sys(size: 12.5, weight: .semibold)).foregroundStyle(PS.fg3).buttonStyle(.plain)
    }
}

/// The one-phrase hints an empty card or link row shows (P1-9): one short phrase each, never a sentence. The tests check
/// each fits one line at the hint size on a 375-pt phone.
enum PreopEmptyHints {
    /// The Airway Examination card.
    static let airway = "Mallampati, difficult-airway signs, teeth"
    /// The Lines & Devices card of the Preoperative tab.
    static let lines = "Lines and devices on arrival"
    /// The Lines & Devices card of the Intraoperative tab.
    static let intraopLines = "Lines, airway and mechanical support"
    /// The Intraoperative tab's link rows, by their part.
    static let intraop: [String: String] = [
        "meds": "TXA, steroids, antibiotic time, reversal",
        "echo": "Pre- and post-bypass TEE findings",
        "labs": "Blood gas and coag sets, with times",
        "regional": "Blocks and neuraxial, drugs, catheters",
        "events": "What happened during the case",
        "considerations": "Difficult airway, transfusion, pressors",
    ]
    /// The case timers row while none runs, and once some do.
    static let caseTimersNone = "+ Case timers"
    static let caseTimersRunning = "Case timers"
    /// The hint text size, and the room a link row's hint has on a 375-pt phone (the page's 20-pt margins, the card's
    /// 14-pt padding and the 32-pt indent under the icon).
    static let hintFontSize: CGFloat = 12.5
    static let hintRoomAt375: CGFloat = 375 - 40 - 28 - 32
}
