import ApplicationServices
import CoreGraphics
import Observation

/// The one place the overview's two permissions are read and requested: Screen Recording for window
/// titles and thumbnails, Accessibility to raise and move windows.
///
/// Requested when the user turns the overview on, never at launch. Re-read when Bouncer regains
/// focus after a visit to System Settings, and each time the overview opens, so it needs no timer.
@MainActor
@Observable
public final class DecksPermissions {
    public private(set) var screenRecording = false
    public private(set) var accessibility = false

    public init() { refresh() }

    public func refresh() {
        screenRecording = CGPreflightScreenCaptureAccess()
        accessibility = AXIsProcessTrusted()
    }

    /// Screen Recording only takes effect on the next launch, so a grant here will not flip
    /// `screenRecording` until Bouncer restarts.
    public func request() {
        if !screenRecording { CGRequestScreenCaptureAccess() }
        // The constant is exported as a mutable global, which Swift 6 will not read across isolation.
        if !accessibility { AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) }
    }
}
