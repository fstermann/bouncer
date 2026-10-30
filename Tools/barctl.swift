// Sends one command to the dev harness in a running Bouncer Dev and prints its reply.
//
// Run through the interpreter: `make ctl CMD="shoot /tmp/bar.png"`. Posting a distributed
// notification needs no permission; the harness inside the app holds the ones that do.
//
//   click                              what a click on Bouncer's icon does
//   open, close                        the standalone bar
//   dump [path]                        every item, the chevron and Bouncer's windows, with frames
//   shoot <path.png> [height]          the top of the main display, 120 pt by default
//   record <path.mov> <seconds> [height]  the same as a video, at most 30 s
import Foundation

let command = CommandLine.arguments.dropFirst().joined(separator: " ")
guard !command.isEmpty else {
    print("usage: barctl click | open | close | dump [path] | shoot <png> [height] | record <mov> <seconds> [height]")
    exit(1)
}

let id = UUID().uuidString
let center = DistributedNotificationCenter.default()
var reply: String?
let observer = center.addObserver(forName: Notification.Name("com.bouncer.dev.reply"), object: id, queue: .main) {
    reply = $0.userInfo?["result"] as? String ?? ""
}
center.postNotificationName(
    Notification.Name("com.bouncer.dev.command"), object: command, userInfo: ["reply": id], deliverImmediately: true
)

let deadline = Date().addingTimeInterval(40)
while reply == nil, Date() < deadline {
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}
guard let reply else {
    print("no reply: is Bouncer Dev running?")
    exit(1)
}
print(reply)
exit(reply.hasPrefix("failed") || reply.hasPrefix("unknown") ? 1 : 0)
