import AppKit
import Carbon.HIToolbox
import Hotkeys
import SwiftUI

/// Click to arm, then press a combo. Escape cancels, Delete clears.
struct HotkeyRecorder: NSViewRepresentable {
    @Binding var combo: KeyCombo?

    init(combo: Binding<KeyCombo?>) {
        _combo = combo
    }

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onChange = { combo = $0 }
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.combo = combo
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: RecorderView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 130, height: 22)
    }

    /// Captures key events itself instead of going through a global monitor, so
    /// recording needs no Accessibility permission.
    final class RecorderView: NSButton {
        var onChange: ((KeyCombo?) -> Void)?
        var combo: KeyCombo? {
            didSet { updateTitle() }
        }

        private var isRecording = false {
            didSet { updateTitle() }
        }

        init() {
            super.init(frame: .zero)
            bezelStyle = .push
            setButtonType(.momentaryPushIn)
            target = self
            action = #selector(startRecording)
            updateTitle()
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("unavailable") }

        override var acceptsFirstResponder: Bool { isRecording }

        @objc private func startRecording() {
            isRecording = true
            window?.makeFirstResponder(self)
        }

        override func resignFirstResponder() -> Bool {
            isRecording = false
            return super.resignFirstResponder()
        }

        override func keyDown(with event: NSEvent) {
            guard isRecording else {
                super.keyDown(with: event)
                return
            }

            switch Int(event.keyCode) {
            case kVK_Escape:
                break
            case kVK_Delete:
                onChange?(nil)
            default:
                guard let newCombo = KeyCombo(event: event) else { return }
                onChange?(newCombo)
            }
            window?.makeFirstResponder(nil)
        }

        private func updateTitle() {
            title = if isRecording {
                "Press a shortcut…"
            } else {
                combo?.displayString ?? "Record Shortcut"
            }
        }
    }
}
