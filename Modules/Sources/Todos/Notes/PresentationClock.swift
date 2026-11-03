import AppKit
import MenuBar
import Observation
import SwiftUI

/// The timer running for a talk, if any, and its label beside the notch, which stays up with the
/// panel closed.
///
/// The label's digits are SwiftUI's own timer text, which the system redraws; Bouncer schedules
/// nothing but one wait for each change of colour, and none at all once the timer is stopped.
@MainActor
@Observable
final class PresentationClock {
    private(set) var timer: PresentationTimer?
    private(set) var phase: PresentationTimer.Phase = .running

    @ObservationIgnored private var label: TimerLabelWindow?
    @ObservationIgnored private var phaseChange: Task<Void, Never>?

    static let minutes = [5, 10, 15, 20, 30, 45, 60]

    func startCountdown(minutes: Int) {
        start(PresentationTimer(kind: .countdown(TimeInterval(minutes * 60)), start: Date()))
    }

    func startStopwatch() {
        start(PresentationTimer(kind: .stopwatch, start: Date()))
    }

    func stop() {
        phaseChange?.cancel()
        phaseChange = nil
        timer = nil
        label?.orderOut(nil)
        label = nil
    }

    private func start(_ timer: PresentationTimer) {
        stop()
        self.timer = timer
        updatePhase()
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }
        let label = TimerLabelWindow(clock: self, on: screen)
        label.orderFrontRegardless()
        self.label = label
    }

    private func updatePhase() {
        guard let timer else { return }
        let now = Date()
        phase = timer.phase(at: now)
        guard let next = timer.nextChange(after: now) else { return }
        phaseChange = Task { [weak self] in
            try? await Task.sleep(for: .seconds(next.timeIntervalSinceNow))
            guard !Task.isCancelled else { return }
            self?.updatePhase()
        }
    }
}

/// The time left, or since the start, live.
struct TimerText: View {
    let timer: PresentationTimer
    let phase: PresentationTimer.Phase

    var body: some View {
        Group {
            if let end = timer.end, phase != .over {
                Text(timerInterval: timer.start...end, countsDown: true)
            } else {
                // Past a countdown's end, the time it has run over.
                Text(phase == .over ? "+" : "") + Text(timer.end ?? timer.start, style: .timer)
            }
        }
        .monospacedDigit()
        .foregroundStyle(color)
    }

    private var color: Color {
        switch phase {
        case .running: .white
        case .ending: .orange
        case .over: .red
        }
    }
}

/// The timer as a black tab grown out of the notch's left side, at the menu bar's height, where
/// the app menus seldom reach. Clicking it offers to stop the timer.
private final class TimerLabelWindow: NSPanel {
    private static let width: CGFloat = 64

    init(clock: PresentationClock, on screen: NSScreen) {
        let notch = DisplayNotch.range(
            left: screen.auxiliaryTopLeftArea, right: screen.auxiliaryTopRightArea, screen: screen.frame
        )
        let height = screen.menuBarHeight
        // Into the notch a little, so the tab reads as part of it, its square end hidden behind it.
        // Without a notch, a pill at the top centre.
        let left = notch.isReal ? notch.range.lowerBound - Self.width + 8 : screen.frame.midX - Self.width / 2
        let frame = CGRect(x: left, y: screen.frame.maxY - height, width: Self.width, height: height)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // Under the pages' panel, which covers it while open.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 3)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        contentView = NSHostingView(rootView: TimerLabel(clock: clock, isBesideNotch: notch.isReal))
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

private struct TimerLabel: View {
    let clock: PresentationClock
    let isBesideNotch: Bool

    var body: some View {
        Menu {
            Button("Stop Timer", action: clock.stop)
        } label: {
            if let timer = clock.timer {
                TimerText(timer: timer, phase: clock.phase)
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .padding(.trailing, isBesideNotch ? 8 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            UnevenRoundedRectangle(
                bottomLeadingRadius: 8, bottomTrailingRadius: isBesideNotch ? 0 : 8
            ).fill(.black)
        )
        .environment(\.colorScheme, .dark)
    }
}
