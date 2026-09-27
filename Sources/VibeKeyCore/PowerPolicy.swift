import Foundation

public enum VibeKeyPowerPolicy {
    /// Idle standby is host-initiated power management; long-connect mode keeps
    /// the firmware handshake alive while the Mac remains in normal use.
    public static func shouldEnterIdleStandby(
        isLongConnectedMode: Bool,
        standbyTimeoutSeconds: TimeInterval,
        idleInterval: TimeInterval
    ) -> Bool {
        guard !isLongConnectedMode, standbyTimeoutSeconds > 0 else { return false }
        return idleInterval >= standbyTimeoutSeconds
    }
}
