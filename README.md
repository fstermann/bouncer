<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Assets/logo-dark.svg">
  <img src="Assets/logo-light.svg" alt="bouncer" height="96">
</picture>

A menu bar manager for macOS. Decides what gets in.

bouncer splits the menu bar into three sections — **Visible**, **Hidden**, and
**Always Hidden** — and collapses the ones you are not using. Reveal them with a click,
a keyboard shortcut, or by moving the pointer into the menu bar.

Requires macOS 14 or later. Apple Silicon and Intel.

## Design principles

Two rules decide every tradeoff in this codebase:

**Resource efficiency.** bouncer is idle almost all of the time, and idle must mean
*zero work*. No polling loops, no timers ticking in the background, no global event
monitors installed for features you have turned off. The core hide/show mechanism is a
single `NSStatusItem` width assignment — no screen capture, no per-item bookkeeping,
no private API. bouncer never asks for Accessibility or Screen Recording permission.

**Clean design.** Logic lives in small SwiftPM modules with one job each and explicit
dependencies. Anything worth testing is a pure function over plain values. The app
target is a thin shell that wires modules together and owns no logic of its own.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how the hiding actually works.

## Building

Requires Xcode 16.4 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen swiftlint`).

```sh
make run       # generate the project, build, launch
make test      # module tests, no Xcode project needed
make lint      # SwiftLint
```

`Bouncer.xcodeproj` is generated from `project.yml` and is not checked in — edit
`project.yml`, then `make generate`.

## Status

On first launch nothing is hidden yet: the dividers start at the far left of the menu
bar, and Bouncer's chevron appears near the right. Open **Settings → Menu Bar → Arrange
menu bar items**, then Cmd-drag items to the left of a divider to hide them.

Working today:

- Three-section menu bar with collapsing dividers
- Reveal by clicking bouncer's icon, a global shortcut, or pointer hover
- Auto-rehide: never, after a delay, or on app switch
- Layout inspector showing which section each item is in
- Launch at login, preferences persisted

Not built yet — see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#roadmap):

- Rendering hidden items in a standalone bar rather than revealing the real menu bar
- Per-app rules and profiles
- Custom menu bar appearance
- Per-display behavior

## Brand

`App/Resources/Logo.svg` is the source of truth for the mark. The menu bar glyph and the
boundary dot are cropped out of it into `MenuBarIcon.imageset` and `DividerIcon.imageset`
and flattened to one colour, because status item images must be templates; both keep the
mark's 96-unit box so one height sizes them together. `Assets/` holds the
derived lockups and the app icon; the wordmark there is a geometric grotesque drawn as
vector paths, so it renders identically everywhere with no font dependency. Gotham
itself is a licensed Hoefler&Co face — if you hold a licence, reset the wordmark in
Gotham Bold, lowercase, and drop it into `Assets/logo-{light,dark}.svg`.

## License

MIT
