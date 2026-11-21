# Performance

Everything Bouncer shows has to feel instant, and that is measured, not judged by eye. `make bench`
times what a person waits for in a running Bouncer Dev and fails when a median breaks its budget.

```sh
make bench                                          # every scenario, 5 runs, writes .bench/<commit>.json
make bench ARGS="--scenario todos-open --runs 3"    # some scenarios
make bench ARGS="--label before"                    # names the results file
make bench ARGS="--compare .bench/before.json .bench/after.json"
```

It drives this Mac's screen for about 10 minutes: hands off the mouse and keyboard, on a desktop rather
than a full screen Space (where the bar hides until the pointer reaches the top). It relaunches Bouncer
Dev first. `.bench/` is ignored by Git.

## Budgets

| Metric | Budget | Why |
| --- | --- | --- |
| `first` of every scenario | 100 ms | The limit for a response to feel instant (Nielsen) |
| `done` of every scenario | p95 of the first full run plus 10% | Guards against regressions; not a goal |
| `idle.cpu` | 0.1% | No work at rest |
| `idle.wakeups` | 1 per second | No work at rest |

The budgets live in `budgets` at the top of `Tools/bench.swift`. Lower a `done` budget when a change makes
it faster; raise one only with the reason in the commit.

## What it measures

Each scenario starts from rest (the dev-only `rest` command closes every page, the bar and decks), puts
Bouncer Dev where the action starts, then records the screen around one action:

- `bar-open`, `bar-close`: the icon's click. `-overflow`: the same with 12 extra status items
  (`Tools/bench-items.swift`), so the section needs both sides of the notch.
- `bar-to-todos`, `todos-to-bar`: ⌘⇧B from the bar, the icon from the todo page.
- `todos-`, `notes-`, `claude-open` and `-close`: ⌘⇧B, ⌘⇧N, ⌘⇧C.
- `decks-open`, `decks-close`: ⌘⇧W.
- `idle`: Bouncer Dev's CPU time and wakeups over 30 s, nothing touched.

`first` is when the first changed pixel reached the screen, `done` when the screen stopped changing,
both in ms. The bar scenarios look only at the bar left of Bouncer's icon, so the clock is not a change.

The dev-only `capture` command records the movie and takes the action. A movie's times start at its
first frame, on no clock the action can be read on, so a 16 pt square in the corner of the recording
turns from black to white as the action is posted, and times count from the frame that shows it. That
leaves out the one frame anything takes to reach the screen.

## First run

fa0d8b1, 2026-11-21, 14-inch MacBook Pro, macOS 27.2. Medians in ms, p95 in brackets.

| Scenario | first | done |
| --- | --- | --- |
| bar-open | 33 (50) | 375 (592) |
| bar-open-overflow | 42 (58) | 1425 (1458) |
| bar-close | **125** (142) | 717 (725) |
| bar-close-overflow | 75 (83) | 742 (783) |
| bar-to-todos | **283** (342) | 767 (770) |
| todos-to-bar | 17 (33) | 695 (708) |
| todos-open | **250** (258) | 375 (378) |
| todos-close | 25 (33) | 233 (242) |
| notes-open | 58 (83) | 158 (175) |
| notes-close | 17 (25) | 217 (225) |
| claude-open | 92 (117) | 200 (233) |
| claude-close | 17 (25) | 200 (233) |
| decks-open | **158** (317) | 158 (512) |
| decks-close | 60 (67) | 60 (67) |
| idle | 0.0% CPU | 0.5 wakeups/s |

Bold breaks the 100 ms budget, so `make bench` fails until those four are fixed.

## Procedure

1. Run a baseline with a label before changing code, on the same branch state.
2. Change one thing, run again with the same `--runs`, and `--compare`. Read medians; read p95 for noise.
3. Put the before and after medians, the run count and the scenario in the commit message.
4. Keep timing out of `make test`: unit tests count states and calls, never milliseconds.

## Pitfalls

- **A stream that hands frames to the app adds the system's screen-sharing item to the menu bar**,
  which widens the section and moves every item. Recording to a file shows only a dot right of the
  clock. So `capture` records a movie.
- **Clicks posted on a status item stopped landing** (2026-11-21), while clicks on the Apple menu still
  did. The bar scenarios therefore run the icon's handler directly (`click`) and leave out the click's
  trip through the system to Bouncer.
- **Posted ⌘⇧← and ⌘⇧→ do not switch pages.** Not checked with a real keyboard.
- **A black bar in a recording means a full screen Space.** Leave it and run again.
- **Idle counts every wakeup**, including the pointer moves the hover monitor receives when reveal on
  hover or near the notch is on. Touching the mouse during the 30 s spoils the reading.
