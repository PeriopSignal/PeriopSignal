import AVFoundation
import Foundation
import MediaPlayer
import Observation
import SwiftUI

/// Reads posts aloud, podcast-style: a queue of posts, play/pause, skip, lock-screen controls and
/// background playback (UIBackgroundModes: audio). A post with a studio recording (`post.audio`,
/// made by the repository's audio workflow) streams that MP3; every other post is spoken by the
/// phone's own voice.
@MainActor
@Observable
final class SpeechPlayer: NSObject, AVSpeechSynthesizerDelegate {
    enum Mode { case idle, speech, recording }

    private(set) var queue: [Post] = []
    private(set) var index = 0
    private(set) var segmentIndex = 0
    private(set) var isPlaying = false
    /// True while the mini player should be shown.
    private(set) var isActive = false
    private(set) var finished = false
    private(set) var isBuffering = false
    private(set) var mode: Mode = .idle
    /// 0…1 through the current recording (speech uses segment counts instead).
    private(set) var recordingProgress: Double = 0

    /// Injected at launch: voice choice and whether recordings are preferred.
    var preferences: Preferences?

    private let synth = AVSpeechSynthesizer()
    private var segments: [String] = []
    private var remoteCommandsReady = false
    private var interruptionObserver: NSObjectProtocol?
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var downloadTask: Task<Void, Never>?
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
    var progress: Double {
        if mode == .recording { return recordingProgress }
        return segments.isEmpty ? 0 : Double(min(segmentIndex, segments.count)) / Double(segments.count)
    }
    var positionText: String { queue.count > 1 ? "\(index + 1) of \(queue.count)" : "" }

    /// Playback speed as a multiplier of normal, derived from the stored speech rate.
    var playbackMultiplier: Float { Float(SpeechRate.nearest(Double(rate)).multiplier) }

    // MARK: Controls

    func play(_ posts: [Post], startAt start: Int = 0) {
        guard !posts.isEmpty else { return }
        stopPlayback()
        queue = posts
        index = min(max(0, start), posts.count - 1)
        isActive = true
        finished = false
        activateSession()
        setupRemoteCommands()
        loadCurrent()
        begin()
    }

    func play(_ post: Post) { play([post]) }

    func toggle() {
        if finished { index = 0; finished = false; loadCurrent(); begin(); return }
        switch mode {
        case .recording:
            guard let player else {
                // Still downloading: a tap pauses the download; the next tap starts again.
                if isBuffering { stopPlayback(); mode = .recording } else { begin() }
                return
            }
            if isPlaying { player.pause(); isPlaying = false } else { activateSession(); player.rate = playbackMultiplier; isPlaying = true }
        case .speech:
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
        case .idle:
            begin()
        }
        updateNowPlaying()
    }

    func next() {
        guard hasNext else { finish(); return }
        stopPlayback()
        index += 1
        loadCurrent()
        begin()
    }

    func previous() {
        let restart: Bool
        if mode == .recording, let t = player?.currentTime().seconds, t > 3 { restart = true }
        else { restart = segmentIndex > 1 || !hasPrevious }
        stopPlayback()
        if restart {
            segmentIndex = 0
        } else {
            index -= 1
            loadCurrent()
        }
        begin()
    }

