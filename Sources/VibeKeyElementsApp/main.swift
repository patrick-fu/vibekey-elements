import AppKit
import Foundation
import VibeKeyCore

if let resultPath = VibeKeyPermissionProbe.resultPath(from: Array(CommandLine.arguments.dropFirst())) {
    let reports = VibeKeyPermissionCenter.live.check()
    exit(VibeKeyPermissionProbe.write(reports, to: resultPath) ? EXIT_SUCCESS : EXIT_FAILURE)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
