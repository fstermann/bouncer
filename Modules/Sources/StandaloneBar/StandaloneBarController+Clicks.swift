import AppKit
import BouncerFoundation

extension StandaloneBarController {
    /// Opens the real item a replica stands for.
    ///
    /// The sweep that finds the elements is usually long finished by the first click; when it
    /// is not, this waits for it rather than holding every open behind it.
    func forward(to item: MenuBarItem) {
        guard ClickForwarder.isPermitted else {
            Log.menuBar.error("Standalone bar: click ignored, Accessibility not granted")
            return
        }
        guard let resolving = resolvingElements else { return }
        Task { [weak self] in
            let elements = await resolving.value
            guard let self, let element = elements[item.windowID] else {
                Log.menuBar.error("Standalone bar: the clicked item cannot be reached")
                return
            }
            self.open(element)
        }
    }

    /// Presses an item's element and follows whatever menu it opens.
    private func open(_ element: ItemElement) {
        if let owner = ClickForwarder.owner(of: element) {
            menus.watch(pid: owner) { [weak self] isOpen in
                guard let self else { return }
                self.isMenuOpen = isOpen
                guard !isOpen else { return }
                self.menus.stop()
                // The pointer is usually deep in the menu that just closed.
                self.closeIfThePointerHasLeft()
            }
        }
        Task.detached { ClickForwarder.press(element) }
    }
}
