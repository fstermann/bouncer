import Foundation
import Screenshots

/// Takes a screenshot and returns what to type for the saved image, an embed in a note or a path in a
/// question to Claude; `nil` once cancelled.
typealias TakeScreenshot = @MainActor (ScreenshotArea) async -> String?

/// An embed for a note's text to put in at its cursor; a new one each time, so the same embed twice
/// still counts as two.
struct EmbedRequest: Equatable {
    let embed: String
    let id = UUID()
}
