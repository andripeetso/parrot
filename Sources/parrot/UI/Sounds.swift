import AppKit

/// Short system sounds for recording start and stop.
enum Sounds {
    static var enabled = true
    private static let start = NSSound(named: "Tink")
    private static let stop = NSSound(named: "Pop")

    static func playStart() { play(start) }
    static func playStop() { play(stop) }

    private static func play(_ sound: NSSound?) {
        guard enabled, UserDefaults.standard.object(forKey: Prefs.sounds) as? Bool ?? true, let sound else { return }
        sound.stop()
        sound.play()
    }
}
