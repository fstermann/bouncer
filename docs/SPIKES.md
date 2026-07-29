# Spikes

Sixteen throwaway programs answered one question each before the standalone bar was
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

## What was asked

Where status items live and what is readable without permission; whether an off-screen item
can be captured and how fast; what a captured item looks like; the cost of revealing before
capturing, first synthetically and then end to end on the items that are actually hidden;
which cover is indistinguishable from empty menu bar, against a detailed background and
against real menu bar content with nothing injected; whether that cover can be refreshed
while the items sit under it; stream latency and cost at rest; and whether synthesised
clicks are delivered at all, with and without Accessibility, and where the menu opens when
they are.

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
