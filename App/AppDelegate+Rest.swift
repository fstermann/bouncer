#if DEV
extension AppDelegate {
    /// The harness command that closes everything at once: where every `make bench` run starts.
    func wireRest() {
        harness?.commands["rest"] = { [weak self] _ in
            guard let self else { return "gone" }
            for (_, controller) in contentPages where controller.isOpen {
                await controller.close(animated: false, into: nil)
            }
            if decks.isOpen { decks.close() }
            await standaloneBar.close()
            return "at rest"
        }
    }
}
#endif
