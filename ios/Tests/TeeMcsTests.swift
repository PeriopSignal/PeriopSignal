import XCTest
@testable import PeriopSignal

/// The TEE companion and mechanical-support content (1.9): it decodes, the basic set is Reeves' 11, and the draft
/// handoff to My Patient stays short, marked as a draft and names what is missing.
final class TeeMcsTests: XCTestCase {
    private func bundle() throws -> ReferenceBundle {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reference", withExtension: "json"))
        return try ReferenceLoader.decode(try Data(contentsOf: url))
    }

    func testTeeDecodesWithReevesBasicEleven() throws {
        let t = try XCTUnwrap(try bundle().tee)
        XCTAssertEqual(t.views.count, 28)
        XCTAssertEqual(t.views.filter(\.basic).count, 11)
        XCTAssertNotNil(t.surgery("all"))
        XCTAssertFalse(t.required?.isEmpty ?? true, "the conditions are required")
    }

    func testHandoffIsAboutSixLinesAndADraft() throws {
        let t = try XCTUnwrap(try bundle().tee)
        let all = t.surgery("all")!.post + t.surgery("mv")!.post
        let lines = TeeCompanionView.handoffLines(t, surgery: "mv", post: true, checked: Array(all.prefix(3)),
                                                  unchecked: Array(all.dropFirst(3)), found: ["SAM / LVOT obstruction"], at: Date())
        XCTAssertLessThanOrEqual(lines.count, 6)
        XCTAssertTrue(lines[0].hasPrefix("TEE draft: confirm with the echocardiographer"))
        XCTAssertTrue(lines.contains { $0.contains("SAM / LVOT obstruction") })
        let pre = TeeCompanionView.handoffLines(t, surgery: "mv", post: false, checked: [], unchecked: t.surgery("all")!.pre, found: [], at: Date())
        XCTAssertTrue(pre.contains { $0.hasPrefix("Required, not recorded") })
    }

    func testMcsDevicesHaveQuestionsAndFlaggedNumbers() throws {
        let m = try XCTUnwrap(try bundle().mcs)
        XCTAssertEqual(Set(m.devices.map(\.id)), ["lvad", "impella", "ecmo", "iabp", "protekduo"])
        for dev in m.devices {
            XCTAssertFalse(dev.questions.isEmpty, dev.id)
            for row in dev.rows { XCTAssertEqual(row.count, 3, "\(dev.id): item, number, flag") }
            for kind in dev.deviceKinds ?? [] { XCTAssertNotNil(DeviceKind(rawValue: kind), "\(dev.id): \(kind) is a My Patient device kind") }
        }
    }
}
