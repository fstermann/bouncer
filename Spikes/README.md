# Spikes

Throwaway programs written to answer one question each about the standalone bar, kept
because several of the answers contradict the obvious design and would otherwise have to be
rediscovered. Measured on macOS 26.5.

Build and run one with:

```sh
swiftc -O Spikes/<name>.swift -o Spikes/.bin/<name>
```

The ones that capture the screen have to run from a signed bundle, or macOS attributes the
Screen Recording prompt to whatever launched them. See `capture.swift` for the bundle
layout used.

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

## The spikes

| File | Question |
| --- | --- |
| `enumerate.swift` | Where do status items live, and what is readable without permission? |
| `capture.swift` | Can an off-screen item be captured, and how fast? |
| `items.swift` | What does a captured item actually look like? |
| `final.swift` | Occlusion and the cost of revealing before capturing |
| `hidden.swift` | The same, on the items that are actually hidden — end to end |
| `cover.swift` | Which cover is indistinguishable from empty menu bar? |
| `coverdetail.swift` | Does the sampled cover survive a detailed background, and staleness |
| `realbg.swift` | The cover against real menu bar content, with nothing injected |
| `exclude.swift` | Can the cover be refreshed while the items sit under it? |
| `stream.swift` | Stream latency, cost at rest, and cover variants |
| `clicks.swift` | Are synthesised clicks delivered without Accessibility? |
| `forwarding.swift` | Do they land with it, and where does the menu open? |

## Spikes that measured nothing

Kept as a warning, because each looked like a result at the time.

- `occlusion.swift`, `occlusion2.swift`, `occlusion3.swift` concluded that covering an item
  suppresses its pixels. They were run while a fullscreen window was up, so the menu bar was
  not being drawn and *nothing* was capturable. `final.swift` reversed the verdict once the
  bar was on screen. The lesson stuck: a capture that returns empty means "not drawn" at
  least as often as it means "not permitted".
- `ab.swift` chased the same blank captures through a wrong hypothesis (that an
  `NSApplication` was required) before the fullscreen window was identified.
- `coverdetail.swift` initially scored a perfect cover against a background it had painted
  *over* the real windows rather than behind them, because AppKit constrains normal-level
  windows out of the menu bar band. It now refuses to report a number when its backdrop
  fails to reach the bar.
