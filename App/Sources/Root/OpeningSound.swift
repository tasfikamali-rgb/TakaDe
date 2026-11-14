import AVFoundation

/// The short opening sound (App/Resources/Sounds/opening.caf, made by
/// scripts/brand-sound/make_opening_sound.py). It plays with the opening on a cold launch
/// only, not on every return from the background, so switching to bKash and back stays
/// quiet. Settings > Appearance > Opening sound turns it off.
///
/// The audio session is `.ambient`: the ring/silent switch mutes it and it mixes with
/// whatever is already playing (music, a call) instead of stopping it.
@MainActor
enum OpeningSound {
    static let storageKey = "openingSoundOn"
    private static var player: AVAudioPlayer?

    static var isOn: Bool {
        UserDefaults.standard.object(forKey: storageKey) as? Bool ?? true
    }

    /// Loads the file ahead of time so `play()` starts on the exact frame of the split.
    static func prepare() {
        guard isOn, player == nil,
              let url = Bundle.main.url(forResource: "opening", withExtension: "caf") else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 0.8
            player.prepareToPlay()
            Self.player = player
        } catch {
            // No sound is fine: the opening is the same without it.
            Self.player = nil
        }
    }

    static func play() {
        guard isOn, let player else { return }
        player.currentTime = 0
        player.play()
    }

    /// Frees the player once the opening is over; it isn't needed again until the next launch.
    static func release() {
        player?.stop()
        player = nil
    }
}
