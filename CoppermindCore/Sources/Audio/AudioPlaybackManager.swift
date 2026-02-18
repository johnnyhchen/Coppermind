// AudioPlaybackManager.swift — AVAudioPlayer wrapper for recording playback
// CoppermindCore

import AVFoundation
import Foundation
import Observation

/// Manages audio playback of recorded notes with transport controls, progress tracking,
/// and segment-based playback for reviewing individual transcription segments.
@Observable
public final class AudioPlaybackManager: @unchecked Sendable {

    // MARK: - State

    public enum PlaybackState: Sendable, Equatable {
        case idle
        case loading
        case playing(progress: Double)
        case paused(progress: Double)
        case finished
        case error(String)
    }

    // MARK: - Observable Properties

    public private(set) var state: PlaybackState = .idle
    public private(set) var currentTime: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public private(set) var currentLevel: Float = 0

    /// Whether audio is actively playing.
    public var isPlaying: Bool {
        if case .playing = state { return true }
        return false
    }

    /// Playback rate (0.5x – 2.0x).
    public var playbackRate: Float = 1.0 {
        didSet {
            playbackRate = min(max(playbackRate, 0.5), 2.0)
            audioPlayer?.rate = playbackRate
        }
    }

    // MARK: - Private Properties

    private var audioPlayer: AVAudioPlayer?
    private var progressTimer: Timer?
    private var segmentEndTime: TimeInterval?
    private var currentFileURL: URL?
    private let delegateHandler = PlayerDelegateHandler()

    // MARK: - Init

    public init() {
        delegateHandler.onFinish = { [weak self] in
            self?.handlePlaybackFinished()
        }
    }

    // MARK: - Playback Controls

    /// Load and play an audio file from the beginning.
    ///
    /// - Parameter url: The URL of the audio file.
    public func play(from url: URL) async throws {
        state = .loading

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = delegateHandler
            player.enableRate = true
            player.rate = playbackRate
            player.isMeteringEnabled = true
            player.prepareToPlay()

            self.audioPlayer = player
            self.currentFileURL = url
            self.duration = player.duration
            self.currentTime = 0
            self.segmentEndTime = nil

            player.play()
            startProgressTimer()
            state = .playing(progress: 0)
        } catch {
            state = .error(error.localizedDescription)
            throw error
        }
    }

    /// Legacy alias for backward compatibility.
    public func play(url: URL) async throws {
        try await play(from: url)
    }

    /// Play a specific segment of the audio (timestamp + duration).
    /// Automatically pauses when the segment ends.
    ///
    /// - Parameters:
    ///   - segment: The transcription segment to play.
    ///   - url: The audio file URL. If already loaded, reuses the player.
    public func playSegment(
        _ segment: TranscriptionResult.Segment,
        from url: URL
    ) async throws {
        // If the same file is already loaded, just seek
        if let player = audioPlayer, currentFileURL == url {
            player.currentTime = segment.timestamp
            segmentEndTime = segment.timestamp + segment.duration
            currentTime = segment.timestamp

            if !player.isPlaying {
                player.play()
                startProgressTimer()
            }
            state = .playing(progress: segment.timestamp / duration)
        } else {
            // Load the file first, then seek
            try await play(from: url)
            audioPlayer?.currentTime = segment.timestamp
            currentTime = segment.timestamp
            segmentEndTime = segment.timestamp + segment.duration
        }
    }

    /// Play a time range within the audio.
    ///
    /// - Parameters:
    ///   - startTime: Start time in seconds.
    ///   - endTime: End time in seconds.
    public func playRange(from startTime: TimeInterval, to endTime: TimeInterval) {
        guard let player = audioPlayer else { return }

        let clampedStart = min(max(startTime, 0), duration)
        let clampedEnd = min(max(endTime, clampedStart), duration)

        player.currentTime = clampedStart
        currentTime = clampedStart
        segmentEndTime = clampedEnd

        if !player.isPlaying {
            player.play()
            startProgressTimer()
        }
        state = .playing(progress: clampedStart / duration)
    }

    /// Pause playback.
    public func pause() {
        guard case .playing = state else { return }

        audioPlayer?.pause()
        stopProgressTimer()
        let progress = duration > 0 ? currentTime / duration : 0
        state = .paused(progress: progress)
    }

    /// Resume paused playback.
    public func resume() {
        guard case .paused = state else { return }

        audioPlayer?.play()
        startProgressTimer()
        state = .playing(progress: duration > 0 ? currentTime / duration : 0)
    }

    /// Toggle between play and pause.
    public func togglePlayPause() {
        if case .playing = state {
            pause()
        } else if case .paused = state {
            resume()
        }
    }

    /// Stop playback entirely and release resources.
    public func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        stopProgressTimer()
        currentTime = 0
        duration = 0
        currentLevel = 0
        segmentEndTime = nil
        currentFileURL = nil
        state = .idle
    }

    /// Seek to a specific time.
    ///
    /// - Parameter time: Target time in seconds.
    public func seek(to time: TimeInterval) {
        let clampedTime = min(max(time, 0), duration)
        audioPlayer?.currentTime = clampedTime
        currentTime = clampedTime

        // Clear segment end if seeking outside of it
        if let endTime = segmentEndTime, clampedTime >= endTime {
            segmentEndTime = nil
        }
    }

    /// Skip forward by a number of seconds.
    public func skipForward(seconds: TimeInterval = 15) {
        seek(to: currentTime + seconds)
    }

    /// Skip backward by a number of seconds.
    public func skipBackward(seconds: TimeInterval = 15) {
        seek(to: currentTime - seconds)
    }

    // MARK: - Progress Info

    /// Formatted current time string (mm:ss).
    public var formattedCurrentTime: String {
        Self.format(time: currentTime)
    }

    /// Formatted duration string (mm:ss).
    public var formattedDuration: String {
        Self.format(time: duration)
    }

    /// Formatted remaining time string (-mm:ss).
    public var formattedRemainingTime: String {
        "-" + Self.format(time: max(duration - currentTime, 0))
    }

    /// Progress as a fraction (0.0–1.0).
    public var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    // MARK: - Private Helpers

    private func startProgressTimer() {
        stopProgressTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.updateProgress()
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func updateProgress() {
        guard let player = audioPlayer else { return }

        currentTime = player.currentTime
        player.updateMeters()
        currentLevel = player.averagePower(forChannel: 0)

        // Check if segment playback should stop
        if let endTime = segmentEndTime, currentTime >= endTime {
            player.pause()
            currentTime = endTime
            segmentEndTime = nil
            stopProgressTimer()
            let progress = duration > 0 ? currentTime / duration : 0
            state = .paused(progress: progress)
            return
        }

        if !player.isPlaying && currentTime >= duration - 0.1 {
            handlePlaybackFinished()
        } else {
            let progress = duration > 0 ? currentTime / duration : 0
            state = .playing(progress: progress)
        }
    }

    private func handlePlaybackFinished() {
        state = .finished
        stopProgressTimer()
        segmentEndTime = nil
    }

    /// Format seconds as mm:ss.
    private static func format(time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    deinit {
        progressTimer?.invalidate()
        audioPlayer?.stop()
    }
}

// MARK: - AVAudioPlayerDelegate Handler

/// Delegate handler for AVAudioPlayer completion events.
/// Separated from the main class to avoid @unchecked Sendable on the delegate conformance.
private final class PlayerDelegateHandler: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {

    var onFinish: (() -> Void)?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish?()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        onFinish?()
    }
}
