import Compression
import Foundation

// MARK: - A patient as a link (1.12, opt-in)
//
// Since iOS 17 a FILE received by AirDrop lands in Files, not in the app that owns its type (Apple calls this
// intended), so a patient sent as a file needs the Files app, Share, then Periop Signal. A URL with the app's own
// scheme can open the app directly, so with the "AirDrop opens Periop Signal directly" switch on, the AirDrop activity
// is given this link and every other activity (Messages) still gets the file.
//
//   periopsignal://receive?v=1&z=<payload>
//
// payload = base64url, no padding, of the DEFLATE-compressed bytes of PatientPacket.encoded(). The compression is the
// Compression framework's COMPRESSION_ZLIB (Apple's name for raw DEFLATE, RFC 1951, with no zlib header); both ends are
// this app, so it only has to agree with itself.
//
// A link can come from anywhere, so reading one is defensive: the scheme, host and version are checked, the payload is
// capped, the inflated size is capped while it streams (a small payload that would inflate to gigabytes stops at
// PatientPacket.maxBytes), and the packet is then read exactly as a file is (PatientPacket.decode). A link never opens
// a patient by itself: it only fills the inbox's pending packet, and the user answers the "Patient Received" sheet.
// The URL holds the patient: nothing here logs it, and PeriopSignalApp takes it before the router sees it.

enum PatientLink {
    static let scheme = "periopsignal"
    static let host = "receive"
    static let version = "1"
    /// The longest payload read (characters of base64url).
    static let maxPayload = 200_000
    /// A link longer than this is not made: AirDrop sends the file as before. (A very long URL is unreliable through
    /// the share sheet; a record with ordinary notes is a few thousand characters.)
    static let maxLinkLength = 60_000

    /// True for a URL that is a patient link: periopsignal://receive, whatever follows. Anything else, including
    /// periopsignal://patient (the tab link), goes to the router.
    static func isPatientLink(_ url: URL) -> Bool {
        url.scheme?.lowercased() == scheme && url.host?.lowercased() == host
    }

    // MARK: Making a link

    /// The link for a packet, or nil when it would be longer than `maxLinkLength` (then the file is sent instead).
    static func url(for packet: PatientPacket) -> URL? {
        guard let bytes = try? packet.encoded(), let packed = deflate(bytes) else { return nil }
        let text = "\(scheme)://\(host)?v=\(version)&z=" + base64URL(packed)
        guard text.count <= maxLinkLength else { return nil }
        return URL(string: text)
    }

    // MARK: Reading a link

    /// The packet in a link. Throws the same problems a bad file does (their messages are what the user sees).
    static func decode(_ url: URL) throws -> PatientPacket {
        guard isPatientLink(url) else { throw PatientPacket.Problem.notAPatient }
        // Bound the work before parsing: the longest valid link is the payload plus a short fixed head.
        guard url.absoluteString.utf8.count <= maxPayload + 200 else { throw PatientPacket.Problem.tooLarge }
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw PatientPacket.Problem.notAPatient }
        let path = parts.path
        guard path.isEmpty || path == "/" else { throw PatientPacket.Problem.notAPatient }
        let items = parts.queryItems ?? []
        guard let v = items.first(where: { $0.name == "v" })?.value else { throw PatientPacket.Problem.notAPatient }
        guard v == version else {
            if let n = Int(v), n > Int(version) ?? 1 { throw PatientPacket.Problem.newerFormat }
            throw PatientPacket.Problem.notAPatient
        }
        guard let payload = items.first(where: { $0.name == "z" })?.value, !payload.isEmpty else { throw PatientPacket.Problem.notAPatient }
        guard payload.utf8.count <= maxPayload else { throw PatientPacket.Problem.tooLarge }
        guard let packed = fromBase64URL(payload), !packed.isEmpty else { throw PatientPacket.Problem.unreadable }
        let inflated = run(packed, limit: PatientPacket.maxBytes)
        // Either damaged, or it inflates past the cap; the second is the one worth naming.
        guard let bytes = inflated.data else { throw (inflated.passedLimit ? PatientPacket.Problem.tooLarge : PatientPacket.Problem.unreadable) }
        return try PatientPacket.decode(bytes)
    }

    // MARK: base64url

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// nil for anything outside the base64url alphabet (a padded or standard-base64 payload is not ours).
    static func fromBase64URL(_ s: String) -> Data? {
        for u in s.utf8 {
            let ok = (u >= 48 && u <= 57) || (u >= 65 && u <= 90) || (u >= 97 && u <= 122) || u == 45 || u == 95
            if !ok { return nil }
        }
        var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        // A length of 1 more than a multiple of 4 is never valid base64.
        if t.utf8.count % 4 == 1 { return nil }
        while t.utf8.count % 4 != 0 { t += "=" }
        return Data(base64Encoded: t)
    }

    // MARK: DEFLATE

    private static let chunk = 64 * 1024

    static func deflate(_ data: Data) -> Data? {
        try? (data as NSData).compressed(using: .zlib) as Data
    }

    /// The inflated bytes, or nil when the input is damaged or the output would pass `limit`. Streamed in 64 KB pieces
    /// and stopped as soon as the total passes the limit, so a small payload cannot make a large buffer.
    static func inflate(_ input: Data, limit: Int) -> Data? {
        run(input, limit: limit).data
    }

    private static func run(_ input: Data, limit: Int) -> (data: Data?, passedLimit: Bool) {
        guard !input.isEmpty else { return (nil, false) }
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
        defer { dst.deallocate() }
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) != COMPRESSION_STATUS_ERROR else {
            return (nil, false)
        }
        defer { compression_stream_destroy(stream) }
        var out = Data()
        return input.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> (data: Data?, passedLimit: Bool) in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return (nil, false) }
            stream.pointee.src_ptr = base
            stream.pointee.src_size = input.count
            stream.pointee.dst_ptr = dst
            stream.pointee.dst_size = chunk
            let finalize = Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
            while true {
                let before = stream.pointee.src_size
                let status = compression_stream_process(stream, finalize)
                let produced = chunk - stream.pointee.dst_size
                if produced > 0 { out.append(dst, count: produced) }
                if out.count > limit { return (nil, true) }
                switch status {
                case COMPRESSION_STATUS_END:
                    return (out, false)
                case COMPRESSION_STATUS_OK:
                    // No input used and nothing produced: stuck (a damaged stream), not a long one.
                    if produced == 0 && stream.pointee.src_size == before { return (nil, false) }
                    stream.pointee.dst_ptr = dst
                    stream.pointee.dst_size = chunk
                default:
                    return (nil, false)
                }
            }
        }
    }
}
