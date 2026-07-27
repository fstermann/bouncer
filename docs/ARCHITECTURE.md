# Architecture

## How hiding works

macOS lays status items out right to left and gives each item a width. There is no API
to hide someone else's status item — but an item's width is ours to choose, and a wide
enough item pushes everything to its left past the edge of the display.

Bouncer creates two status items and uses them as **dividers**. Only `.fullyRevealed`
puts all three sections on screen at once, so that is the state drawn here — and it is
the only state in which the outer boundary is visible at all:

```
┌──────────────────────────────────────────────────────────────┐
│  … app items …  ●● … app items …  ●  … app items …  ≡●  🕐   │
│  always hidden  ▲     hidden      ▲     visible               │
│                 │                 │                           │
│    alwaysHidden divider     hidden divider                    │
└──────────────────────────────────────────────────────────────┘
```

A divider is **expanded** (10 000 pt — everything to its left is off screen) or a
**marker**: the boundary glyph, drawn on the divider's own button and clickable to
collapse the section again. One dot for the hidden boundary, two for the one further out.

| Visibility       | hidden divider | alwaysHidden divider | on screen                  |
| ---------------- | -------------- | -------------------- | -------------------------- |
| `.collapsed`     | expanded       | expanded             | Bouncer's icon only        |
| `.revealed`      | `●`            | expanded             | hidden section, no `●●`    |
| `.fullyRevealed` | `●`            | `●●`                 | everything                 |

In `.revealed` the alwaysHidden divider is off screen along with the section it governs,
so its marker is not drawn — there is no boundary to point at yet.

The marker is the divider, not a neighbouring item. The boundary is wherever the divider
sits, so a separate marker would put the drop target one slot off and items dropped
beside it would land on the wrong side.

The alwaysHidden divider exists only while the always-hidden section is enabled. A
divider that is in the bar hides whatever is left of it, and a section the user cannot
reveal must hide nothing.

That is the entire mechanism: two width assignments. It costs nothing at rest, needs no
permissions, and survives OS updates that break screenshot-based approaches.

Section membership is not stored anywhere — it *is* the item's position relative to the
dividers, which macOS already persists per app via `NSStatusItem.autosaveName`. Users
rearrange sections by Cmd-dragging items across a divider, exactly as they already
rearrange the menu bar. `MenuBarLayout.classify` reads membership back out of x-positions
when the layout inspector needs to display it.

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
   Hotkeys          KeyCombo + Carbon global shortcut registration.
      ↑
  Settings          Preferences value type, persistence, launch-at-login.
      ↑
   MenuBar          Dividers, item scanning, section classification,
                    visibility state, reveal/rehide policy.
      ↑
  BouncerUI         SwiftUI settings panes.
      ↑
    App             AppDelegate: constructs the graph, owns the menu and window.
```

Dependencies point one way only. `MenuBar` is AppKit-facing but its decision logic
(`MenuBarLayout`, `MenuBarVisibility`) is pure and tested without a running app, which is
why `make test` needs no Xcode project and finishes in under a second.

### Notable types

- **`ControlItem`** — one divider. Owns the width policy and the boundary marker drawn
  on it, nothing else.
- **`MenuBarManager`** — structure and visibility state. Deliberately does not know
  *why* visibility changes.
- **`RevealController`** — the *why*: shortcuts, hover, auto-rehide. Separated so input
  policy can grow without touching the bar itself.
- **`MenuBarItemScanner`** — reads the window server's list, keeping windows on layer 25
  (`NSStatusWindowLevel`). Frames and owner names need no permission; item *images*
  would, so we do not read them.
- **`SettingsStore`** — one JSON blob in `UserDefaults`. One read at launch, one
  coalesced write per burst of edits.

## Performance rules

These are enforced by review, not by tooling:

1. **No work at rest.** No repeating timers, no run loop observers, no display links.
   State changes come from user input or system notifications.
2. **Pay only for what you enable.** The global mouse monitor is installed when
   `revealOnHover` is on and removed when it is off. Same for the app-activation
   observer. A user with both off has zero installed observers.
3. **Polling is a last resort, is scoped, and is documented.** Exactly one poll exists:
   item frames refresh at 2 Hz while the layout inspector is open, because dragging a
   status item produces no notification. It stops when the pane closes.
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
