# bouncer

macOS menu bar manager. Read `docs/ARCHITECTURE.md` before changing how hiding works.

## Commands

```sh
make test      # module tests — fast, no Xcode project needed
make lint      # SwiftLint (must be clean)
make run       # generate project, build, launch
```

`xcode-select` may point at the Command Line Tools; the Makefile sets `DEVELOPER_DIR`
to `/Applications/Xcode.app` itself.

## Rules

Two principles decide every tradeoff — see README. In practice:

- **No work at rest.** No repeating timers, run loop observers or display links.
  Changes come from user input or system notifications. The one existing poll (layout
  inspector, 2 Hz, only while open) is documented at its call site; add none without
  the same justification.
- **Install observers only while the feature that needs them is enabled**, and remove
  them when it is disabled.
- **No new permission prompts.** Bouncer asks for neither Accessibility nor Screen
  Recording. A feature that needs one is opt-in and goes behind a separate module.
- **Logic goes in `Modules/`, not `App/`.** The app target wires things together and
  owns no behavior. Anything worth testing must be a pure function over plain values.
- **Dependencies point one way** (`BouncerFoundation → Hotkeys → Settings → MenuBar →
  BouncerUI`). Do not add a back edge; introduce a new module instead.
- `Bouncer.xcodeproj` is generated — edit `project.yml`, never the project file.
- `App/Resources/Logo.svg` is the source of truth for the mark. The app icon, the
  README lockups and `MenuBarIcon.imageset` are derived from it — update them
  together. The menu bar copy is cropped and flattened to one colour because status
  item images must be templates.
