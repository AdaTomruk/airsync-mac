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
    private var observer: NSObjectProtocol?
    
    /// Callback to be invoked when Focus mode state changes
    var onFocusModeChanged: ((Bool) -> Void)?
    
    private init() {}
    
    /// Start monitoring Focus mode state changes
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        lastKnownState = checkFocusModeState()
        
        // Monitor distributed notification for Focus mode changes
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.controlcenter.FocusModes.changed"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleFocusModeChange()
        }
        
        // Also monitor DND state changes (for backward compatibility)
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleFocusModeChange),
            name: NSNotification.Name("com.apple.notificationcenterui.dndswitchtoggled"),
            object: nil
        )
        
        print("[focus-mode] Started monitoring Focus mode state")
    }
    
    /// Stop monitoring Focus mode state changes
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        isMonitoring = false
        
        if let observer = observer {
            DistributedNotificationCenter.default().removeObserver(observer)
            self.observer = nil
        }
        
        DistributedNotificationCenter.default().removeObserver(self)
        
        print("[focus-mode] Stopped monitoring Focus mode state")
    }
    
    @objc private func handleFocusModeChange() {
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
    func checkFocusModeState() -> Bool {
        // Try to check using the assertion file method (most reliable)
        let assertionPath = "\(NSHomeDirectory())/Library/DoNotDisturb/DB/Assertions.json"
        
        if let data = try? Data(contentsOf: URL(fileURLWithPath: assertionPath)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let data = json["data"] as? [[String: Any]],
           !data.isEmpty {
            // If there are any assertions, Focus mode is likely active
            return true
        }
        
        // Fallback: Check the ModeConfigurations.json file
        let configPath = "\(NSHomeDirectory())/Library/DoNotDisturb/DB/ModeConfigurations.json"
        if let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let data = json["data"] as? [[String: Any]] {
            // Check if any mode is currently active
            for mode in data {
                if let mode = mode["mode"] as? [String: Any],
                   let configuration = mode["configuration"] as? [String: Any] {
                    // Check for active mode indicators
                    // This is a heuristic and may need adjustment
                    return false // Conservative: assume off if we can't determine
                }
            }
        }
        
        return false
    }
    
    /// Get the current Focus mode state synchronously
    func getCurrentState() -> Bool {
        return checkFocusModeState()
    }
}
