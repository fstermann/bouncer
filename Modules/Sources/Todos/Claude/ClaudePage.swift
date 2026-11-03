import MenuBar
import Observation
import SwiftUI

/// One question and Claude's answer to it, as it arrives.
struct ClaudeExchange: Identifiable, Equatable, Codable {
    var id: Int
    let question: String
    var answer = ""
    /// The tool Claude is using while it has not yet gone on answering.
    var activity: String?
    var failure: String?
    var isAnswered = false
}

/// What the Claude page shows: the chats so far, or the questions asked in one and the answers to them.
@MainActor
@Observable
final class ClaudePage {
    var exchanges: [ClaudeExchange] = []
    /// Past chats, newest first, offered while no chat is showing.
    var chats: [ClaudeChat] = []
    var draft = ""
    /// The folder the next new chat starts in.
    var folder = ""
    /// What the folder menu offers: the folder set in Settings, then those past chats began in.
    var folders: [String] = []
    var isChoosingFolder = false
    @ObservationIgnored var folderAnchor: CGRect = .zero
    @ObservationIgnored var menuSize: CGSize = .zero
    /// Whether the chat showing has a session the terminal can resume.
    var canHandOff = false
    var menuBarHeight: CGFloat = 24
    var focusRequests = 0
    var listHeight: CGFloat = 0
    var contentHeight: CGFloat?

    @ObservationIgnored var onAsk: (@MainActor (String) -> Void)?
    @ObservationIgnored var onStop: (@MainActor () -> Void)?
    /// Leaves the chat for the list, so the next question starts a new one.
    @ObservationIgnored var onBack: (@MainActor () -> Void)?
    @ObservationIgnored var onPick: (@MainActor (ClaudeChat) -> Void)?
    @ObservationIgnored var onHandOff: (@MainActor () -> Void)?
    @ObservationIgnored var onPickFolder: (@MainActor (String) -> Void)?
    /// Picks a folder the menu does not offer, in an Open dialog.
    @ObservationIgnored var onChooseFolder: (@MainActor () -> Void)?
    @ObservationIgnored var onResize: (@MainActor () -> Void)?

    var isInChat: Bool { !exchanges.isEmpty }

    var folderName: String { URL(filePath: folder).lastPathComponent }

    var isAnswering: Bool { exchanges.last.map { !$0.isAnswered } ?? false }

    /// Nothing half-typed that the pointer leaving would throw away, and no menu open. An answer on
    /// its way, or one being read, is there again on the next open.
    var isIdle: Bool { draft.isEmpty && !isChoosingFolder }

    func ask() {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isAnswering else { return }
        draft = ""
        onAsk?(question)
    }

    static let width: CGFloat = 520
    static let maxListHeight: CGFloat = 420

    var height: CGFloat { contentHeight ?? menuBarHeight + 60 }
}

extension ClaudePage: PanelPage {
    var width: CGFloat { Self.width }
    func menuFrame(in panel: CGRect) -> CGRect? { folderMenuFrame(in: panel) }

    var view: ClaudePageView { ClaudePageView(page: self) }
    var menuView: FolderMenu { FolderMenu(page: self) }
}

struct ClaudePageView: View {
    nonisolated private static let list = "list"
    @Bindable var page: ClaudePage
    @FocusState private var isTyping: Bool
    @State private var aboveTop: CGFloat = 0
    @State private var belowBottom: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            topRow
            if page.isInChat {
                scrolling {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(page.exchanges) { ExchangeView(exchange: $0).id($0.id) }
                    }
                }
            } else if !page.chats.isEmpty {
                scrolling {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(page.chats) { chat in
                            ChatRow(chat: chat, showsFolder: chat.folderName != page.folderName) { page.onPick?(chat) }
                        }
                    }
                }
            }
            inputRow
        }
        .modifier(FolderMenuAnchoring(page: page))
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            page.contentHeight = height
            page.onResize?()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    /// Left of the notch the way back, or the folder new chats start in; right of the page button, the
    /// way to the terminal.
    private var topRow: some View {
        HStack(spacing: 8) {
            Group {
                if page.isInChat {
                    Button { page.onBack?() } label: { Label("Chats", systemImage: "chevron.left") }
                        .help("Back to your chats, where the next question starts a new one")
                } else {
                    Button { page.isChoosingFolder.toggle() } label: { Label(page.folderName, systemImage: "folder") }
                        .lineLimit(1)
                        .help("The folder the next chat starts in")
                        .anchorPreference(key: MenuAnchor.self, value: .bounds) { page.isChoosingFolder ? $0 : nil }
                }
            }
            .frame(maxWidth: Self.leftOfNotch, alignment: .leading)
            Spacer()
            if page.isInChat {
                Button { page.onHandOff?() } label: { Label("Terminal", systemImage: "apple.terminal") }
                    .disabled(!page.canHandOff || page.isAnswering)
                    .help("Go on with this chat in the terminal")
            }
        }
        .buttonStyle(TopRowButtonStyle())
        .font(.caption)
        .padding(.horizontal, 14)
        .frame(height: page.menuBarHeight)
    }

    private static let capHeight = NSFont.systemFont(ofSize: NSFont.systemFontSize).capHeight

    /// What the top row has left of a notch about 200 pt wide.
    private static var leftOfNotch: CGFloat { (ClaudePage.width - 200) / 2 - 20 }

    private func scrolling(@ViewBuilder _ content: () -> some View) -> some View {
        let content = content()
        return ScrollViewReader { proxy in
            ScrollView {
                content
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { page.listHeight = $0 }
                    .onGeometryChange(for: CGFloat.self) { -$0.frame(in: .named(Self.list)).minY } action: {
                        aboveTop = $0
                    }
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        let visible = geometry.bounds(of: .named(Self.list))?.height ?? .infinity
                        return geometry.frame(in: .named(Self.list)).maxY - visible
                    } action: { belowBottom = $0 }
                    .background(OverlayScrollers())
            }
            .coordinateSpace(.named(Self.list))
            .mask(EdgeFade(axis: .vertical, beforeStart: aboveTop, pastEnd: belowBottom, ramp: 6))
            .frame(height: min(page.listHeight, ClaudePage.maxListHeight))
            // Follows the answer down as it grows.
            .onChange(of: page.exchanges.last?.answer, initial: true) {
                if let last = page.exchanges.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private var inputRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(nsImage: ClaudeMark.image(side: 13))
                .renderingMode(.template)
                .frame(width: TodoPage.markWidth)
                .foregroundStyle(.secondary)
                // An image has no baseline, so it would sit on the text's; centred on its capitals instead.
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + Self.capHeight / 2 }
            TextField(page.isInChat ? "Reply" : "Ask away", text: $page.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused($isTyping)
                .onSubmit(page.ask)
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.shift) else { return .ignored }
                    page.draft += "\n"
                    return .handled
                }
            if page.isAnswering {
                Button { page.onStop?() } label: { Image(systemName: "stop.circle") }
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .help("Stop")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .onChange(of: page.focusRequests, initial: true) { isTyping = true }
    }
}

