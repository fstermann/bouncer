// Status items that make Bouncer's hidden section wider than the room right of the notch, for the bench's
// overflow scenarios. New items land in the hidden section. Runs until terminated.
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let items = (0..<12).map { index in
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.button?.title = "D\(index)"
    return item
}
app.run()
