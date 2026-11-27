import AppKit
import SwiftUI

/// Bouncer's own symbols, drawn in `Assets/Icons` and built into this module's asset catalog by
/// `Tools/icons.sh`. They are symbol images, so they follow font size and weight like SF Symbols.
public enum Icon: String, CaseIterable, Sendable {
    // Pages
    case items, todos, note
    // Actions
    case close, closeCircle = "close-circle", plus, trash, pencil, search
    case chevronLeft = "chevron-left", chevronRight = "chevron-right", openLink = "open-link", restore, send
    case popOut = "pop-out", fullScreen = "full-screen", leaveFullScreen = "leave-full-screen", stop
    case camera, cameraRegion = "camera-region", archive, archiveFill = "archive-fill"
    case folder, folderAdd = "folder-add", terminal, refresh
    // States
    case checkmark, circle, circleHalf = "circle-half", checkCircle = "check-circle"
    case checkCircleFill = "check-circle-fill", dot, warning
    // Things
    case tag, calendar, bell, bellFill = "bell-fill", clock, timer, image, people, peopleFill = "people-fill"
    case link, today, tomorrow, briefcase, textCursor = "text-cursor"
    // Settings sections
    case toggles, cursorMotion = "cursor-motion", download
    // Deck badges
    case stack, star, heart, bolt, flame, leaf, house, chat, envelope, book, graduation, hammer, wrench, gear
    case code, sparkles, paintbrush, music, gamepad, cart

    /// A template symbol image, for AppKit; `nil` only if the catalog lacks it.
    public func nsImage(accessibilityDescription: String? = nil) -> NSImage? {
        let image = Bundle.module.image(forResource: rawValue)
        image?.accessibilityDescription = accessibilityDescription
        return image
    }
}

extension Image {
    public init(_ icon: Icon) {
        self.init(icon.rawValue, bundle: .module)
    }
}

extension Label where Title == Text, Icon == Image {
    public init(_ title: String, icon: BouncerFoundation.Icon) {
        self.init { Text(title) } icon: { Image(icon) }
    }
}
