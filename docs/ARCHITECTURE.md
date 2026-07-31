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
permissions, and survives OS updates that break screenshot-based approaches. It is what
hides the items no matter what else is switched on — the standalone bar below borrows the
section for as long as it is open and hands it straight back.

Section membership is not stored anywhere — it *is* the item's position relative to the
dividers, which macOS already persists per app via `NSStatusItem.autosaveName`. Users
rearrange sections by Cmd-dragging items across a divider, exactly as they already
rearrange the menu bar.

Bouncer does not list what is in each section, because it cannot say anything useful about
them. macOS hosts nearly every status item in the Control Center process, so the window
server reports the same owner for almost all of them; the window name that would identify
one — and the item's image — need Screen Recording. The menu bar itself is the display.

### The standalone bar

Ice and friends can render hidden items inside their own bar, which is nicer than
revealing the real menu bar. It requires reading other apps' item images, which means
Screen Recording permission, and click forwarding, which means Accessibility — a large,
permission-hungry, fragile subsystem next to two width assignments. So it is built, in
`StandaloneBar`, and it is opt-in: off by default, asking for its permissions only when the
user switches it on, with the divider mechanism still doing the hiding.

There is no capture pipeline. The section is photographed once per open, in a single call,
while its items are still parked off the display — ScreenCaptureKit cannot reach a window
out there, so that call goes through SkyLight's private window capture, and a macOS release
that drops it leaves the bar without pictures rather than crashing. The cover that hides
the real items while they are revealed is a flat colour, not a picture of the bar: a still
of the whole bar swapped in and out was visible as the bar twitching, and it knew nothing
about the wallpaper moving under it or the shadow a menu casts over it.

The reveal is for the menus alone. A status item anchors its menu to its own window, so an
item left parked off the display opens its menu off the display too — measured, at x =
-4237. That is the one thing the pictures cannot stand in for.

It inverts the divider mechanism rather than reusing it. **An item pushed off the display
stops being drawn, and an item that is not drawn has no pixels to copy** — so a section
hidden the usual way cannot be replicated at all. Covering one costs nothing by comparison,
because a window capture ignores whatever is on top of it. So the section is revealed into
its ordinary place, that stretch of bar is covered with a picture of itself taken *before*
the reveal — which is therefore already a picture without the items — and the items are
drawn again a row lower. Hidden from the eye, fully alive to the capture.

The cover and the shelf are two windows and one panel: it slides out of the menu bar with the
replicas leading and the cover behind them, and slides back in the same way. That is why the
landing has to be *worked out* rather than measured — the panel is built and moving before the
reveal, so it cannot wait to be told where the section went. It lands where the items pack
edge to edge left of the visible run, one collapsed divider's width clear of it.

Three consequences worth knowing before changing any of it:

- **Replicas are stills.** The pictures are taken once per open. Streaming them keeps the
  clock ticking and earns the large screen recording pill, which lands *in* the bar and
  pushes every item along — moving the very items the replicas have to stay aligned with.
- **Replicas sit at their real horizontal positions**, not packed together. A status item
  anchors its menu to its own window and the real item cannot be moved, so a packed bar
  would open menus nowhere near the replica clicked.
- **Clicks go through Accessibility, not synthesised events.** Since macOS 26 every status
  item window belongs to Control Center, so a click posted at an item's position reaches
  only the items Control Center genuinely owns. Each app still publishes its own items
  under its extras menu bar, where pressing one opens the same menu a real click would.

### Rearranging from the standalone bar

Cmd-dragging a replica rearranges the real menu bar — including dragging an item clear of the
hidden section, or into it from the visible one, which a bar of pictures could not otherwise
offer.

**Only the press is synthesised.** A Cmd+mouse-down posted at the real item starts a drag that
then tracks the user's own pointer, and their own release finishes it. The pointer is put on the
item, one event goes out, the pointer is handed straight back — and from there the menu bar is
doing what it does for anybody, a row above where the user's hand actually is. That is the whole
of `ItemHandoff`, and it is why there is no packing rule here, no predicted order and no drop
point: the window server decides all of it.

Four things were measured to get there, and each one is load-bearing:

- **The press has to be posted where the pointer is.** A warp is a request like any other, so a
  press posted in the same breath is judged against where the pointer still was. There is a beat
  between them, and the same beat on the way back.
- **The release has to be carried back into the bar** by a `leftMouseDragged` before it is posted,
  not by warping. A warp moves the cursor and tells nobody; a drag in flight is following the
  events it is sent, which is why the user's own movement carries the item and a warp does not.
  A status item released *below* the bar has its move abandoned.
- **The release cannot be waited for on the shelf.** The pointer is warped out of that window as
  the gesture begins and the window server takes the drag over, so a mouse-up finding its way back
  to the view that started it is something to hope for, not to depend on. It is watched for with a
  global monitor instead. Every fix aimed at the ending was dead code until this was found.
- **`ClickShield` must stand down, not go away.** It is the one window above the items that takes
  mouse events, so it swallows the press — and `orderOut` was measured taking 150 to 300 ms to
  stop a window hit-testing. `ignoresMouseEvents` lands within 30 ms.

While the drag is on, nothing is decided and everything is drawn: `Handover` follows the real
items into the shelf and the cover every 16 ms, so the panel shows what the bar is doing rather
than what it ought to be doing. The replica of the item in hand is not drawn at all — it has no
frame to be drawn at, because a dragged item leaves the status item layer entirely, and the user
is holding the real one anyway.