/// A text button that brightens under the pointer, small enough for the row beside the notch.
private struct TopRowButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.white.opacity(isHovered && isEnabled ? 0.12 : 0), in: .capsule)
            .foregroundStyle(isEnabled ? .secondary : .quaternary)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(.capsule)
            .onHover { isHovered = $0 }
    }
}

private struct ChatRow: View {
    let chat: ClaudeChat
    let showsFolder: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(chat.title)
                    .lineLimit(1)
                Spacer(minLength: 12)
                if showsFolder {
                    Text(chat.folderName)
                        .lineLimit(1)
                        .foregroundStyle(.tertiary)
                }
                Text(chat.updated, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.white.opacity(isHovered ? 0.08 : 0), in: .rect(cornerRadius: 6))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .font(.callout)
        .padding(.horizontal, -8)
        .onHover { isHovered = $0 }
        .help("Pick up this chat")
    }
}

extension ClaudeChat {
    var folderName: String { URL(filePath: folder).lastPathComponent }
}

private struct ExchangeView: View {
    let exchange: ClaudeExchange

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(exchange.question)
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.white.opacity(0.1), in: .rect(cornerRadius: 10))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 60)
            if !exchange.answer.isEmpty { MarkdownAnswer(text: exchange.answer) }
            if let failure = exchange.failure {
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            } else if !exchange.isAnswered {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    if let activity = exchange.activity {
                        Text(activity).font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// An answer drawn block by block: headings, lists, quotes, code and tables, with inline Markdown in each.
struct MarkdownAnswer: View {
    let text: String

    var body: some View {
        let blocks = MarkdownBlock.parse(text)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(blocks.indices, id: \.self) { index in
                view(for: blocks[index])
                    .padding(.top, index == 0 ? 0 : Self.gap(after: blocks[index - 1], before: blocks[index]))
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The items of one list sit closer together than the blocks around them.
    private static func gap(after previous: MarkdownBlock, before next: MarkdownBlock) -> CGFloat {
        if case .item = previous, case .item = next { return 4 }
        if case .heading = previous { return 4 }
        return 10
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let text):
            Text(Self.inline(text)).font(.headline)
        case .paragraph(let text):
            Text(Self.inline(text)).fixedSize(horizontal: false, vertical: true)
        case .item(let marker, let text, let depth):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(marker)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 14, alignment: .trailing)
                Text(Self.inline(text)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(depth) * 18)
        case .quote(let text):
            Text(Self.inline(text))
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
                .overlay(alignment: .leading) { Rectangle().fill(.quaternary).frame(width: 2) }
        case .code(let text):
            Text(text)
                .font(Self.codeFont)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.07), in: .rect(cornerRadius: 6))
        case .table(let rows):
            table(rows)
        case .rule:
            Divider()
        }
    }

    private func table(_ rows: [[String]]) -> some View {
        let columns = rows.map(\.count).max() ?? 0
        return Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            ForEach(rows.indices, id: \.self) { index in
                GridRow {
                    ForEach(0..<columns, id: \.self) { column in
                        Text(Self.inline(column < rows[index].count ? rows[index][column] : ""))
                            .fontWeight(index == 0 ? .semibold : nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if index == 0 { Divider().gridCellUnsizedAxes(.horizontal) }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.12)))
    }

    private static let codeFont = Font.system(size: 12, design: .monospaced)

    /// Inline code drawn a size smaller on a tint, so it reads as code rather than as wide-set words.
    private static func inline(_ text: String) -> AttributedString {
        var string = (try? AttributedString(
            markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
        for run in string.runs where run.inlinePresentationIntent?.contains(.code) == true {
            string[run.range].font = codeFont
            string[run.range].backgroundColor = .white.opacity(0.12)
        }
        return string
    }
}
