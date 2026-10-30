import Foundation

/// The terms a user accepts on first launch, and the privacy notes, as plain text the app shows.
/// Changing the terms means a new `version`: everyone is asked to accept again.
enum Terms {
    static let version = "2026-10-30"

    /// The first-launch screen's points (title, body).
    static let points: [(icon: String, title: String, body: String)] = [
        ("stethoscope", "For licensed clinicians",
         "Periop Signal is a reference for anesthesiologists and other licensed clinicians, not medical advice for patients."),
        ("checklist", "A reference aid, not a decision",
         "Its calculators, checklists and summaries condense published guidelines and papers. They can contain errors or fall out of date, and they do not replace your clinical judgment, your institution's protocols or the source documents. Check doses and recommendations before acting."),
        ("building.columns", "Not reviewed by the FDA",
         "The app has not been reviewed or cleared by the U.S. Food and Drug Administration or any other regulator."),
        ("lock.iphone", "Patient details stay on this phone",
         "My Patient keeps what you enter on this iPhone unless you send it to a colleague yourself. Don't enter names, record numbers, dates of birth or other identifiers."),
    ]

    static let acceptLabel = "I'm a licensed clinician and I agree"

    /// The full terms, section by section.
    static let sections: [(title: String, body: String)] = [
        ("Who it is for",
         "Periop Signal is for anesthesiologists, anesthesia trainees and other licensed health professionals. It is not intended for patients or the public, and using it creates no doctor–patient relationship."),
        ("Reference, not advice",
         "The feed summarizes published papers and society documents. The Reference tools condense published guidelines and papers into calculators and checklists, and My Patient organizes what you enter. None of it is medical advice, and none of it replaces your clinical judgment, your institution's protocols or the source documents. Check doses, thresholds and recommendations against the source before acting on them."),
        ("Accuracy",
         "Content is checked against its sources, but it can contain errors or omissions, and guidelines change. Each tool names its sources; where the app and a source differ, follow the source. Emergency checklists and timers support, and do not replace, your team and your institution's protocols."),
        ("Regulation",
         "The app has not been reviewed or cleared by the U.S. Food and Drug Administration or any other regulator."),
        ("AI answers",
         "Ask answers questions with Apple Intelligence on the phone when it is available, otherwise with Anthropic's Claude through the Periop Signal proxy. AI answers can be wrong: check them against the sources they cite."),
        ("Patient information",
         "My Patient stores what you enter on this iPhone, in a protected file that cannot be read while the phone is locked and is excluded from iCloud and computer backups; Clear removes it. It leaves the phone only when you send it yourself: a handoff shared as text, or a patient sent to a colleague's Periop Signal by AirDrop or Messages, which goes directly between the phones and not through Periop Signal. Messages keeps a copy in that conversation until you delete it. Don't enter names, record numbers, dates of birth or other identifiers. You are responsible for following HIPAA and your institution's policies, including where you share a handoff or send a patient."),
        ("No warranty",
         "The app and its content are provided as is, without warranties of any kind. To the extent the law allows, the author is not liable for any loss or harm arising from its use."),
        ("Links",
         "Links lead to journals, societies and other sites that Periop Signal does not control."),
        ("Changes",
         "These terms may change; the app asks you to accept a new version before you continue."),
    ]

    /// What leaves the phone, and where it goes.
    static let privacy: [(title: String, body: String)] = [
        ("No account, ads or tracking", "There is no sign-in, no advertising and no analytics."),
        ("Feed and audio", "Posts, the reference content and recordings are downloaded from the Periop Signal website and its GitHub repository."),
        ("Saved posts and progress", "Saved posts, read status and quiz progress sync through your own iCloud account (Apple's key-value storage); the author cannot see them."),
        ("Alerts", "If you turn alerts on, Google's Firebase Cloud Messaging holds a device token and the topics you follow, used only to send the morning alert."),
        ("Ask", "When a question is answered by Claude, the question and the reference material shown with it are sent through the Periop Signal proxy to Anthropic; nothing else."),
        ("My Patient", "Nothing entered in My Patient leaves the phone unless you share a handoff or send the patient to a colleague, which goes by AirDrop or Messages directly between the phones. Fill from a note reads the note on the phone and doesn't keep it; dictating it uses iOS keyboard dictation, under Apple's privacy terms."),
    ]
}
