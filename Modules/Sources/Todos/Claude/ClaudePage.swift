import Observation
import SwiftUI

/// One question and Claude's answer to it, as it arrives.
struct ClaudeExchange: Identifiable, Equatable {
    let id: Int
    let question: String
    var answer = ""
    /// The tool Claude is using while it has not yet gone on answering.
    var activity: String?
    var failure: String?
    var isAnswered = false
}

/// What the Claude page shows: the questions asked in this conversation and the answers to them.
@MainActor
@Observable
final class ClaudePage {
    var exchanges: [ClaudeExchange] = []
    var draft = ""
    /// The folder Claude is asked in, by name.
    var folderName = ""
    var menuBarHeight: CGFloat = 24
    var focusRequests = 0
    var listHeight: CGFloat = 0
    var contentHeight: CGFloat?

    @ObservationIgnored var onAsk: (@MainActor (String) -> Void)?
    @ObservationIgnored var onStop: (@MainActor () -> Void)?
    /// Forgets the conversation, so the next question starts a new one.
    @ObservationIgnored var onNew: (@MainActor () -> Void)?
    @ObservationIgnored var onResize: (@MainActor () -> Void)?

    var isAnswering: Bool { exchanges.last.map { !$0.isAnswered } ?? false }

    /// Nothing half-typed that the pointer leaving would throw away. An answer on its way, or one
    /// being read, is there again on the next open.
    var isIdle: Bool { draft.isEmpty }

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
    func menuFrame(in panel: CGRect) -> CGRect? { nil }
    var view: ClaudePageView { ClaudePageView(page: self) }
    var menuView: EmptyView { EmptyView() }
}

struct ClaudePageView: View {
    private static let list = "list"
    @Bindable var page: ClaudePage
    @FocusState private var isTyping: Bool
    @State private var aboveTop: CGFloat = 0
    @State private var belowBottom: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            topRow
            if !page.exchanges.isEmpty { list }
            inputRow
        }
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            page.contentHeight = height
            page.onResize?()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    private var topRow: some View {
        HStack(spacing: 8) {
            Text(page.folderName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help("The folder Claude is asked in, set in Settings")
            if !page.exchanges.isEmpty {
                Button { page.onNew?() } label: { Image(systemName: "square.and.pencil") }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .help("New conversation")
            }
            Spacer()
        }
        // Left of the notch, since the page button takes the right.
        .frame(maxWidth: Self.leftOfNotch, alignment: .leading)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: page.menuBarHeight)
    }

    /// What the top row has left of a notch about 200 pt wide.
    private static var leftOfNotch: CGFloat { (ClaudePage.width - 200) / 2 - 20 }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(page.exchanges) { ExchangeView(exchange: $0).id($0.id) }
                }
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
            Image(systemName: "sparkle")
                .frame(width: TodoPage.markWidth)
                .foregroundStyle(.tertiary)
            TextField(page.exchanges.isEmpty ? "Ask Claude" : "Ask a follow-up", text: $page.draft, axis: .vertical)
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

private struct ExchangeView: View {
    let exchange: ClaudeExchange

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(exchange.question)
                .foregroundStyle(.secondary)
            if !exchange.answer.isEmpty {
                Text(Self.markdown(exchange.answer))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
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

    /// Bold, italics, code and links; the lines as they came, since block syntax is not drawn.
    private static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
