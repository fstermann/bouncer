<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Assets/logo-dark.svg">
  <img src="Assets/logo-light.svg" alt="bouncer" height="96">
</picture>

### A menu bar manager for macOS. Decides what gets in.

bouncer splits the menu bar into three sections — **Visible**, **Hidden** and
**Always Hidden** — and collapses the ones you are not using.<br>
Reveal them with a click, a keyboard shortcut, or by moving the pointer into the menu bar.

<sub>Requires macOS 14 or later · Apple Silicon and Intel</sub>

</div>

## Principles

Two things decide every tradeoff:

**Speed.** Revealing a section is instant, and idle means *zero work* — no polling loops,
no background timers, no global event monitors installed for features you have turned off.
The core hide/show mechanism is a single `NSStatusItem` width assignment: no screen
capture, no per-item bookkeeping, no private API, and no Accessibility or Screen Recording
permission.

**Minimalism.** The interface is as small as the job allows. No dock icon, no window you
have to keep around, no chrome on the menu bar beyond one mark and the dividers doing the
work. Settings are a short list of plain choices rather than a wall of toggles, and
nothing animates for the sake of animating.

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

Logic lives in small SwiftPM modules under `Modules/` with one job each and explicit
dependencies; anything worth testing is a pure function over plain values. The app target
is a thin shell that wires them together and owns no logic of its own.

## Status

On first launch nothing is hidden yet: the dividers start at the far left of the menu
bar, and Bouncer's mark appears near the right. Open **Settings → Menu Bar → Arrange
menu bar items**, then Cmd-drag items to the left of a divider to hide them. A revealed
section ends at the boundary glyph on its divider; anything to the right of it stays
visible.

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

`App/Resources/Logo.svg` is the source of truth for the mark. The menu bar glyph, the same
glyph with its dot hollowed out, and the boundary glyph and its mirror are cropped out of
it into `MenuBarIcon.imageset`, `MenuBarIconOpen.imageset`, `SectionEndIcon.imageset` and
`SectionStartIcon.imageset` and flattened to one colour, because status item images must
be templates — the boundary glyphs are a lighter tone by way of partial alpha, which the
system tints along with the rest. All keep the mark's 96-unit box so one height sizes them
together. `Assets/` holds the
derived lockups and the app icon; the wordmark there is a geometric grotesque drawn as
vector paths, so it renders identically everywhere with no font dependency. Gotham
itself is a licensed Hoefler&Co face — if you hold a licence, reset the wordmark in
Gotham Bold, lowercase, and drop it into `Assets/logo-{light,dark}.svg`.

## License

MIT
