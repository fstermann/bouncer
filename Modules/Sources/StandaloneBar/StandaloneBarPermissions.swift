import CoreGraphics
import Observation

/// Whether one of the standalone bar's two permissions is currently held.
public enum PermissionStatus: Sendable {
    case granted, missing
}

/// The one place the standalone bar's two permissions are read and requested: Screen
/// Recording to read other apps' items, Accessibility to click them. Keeping every call in
/// this type keeps the permission surface a directory rather than a grep, even now that the
/// settings pane shows and triggers it.
///
/// Requests happen when the user turns the standalone bar on — never at launch, never on
/// hover. macOS has no single dialog for both, so `request()` fires both prompts at once
/// rather than merging them.
@MainActor
@Observable
public final class StandaloneBarPermissions {
    public private(set) var screenRecording: PermissionStatus = .missing
    public private(set) var accessibility: PermissionStatus = .missing

    public var allGranted: Bool { screenRecording == .granted && accessibility == .granted }

    public init() { refresh() }

    /// Re-read both. Driven by the app regaining focus after the user visits System
    /// Settings, so it carries no timer and no poll.
    public func refresh() {
        screenRecording = Self.screenRecordingGranted ? .granted : .missing
        accessibility = ClickForwarder.isPermitted ? .granted : .missing
    }

    /// Ask for whichever is still missing, both at once — the moment the user turns the
    /// standalone bar on. Screen Recording only takes effect on the next launch, so a
    /// grant here will not flip `screenRecording` until Bouncer restarts.
    public func request() {
        if screenRecording == .missing { CGRequestScreenCaptureAccess() }
        if accessibility == .missing { ClickForwarder.requestPermission() }
    }

    /// Live preflight for the hover path, which reads it every time and needs no observation.
    public static var screenRecordingGranted: Bool { CGPreflightScreenCaptureAccess() }
}
