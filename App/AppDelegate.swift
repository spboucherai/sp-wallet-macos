// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: App/AppDelegate.swift
// Description: Application delegate: activity tracking (no polling in the background), the optional window lock, notification permission on demand, and a guard that the main window exists after a relaunch.
import AppKit
import UserNotifications

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        NSWindow.allowsAutomaticWindowTabbing = false
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        AppActivity.isActive = true
        model?.lock.appDidBecomeActive()
        if let m = model, m.phase == .signedIn { Task { await m.refreshPortfolio() } }
    }
    func applicationDidResignActive(_ notification: Notification) { AppActivity.isActive = false; model?.lock.appDidResign() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // a notification is shown even when the app is frontmost
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .list, .sound] }
}