**What the section holds is decided only at rest.** The rule is packing: macOS lays status items
edge to edge and the divider stands between the section and the visible run, so an item dragged
out is separated from the section by the divider's width and one dragged in is packed against it.
Bouncer's own items have to be out of the way first or the divider bridges the two into one — and
they are found by *name*, via `StatusItemScanner.bouncersOwn()`, because nothing else identifies
them: a divider is a 17 pt hairline the size of a real item while its section is revealed, and a
wide window pinned to the left of the display when it is not.

That rule may not be applied mid-drag. The bar is halfway through rearranging itself, items are
momentarily further apart than they will end up, and a reading taken then loses them one by one as
the user drags past — with nothing to bring them back, because the next reading is taken around
what is left.

An item can also be dragged *into* the section without touching the shelf at all, in the real menu
bar. The only signal for that is a release with Cmd held while the bar is open, after which the
section is read again and anything new is photographed and resolved like any other item.

Known gap: a notched display. The section can reach across the notch, and both the shelf's width
and the packing rule read that as a gap in the bar rather than a piece of display with no bar
under it.

The items stay revealed and live underneath the cover for as long as the bar is open, which
is why two things exist that otherwise look redundant: `MenuBarManager.isRevealHeld`, so
auto-rehide does not put the section away underneath an open bar, and `ClickShield`, so the
covered strip does not open the menus of items the user cannot see.

Each of these came out of a spike rather than from first principles;
[SPIKES.md](SPIKES.md) has the measurements.

## Modules

Logic lives in `Modules/` (a SwiftPM package); `App/` is a thin shell.

```
BouncerFoundation   Logging, signposts, observation helper. No dependencies.
      ↑
  Settings          Preferences value type, persistence, launch-at-login.
      ↑
   MenuBar          Dividers, visibility state, reveal/rehide policy.
      ↑         ↑
  BouncerUI  StandaloneBar    The SwiftUI settings pane; the replica bar and all
      ↑         ↑             it needs — capture, cover, click forwarding.
      └── App ──┘             AppDelegate: constructs the graph, owns the menu
                              and window.
```

`StandaloneBar` is a module of its own because it is the one feature that asks for
permissions. Keeping it off to the side means the permission surface is a directory, not a
grep.

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
  coalesced write per burst of edits. Keys added after 0.1.0 decode as optional, so a blob
  written before one existed keeps the user's other settings.
- **`StandaloneBarController`** — opens and closes the replica bar, and owns the ordering
  the whole feature turns on: photograph, draw the panel where the section is about to land,
  run it out of the menu bar, reveal underneath it — and the reverse on the way out, where
  the section is put away *before* the panel goes, because the cover leaves with it.
- **`ItemHandoff`** — the two synthesised events a rearrangement needs: a press to put the real
  item in the user's hand, and a release to land it.
- **`Handover`** — the mode the bar is in while they rearrange. Follows the real items into the
  shelf, and works out what the section holds once they let go.
- **`MenuBarItemGeometry`** — the standalone bar's decisions as pure functions over frames:
  what is off screen, what is a divider, where the cover goes, where each replica sits, and which
  items are packed together into a section.
  Tested against recorded window lists with no running app, the same way `MenuBarVisibility`
  is.

## Performance rules

These are enforced by review, not by tooling:

1. **No work at rest.** No repeating timers, no run loop observers, no display links.
   State changes come from user input or system notifications.
2. **Pay only for what you enable.** The global mouse monitor is installed when
   `revealOnHover` is on and removed when it is off. Same for the app-activation
   observer. A user with both off has zero installed observers. The standalone bar goes
   further: its pointer monitor, its menu observer and its windows exist only while the
   bar is open, so a user who has enabled it and closed it is paying nothing either.
3. **Polling is a last resort, is scoped, and is documented.** One exists: `PlacementWait`
   reads item frames every 8–16 ms while the standalone bar opens and closes. The window
   server places status items over several frames and sends no notification when it has
   finished, so there is nothing to observe; each wait returns the moment the state it is
   after arrives, is bounded, and runs only inside an interaction the user just asked for.
   Anything else that needs one has to justify why no notification carries the same change,
   and stop polling the moment the feature that needs it is closed.
4. **Value types over object graphs.** `Preferences` is one `Hashable` struct, so
   "did anything change" is `==` and persistence is one encode.
5. **Release builds use whole-module optimisation and thin LTO** (`project.yml`).

Measure before optimising: `Log.signposter` is wired up for
`xctrace record --template 'Time Profiler'`.

## Roadmap

Ordered by how much of the current design they disturb — earlier items fit the existing
boundaries, later ones need new ones.

1. **Per-display behavior.** `MenuBarManager` assumes `NSScreen.main`; dividers exist
   per screen already. Needs a manager per screen, and the standalone bar needs one bar
   per screen with it.
2. **Rules.** "Always keep this app's item visible", "hide this item after N minutes".
   A new `Rules` module feeding `RevealController`; no change to the bar.
3. **Profiles.** `Preferences` becomes one of several named values; `SettingsStore`
   grows a selection. The rest of the app already only reads `preferences`.
4. **Appearance.** Custom menu bar tint/shape. Needs an overlay window; independent of
   the divider mechanism.

The standalone bar was item 5 and is built; what is left of it is a full screen space,
where the menu bar is not drawn and so nothing can be captured, and the per-display work
in item 1.
