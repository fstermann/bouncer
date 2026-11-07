import Foundation
import Screenshots

/// Takes a screenshot for a note and returns the embed of the saved image; `nil` once cancelled.
typealias TakeScreenshot = @MainActor (ScreenshotArea) async -> String?

/// An embed for a note's text to put in at its cursor; a new one each time, so the same embed twice
/// still counts as two.
struct EmbedRequest: Equatable {
    let embed: String
    let id = UUID()
}
