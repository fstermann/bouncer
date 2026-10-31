#if DEV
import AppKit
import BouncerFoundation
import MenuBar

/// Drives and photographs the bar from a shell, so a change can be checked without a person
/// watching it. Bouncer Dev only.
///
/// It lives in the app because the app holds the permissions: Screen Recording for pictures,
/// Accessibility for the items. A shell has neither. The observer is the only thing installed;
/// nothing runs until a command arrives. `Tools/barctl.swift` sends commands and prints replies.
@MainActor
public final class DevHarness {
    public static let commandName = Notification.Name("com.bouncer.dev.command")
    public static let replyName = Notification.Name("com.bouncer.dev.reply")

    private let controller: StandaloneBarController
    private let menuBar: MenuBarManager
    private var observer: NSObjectProtocol?

    public init(controller: StandaloneBarController, menuBar: MenuBarManager) {
        self.controller = controller
        self.menuBar = menuBar
    }

    public func listen() {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Self.commandName, object: nil, queue: .main
        ) { [weak self] note in
            // Copied out before the hop: the notification itself is not `Sendable`.
            let command = (note.object as? String) ?? ""
            let replyID = note.userInfo?["reply"] as? String
            Task { @MainActor in
                let result = await self?.handle(command) ?? "harness gone"
                Self.reply(result, to: replyID)
            }
        }
    }

    private func handle(_ command: String) async -> String {
        let words = command.split(separator: " ").map(String.init)
        let path = words.count > 1 ? words[1] : ""
        let number = words.count > 2 ? Double(words[2]) : nil
        let height = words.count > 3 ? Double(words[3]).map { CGFloat($0) } : nil
        switch words.first {
        case "click":
            menuBar.onIconClick?()
            return "clicked"
        case "open":
            await controller.open()
            return "opened"
        case "close":
            await controller.close()
            return "closed"
        case "hit":
            return DevBarReader.element(at: CGPoint(x: Double(path) ?? 0, y: number ?? 0))
        case "dump":
            return written(await state(), to: path)
        case "shoot":
            let height = number.map { CGFloat($0) } ?? DevCamera.defaultHeight
            return await outcome { try await DevCamera.shoot(height: height, to: URL(fileURLWithPath: path)) }
        case "record":
            let seconds = min(number ?? 3, DevCamera.longestRecording)
            return await outcome {
                try await DevCamera.record(
                    seconds: seconds, height: height ?? DevCamera.defaultHeight, to: URL(fileURLWithPath: path)
                )
            }
        case "drag":
            let hold = words.count > 3 ? Double(words[3]) ?? 0 : 0
            let start = CGPoint(x: Double(path) ?? 0, y: 12)
            await Self.cmdDrag(from: start, to: CGPoint(x: number ?? 0, y: 12), holding: hold)
            return "dragged"
        case "press":
            Self.click(at: CGPoint(x: Double(path) ?? 0, y: number ?? 0))
            return "pressed"
        default:
            return "unknown command: \(command)"
        }
    }

    /// A Cmd-drag as the user makes one, posted from here because the app holds Accessibility,
    /// which posting needs. It holds the item at `end` for `hold` seconds before letting go, and puts
    /// the pointer back where it was.
    private static func cmdDrag(from start: CGPoint, to end: CGPoint, holding hold: TimeInterval) async {
        let home = CGEvent(source: nil)?.location ?? start
        func post(_ type: CGEventType, at point: CGPoint) {
            let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
        post(.leftMouseDown, at: start)
        let steps = 30
        for step in 1...steps {
            try? await Task.sleep(for: .milliseconds(16))
            let progress = CGFloat(step) / CGFloat(steps)
            post(.leftMouseDragged, at: CGPoint(
                x: start.x + (end.x - start.x) * progress, y: start.y + (end.y - start.y) * progress
            ))
        }
        try? await Task.sleep(for: .seconds(0.1 + hold))
        post(.leftMouseUp, at: end)
        CGWarpMouseCursorPosition(home)
    }

    /// A left click as the user makes one, posted from here for the same reason as `cmdDrag`.
    private static func click(at point: CGPoint) {
        let home = CGEvent(source: nil)?.location ?? point
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }
        CGWarpMouseCursorPosition(home)
    }

    private func outcome(_ work: () async throws -> String) async -> String {
        do { return try await work() } catch { return "failed: \(error.localizedDescription)" }
    }

    private func written(_ text: String, to path: String) -> String {
        guard !path.isEmpty else { return text }
        do {
            try text.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
            return path
        } catch {
            return "failed: \(error.localizedDescription)"
        }
    }

    private static func reply(_ result: String, to id: String?) {
        guard let id else { return }
        DistributedNotificationCenter.default().postNotificationName(
            replyName, object: id, userInfo: ["result": result], deliverImmediately: true
        )
    }

    // MARK: - Reading the bar

    /// Every frame that matters: the items as Accessibility reports them, which is the only
    /// source on macOS 27, the window server's view, which is the source on 26, and the panel.
    private func state() async -> String {
        var lines: [String] = []
        if let screen = NSScreen.main {
            lines.append("screen \(Self.text(screen.frame))")
            if let notch = Notch.on(displayOf: screen.frame) {
                lines.append("notch \(Self.text(notch.range)) \(notch.isReal ? "real" : "stand-in")")
            }
        }
        lines.append("section ends at \(menuBar.hiddenSectionEnd.map { "\(Int($0))" } ?? "unknown")")
        lines.append(menuBar.devState)
        lines.append("chevron \(AgentOverflow.state)")
        let width = controller.lastLayout.map { "\(Int($0.width))" } ?? "unknown"
        lines.append("section width \(width) shift \(Int(menuBar.sectionShift))")
        lines.append("band \(controller.tab.devSpan.map(Self.text) ?? "none")")
        for item in await DevBarReader.accessibilityItems() {
            lines.append("item \(Self.text(item.frame)) \(item.owner)")
        }
        let own = StatusItemScanner.bouncersOwn()
        for item in StatusItemScanner.scan() {
            lines.append("window item \(item.windowID) \(Self.text(item.frame)) \(own[item.windowID] ?? "")")
        }
        for window in DevBarReader.bouncerWindows() {
            lines.append("bouncer window \(window.id) level \(window.layer) \(Self.text(window.frame))")
        }
        return lines.joined(separator: "\n")
    }

    private static func text(_ rect: CGRect) -> String {
        String(format: "x %.0f...%.0f y %.0f w %.0f h %.0f", rect.minX, rect.maxX, rect.minY, rect.width, rect.height)
    }

    private static func text(_ range: ClosedRange<CGFloat>) -> String {
        String(format: "%.1f...%.1f", range.lowerBound, range.upperBound)
    }
}
#endif
