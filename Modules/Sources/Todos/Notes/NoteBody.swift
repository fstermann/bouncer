import AppKit
import SwiftUI

/// A note's text, with each embedded image shown as one photo icon that shows the image while the
/// pointer rests on it, and goes with one Backspace. The text is kept as Markdown, the icons as the
/// embeds they stand for.
struct NoteBody: NSViewRepresentable {
    @Binding var text: String
    let images: PastedImages?
    /// Bumped to put the cursor in the text.
    let focusRequests: Int
    let onFocus: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NoteTextView(usingTextLayoutManager: false)
        textView.delegate = context.coordinator
        textView.images = images
        textView.onFocus = onFocus
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = NoteTextView.font
        textView.textColor = .white
        textView.insertionPointColor = .white
        textView.typingAttributes = NoteTextView.attributes
        textView.isVerticallyResizable = true
        textView.autoresizingMask = .width
        textView.textContainer?.widthTracksTextView = true
        textView.textStorage?.setAttributedString(NoteTextView.attributed(text))
        context.coordinator.shown = text

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.scrollerKnobStyle = .light
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NoteTextView else { return }
        context.coordinator.body = self
        textView.images = images
        textView.onFocus = onFocus
        if text != context.coordinator.shown {
            textView.textStorage?.setAttributedString(NoteTextView.attributed(text))
            context.coordinator.shown = text
        }
        if focusRequests > 0, focusRequests != context.coordinator.focusRequests {
            context.coordinator.focusRequests = focusRequests
            // A turn later, once the view is in the window.
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var body: NoteBody
        /// The Markdown the view shows, so an update with the same text leaves the view alone.
        var shown = ""
        var focusRequests = 0

        init(_ body: NoteBody) {
            self.body = body
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NoteTextView else { return }
            shown = textView.markdown
            body.text = shown
        }
    }
}

/// Stands for one embedded image in the note's text.
final class ImageAttachment: NSTextAttachment {
    let name: String
    /// The embed as written, `![[name|300]]` with a width, so it is written back the same.
    let raw: String

    init(name: String, raw: String) {
        self.name = name
        self.raw = raw
        super.init(data: nil, ofType: nil)
        image = Self.icon
        let size = Self.icon.size
        bounds = CGRect(x: 0, y: -2, width: size.width, height: size.height)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private static let icon: NSImage = {
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white.withAlphaComponent(0.6)]))
        let symbol = NSImage(systemSymbolName: "photo", accessibilityDescription: "Image")?
            .withSymbolConfiguration(configuration) ?? NSImage()
        return symbol
    }()
}

final class NoteTextView: NSTextView {
    var images: PastedImages?
    var onFocus: ((Bool) -> Void)?
    private var hovered: ImageAttachment?
    private var hovering: Task<Void, Never>?

    static let font = NSFont.systemFont(ofSize: 13)
    /// White, as the panel is black whatever the system's appearance.
    static var attributes: [NSAttributedString.Key: Any] { [.font: font, .foregroundColor: NSColor.white] }
    private static let hoverDelay: Duration = .milliseconds(300)

    static func attributed(_ markdown: String) -> NSAttributedString {
        let text = NSMutableAttributedString()
        for segment in ImageEmbed.segments(of: markdown) {
            switch segment {
            case .text(let string):
                text.append(NSAttributedString(string: string, attributes: attributes))
            case .image(let name, let raw):
                text.append(embed(ImageAttachment(name: name, raw: raw)))
            }
        }
        return text
    }

    private static func embed(_ attachment: ImageAttachment) -> NSAttributedString {
        let text = NSMutableAttributedString(attachment: attachment)
        text.addAttributes(attributes, range: NSRange(location: 0, length: text.length))
        return text
    }

    var markdown: String {
        markdown(in: NSRange(location: 0, length: textStorage?.length ?? 0))
    }

    private func markdown(in range: NSRange) -> String {
        guard let storage = textStorage else { return "" }
        var markdown = ""
        storage.enumerateAttribute(.attachment, in: range) { value, run, _ in
            if let attachment = value as? ImageAttachment {
                markdown += String(repeating: attachment.raw, count: run.length)
            } else {
                markdown += (storage.string as NSString).substring(with: run)
            }
        }
        return markdown
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onFocus?(true) }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { onFocus?(false) }
        return resigned
    }

    // MARK: Pasting and copying images

    override func paste(_ sender: Any?) {
        guard let png = PastedImageKeys.png(on: .general), let embed = images?.save(png),
              case .image(let name, let raw) = ImageEmbed.segments(of: embed).first
        else { return super.paste(sender) }
        insert(Self.embed(ImageAttachment(name: name, raw: raw)))
    }

    /// As Markdown, so an image copied out keeps its embed rather than becoming a blank.
    override func copy(_ sender: Any?) {
        let selection = selectedRange()
        guard selection.length > 0 else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown(in: selection), forType: .string)
    }

    override func cut(_ sender: Any?) {
        copy(sender)
        insert(NSAttributedString(string: "", attributes: Self.attributes))
    }

    private func insert(_ text: NSAttributedString) {
        let range = selectedRange()
        guard let storage = textStorage, shouldChangeText(in: range, replacementString: text.string) else { return }
        storage.replaceCharacters(in: range, with: text)
        didChangeText()
        setSelectedRange(NSRange(location: range.location + text.length, length: 0))
        typingAttributes = Self.attributes
    }

    // MARK: Showing an image on hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.filter { $0.owner === self && $0.userInfo?["images"] != nil }.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: ["images": true]
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        hover(attachment(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hover(nil)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil { hover(nil) }
    }

    /// The image icon under `point`, in the view's coordinates.
    private func attachment(at point: CGPoint) -> ImageAttachment? {
        guard let layoutManager, let textContainer, let storage = textStorage, storage.length > 0 else { return nil }
        let inContainer = CGPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = layoutManager.glyphIndex(for: inContainer, in: textContainer)
        guard layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
            .contains(inContainer) else { return nil }
        let index = layoutManager.characterIndexForGlyph(at: glyph)
        guard index < storage.length else { return nil }
        return storage.attribute(.attachment, at: index, effectiveRange: nil) as? ImageAttachment
    }

    private func hover(_ attachment: ImageAttachment?) {
        guard attachment !== hovered else { return }
        hovered = attachment
        hovering?.cancel()
        ImagePopover.shared.hide()
        guard let attachment, let images else { return }
        hovering = Task { [weak self] in
            try? await Task.sleep(for: Self.hoverDelay)
            guard !Task.isCancelled, self?.hovered === attachment, let image = images.load(attachment.name) else {
                return
            }
            ImagePopover.shared.show(image, under: NSEvent.mouseLocation)
        }
    }
}
