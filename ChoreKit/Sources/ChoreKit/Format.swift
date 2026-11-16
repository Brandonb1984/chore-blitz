import Foundation

/// "30:00", "4:05", "0:01" while time is left; "+1:30" once it's run over.
public func countdownText(_ remaining: TimeInterval) -> String {
    if remaining > 0 {
        let s = Int(remaining.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
    let s = Int((-remaining).rounded(.down))
    return String(format: "+%d:%02d", s / 60, s % 60)
}
