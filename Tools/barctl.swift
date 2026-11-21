// Sends one command to the dev harness in a running Bouncer Dev and prints its reply.
//
// Compiled once by `make ctl CMD="shoot /tmp/bar.png"`. Posting a distributed
// notification needs no permission; the harness inside the app holds the ones that do.
//
//   still [command ...]                runs the command, then waits until the bar's frames stop moving
//   ready                              waits for a launching Bouncer Dev to answer
//   click                              what a click on Bouncer's icon does
//   open, close                        the standalone bar
//   dump [path]                        every item, the chevron and Bouncer's windows, with frames
//   shoot <path.png> [height]          the top of the main display, 120 pt by default
//   record <path.mov> <seconds> [height]  the same as a video, at most 30 s
//   key <shortcut>                     presses it, as cmd+shift+n, escape or cmd+z
//   type <text>                        types it into whatever has focus
//   tap <x> <y>                        clicks there, in the coordinates dump prints
//   odrag|pdrag <x1> <y1> <x2> <y2>     an Option-drag or a plain drag between two points
//   move <x> <y> [<x> <y> ...]         glides the pointer to each point in turn, 0.2 s each
//   decks [on|off|group n|hover i|clear [windows|spaces]|spaces|cards|pictures|focus id]  the window overview: toggle it, or set it up
import Foundation

let command = CommandLine.arguments.dropFirst().joined(separator: " ")
guard !command.isEmpty else {
    print("usage: barctl click | open | close | dump [path] | shoot <png> [height] | record <mov> <seconds> [height] | key <shortcut> | type <text> | tap <x> <y>")
    exit(1)
}

let id = UUID().uuidString
let center = DistributedNotificationCenter.default()
var reply: String?
let observer = center.addObserver(forName: Notification.Name("com.bouncer.dev.reply"), object: id, queue: .main) {
    reply = $0.userInfo?["result"] as? String ?? ""
}
func post() {
    center.postNotificationName(
        Notification.Name("com.bouncer.dev.command"), object: command, userInfo: ["reply": id], deliverImmediately: true
    )
}
post()

// A command posted before the app listens is dropped, so `ready` posts again until it is answered.
let deadline = Date().addingTimeInterval(40)
var posted = Date()
while reply == nil, Date() < deadline {
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    if command == "ready", Date().timeIntervalSince(posted) > 0.25 {
        post()
        posted = Date()
    }
}
guard let reply else {
    print("no reply: is Bouncer Dev running?")
    exit(1)
}
print(reply)
exit(reply.hasPrefix("failed") || reply.hasPrefix("unknown") ? 1 : 0)
