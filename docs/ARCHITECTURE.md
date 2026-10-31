# Architecture

Bouncer has two modes, and the user picks one or both on first launch: **menu bar items**, which
hides items behind dividers, and **todos**, the todo page under the notch. Each works without the
other (`Preferences.enableMenuBarItems`, `Preferences.enableTodos`). With menu bar items off there
is no divider in the bar, Bouncer's icon opens the todo page, and nothing of this section runs;
with todos off there is no todo page, no switch to it and no ⌘⇧B.

## How hiding works

macOS lays status items out right to left and gives each item a width. There is no API
to hide someone else's status item — but an item's width is ours to choose, and a wide
enough item pushes everything to its left past the edge of the display.

Bouncer creates two status items and uses them as **dividers**. A divider is either
**expanded** (wide enough that everything to its left is hidden) or a **boundary**: a glyph
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

How wide is expanded depends on the OS. Up to macOS 26 it is 10 000 pt, and everything left of
the divider runs off the display. macOS 27 draws every status item in one `MenuBarAgent` window
and evicts an item longer than 740 pt (14-inch MacBook Pro). Shorter, an item with no room goes
behind the system's overflow chevron, which shows it left of the notch, and one too wide for that
is dropped with everything left of it, chevron included. So the divider is as long as the bar
left of the notch (`ExpandedDivider`), which no front app's menus leave the overflow room for.
The divider reads its right edge from its own frame while it is narrow, because the frame of an
expanded one keeps a stale origin. [SPIKES.md](SPIKES.md#macos-27) has the measurements.

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

On macOS 27 none of the below applies: `openInTheBar` reveals the section into the menu bar and
leaves it there. Items can only sit right of the notch, and those that do not fit go behind a
chevron, which Bouncer opens through Accessibility so they show left of the notch. Widening the
divider while revealed (`sectionShift`) pushes half the section past what fits, so `NotchSplit`
picks the shift that lands it evenly on both sides, from the width measured at the last close
(and on the first open only: a reading taken while the overflow still arrives, in batches up to
100 ms apart, splits it differently each time). A black shade above the items hides the chevron
and takes its clicks, which would take the left side away and leave the band over the app menus;
it holds the switch to the todo page instead. The layout read at close also places the band, so an open grows it both ways at once with a
copy above the items in two halves, and reveals the section behind it. The right half fades 200 ms after
the reveal, opening or switching from the todo page alike: the right side lands an item at a time
from some 30 ms in, while Accessibility stalls for some 300 ms, so it is not read. The left half fades once the overflow has slid out (400 ms after the
chevron is pressed): until then app menus draw over the band, and any fade before it shows them
through. Closing runs the
other way: the copy fades in, the section collapses behind it, then both shrink into the notch. macOS slides both sides out of the notch itself, so nothing is photographed or
replicated, clicks reach the real items, and Screen Recording is not needed. The bar adds only
`NotchTab`: a black band grown sideways out of the notch behind the items, at the menu bar's own
level, which the window server draws over the bar's backdrop and under its items. Closing closes the chevron before collapsing: it stays open
across a collapse, and left open, every later reveal draws the overflow over the app menus. Another app coming to the
front closes it, open or collapsed, taking the left side back into the notch, so the bar closes with
it, and a layout is only measured while it is open. An item dragged in or out while the bar is open moves the section's ends, so
every release reads the items again once they hold still and refits the band. An app launching or
quitting adds or takes away items, so a change to the running apps, watched only while the bar is
open, refits it too; the launch notification would miss agents, which own most items. Accessibility stalls through a
drag, so during one the band's right end follows the divider, which items dragged in or out move
and whose window moves say so. Items
that fit on neither side are dropped by macOS and cannot be shown. Rearranging is not built there.

There is no capture pipeline. The section is photographed once per open, in a single call,
while its items are still parked off the display — ScreenCaptureKit cannot reach a window
out there, so that call goes through SkyLight's private window capture, and a macOS release
that drops it leaves the bar without pictures rather than crashing. The cover that hides
the real items while they are revealed is a painted surface, not a picture of the bar: a still
of the whole bar swapped in and out was visible as the bar twitching, and it knew nothing
about the wallpaper moving under it or the shadow a menu casts over it. Both halves of the
panel are painted black, so it reads as the notch grown down into the bar.

The reveal is for the menus alone. A status item anchors its menu to its own window, so an
item left parked off the display opens its menu off the display too — measured, at x =
-4237. That is the one thing the pictures cannot stand in for.

It inverts the divider mechanism rather than reusing it. **An item pushed off the display
still takes clicks and still opens a menu, but it opens it out there** — so a section hidden
the usual way cannot be operated at all. Covering one costs nothing by comparison, because
the items underneath a cover stay exactly as clickable as they were. So the section is
revealed into its ordinary place, that stretch of bar is covered, and the items are drawn
again a row lower. Hidden from the eye, fully alive to a click.

The cover and the shelf are two windows and one panel, and the landing has to be *worked out*
rather than measured: the panel is built and moving before the reveal, so it cannot wait to be
told where the section went. It lands where the items pack edge to edge left of the visible run,
one collapsed divider's width clear of it.

The panel grows out of the notch. It starts as the notch, black on black, and grows wider and taller at once on one spring, its lower corners
travelling diagonally out to where it rests, the replicas blurring into focus as it lands. The
way back blurs them out, then lifts and gathers without bounce (`NotchSlide`), every property on
Core Animation springs from one start time. A display without a notch gets a notch-sized
stand-in at the top centre, faded in as it grows. To make the panel grow evenly either
side of the notch, the section is pushed left until it is centred under it, by widening the hidden
divider while it is revealed (`NotchCentring`). The window server places items behind the notch
without complaint, and those are covered anyway. It does not always take the widening quietly:
measured, it reorders the items around a widened item whenever one would sit across the notch's
edge, trading items from one side of it to the other. For the divider that would be an item
changing sections, so the landing is checked after the reveal and the shift dropped when anything
crossed. The panel then reaches further to one side of the notch than the other.

The camera, microphone and screen recording indicator would trip that check every time. macOS
keeps it on screen right of the divider while the section is hidden, and moves it in among the
section's items as it is revealed. So the item it followed is remembered, and from the next open
the indicator is counted as part of the section, replica and all (`PrivacyIndicator`).

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
- **A drop delivers more than one release.** Measured at two `leftMouseUp`s, 1 ms apart. The watch
  takes itself down on the first, before passing it on, because one gesture has to end the
  handover exactly once — and `end` reports *no handover of mine to end* as `nil` rather than as an
  empty section, which is a thing the bar closes itself over.

While the drag is on, nothing is decided and everything is drawn: `Handover` follows the real
items into the shelf and the cover every 16 ms, so the panel shows what the bar is doing rather
than what it ought to be doing. The replica of the item in hand is not drawn at all — it has no
frame to be drawn at, because a dragged item leaves the status item layer entirely, and the user
is holding the real one anyway.

**What the section holds is counted from the divider: everything on screen to its left.** That is
not a heuristic but the divider mechanism's own definition — hiding a section *is* expanding the
divider until what is left of it goes off the display — so an item the user drags across that
boundary changes sides by the same rule that put it where it was.

Two rules were tried before it, and both read the gaps between items: the run holding most of the
section's last known members, and then the unbroken run packed against the divider. Each failed
differently and both failed for the same reason. The first followed the items rather than the
boundary, so dragging a majority out moved the whole section to the wrong side of the bar with
nothing to bring it back. The second could not be asked mid-drag, because mid-drag there *is* a
gap: macOS opens a hole where the item in hand is going to land, and a rule that stops at the
first gap stops at that hole. Counting from the boundary asks nothing about gaps, so the same
reading serves a bar at rest and a bar being rearranged.

For the same reason the panel is measured **to the divider** rather than to its last item. An item
pulled in from the visible side lands against the divider first, so its hole is past every item
there is — a panel measured off the items alone would keep its width for the whole drag and snap
wider on the drop. At rest the two agree exactly, because the section is packed flush.

Bouncer's own items have to be out of the way first, and they are found by *name*, via
`StatusItemScanner.bouncersOwn()`, because nothing else identifies them: a divider is a 17 pt
hairline the size of a real item while its section is revealed, and a wide window pinned to the
left of the display when it is not. The names are needed as well as the IDs, because **the icon is
not beside the divider**: it is seeded at the right end of the bar (`StatusItemPosition.icon`) and
the user's visible items sort between the two. Naming is one enumeration of every window on the
system, so it is done once per drag rather than once per frame.

An item can also be dragged *into* the section without touching the shelf at all, in the real menu
bar. Bouncer is no part of that gesture, so it reads it off the pointer: a Cmd-drag with the
pointer still up in the bar starts the same follow a handover does, and the release that ends it
— with Cmd still held or not, since letting Cmd go first ends the drag just the same — reads the
section again and photographs anything new. Without the follow the panel stands still through the
whole drag and jumps once at the end of it. The look runs only while a follow is up, and stands
down for the whole of a handover, at both ends of its wait: the release it watches for is the
same one that ends a drag, and both would otherwise settle the bar at once.

Dragging the *last* item out closes the bar. A shelf of nothing over a cover hiding nothing is not
a bar; it is a stretch of menu bar that swallows clicks for no reason.

Known gap: a notched display. The section can reach across the notch, and both the shelf's width
and the packing rule read that as a gap in the bar rather than a piece of display with no bar
under it.

The items stay revealed and live underneath the cover for as long as the bar is open, which
is why two things exist that otherwise look redundant: `MenuBarManager.isRevealHeld`, so
auto-rehide does not put the section away underneath an open bar, and `ClickShield`, so the
covered strip does not open the menus of items the user cannot see.

Each of these came out of a spike rather than from first principles;
[SPIKES.md](SPIKES.md) has the measurements.

### The todo page

The notch panel has a second page: the open `- [ ]` lines of a Markdown file. By default that is
`Todos.md` in Bouncer's Application Support folder; the user can pick another instead, such as an
inbox in an Obsidian vault, whose own sync carries edits between devices. It lives in
`Todos`, apart from `StandaloneBar`, because it needs none of that module's permissions: a picked
file is reached through a security-scoped bookmark made when the user picked it, so a vault in
Documents asks for nothing. The panel is its own black window grown out of the notch, not the replica bar's
shelf, since it has no section to cover.

The file is read when the page opens and watched only while it is open, through a file system
event source; a change synced in while it is closed is read on the next open. Edits are made to the
file as it is on disk at that moment, and a tick or edit whose line no longer holds the todo is dropped
rather than landing on another line.

Each page switches to the other from the top right of the panel, while both are on. On the items page the
`ClickShield` takes its click, since it already swallows clicks over the section's last item, so the
switch costs the user nothing; it follows the section through every open and rearrangement because
the shield does. The cover draws it, so it rides the panel's edge and comes into focus with the
replicas instead of appearing once the panel has landed.

Both pages move alike, on the same `Motion` springs: the panel grows, and its content is cut to the
panel's shape and pinned to its top, so the panel reveals it rather than the content appearing
beside a panel still on its way. The content comes into focus as the panel lands and goes out of
focus as it leaves.
With both pages on, hover opens whichever the switch last chose (`Preferences.notchPage`). Without
the items page, the notch opens the todo page and the rest of the menu bar reveals the items. Switching morphs
rather than closing one panel and opening the other, and the todo panel does all the moving: it
fades in over the items panel, which is then taken down unanimated underneath it, and springs to
its own shape. Going back, the items panel's windows are built invisible underneath it, the todo
panel springs to their outline (`StandaloneBarController.open(closingWhenLeft:takingShape:)`), they
show, and only then is the section revealed under them; the todo panel fades off last. Shown any
sooner they stick out past the panel still changing shape, and hidden while the section is revealed
they leave its real items showing in the menu bar.
On macOS 27 the items panel is the band: the todo panel grows out of it, which then waits out the
items leaving, and goes back into its saved shape, under which the band goes up covered
(`TakeOver`). The todo panel fades off it there, and the bar opens on from that point as it always
does. One page is open at a time: Bouncer's icon over the todo page switches to the items page, and
nothing opens either page while a switch is running. The items page counts as open from the start
of its open (`isShowing`), and a switch away from it waits for that open to finish.

The file is read the way the Tasks plugin writes it: `#tags` anywhere in a task, `📅` before its due
day and `✅` before the day it was done, which Bouncer stamps when ticking so the vault's queries
count todos ticked here. Indented lines under a task are its note. Preset categories are a
`categories` list in the file's frontmatter.

### Checking the bar from a shell

The bar's bugs are disagreements between where Bouncer draws something and where the real items
are, which unit tests and log lines don't see. `DevHarness` lets a shell look: Bouncer Dev
only, it observes the distributed notification `com.bouncer.dev.command`, runs the command and
answers on `com.bouncer.dev.reply`. The observer is all it installs, and a recording stops
itself. It reads items through Accessibility, because on macOS 27 the window list has none, and
photographs the display through ScreenCaptureKit, so pictures include the bar's background and
the pointer. `Tools/barctl.swift` is the sender. Commands are listed in `AGENTS.md`.

It cannot rearrange items: macOS starts no status item drag from synthesised input.

## Modules

Logic lives in `Modules/` (a SwiftPM package); `App/` is a thin shell.

```
BouncerFoundation   Logging, signposts, observation helper, the panel's springs. No dependencies.
      ↑         ↑
  Settings   Updates   Preferences value type, persistence, launch-at-login.
      ↑         ↑      Sparkle, wrapped thin — the one third-party dependency.
   MenuBar      │      Dividers, visibility state, reveal/rehide policy.
      ↑    ↑    │
  BouncerUI ────┘  StandaloneBar   The SwiftUI settings pane; the replica bar and all
      ↑                  ↑         it needs — capture, cover, click forwarding.
      └────── App ───────┘         AppDelegate: constructs the graph, owns the menu
                                   and window.

Todos   The todo page: Markdown task lines, the file, the panel. Depends on
        BouncerFoundation, Settings and MenuBar; BouncerUI and App depend on it.
```

`StandaloneBar` is a module of its own because it is the one feature that asks for
permissions. Keeping it off to the side means the permission surface is a directory, not a
grep. `BouncerUI` depends on it so the settings pane can show and trigger those permissions
through `StandaloneBarPermissions` — the single entry point every Screen Recording and
Accessibility call goes through — but the calls themselves stay in this directory. `Updates`
is separate for the same reason in the other direction: it is where the only third-party
code and the only outbound network request live.

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
  policy can grow without touching the bar itself. What a hover reveals is the app layer's
  to replace, the way an icon click is, because the standalone bar is not this module's
  business.
- **`SettingsStore`** — one JSON blob in `UserDefaults`. One read at launch, one
  coalesced write per burst of edits. Keys added after 0.1.0 decode as optional, so a blob
  written before one existed keeps the user's other settings.
- **`StandaloneBarPermissions`** — the one place Screen Recording and Accessibility are
  read and requested. Requested together when the user turns the bar on; re-read when the
  app regains focus, so the settings pane shows live status without a timer.
- **`StandaloneBarController`** — opens and closes the replica bar, and owns the ordering
  the whole feature turns on: photograph, draw the panel where the section is about to land,
  run it out of the menu bar, reveal underneath it — and the reverse on the way out, where
  the section is put away *before* the panel goes, because the cover leaves with it.
- **`BarClosing`** — when that bar puts itself away. "Hide again" governs it as well as the
  menu bar reveal: the same delay, the same close on an app change, the same never. Its
  observer and its pending close exist only while the bar is open.
- **`ItemHandoff`** — the two synthesised events a rearrangement needs: a press to put the real
  item in the user's hand, and a release to land it.
- **`Handover`** — the mode the bar is in while they rearrange. Follows the real items into the
  shelf, and works out what the section holds once they let go.
- **`UpdateController`** — Sparkle behind four members. Holds no state of its own: Sparkle
  persists both preferences into the app's defaults, so the toggles read and write it directly
  rather than keeping a copy in `Preferences` that could disagree. Same reasoning as
  `LaunchAtLogin`, where the system is the source of truth.
- **`MenuBarItemGeometry`** — the standalone bar's decisions as pure functions over frames:
  what is off screen, what is a divider, where the cover goes, where each replica sits, and which
  items are packed together into a section.
  Tested against recorded window lists with no running app, the same way `MenuBarVisibility`
  is.

## Performance rules

These are enforced by review, not by tooling:

1. **No work at rest.** No repeating timers, no run loop observers, no display links.
   State changes come from user input or system notifications. One exception, and it is a
   distribution problem rather than a feature: Sparkle schedules a check once a day, because an
   app that is launched at login and never quit would otherwise never learn a fix exists. It is
   one timer, it fires 86,400 seconds apart, and turning the check off in Settings leaves
   nothing scheduled at all.
2. **Pay only for what you enable.** The global mouse monitor, and its local twin for Bouncer's
   own windows, are installed when `revealOnHover` or `revealNearNotch` is on and removed when
   both are off, together with the observation that reveals again when the pointer came back
   while the section was going away, and the one-shot wait for the hover delay. Same for the
   app-activation observer. A user with both off has zero installed observers. The standalone
   bar goes further: its pointer monitor, its menu observer and its windows exist only while
   the bar is open, so a user who has enabled it and closed it is paying nothing either.
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
