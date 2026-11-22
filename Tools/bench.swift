// Times what a person waits for in a running Bouncer Dev, and compares runs. `make bench` builds and runs it.
//
//   make bench                                     every scenario, 5 runs, writes .bench/<commit>.json
//   make bench ARGS="--scenario bar-open --runs 3"  some scenarios
//   make bench ARGS="--label before"                names the results file
//   make bench ARGS="--compare .bench/before.json .bench/after.json"
//
// Each scenario puts Bouncer Dev in a known state, then has it record the screen around one action: a
// real click or key press. `first` is when the first changed pixel reached the screen, `done` when the
// screen stopped changing, both in ms from the frame that first shows the action's marker (see
// DevCapture), so they leave out the one frame anything takes to reach the screen. Idle is Bouncer Dev's CPU and wakeups over 30 s
// while nobody touches the Mac. It fails when a median breaks a budget in `budgets`.
import AVFoundation
import Darwin
import Foundation

// MARK: - Budgets

/// Median limits in ms (CPU in %, wakeups per second for idle), by "scenario.metric". `first` is 100 ms
/// everywhere, the limit for a response to feel instant; `done` is the p95 of the first full run
/// (fa0d8b1, 2026-11-21) plus 10%, so it guards against regressions rather than setting a goal.
let budgets: [String: Double] = [
    "bar-close-overflow.done": 862,
    "bar-close-overflow.first": 100,
    "bar-close.done": 798,
    "bar-close.first": 100,
    "bar-open-overflow.done": 1604,
    "bar-open-overflow.first": 100,
    "bar-open.done": 652,
    "bar-open.first": 100,
    "bar-to-todos.done": 848,
    "bar-to-todos.first": 100,
    "claude-close.done": 257,
    "claude-close.first": 100,
    "claude-open.done": 257,
    "claude-open.first": 100,
    "decks-close.done": 74,
    "decks-close.first": 100,
    "decks-open.done": 564,
    "decks-open.first": 100,
    "notes-close.done": 248,
    "notes-close.first": 100,
    "notes-open.done": 193,
    "notes-open.first": 100,
    "todos-close.done": 267,
    "todos-close.first": 100,
    "todos-open.done": 416,
    "todos-open.first": 100,
    "todos-to-bar.done": 779,
    "todos-to-bar.first": 100,
    "idle.cpu": 0.1,
    "idle.wakeups": 1,
]

// MARK: - Talking to Bouncer Dev

func ctl(_ command: String, timeout: TimeInterval = 40) -> String {
    let id = UUID().uuidString
    let center = DistributedNotificationCenter.default()
    var reply: String?
    let observer = center.addObserver(forName: Notification.Name("com.bouncer.dev.reply"), object: id, queue: .main) {
        reply = $0.userInfo?["result"] as? String ?? ""
    }
    defer { center.removeObserver(observer) }
    center.postNotificationName(
        Notification.Name("com.bouncer.dev.command"), object: command, userInfo: ["reply": id], deliverImmediately: true
    )
    let deadline = Date().addingTimeInterval(timeout)
    while reply == nil, Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    return reply ?? "no reply: is Bouncer Dev running?"
}

func wait(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("bench: \(message)\n".utf8))
    exit(2)
}

// MARK: - Scenarios

struct Scenario {
    let name: String
    /// Commands that bring Bouncer Dev from rest, where every run starts, to where the action starts.
    var setup: [String] = []
    let action: String
    var seconds: Double = 2.5
    /// Points captured from the top of the display, and pixels per point.
    /// Room under the bar for the marker, which must sit below it.
    var height: Double = 50
    var scale: Double = 1
    /// Whether only the bar left of Bouncer's icon counts, leaving the clock out.
    var barOnly = true
    var overflowing = false
}

let fullHeight = 982.0
let scenarios: [Scenario] = [
    // `click` runs what a click on the icon does, without the click: clicks posted on a status item stopped
    // landing (2026-11-21), the Apple menu's still did. So these leave out the click's trip to Bouncer.
    Scenario(name: "bar-open", action: "click"),
    Scenario(name: "bar-close", setup: ["click"], action: "click"),
    Scenario(name: "bar-open-overflow", action: "click", overflowing: true),
    Scenario(name: "bar-close-overflow", setup: ["click"], action: "click", overflowing: true),
    Scenario(name: "bar-to-todos", setup: ["click"], action: "key cmd+shift+b",
             height: fullHeight, scale: 0.25, barOnly: false),
    Scenario(name: "todos-to-bar", setup: ["key cmd+shift+b"], action: "click",
             height: fullHeight, scale: 0.25, barOnly: false),
] + [("todos", "b"), ("notes", "n"), ("claude", "c")].flatMap { page, key in
    [
        Scenario(name: "\(page)-open", action: "key cmd+shift+\(key)",
                 height: fullHeight, scale: 0.25, barOnly: false),
        Scenario(name: "\(page)-close", setup: ["key cmd+shift+\(key)"], action: "key cmd+shift+\(key)",
                 height: fullHeight, scale: 0.25, barOnly: false),
    ]
} + [
    Scenario(name: "decks-open", action: "key cmd+escape", seconds: 3,
             height: fullHeight, scale: 0.25, barOnly: false),
    Scenario(name: "decks-close", setup: ["key cmd+escape"], action: "key cmd+escape",
             height: fullHeight, scale: 0.25, barOnly: false),
]

