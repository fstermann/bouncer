# Architecture

## How hiding works

macOS lays status items out right to left and gives each item a width. There is no API
to hide someone else's status item — but an item's width is ours to choose, and a wide
enough item pushes everything to its left past the edge of the display.

Bouncer creates two status items and uses them as **dividers**. A divider is either
**expanded** (10 000 pt — everything to its left is off screen) or a **boundary**: a glyph
on the divider's own button, clickable to walk the bar back. Only `.fullyRevealed` puts
all three sections on screen at once, so that is the state drawn here:

```
┌──────────────────────────────────────────────────────────────┐
│  … app items …  |≡  … app items …  ≡|  … app items …  ≡○  🕐 │
│  always hidden  ▲      hidden      ▲       visible    ▲       │
│                 │                  │                 │       │
│    alwaysHidden divider      hidden divider    Bouncer's icon │
└──────────────────────────────────────────────────────────────┘
```

That glyph — the mark's bars, plus a rule at the boundary itself — is drawn **on the
divider**, so it sits exactly where hiding ends. The hidden divider carries `≡|` and
the always-hidden divider its mirror `|≡`, so the two bracket the hidden section between
them. A section needs no other marking: it runs from its own divider leftwards to the next
one, and everything left of the outermost boundary is always hidden. Clicking a boundary
opens whatever is still beyond it and collapses once there is nothing left.

The boundary glyphs are drawn at partial alpha rather than in a second colour, so they sit
back from the logo. A status item image must be a template, and the system tints its
*alpha* — so partial alpha reads as a lighter grey and still follows a light or dark menu
bar.

Bouncer's icon is a *button*, not a boundary. It sits at the right end of the bar with the
dot filled while everything is put away and hollow while anything is open, and the user's
always-visible items may well sort between it and the divider — which is fine, because the
divider's own glyph is what says where the hidden section stops.

That split is forced. A status item's preferred position is a *hint*: macOS orders our
items against every other app's however it likes, so an item that is merely meant to sit
beside the boundary can end up a slot off it with someone else's item drawn in the gap.
Only the glyph on the divider is exact — which is why no boundary is ever marked by a
neighbouring item.

| Visibility       | hidden divider | alwaysHidden divider | icon | on screen         |
| ---------------- | -------------- | -------------------- | ---- | ----------------- |
| `.collapsed`     | expanded       | expanded             | `≡●` | `≡●` and visible  |
| `.revealed`      | `≡\|`          | expanded             | `≡○` | `… ≡\| … ≡○`      |
| `.fullyRevealed` | `≡\|`          | `\|≡`                | `≡○` | `… \|≡ … ≡\| … ≡○` |

In `.revealed` the alwaysHidden divider is off screen along with the section it governs,
so its glyph is not drawn — there is no boundary to point at yet, and the hidden section
simply runs off the edge of the display.

The alwaysHidden divider exists only while the always-hidden section is enabled. A
divider that is in the bar hides whatever is left of it, and a section the user cannot
reveal must hide nothing.

That is the entire mechanism: two width assignments. It costs nothing at rest, needs no
permissions, and survives OS updates that break screenshot-based approaches.

Section membership is not stored anywhere — it *is* the item's position relative to the
dividers, which macOS already persists per app via `NSStatusItem.autosaveName`. Users
rearrange sections by Cmd-dragging items across a divider, exactly as they already
rearrange the menu bar.

Bouncer does not list what is in each section, because it cannot say anything useful about
them. macOS hosts nearly every status item in the Control Center process, so the window
server reports the same owner for almost all of them; the window name that would identify
one — and the item's image — need Screen Recording. The menu bar itself is the display.

### Why not the screenshot approach

Ice and friends can render hidden items inside their own bar, which is nicer than
revealing the real menu bar. It requires reading other apps' item images, which means
Screen Recording permission, a capture pipeline running whenever the bar is open, and
click forwarding by synthesising events. That is a large, permission-hungry, fragile
subsystem. Bouncer's default is the cheap mechanism; if the standalone bar is built
later it goes behind an opt-in, with the divider mechanism still doing the hiding.

## Modules

Logic lives in `Modules/` (a SwiftPM package); `App/` is a thin shell.

```
BouncerFoundation   Logging, signposts, observation helper. No dependencies.
      ↑
  Settings          Preferences value type, persistence, launch-at-login.
      ↑
   MenuBar          Dividers, visibility state, reveal/rehide policy.
      ↑
  BouncerUI         The SwiftUI settings pane.
      ↑
    App             AppDelegate: constructs the graph, owns the menu and window.
```

Dependencies point one way only. `MenuBar` is AppKit-facing but its decision logic
(`MenuBarVisibility`) is pure and tested without a running app, which is why `make test`
needs no Xcode project and finishes in under a second.

### Notable types

- **`ControlItem`** — one divider. Owns the width policy and the boundary glyph drawn on
  it, nothing else.
- **`StatusItemPosition`** — slots. Seeded once so Bouncer's own items start in the right
  order, then left alone; the value is a hint, so nothing may depend on it.
- **`MenuBarManager`** — structure and visibility state. Deliberately does not know
  *why* visibility changes.
- **`RevealController`** — the *why*: hover, auto-rehide. Separated so input
  policy can grow without touching the bar itself.
- **`SettingsStore`** — one JSON blob in `UserDefaults`. One read at launch, one
  coalesced write per burst of edits.

## Performance rules

These are enforced by review, not by tooling:

1. **No work at rest.** No repeating timers, no run loop observers, no display links.
   State changes come from user input or system notifications.
2. **Pay only for what you enable.** The global mouse monitor is installed when
   `revealOnHover` is on and removed when it is off. Same for the app-activation
   observer. A user with both off has zero installed observers.
3. **Polling is a last resort, is scoped, and is documented.** No poll exists. Anything
   that needs one has to justify why no notification carries the same change, and stop
   polling the moment the feature that needs it is closed.
4. **Value types over object graphs.** `Preferences` is one `Hashable` struct, so
   "did anything change" is `==` and persistence is one encode.
5. **Release builds use whole-module optimisation and thin LTO** (`project.yml`).

Measure before optimising: `Log.signposter` is wired up for
`xctrace record --template 'Time Profiler'`.

## Roadmap

Ordered by how much of the current design they disturb — earlier items fit the existing
boundaries, later ones need new ones.

1. **Per-display behavior.** `MenuBarManager` assumes `NSScreen.main`; dividers exist
   per screen already. Needs a manager per screen.
2. **Rules.** "Always keep this app's item visible", "hide this item after N minutes".
   A new `Rules` module feeding `RevealController`; no change to the bar.
3. **Profiles.** `Preferences` becomes one of several named values; `SettingsStore`
   grows a selection. The rest of the app already only reads `preferences`.
4. **Appearance.** Custom menu bar tint/shape. Needs an overlay window; independent of
   the divider mechanism.
5. **Standalone bar.** The screenshot approach described above, opt-in. The largest
   change: new capture module, new permission, click forwarding.
