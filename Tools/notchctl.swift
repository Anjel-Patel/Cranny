// Sends a command to a running Cranny, e.g. `notchctl open tray`, `notchctl close`.
import Foundation

let command = CommandLine.arguments.dropFirst().joined(separator: " ")
guard !command.isEmpty else {
    print("usage: notchctl <open [nook|tray] | close | toggle | settings [pane] | hover [seconds] | update | media toggle|next|previous>")
    exit(1)
}
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("io.github.rdbms234.Cranny.command"), object: command, userInfo: nil, deliverImmediately: true
)
