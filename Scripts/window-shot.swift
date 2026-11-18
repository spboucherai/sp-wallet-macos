// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Scripts/window-shot.swift
// Description: Captures the frontmost window of a named app to a PNG (evidence for visual checks).
// Usage: swift Scripts/window-shot.swift <AppName> <output.png>
import CoreGraphics
import Foundation
let args = CommandLine.arguments
guard args.count == 3 else { print("usage: window-shot <AppName> <out.png>"); exit(2) }
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let wins = list.filter { ($0["kCGWindowOwnerName"] as? String) == args[1] && ($0["kCGWindowLayer"] as? Int) == 0 }
guard let win = wins.first, let id = win["kCGWindowNumber"] as? Int else { print("no window for \(args[1])"); exit(1) }
print("window \(id) \(win["kCGWindowBounds"] ?? "") title=\(win["kCGWindowName"] ?? "")")
let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture"); p.arguments = ["-l", String(id), "-o", "-x", args[2]]
try! p.run(); p.waitUntilExit(); print("saved \(args[2])")
