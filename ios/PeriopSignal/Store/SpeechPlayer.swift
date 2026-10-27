import AVFoundation
import Foundation
import MediaPlayer
import Observation
import SwiftUI

/// Reads posts aloud with the system voice, podcast-style: a queue of posts, play/pause, skip,
/// lock-screen controls, and background playback (UIBackgroundModes: audio).
@MainActor
@Observable
final class SpeechPlayer: NSObject, AVSpeechSynthesizerDelegate {
    private(set) var queue: [Post] = []
    private(set) var index = 0
    private(set) var segmentIndex = 0
    private(set) var isPlaying = false
    /// True while the mini player should be shown.
    private(set) var isActive = false
    private(set) var finished = false

    private let synth = AVSpeechSynthesizer()
    private var segments: [String] = []
    private var remoteCommandsReady = false
    private var interruptionObserver: NSObjectProtocol?
    var rate: Float = AVSpeechUtteranceDefaultSpeechRate

    override init() {
        super.init()
        synth.delegate = self
        interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in self?.handleInterruption(note) }
        }
    }

    var current: Post? { queue.indices.contains(index) ? queue[index] : nil }
    var hasNext: Bool { index + 1 < queue.count }
    var hasPrevious: Bool { index > 0 }
    var progress: Double { segments.isEmpty ? 0 : Double(min(segmentIndex, segments.count)) / Double(segments.count) }
    var positionText: String { queue.count > 1 ? "\(index + 1) of \(queue.count)" : "" }

    // MARK: Controls

    func play(_ posts: [Post], startAt start: Int = 0) {
        guard !posts.isEmpty else { return }
        stopSpeaking()
        queue = posts
        index = min(max(0, start), posts.count - 1)
        isActive = true
        finished = false
        activateSession()
        setupRemoteCommands()
        loadCurrent()
        speakSegment()
    }

    func play(_ post: Post) { play([post]) }

    func toggle() {
        if finished { index = 0; finished = false; loadCurrent(); speakSegment(); return }
        if isPlaying {
            synth.pauseSpeaking(at: .word)
            isPlaying = false
        } else if synth.isPaused {
            synth.continueSpeaking()
            isPlaying = true
        } else {
            activateSession()
            speakSegment()
        }
        updateNowPlaying()
    }

    func next() {
        guard hasNext else { finish(); return }
        stopSpeaking()
        index += 1
        loadCurrent()
        speakSegment()
    }

    func previous() {
        stopSpeaking()
        if segmentIndex > 1 || !hasPrevious {
            segmentIndex = 0
        } else {
            index -= 1
            loadCurrent()
        }
        speakSegment()
    }

    func stop() {
        stopSpeaking()
        isPlaying = false
        isActive = false
        finished = false
        queue = []
        segments = []
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func setRate(_ value: Double) {
        rate = Float(value)
        guard isPlaying else { return }
        // Re-speak the current segment at the new rate.
        stopSpeaking()
        speakSegment()
    }

    // MARK: Internals

    private func loadCurrent() {
        segmentIndex = 0
        segments = current.map(Self.segments(for:)) ?? []
        updateNowPlaying()
    }

    private func speakSegment() {
        guard segmentIndex < segments.count else { advancePost(); return }
        let u = AVSpeechUtterance(string: segments[segmentIndex])
        u.voice = Self.preferredVoice
        u.rate = rate
        u.postUtteranceDelay = 0.3
        synth.speak(u)
        isPlaying = true
        updateNowPlaying()
    }

    private func advancePost() {
        if hasNext {
            index += 1
            loadCurrent()
            speakSegment()
        } else {
            finish()
        }
    }

    private func finish() {
        stopSpeaking()
        isPlaying = false
        finished = true
        segmentIndex = segments.count
        updateNowPlaying()
    }

    private func stopSpeaking() {
        if synth.isSpeaking || synth.isPaused {
            synth.stopSpeaking(at: .immediate)
        }
        isPlaying = false
    }

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [])
        try? session.setActive(true)
    }

    private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            if isPlaying { synth.pauseSpeaking(at: .word); isPlaying = false }
        case .ended:
            let opts = AVAudioSession.InterruptionOptions(rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            if opts.contains(.shouldResume), isActive, !finished { toggle() }
        @unknown default: break
        }
    }

    // MARK: AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.isActive else { return }
            self.segmentIndex += 1
            self.speakSegment()
        }
    }

    // MARK: Lock screen

    private func setupRemoteCommands() {
        guard !remoteCommandsReady else { return }
        remoteCommandsReady = true
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in Task { @MainActor in if self?.isPlaying == false { self?.toggle() } }; return .success }
        c.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in if self?.isPlaying == true { self?.toggle() } }; return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previous() }; return .success }
        c.skipForwardCommand.isEnabled = false
        c.skipBackwardCommand.isEnabled = false
    }

    private func updateNowPlaying() {
        guard let post = current else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: post.headline,
            MPMediaItemPropertyArtist: "Periop Signal · \(post.journal)",
            MPMediaItemPropertyAlbumTitle: "\(post.kind) · \(PSDate.display(post.date, long: true))",
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyIsLiveStream: false,
        ]
        if queue.count > 1 {
            info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = index
            info[MPNowPlayingInfoPropertyPlaybackQueueCount] = queue.count
        }
        if let art = artwork { info[MPMediaItemPropertyArtwork] = art }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    @ObservationIgnored private lazy var artwork: MPMediaItemArtwork? = {
        let renderer = ImageRenderer(content: LogoMark(size: 300, cornerRadius: 0))
        renderer.scale = 2
        guard let image = renderer.uiImage else { return nil }
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }()

    // MARK: Text

    static let preferredVoice: AVSpeechSynthesisVoice? = {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "en-US" }
        func rank(_ v: AVSpeechSynthesisVoice) -> Int {
            switch v.quality {
            case .premium: return 3
            case .enhanced: return 2
            default: return 1
            }
        }
        return voices.max { rank($0) < rank($1) } ?? AVSpeechSynthesisVoice(language: "en-US")
    }()

    /// The post as spoken paragraphs: headline, source line, take-home, overview, stated limitations.
    static func segments(for post: Post) -> [String] {
        var out: [String] = []
        out.append(spoken(post.headline))
        var source = "From \(post.journal), \(post.kind.lowercased())"
        if !post.trialName.isEmpty { source += ", the \(post.trialName) trial" }
        source += ", \(PSDate.display(post.date, long: true))."
        out.append(source)
        if !post.takeHome.isEmpty {
            out.append(post.takeHomeIsAuthors ? "The authors' key points." : "Take-home.")
            out.append(contentsOf: post.takeHome.map(spoken))
        }
        for block in MarkdownBlocks.parse(post.deepDive) {
            switch block {
            case .heading(let h): out.append(spoken(h))
            case .paragraph(let p): out.append(spoken(p))
            case .bullets(let items): out.append(contentsOf: items.map(spoken))
            }
        }
        if !post.authorLimitations.isEmpty {
            out.append("Limitations stated by the authors.")
            out.append(contentsOf: post.authorLimitations.map(spoken))
        }
        return out.filter { !$0.isEmpty }
    }

    /// Strips markdown and expands a few abbreviations the voice would otherwise spell out oddly.
    static func spoken(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        let swaps: [(String, String)] = [
            (#"/kg/min\b"#, " per kilogram per minute"), (#"/kg/h\b"#, " per kilogram per hour"), (#"/kg\b"#, " per kilogram"),
            (#"/min\b"#, " per minute"), (#"/h\b"#, " per hour"), (#"/L\b"#, " per litre"), (#"/dL\b"#, " per decilitre"),
            (#"\bvs\.?\b"#, "versus"), (#"\bmcg\b"#, "micrograms"), (#"\bμg\b"#, "micrograms"), (#"\bkg\b"#, "kilograms"),
            (#"\bmL\b"#, "millilitres"), (#"\bmmHg\b"#, "millimetres of mercury"), (#"\bh\b(?=[\s,.;])"#, "hours"),
            (#"\bmin\b(?=[\s,.;])"#, "minutes"), (#"≥"#, "at least "), (#"≤"#, "at most "), (#"\bn\s?=\s?"#, "n equals "),
            (#"\bCI\b"#, "confidence interval"), (#"\bRCT\b"#, "randomized trial"), (#"\bICU\b"#, "I C U"), (#"\bOR\b(?=\s\d)"#, "odds ratio"),
            (#"\bHR\b(?=\s\d)"#, "hazard ratio"), (#"\bRR\b(?=\s\d)"#, "relative risk"), (#"\bTEE\b"#, "T E E"), (#"\bECMO\b"#, "ECMO"),
        ]
        for (pattern, rep) in swaps {
            t = t.replacingOccurrences(of: pattern, with: rep, options: .regularExpression)
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
