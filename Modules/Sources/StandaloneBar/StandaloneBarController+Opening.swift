extension StandaloneBarController {
    /// Open, or on its way: what another page has to wait for, not open over.
    public var isShowing: Bool { isOpen || isOpening }

    /// Returns once an open underway has finished, at once if none is.
    public func opening() async {
        guard isOpening else { return }
        await withCheckedContinuation { whenOpened.append($0) }
    }

    func endOpening() {
        isOpening = false
        whenOpened.forEach { $0.resume() }
        whenOpened = []
    }
}
