import CoreGraphics
import Foundation

// Small dev helper: prints on-screen window ids for the MQ80 Studio app so
// `screencapture -l <id>` can capture just the app window (clean screenshots).
let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    exit(1)
}
var found = false
for window in windows {
    let owner = window[kCGWindowOwnerName as String] as? String ?? ""
    let number = window[kCGWindowNumber as String] as? Int ?? 0
    let layer = window[kCGWindowLayer as String] as? Int ?? 0
    let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
    let width = bounds["Width"] as? Double ?? 0
    if owner.contains("IQUNIX") || owner.contains("MQ80"), layer == 0, width > 600, number > 0 {
        print(number)
        found = true
    }
}
if !found { exit(2) }
