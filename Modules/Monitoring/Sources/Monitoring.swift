/// The factory: what the Monitor needs from this machine, built here so the
/// App never names an implementation.
public enum Monitoring {
    /// Sleep, wake and battery as this machine reports them; `nil` where the
    /// platform has no adapter, and the Monitor then never pauses for power.
    public static func makePowerState() -> (any PowerStateProvider)? {
        #if os(macOS)
        SystemPowerStateProvider()
        #else
        nil
        #endif
    }
}
