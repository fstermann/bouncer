# bouncer

macOS menu bar manager. Read `docs/ARCHITECTURE.md` before changing how hiding works.

## Commands

```sh
make test      # module tests — fast, no Xcode project needed
make lint      # SwiftLint (must be clean)
make run       # generate project, build, launch
make release   # signed universal DMG + Sparkle zip; needs RELEASE_SIGN_IDENTITY
```

`xcode-select` may point at the Command Line Tools; the Makefile sets `DEVELOPER_DIR`
to `/Applications/Xcode.app` itself. So use `make` — running `swift build` directly picks the
Command Line Tools' Swift, and its `Modules/.build` then fails to load under the Xcode toolchain
with "module compiled with Swift X cannot be imported by Swift Y". On that error, `rm -rf
Modules/.build`.

`log show` fails inside Claude Code ("Could not open local log store: Operation not
permitted"), with the sandbox disabled and through the user's `!` prefix alike. Don't use
`Logger` to debug; have temporary debug lines append to a file in the scratchpad and read
that. The app is not sandboxed, so it can write there.

## Checking it yourself

Don't ask the user to try a bar change and report back; drive a running Bouncer Dev with
`make ctl`. It talks to `DevHarness` (Bouncer Dev only), which holds the Screen Recording and
Accessibility grants a shell lacks, and prints the app's reply:

```sh
make ctl CMD="click"                        # what a click on the icon does
make ctl CMD="open"                         # or close: the standalone bar
make ctl CMD="dump"                         # items by app, chevron, Bouncer's windows, with frames
make ctl CMD="hit 900 15"                   # whose element a click at that point reaches
make ctl CMD="press 900 15"                 # a real left click there, the pointer put back after
make ctl CMD="drag 1209 960 1.5"            # Cmd-drag the item at x 1209 to x 960, held there 1.5 s
make ctl CMD="shoot /path/bar.png"          # top 120 pt of the main display, then Read the PNG
make ctl CMD="record /path/bar.mov 3"       # video, at most 30 s; run it in the background, then act
ffmpeg -loglevel error -i bar.mov -vf "fps=5,scale=1512:-1,tile=1x15" -frames:v 1 sheet.png
```

Clicks posted from a shell do not land; `press` and `drag` do, because Bouncer Dev posts them.
`hit` says what a click would reach without making one. The last
line turns a recording into one image of stacked frames, which can be Read. A black bar
in a picture means the user is in a full-screen space: ask them to leave it.

For a glitch that lasts a frame, record at full rate (`record path secs height`: the third word
is the height in pt, not fps), split every frame with
`ffmpeg -i bar.mov -fps_mode passthrough f/%04d.png`, and tile a crop of 6 to 15 consecutive
frames. ffmpeg here has no drawtext and Python no PIL: count frames by position.

## Rules

Two principles decide every tradeoff — see README. In practice:

- **No work at rest.** No repeating timers, run loop observers or display links.
  Changes come from user input or system notifications. There is no poll; a new one has
  to justify why no notification carries the same change, and must stop when the feature
  that needs it is closed.
- **Install observers only while the feature that needs them is enabled**, and remove
  them when it is disabled.
- **No new permission prompts.** Bouncer asks for neither Accessibility nor Screen
  Recording. A feature that needs one is opt-in and goes behind a separate module.
- **Logic goes in `Modules/`, not `App/`.** The app target wires things together and
  owns no behavior. Anything worth testing must be a pure function over plain values.
- **Dependencies point one way** (`BouncerFoundation → Settings → MenuBar → BouncerUI`).
  Do not add a back edge; introduce a new module instead.
- `Bouncer.xcodeproj` is generated — edit `project.yml`, never the project file.
- **Dev is a different app.** `make run` builds `Bouncer Dev` / `com.bouncer.app.dev`, with its
  own defaults domain, permissions and no updater, so it can run beside an installed Bouncer.
  Never `pkill -x Bouncer` in a dev workflow — that kills the user's installed copy.
  Code only Bouncer Dev should contain goes behind `#if DEV`; the release build never compiles it.
- **Keep the Dev signature stable.** `.signing.mk` supplies the persistent `Bouncer Dev`
  identity through `make build` / `make run`. Never override it with
  `CODE_SIGN_IDENTITY=-` or launch an ad-hoc-signed Dev build: its designated requirement is
  tied to a changing code hash, so macOS invalidates its Accessibility and Screen Recording
  grants on every rebuild.
- **Versions belong to release-please.** `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in
  `project.yml` are bumped by it off Conventional Commits; never edit them by hand, and keep
  the `x-release-please-version` annotations on those lines.
- **A glitch that comes and goes is fixed only by numbers.** Reproduce it on the old build
  first, then show it gone in several runs of the new one (e.g. 3 of 3 before, 0 of 5 after).
  One clean run proves nothing.
- **Measure an animation bug before fixing it.** Log the frames, model and presentation values
  involved to the scratchpad file and find where they disagree with what the recording shows.
  Don't ship a fix that only might help.
- `App/Resources/Logo.svg` is the source of truth for the mark. The app icon, the
  README lockups, `MenuBarIcon.imageset`, `MenuBarIconOpen.imageset`,
  `SectionEndIcon.imageset` and its mirror `SectionStartIcon.imageset` are derived from
  it — update them together. The status item copies are cropped and flattened to one
  colour because status item images must be templates; a lighter tone is partial alpha,
  never a second colour. All keep the mark's 96-unit box so one height sizes them
  together.