// MARK: - Reading a capture

struct Capture {
    let width: Int, height: Int
    let times: [Double]
    /// Gray frames, one byte a pixel.
    let pixels: Data
    /// The first frame showing the marker white: the action was posted just before it was drawn.
    let action: Int?

    init(path: String, scale: Double) {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        guard let track = asset.tracks(withMediaType: .video).first,
              let reader = try? AVAssetReader(asset: asset)
        else { fail("unreadable capture \(path)") }
        let output = AVAssetReaderTrackOutput(
            track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        reader.add(output)
        reader.startReading()
        var width = 0, height = 0, times: [Double] = [], pixels = Data()
        while let sample = output.copyNextSampleBuffer(), let buffer = CMSampleBufferGetImageBuffer(sample) {
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            width = CVPixelBufferGetWidth(buffer)
            height = CVPixelBufferGetHeight(buffer)
            let row = CVPixelBufferGetBytesPerRow(buffer)
            let source = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
            var gray = [UInt8](repeating: 0, count: width * height)
            for line in 0..<height {
                for column in 0..<width {
                    let pixel = source + line * row + column * 4
                    gray[line * width + column] =
                        UInt8((Int(pixel[2]) * 299 + Int(pixel[1]) * 587 + Int(pixel[0]) * 114) / 1000)
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
            pixels.append(contentsOf: gray)
            times.append(CMSampleBufferGetPresentationTimeStamp(sample).seconds)
        }
        self.width = width
        self.height = height
        self.times = times
        self.pixels = pixels
        // The middle of the marker, which sits in the bottom right corner.
        let inset = max(1, Int(8 * scale))
        let spot = (height - inset) * width + (width - inset)
        let size = width * height
        action = pixels.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            return times.indices.dropFirst().first { bytes[$0 * size + spot] > 200 && bytes[($0 - 1) * size + spot] < 60 }
        }
    }

    /// Pixels of columns `columns` that differ by more than a faint shade between frames `one` and `other`.
    func changed(_ one: Int, _ other: Int, columns: Range<Int>) -> Int {
        let size = width * height
        return pixels.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            let first = one * size, second = other * size
            var count = 0
            for line in 0..<height {
                for column in columns {
                    let offset = line * width + column
                    if abs(Int(bytes[first + offset]) - Int(bytes[second + offset])) > 40 { count += 1 }
                }
            }
            return count
        }
    }
}

/// ms from the action to the first changed frame, and to the frame after which nothing changed.
func timing(of capture: Capture, columns: Range<Int>) -> (first: Double, done: Double)? {
    let times = capture.times
    guard let after = capture.action else { return nil }
    let before = after - 1
    let area = capture.height * columns.count
    // Scaled with the area so a blinking caret is not a change, with a floor for a bar icon's few pixels.
    let noticed = max(6, area / 2000), still = max(6, area / 1000)
    guard let first = (after..<times.count).first(where: { capture.changed($0, before, columns: columns) >= noticed })
    else { return nil }
    let last = times.count - 1
    var done = last
    while done > first, capture.changed(done - 1, last, columns: columns) <= still { done -= 1 }
    let ms = { (index: Int) in ((times[index] - times[after]) * 1000).rounded() }
    return (ms(first), ms(done))
}

// MARK: - Idle

/// CPU time in seconds and wakeups of `pid` so far.
func usage(of pid: pid_t) -> (cpu: Double, wakeups: UInt64)? {
    var info = rusage_info_v4()
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
    }
    guard result == 0 else { return nil }
    var base = mach_timebase_info_data_t()
    mach_timebase_info(&base)
    // On Apple silicon these are mach ticks, not nanoseconds.
    let ticks = Double(info.ri_user_time + info.ri_system_time)
    return (ticks * Double(base.numer) / Double(base.denom) / 1e9, info.ri_pkg_idle_wkups + info.ri_interrupt_wkups)
}

