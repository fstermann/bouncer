# Spikes

Twenty-one throwaway programs answered one question each before the standalone bar was
designed. Several of the answers contradict the obvious design, so the answers are kept
here — the programs are not, and live in the history of PR #1 if one ever needs running
again. Measured on macOS 26.5.

Anything measured here is worth re-measuring after a major OS release: every finding below
is about undocumented window server behaviour, and the last one to change took the whole
design with it.

## What was established

| Question | Answer |
| --- | --- |
| Item geometry without permission | Free — exact frames for every item, on screen or off |
| Item identity | Gated — every item reports Control Center with an empty name |
| Items pushed off the display | **No pixels.** Hiding by displacement and replication are mutually exclusive |
| Items in a fullscreen space | No pixels — the menu bar is not drawn, so nothing can refresh |
| Items under an opaque window | **Perfect pixels.** Occlusion costs nothing — this is what makes covering viable |
| `CGWindowListCreateImage` | Obsoleted in the macOS 15 SDK. Every existing manager was built on it |
| Cover fidelity | A sampled bitmap scores 0.00; every `NSVisualEffectView` material scores 41–84 |
| Cover staleness | Drifts to mean 72 once anything moves behind the bar, so it must track |
| Cover refresh | `excludingWindows:` renders the strip as empty menu bar, ~10.6 ms |
| Per-item capture | ~9 ms one-shot; a stream costs 3.4% of a core and ~0 after teardown |
| Clicks | Dropped silently without Accessibility; `postToPid` never works |
| Menu anchoring | Anchored to the item's own x, so replicas must mirror real positions |
| Synthesised Cmd+drag | **Reorders the item.** Rearranging is the system's gesture, not the app's — unlike a click |
| What it needs | `.maskCommand` on the mouse events. No real Cmd keypress, either tap |
| Dragging under the cover | Works, because the cover takes no mouse events. A hit-testable window swallows it |
| Standing a window down | `orderOut` takes **150–300 ms** to stop it hit-testing; `ignoresMouseEvents` lands within 30 ms |
| The pointer | **Warped into the bar, unpreventably.** Detaching it does not stop it |
| Hiding the pointer from the background | `CGDisplayHideCursor` holds once the connection sets `SetsCursorInBackground` — so the trip need not be *drawn* |
| Delivering the drag to a process | `postToPid` moves nothing — for a drag as for a click. So the pointer cannot be spared |
| How short the gesture can be | One jump, **26 ms, 5/5**. Stepping the path along is unnecessary |
| Moving an item through Accessibility | **Impossible.** Not one settable attribute across 36 items; the tree offers press, cancel and one remove |
| Moving it through its stored position | Only Apple's own items are readable. A third-party item's is in its own domain, read at item creation |
| Settling after a drop | Starts within ~25 ms and still changing at 230–410 ms. A read at 200 ms sees the old order |
| A dragged item's pixels | Drawn at **window layer 500**, so a cover at 26 does not hide the gesture |
| A real Cmd release mid-drag | Harmless. The drag completes on the flags its own events carry |
| Cost of a drag | The first one **renumbered 21 of 22 status item windows** |
| Handing a drag over | **A synthesised press is enough.** The drag then tracks the user's own pointer and their own release lands it |
| What it needs | Cmd held throughout — the bar reads the modifier on every move, not only at the press |
| Warping vs posting | A warp tells a drag in flight nothing. Position is carried by *events*, so a move back into the bar has to be posted as one |
| Where a release lands | Below the bar the move is abandoned. It has to be brought back into the bar before letting go |
| What a dragged item grows into | Two Control Center windows at layer 500, 152 × 76 and 71 × 38, a fixed 36 pt apart. **Neither ever changes size** — the pill is a content swap animated inside a window that was always that big |
| Where it swaps | Pointer y 13–15: the item's **own centre line**, not the bar's lower edge. It is already a pill while the pointer is inside the menu bar band |
| Hiding another connection's window | Not possible. SkyLight's alpha and level calls need the owning connection, and cross-connection control is the Dock's and the window server's |
| Covering the pill instead | 76 pt of it against a 30 pt shelf, so a cover paints an opaque patch over bar it is hiding nothing in |
| A flag for it | None in Control Center's strings or its prefs, and its log says nothing about the drag at any level |
| Whose logic it is | Not Control Center's own binary: stripped, and it imports `WindowManagerDraggableOverlaySession`. The naming around it is the macOS 26 menu bar customization system |
| Mocking a drag's position | **Impossible.** A posted mouse event moves the physical cursor to it, so a drag's position and the user's pointer are one thing rather than two that can disagree |

## What was asked

Where status items live and what is readable without permission; whether an off-screen item
can be captured and how fast; what a captured item looks like; the cost of revealing before
capturing, first synthetically and then end to end on the items that are actually hidden;
which cover is indistinguishable from empty menu bar, against a detailed background and
against real menu bar content with nothing injected; whether that cover can be refreshed
while the items sit under it; stream latency and cost at rest; whether synthesised
clicks are delivered at all, with and without Accessibility, and where the menu opens when
they are; and whether a synthesised Cmd+drag reorders an item, what it needs to, whether the
cover blocks it, what it costs, and how long the bar takes to settle afterwards; and, once the
cost of that turned out to be the pointer, whether anything at all can move another app's item
without a gesture; and, once it turned out the whole gesture did not have to be synthesised at
all, whether a real hand can finish one that a synthesised press began; and, last, what draws
the pill a dragged item turns into once it is out of the bar, where that swap is triggered,
and whether it can be hidden, covered, placed around, switched off or lied to.

