//
//  FocusModeMonitor.swift
//  airsync-mac
//
//  Created by AirSync on 2025-11-06.
//

import Foundation
import Cocoa

/// Monitors macOS Focus Mode (Do Not Disturb) state changes and notifies observers
class FocusModeMonitor {
    static let shared = FocusModeMonitor()
    
    private var isMonitoring = false
    private var lastKnownState: Bool = false
    private var focusModeObserver: NSObjectProtocol?
    private var dndObserver: NSObjectProtocol?
    
    /// Callback to be invoked when Focus mode state changes
    var onFocusModeChanged: ((Bool) -> Void)?
    
    private init() {}
    
    /// Start monitoring Focus mode state changes
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        lastKnownState = checkFocusModeState()
        
        // Monitor distributed notification for Focus mode changes
        focusModeObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.controlcenter.FocusModes.changed"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleFocusModeChange()
        }
        
        // Also monitor DND state changes (for backward compatibility)
        dndObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.notificationcenterui.dndswitchtoggled"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleFocusModeChange()
        }
        
        print("[focus-mode] Started monitoring Focus mode state")
    }
    
    /// Stop monitoring Focus mode state changes
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        isMonitoring = false
        
        if let observer = focusModeObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            focusModeObserver = nil
        }
        
        if let observer = dndObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            dndObserver = nil
        }
        
        print("[focus-mode] Stopped monitoring Focus mode state")
    }
    
    private func handleFocusModeChange() {
        let currentState = checkFocusModeState()
        
        // Only notify if state actually changed
        if currentState != lastKnownState {
            lastKnownState = currentState
            print("[focus-mode] Focus mode state changed to: \(currentState ? "enabled" : "disabled")")
            onFocusModeChanged?(currentState)
        }
    }
    
    /// Check current Focus mode state
    /// Returns true if Focus mode is enabled, false otherwise
    private func checkFocusModeState() -> Bool {
        // Primary method: Check using the assertion file (most reliable)
        let assertionPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")
        
        if let data = try? Data(contentsOf: assertionPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let assertions = json["data"] as? [[String: Any]],
           !assertions.isEmpty {
            // If there are any assertions, Focus mode is active
            return true
        }
        
        // If assertions file is empty or unavailable, Focus mode is not active
        return false
    }
    
    /// Get the current Focus mode state synchronously
    func getCurrentState() -> Bool {
        return checkFocusModeState()
    }
}