func pid(of name: String) -> pid_t? {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    task.arguments = ["-x", name]
    let pipe = Pipe()
    task.standardOutput = pipe
    try? task.run()
    task.waitUntilExit()
    let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return text.split(separator: "\n").first.flatMap { pid_t($0) }
}

// MARK: - Statistics

func quantile(_ values: [Double], _ fraction: Double) -> Double {
    let sorted = values.sorted()
    return sorted[min(sorted.count - 1, Int((fraction * Double(sorted.count - 1)).rounded()))]
}

func summary(_ values: [Double]) -> [String: Any] {
    ["median": quantile(values, 0.5), "p95": quantile(values, 0.95), "runs": values]
}

func format(_ value: Double?) -> String {
    guard let value else { return "-" }
    return abs(value) >= 100 ? String(format: "%.0f", value) : String(format: "%.1f", value)
}

func table(_ rows: [[String]]) -> String {
    let widths = rows[0].indices.map { column in rows.map { $0[column].count }.max() ?? 0 }
    return rows.map { row in
        row.enumerated().map { column, cell in
            let pad = String(repeating: " ", count: widths[column] - cell.count)
            return column == 0 ? cell + pad : pad + cell
        }.joined(separator: "  ")
    }.joined(separator: "\n")
}

/// "scenario.metric" to its summary, from a results file.
func metrics(in path: String) -> (label: String, values: [String: [String: Any]]) {
    guard let data = FileManager.default.contents(atPath: path),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let values = json["metrics"] as? [String: [String: Any]]
    else { fail("unreadable results \(path)") }
    return (json["label"] as? String ?? path, values)
}

// MARK: - Main

var arguments = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> [String] {
    var found: [String] = []
    while let index = arguments.firstIndex(of: name), index + 1 < arguments.count {
        found.append(arguments[index + 1])
        arguments.removeSubrange(index...(index + 1))
    }
    return found
}

if arguments.first == "--compare", arguments.count == 3 {
    let (beforeLabel, before) = metrics(in: arguments[1])
    let (afterLabel, after) = metrics(in: arguments[2])
    var rows = [["metric", "before p50", "after p50", "change", "before p95", "after p95"]]
    for key in after.keys.sorted() {
        let was = before[key]?["median"] as? Double, now = after[key]?["median"] as? Double
        let change = was.flatMap { was in now.map { was == 0 ? "" : String(format: "%+.0f%%", ($0 - was) / was * 100) } }
        rows.append([
            key, format(was), format(now), change ?? "",
            format(before[key]?["p95"] as? Double), format(after[key]?["p95"] as? Double),
        ])
    }
    print("\(beforeLabel) -> \(afterLabel)\n\(table(rows))")
    exit(0)
}

let runs = Int(option("--runs").last ?? "5") ?? 5
let chosen = option("--scenario")
let root = FileManager.default.currentDirectoryPath
let commit = (try? String(contentsOfFile: "\(root)/.git/HEAD", encoding: .utf8)).map { _ in
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    task.arguments = ["rev-parse", "--short", "HEAD"]
    let pipe = Pipe()
    task.standardOutput = pipe
    try? task.run()
    task.waitUntilExit()
    return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "results"
} ?? "results"
let label = option("--label").last ?? commit
guard arguments.isEmpty else { fail("unknown arguments \(arguments.joined(separator: " "))") }
let known = Set(scenarios.map(\.name) + ["idle"])
if let unknown = chosen.first(where: { !known.contains($0) }) {
    fail("no scenario \(unknown); there are \(known.sorted().joined(separator: ", "))")
}
let picked = scenarios.filter { chosen.isEmpty || chosen.contains($0.name) }
let directory = "\(root)/.bench"
let captures = "\(directory)/captures"
try? FileManager.default.createDirectory(atPath: captures, withIntermediateDirectories: true)

// A fresh Bouncer Dev, so no run inherits state from work done before the bench.
let app = "\(root)/.build/xcode/Build/Products/Debug/Bouncer Dev.app"
guard FileManager.default.fileExists(atPath: app) else { fail("no Bouncer Dev build: make run") }
if let running = pid(of: "Bouncer Dev") {
    kill(running, SIGTERM)
    while pid(of: "Bouncer Dev") != nil { wait(0.1) }
}
let launch = Process()
launch.executableURL = URL(fileURLWithPath: "/usr/bin/open")
launch.arguments = [app]
try? launch.run()
launch.waitUntilExit()
var ready = false
for _ in 0..<20 where !ready {
    wait(0.5)
    ready = ctl("rest", timeout: 2) == "at rest"
}
guard ready, let bouncer = pid(of: "Bouncer Dev") else { fail("Bouncer Dev did not start") }
wait(3)