    func stop() {
        stopPlayback()
        isPlaying = false
        isActive = false
        finished = false
        mode = .idle
        queue = []
        segments = []
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func setRate(_ value: Double) {
        rate = Float(value)
        guard isPlaying else { return }
        switch mode {
        case .recording: player?.rate = playbackMultiplier
        case .speech:
            // Re-speak the current segment at the new rate.
            stopSpeech()
            speakSegment()
        case .idle: break
        }
    }

    // MARK: Internals

    private func loadCurrent() {
        segmentIndex = 0
        recordingProgress = 0
        segments = current.map(Self.segments(for:)) ?? []
        updateNowPlaying()
    }

    /// Starts the current post: the recording when there is one and the reader wants it, else speech.
    private func begin() {
        guard let post = current else { return }
        if preferences?.preferRecordings ?? true, let audio = post.audio, let url = URL(string: audio.url) {
            startRecording(url: url, for: post)
        } else {
            mode = .speech
            speakSegment()
        }
    }

    private func speakSegment() {
        mode = .speech
        guard segmentIndex < segments.count else { advancePost(); return }
        let u = AVSpeechUtterance(string: segments[segmentIndex])
        u.voice = chosenVoice
        u.rate = rate
        u.postUtteranceDelay = 0.3
        synth.speak(u)
        isPlaying = true
        updateNowPlaying()
    }

    private var chosenVoice: AVSpeechSynthesisVoice? {
        if let id = preferences?.voiceID, let v = AVSpeechSynthesisVoice(identifier: id) { return v }
        return Self.preferredVoice
    }

    private func startRecording(url: URL, for post: Post) {
        mode = .recording
        isBuffering = true
        isPlaying = true
        updateNowPlaying()
        let id = post.id
        downloadTask?.cancel()
        downloadTask = Task { [weak self] in
            let local = await AudioCache.localURL(for: url, id: id)
            guard let self, !Task.isCancelled, self.current?.id == id, self.mode == .recording else { return }
            self.isBuffering = false
            guard let local else {
                // No recording reachable: fall back to the phone's voice for this post.
                self.speakSegment()
                return
            }
            self.attachPlayer(url: local)
        }
    }

    private func attachPlayer(url: URL) {
        let item = AVPlayerItem(url: url)
        item.audioTimePitchAlgorithm = .timeDomain
        let p = AVPlayer(playerItem: item)
        player = p
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.mode == .recording else { return }
                self.recordingProgress = 1
                self.advancePost()
            }
        }
        timeObserver = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self, let d = self.player?.currentItem?.duration.seconds, d.isFinite, d > 0 else { return }
                self.recordingProgress = min(1, max(0, time.seconds / d))
                self.updateNowPlaying(elapsed: time.seconds, duration: d)
            }
        }
        p.rate = playbackMultiplier
        isPlaying = true
        updateNowPlaying()
    }

    private func advancePost() {
        stopPlayback()
        if hasNext {
            index += 1
            loadCurrent()
            begin()
        } else {
            finish()
        }
    }

    private func finish() {
        stopPlayback()
        isPlaying = false
        finished = true
        segmentIndex = segments.count
        recordingProgress = 1
        updateNowPlaying()
    }

    private func stopSpeech() {
        if synth.isSpeaking || synth.isPaused {
            synth.stopSpeaking(at: .immediate)
        }
    }

    private func stopPlayback() {
        stopSpeech()
        downloadTask?.cancel()
        downloadTask = nil
        if let p = player {
            p.pause()
            if let t = timeObserver { p.removeTimeObserver(t) }
        }
        if let e = endObserver { NotificationCenter.default.removeObserver(e) }
        timeObserver = nil
        endObserver = nil
        player = nil
        isBuffering = false
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
            if isPlaying {
                if mode == .recording { player?.pause() } else { synth.pauseSpeaking(at: .word) }
                isPlaying = false
            }
        case .ended:
            let opts = AVAudioSession.InterruptionOptions(rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            if opts.contains(.shouldResume), isActive, !finished { toggle() }
        @unknown default: break
        }
    }

    // MARK: AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.isActive, self.mode == .speech else { return }
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

    private func updateNowPlaying(elapsed: Double? = nil, duration: Double? = nil) {
        guard let post = current else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: post.headline,
            MPMediaItemPropertyArtist: "Periop Signal · \(post.journal)",
            MPMediaItemPropertyAlbumTitle: "\(post.kind) · \(PSDate.display(post.date, long: true))",
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(playbackMultiplier) : 0.0,
            MPNowPlayingInfoPropertyIsLiveStream: false,
        ]
        if let duration { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let elapsed { info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed }
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

    // MARK: Voices

    /// Installed English voices, best first (Premium, Enhanced, then the compact ones).
    nonisolated static func englishVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { a, b in
                if rank(a) != rank(b) { return rank(a) > rank(b) }
                if a.language != b.language { return a.language == "en-US" }
                return a.name < b.name
            }
    }

    nonisolated static func rank(_ v: AVSpeechSynthesisVoice) -> Int {
        switch v.quality {
        case .premium: return 3
        case .enhanced: return 2
        default: return 1
        }
    }

    nonisolated static func qualityLabel(_ v: AVSpeechSynthesisVoice) -> String {
        switch v.quality {
        case .premium: return "Premium"
        case .enhanced: return "Enhanced"
        default: return "Compact"
        }
    }

    static let preferredVoice: AVSpeechSynthesisVoice? = {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "en-US" }
        return voices.max { rank($0) < rank($1) } ?? AVSpeechSynthesisVoice(language: "en-US")
    }()

    /// Speaks a short sample with a given voice (voice picker preview), without touching the queue.
    func preview(voice: AVSpeechSynthesisVoice) {
        guard !isActive else { return }
        activateSession()
        stopSpeech()
        let u = AVSpeechUtterance(string: "Periop Signal. In the RATE trial, low-dose heparin was noninferior to standard heparin on ECMO.")
        u.voice = voice
        u.rate = rate
        synth.speak(u)
    }

    // MARK: Text

    nonisolated static let kindSpoken: [String: String] = ["RCT": "a randomized trial", "Guideline": "a guideline", "Consensus": "a consensus statement", "Meta-analysis": "a meta-analysis",
                                                        "Observational": "an observational study", "Registry": "a registry study", "FDA/Regulatory": "a regulatory notice",
                                                        "Device": "device news", "Safety alert": "a safety alert", "Trial update": "a trial update", "Conference": "a conference report"]

    /// The post as spoken paragraphs: headline, source line, take-home, overview, stated limitations.
    nonisolated static func segments(for post: Post) -> [String] {
        var out: [String] = []
        out.append(spoken(post.headline))
        var source = "From \(post.journal), \(kindSpoken[post.kind] ?? post.kind.lowercased())"
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
    nonisolated static func spoken(_ s: String) -> String {
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

/// Downloads recordings once into Caches/audio and hands back the local file.
enum AudioCache {
    static var directory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func cached(id: String) -> URL? {
        let f = directory.appendingPathComponent(id + ".mp3")
        return FileManager.default.fileExists(atPath: f.path) ? f : nil
    }

    /// Returns the local file for a recording, downloading it first when needed; nil when unreachable.
    static func localURL(for remote: URL, id: String) async -> URL? {
        if let f = cached(id: id) { return f }
        do {
            let (tmp, response) = try await URLSession.shared.download(from: remote)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) { return nil }
            let dest = directory.appendingPathComponent(id + ".mp3")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
            return dest
        } catch {
            return nil
        }
    }

    /// Bytes on disk, for the settings screen.
    static var sizeOnDisk: Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: directory)
    }
}
