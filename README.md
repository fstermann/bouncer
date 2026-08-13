<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Assets/logo-dark.svg">
  <img src="Assets/logo-light.svg" alt="bouncer" height="96">
</picture>

### A menu bar manager for macOS. Decides what gets in.

bouncer splits the menu bar into three sections — **Visible**, **Hidden** and
**Always Hidden** — and collapses the ones you are not using.<br>
Reveal them with a click, or by moving the pointer into the menu bar.

<sub>Requires macOS 14 or later · Apple Silicon and Intel</sub>

</div>

## Principles

Two things decide every tradeoff:

**Speed.** Revealing a section is instant, and idle means *zero work* — no polling loops,
no background timers, no global event monitors installed for features you have turned off.
The core hide/show mechanism is a single `NSStatusItem` width assignment: no screen
capture, no per-item bookkeeping, no private API, and no Accessibility or Screen Recording
permission. The standalone bar is the one exception and is off by default: switching it on
asks for both, uses them for nothing else, and everything it installs goes away again when
the bar closes.

**Minimalism.** The interface is as small as the job allows. No dock icon, no window you
have to keep around, no chrome on the menu bar beyond one mark and the dividers doing the
work. Settings are a short list of plain choices rather than a wall of toggles, and
nothing animates for the sake of animating.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how the hiding actually works.

## Installing

Download the latest `.dmg` from [Releases](https://github.com/fstermann/bouncer/releases), drag
Bouncer into Applications, then run this once:

```sh
xattr -dr com.apple.quarantine /Applications/Bouncer.app
```

Bouncer is signed, but with a certificate Apple did not issue and has not notarized, so
Gatekeeper refuses to open it until the quarantine flag is gone. The certificate is not
decoration: it gives the app a stable identity, which is what lets macOS keep the permissions
the standalone bar was granted when a new version replaces the old one. Being asked to paste a
command is a fair reason to be suspicious of an app — the line above only removes that flag,
and you can read what the release ships in `.github/workflows/release.yml`.

Bouncer updates itself from then on, so the command is a one-time cost. It checks once a day,
tells you what it found, and installs nothing without being asked — turn the check off, or let
it install updates on its own, in Settings under **Updates**.

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

`make run` builds **Bouncer Dev** (`com.bouncer.app.dev`), a separate app from the one people
install: its own preferences, its own permission grants, its own login item, and no updater —
so it can sit in the menu bar next to a released Bouncer without either disturbing the other.
Both managing the same menu bar at once does mean two sets of dividers competing over it;
quit one when you are not comparing them.

A checkout builds and runs with no developer account, signed ad-hoc. Two certificates matter
beyond that, both named in `.signing.mk`, which is not checked in:

| | signs | why |
|---|---|---|
| `SIGN_IDENTITY` | `make build` / `make run` | An ad-hoc signature has no stable identity, so macOS forgets the standalone bar's permissions on every rebuild. Any self-signed Code Signing certificate fixes that, and it never leaves your machine. |
| `RELEASE_SIGN_IDENTITY` | `make release` | The identity users' permission grants and Sparkle updates are keyed to. Only ever used to cut a release; the release workflow holds it as a secret. Lose this key and every user re-grants both permissions. |

Versions and releases are handled by release-please off Conventional Commits — merging its
release PR tags the version and publishes the build.

Logic lives in small SwiftPM modules under `Modules/` with one job each and explicit
dependencies; anything worth testing is a pure function over plain values. The app target
is a thin shell that wires them together and owns no logic of its own.

## Status

On first launch nothing is hidden yet: the dividers start at the far left of the menu
bar, and Bouncer's mark appears near the right. Reveal a section, then Cmd-drag items to
the left of a divider to hide them — the same drag macOS already gives you. A revealed
section ends at the boundary glyph on its divider; anything to the right of it stays
visible.

Working today:

- Three-section menu bar with collapsing dividers
- Reveal by clicking bouncer's icon or its boundary glyph, or by pointer hover
- Auto-rehide: never, after a delay, or on app switch
- Launch at login, preferences persisted
- In-app updates, with the daily check and the automatic install both yours to turn off
- Standalone bar: the hidden section replicated below the menu bar rather than revealed in
  it — opt-in, and experimental. One display only, and nothing is drawn in a full screen
  space

Not built yet — see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#roadmap):

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