// Bouncer's icon, whose right edge ends what the bar scenarios look at, from `dump`: "icon (x, y, w, h)" in
// AppKit coordinates.
let dump = ctl("dump")
guard let iconLine = dump.split(separator: "\n").first(where: { $0.hasPrefix("icon (") }) else {
    fail("no icon in dump: \(dump)")
}
let iconNumbers = iconLine.dropFirst("icon (".count).split(separator: ",")
    .compactMap { Double($0.trimmingCharacters(in: CharacterSet(charactersIn: " )"))) }
guard iconNumbers.count == 4 else { fail("unreadable icon line: \(iconLine)") }
let iconRight = iconNumbers[0] + iconNumbers[2]

var results: [String: [String: Any]] = [:]
var missed: [String] = []
var fixture: Process?

for scenario in picked {
    if scenario.overflowing, fixture == nil {
        let items = Process()
        items.executableURL = URL(fileURLWithPath: "\(directory)/bench-items")
        try? items.run()
        fixture = items
        wait(3)
    } else if !scenario.overflowing, let items = fixture {
        items.terminate()
        fixture = nil
        wait(2)
    }
    var firsts: [Double] = [], dones: [Double] = []
    for run in 1...runs {
        _ = ctl("rest")
        wait(1)
        for command in scenario.setup {
            _ = ctl(command)
            wait(1.5)
        }
        let path = "\(captures)/\(scenario.name)-\(run).mov"
        let reply = ctl(
            "capture \(path) \(scenario.seconds) \(scenario.height) \(scenario.scale) \(scenario.action)"
        )
        guard !reply.hasPrefix("failed"), !reply.hasPrefix("no reply"), !reply.hasPrefix("usage") else {
            fail("\(scenario.name): \(reply)")
        }
        wait(1)
        let capture = Capture(path: path, scale: scenario.scale)
        // The marker's columns are left out; so is the clock right of Bouncer's icon in the bar.
        let marker = Int((18 * scenario.scale).rounded(.up))
        let columns = 0..<(scenario.barOnly ? Int(iconRight * scenario.scale) : capture.width - marker)
        if let timing = timing(of: capture, columns: columns) {
            firsts.append(timing.first)
            dones.append(timing.done)
            print("\(scenario.name) \(run)/\(runs): first \(format(timing.first)) ms, done \(format(timing.done)) ms")
        } else {
            missed.append("\(scenario.name) \(run)")
            print("\(scenario.name) \(run)/\(runs): nothing changed")
        }
    }
    if !firsts.isEmpty {
        results["\(scenario.name).first"] = summary(firsts)
        results["\(scenario.name).done"] = summary(dones)
    }
}
fixture?.terminate()

if chosen.isEmpty || chosen.contains("idle") {
    print("idle: hands off the Mac for 30 s")
    wait(3)
    guard let start = usage(of: bouncer) else { fail("cannot read Bouncer Dev's usage") }
    wait(30)
    guard let end = usage(of: bouncer) else { fail("cannot read Bouncer Dev's usage") }
    let cpu = (end.cpu - start.cpu) / 30 * 100, wakeups = Double(end.wakeups - start.wakeups) / 30
    results["idle.cpu"] = summary([cpu])
    results["idle.wakeups"] = summary([wakeups])
    print("idle: \(format(cpu)) % CPU, \(format(wakeups)) wakeups/s")
}

let output: [String: Any] = ["label": label, "date": ISO8601DateFormatter().string(from: Date()), "metrics": results]
let file = "\(directory)/\(label).json"
if let data = try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]) {
    FileManager.default.createFile(atPath: file, contents: data)
}

var rows = [["metric", "p50", "p95", "budget", ""]]
var broken: [String] = []
for key in results.keys.sorted() {
    let median = results[key]?["median"] as? Double, budget = budgets[key]
    let over = median.flatMap { median in budget.map { median > $0 } } ?? false
    if over { broken.append(key) }
    rows.append([key, format(median), format(results[key]?["p95"] as? Double), format(budget), over ? "OVER" : ""])
}
print("\n\(label), \(runs) runs\n\(table(rows))\n\nwritten to \(file)")
if !missed.isEmpty { print("no change seen in: \(missed.joined(separator: ", "))") }
if !broken.isEmpty {
    print("over budget: \(broken.joined(separator: ", "))")
    exit(1)
}
