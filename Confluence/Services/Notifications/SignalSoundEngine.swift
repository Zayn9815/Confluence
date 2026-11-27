import Foundation
import AVFoundation
import CoreHaptics
import UIKit

public enum AlertAudioKind: Sendable {
    case tradeSignal(SoundPreset)
    case trapWarning
    case newsRelease
    case preNewsCountdown
}

/// Manages bundled `.caf` in-app sound playback (`AVAudioSession.Category.ambient` so hardware
/// silent switch is strictly respected and background music is never interrupted) + CoreHaptics tactile double-tap.
@MainActor
public final class SignalSoundEngine {
    public static let shared = SignalSoundEngine()

    private var player: AVAudioPlayer?
    private var hapticEngine: CHHapticEngine?

    public init() {
        configureAmbientAudioSession()
        prepareHaptics()
    }

    public func configureAmbientAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: [])
        } catch {
            // Silent degradation if audio session is unavailable (e.g. simulator)
        }
    }

    public func prepareHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = true
            engine.resetHandler = { [weak self] in
                Task { @MainActor [weak self] in
                    try? self?.hapticEngine?.start()
                }
            }
            engine.stoppedHandler = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.hapticEngine = nil
                }
            }
            try engine.start()
            self.hapticEngine = engine
        } catch {
            self.hapticEngine = nil
        }
    }

    public func playAlert(kind: AlertAudioKind, soundEnabled: Bool, hapticsEnabled: Bool) {
        if soundEnabled {
            let fileName: String?
            switch kind {
            case .tradeSignal(let preset):
                fileName = preset.cafFileName
            case .trapWarning:
                fileName = "trap_warning.caf"
            case .newsRelease, .preNewsCountdown:
                fileName = "news_release_ping.caf"
            }
            if let fileName {
                playBundledCAF(named: fileName)
            }
        }
        if hapticsEnabled {
            triggerDoubleTapHaptic(strong: {
                if case .tradeSignal = kind { return true }
                return false
            }())
        }
    }

    public func previewSound(preset: SoundPreset, hapticsEnabled: Bool = true) {
        guard let fileName = preset.cafFileName else {
            if hapticsEnabled {
                triggerDoubleTapHaptic(strong: false)
            }
            return
        }
        playBundledCAF(named: fileName)
        if hapticsEnabled {
            triggerDoubleTapHaptic(strong: true)
        }
    }

    public func playCopyConfirmationHaptic(enabled: Bool) {
        guard enabled else { return }
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.success)
    }

    private func playBundledCAF(named fileName: String) {
        configureAmbientAudioSession()
        let resource = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        guard let url = Bundle.main.url(forResource: resource, withExtension: ext) else {
            return
        }
        do {
            let audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer.prepareToPlay()
            audioPlayer.play()
            self.player = audioPlayer
        } catch {
            // Fail silently without blocking UI
        }
    }

    private func triggerDoubleTapHaptic(strong: Bool) {
        if CHHapticEngine.capabilitiesForHardware().supportsHaptics {
            do {
                if hapticEngine == nil { prepareHaptics() }
                try hapticEngine?.start()
                let intensity1 = CHHapticEventParameter(parameterID: .hapticIntensity, value: strong ? 0.85 : 0.6)
                let sharpness1 = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.75)
                let intensity2 = CHHapticEventParameter(parameterID: .hapticIntensity, value: strong ? 1.0 : 0.75)
                let sharpness2 = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9)

                let tap1 = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity1, sharpness1], relativeTime: 0.0)
                let tap2 = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity2, sharpness2], relativeTime: 0.11)
                let pattern = try CHHapticPattern(events: [tap1, tap2], parameters: [])
                let player = try hapticEngine?.makePlayer(with: pattern)
                try player?.start(atTime: 0)
                return
            } catch {
                // Fall back to UIKit generator below
            }
        }
        let gen = UIImpactFeedbackGenerator(style: strong ? .medium : .light)
        gen.impactOccurred()
    }
}