The reorder spike and the three pill spikes were written after the fact, against a bar that was
already built. The reorder one is the one worth explaining. It
was worth writing anyway: the obvious inference from the click findings — that a synthesised
event cannot move another app's item — is wrong, because rearranging the bar is not delivered
to the item's app at all.

## Three that measured nothing

Recorded because each looked like a result at the time, and the failure mode is the kind
that repeats.

- Three spikes in a row concluded that covering an item suppresses its pixels. They were run
  while a fullscreen window was up, so the menu bar was not being drawn and *nothing* was
  capturable. The verdict reversed once the bar was on screen. The lesson stuck: **a capture
  that returns empty means "not drawn" at least as often as it means "not permitted"**, and
  it is worth proving the bar is on screen before believing any capture result.
- A fourth chased the same blank captures through a wrong hypothesis — that an
  `NSApplication` was required — before the fullscreen window was identified.
- The cover-fidelity spike first scored a perfect cover against a background it had painted
  *over* the real windows rather than behind them, because AppKit constrains normal-level
  windows out of the menu bar band. A backdrop that cannot reach the bar cannot be scored
  against it.

## macOS 27

Measured on macOS 27.2 (26B123), 14-inch MacBook Pro (notch at x 663.5 to 848.5, bar 1512 pt
wide), 2026-10-29. A throwaway app created status items, set their widths and photographed the
bar with `screencapture`. It ran as an app bundle signed with the development identity, so it
held its own Screen Recording grant.

| Question | Answer |
| --- | --- |
| Who draws status items | **`MenuBarAgent`**, a new process in `/System/Library/CoreServices`. One layer-25 window spans the bar and holds every item |
| Item geometry from the window list | **Gone.** No item has a window of its own, so `CGWindowListCopyWindowInfo` sees only that one window |
| An app's own item frame | Still readable from `button.window.frame`. It arrives with `NSWindow.didMoveNotification` once the item has slid in, x correct from the first move |
| Frame of an item that does not fit | Stale: the width updates, the origin keeps its old value |
| Slots | Still seeded from `NSStatusItem Preferred Position <autosaveName>`. `MenuBarAgent` logs it as "legacy" and no longer writes it back |
| Too many items | The leftmost go behind a `«` chevron (`MenuBarOverflowComponent`). Nothing is pushed off the display |
| Opening the chevron | Draws the overflowed items **left of the notch, over the app menus**, which shrink to make room. The button is `menu-bar-overflow-indicator` (`menu-bar-overflow-indicator-expanded` while open) in `MenuBarAgent`'s `AXExtrasMenuBar`, and `AXPress` toggles it |
| Chevron while the divider hides it | **Not in the bar's list.** Revealing brings it back; collapsing while it is open hides the left side too |
| Chevron state | **Persists** across a collapse and a reveal: left open, every reveal draws the overflow over the app menus |
| Which chevron to press | The one in `MenuBarAgent`'s `AXExtrasMenuBar`. Its full tree holds stale copies, one per window, whose press flips the label and draws nothing |
| Opening it, as drawn | The section right of the notch fades in; the overflow comes out of the notch leftwards, squeezed at first, pushing the app menus aside. Settled about 400 ms after the reveal. Closing the chevron removes the left side at once |
| More items than both sides hold | **The rest are dropped.** 20 items of one app: 1 right of the notch, 12 left of it, 7 listed nowhere, their windows parked at y -33 |
| An item wider than the bar | **Evicted.** Capped at 5016 pt and moved out of the bar; every item left of it stays |
| Divider with its left edge right of the notch | Items left of it go behind the chevron, and the chevron stays on screen right of the notch |
| Divider with its left edge inside the notch | **Hides everything left of it, chevron included.** 525 to 700 pt here, right edge at x 1376 |
| Divider with its left edge past the notch | Evicted, and every item comes back. 750 pt and up here |
| Display without a notch | Not measured. The limit is presumably where the app menus end, which moves with the front app |
| Full screen space | Every capture of the bar is black. The window list cannot tell: the `MenuBarAgent` window is missing from it even while the bar is drawn |

So hiding by width still works, but only within a band: the divider has to end inside the notch.
Too narrow and the chevron offers the hidden items; too wide and the divider disappears.
`ExpandedDivider` aims at the middle of the notch, which leaves about 90 pt either side, roughly
three items appearing or vanishing right of the divider while it is collapsed.

### The standalone bar on macOS 27

Everything it found items by is gone: it read each item's own window from the window list, and
photographed that window while it was parked off the display. Measured the same way, with
Accessibility granted to the spike as well:

| Question | Answer |
| --- | --- |
| Items through Accessibility | Each app's `AXExtrasMenuBar` lists its visible items, `AXMenuBarItem` with exact frames and `AXPress` |
| Hidden items through Accessibility | **Gone from their app's list**, and an element held from before has no frame. `MenuBarAgent`'s own tree still lists them, by owning app, piled at the chevron |
| Identity across a hide and a reveal | **Stable.** The element read after the reveal is `CFEqual` to the one read before the hide |
| Reveal to readable frames | 34 ms, every item at once and at its final x |
| Pictures of hidden items | None while the chevron is closed. Open, `MenuBarAgent`'s transparent window holds them left of the notch, app menus included |
| Pictures under a cover | **Work.** `SCContentFilter(display:excludingWindows:)` with the cover excluded shows the items under it exactly |
| `AXPress` on an item | Delivers the item's own action |

So the order of an open has to change. The pictures cannot come first any more: the section is
revealed under the cover, read through Accessibility, and photographed from a capture of the bar
that leaves Bouncer's own windows out.
