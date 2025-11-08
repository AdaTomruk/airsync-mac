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
    private var pollingTimer: Timer?
    
    /// Callback to be invoked when Focus mode state changes
    var onFocusModeChanged: ((Bool) -> Void)?
    
    private init() {}
    
    /// Start monitoring Focus mode state changes
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        
        // Log system information
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        logWithTimestamp("Starting Focus Mode monitoring")
        logWithTimestamp("macOS version: \(osVersion)")
        
        // Check initial state
        lastKnownState = checkFocusModeState(verbose: true)
        logWithTimestamp("Initial Focus Mode state: \(lastKnownState ? "enabled" : "disabled")")
        
        // Monitor distributed notification for Focus mode changes
        focusModeObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.controlcenter.FocusModes.changed"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.logWithTimestamp("Received notification: com.apple.controlcenter.FocusModes.changed")
            self?.handleFocusModeChange()
        }
        
        // Also monitor DND state changes (for backward compatibility)
        dndObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.notificationcenterui.dndswitchtoggled"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.logWithTimestamp("Received notification: com.apple.notificationcenterui.dndswitchtoggled")
            self?.handleFocusModeChange()
        }
        
        // Start polling fallback timer (checks every 2 seconds)
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.pollFocusModeState()
        }
        
        logWithTimestamp("Started monitoring Focus mode state with polling fallback")
    }
    
    /// Stop monitoring Focus mode state changes
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        isMonitoring = false
        
        // Stop and invalidate polling timer
        pollingTimer?.invalidate()
        pollingTimer = nil
        
        if let observer = focusModeObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            focusModeObserver = nil
        }
        
        if let observer = dndObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            dndObserver = nil
        }
        
        logWithTimestamp("Stopped monitoring Focus mode state")
    }
    
    /// Polling method to check Focus mode state regularly
    private func pollFocusModeState() {
        let currentState = checkFocusModeState(verbose: false)
        
        // Only notify if state actually changed
        if currentState != lastKnownState {
            lastKnownState = currentState
            logWithTimestamp("Focus mode state changed (detected by polling) to: \(currentState ? "enabled" : "disabled")")
            onFocusModeChanged?(currentState)
        }
    }
    
    private func handleFocusModeChange() {
        logWithTimestamp("handleFocusModeChange called")
        let currentState = checkFocusModeState(verbose: true)
        
        // Only notify if state actually changed
        if currentState != lastKnownState {
            lastKnownState = currentState
            logWithTimestamp("Focus mode state changed (detected by notification) to: \(currentState ? "enabled" : "disabled")")
            onFocusModeChanged?(currentState)
        } else {
            logWithTimestamp("State unchanged: \(currentState ? "enabled" : "disabled")")
        }
    }
    
    /// Check current Focus mode state
    /// Returns true if Focus mode is enabled, false otherwise
    /// - Parameter verbose: If true, logs detailed debugging information
    private func checkFocusModeState(verbose: Bool = false) -> Bool {
        // Primary method: Check using the assertion file (most reliable)
        let assertionPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")
        
        if verbose {
            logWithTimestamp("Checking Focus Mode state")
            logWithTimestamp("Assertions.json path: \(assertionPath.path)")
        }
        
        // Check if file exists
        let fileExists = FileManager.default.fileExists(atPath: assertionPath.path)
        if verbose {
            logWithTimestamp("Assertions.json exists: \(fileExists)")
        }
        
        if !fileExists {
            if verbose {
                logWithTimestamp("Assertions.json file not found, Focus mode is disabled")
            }
            return false
        }
        
        // Check file permissions
        let isReadable = FileManager.default.isReadableFile(atPath: assertionPath.path)
        if verbose {
            logWithTimestamp("Assertions.json is readable: \(isReadable)")
        }
        
        if !isReadable {
            if verbose {
                logWithTimestamp("Cannot read Assertions.json file, assuming Focus mode is disabled")
            }
            return false
        }
        
        // Try to read and parse the file
        do {
            let data = try Data(contentsOf: assertionPath)
            if verbose {
                logWithTimestamp("Successfully read Assertions.json, size: \(data.count) bytes")
            }
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if verbose {
                    logWithTimestamp("Successfully parsed JSON structure")
                    // Log the top-level keys
                    logWithTimestamp("JSON keys: \(json.keys.joined(separator: ", "))")
                }
                
                if let assertions = json["data"] as? [[String: Any]] {
                    if verbose {
                        logWithTimestamp("Found 'data' array with \(assertions.count) assertion(s)")
                        
                        // Log details of each assertion
                        for (index, assertion) in assertions.enumerated() {
                            logWithTimestamp("Assertion \(index): keys = \(assertion.keys.joined(separator: ", "))")
                        }
                    }
                    
                    // If there are any assertions, Focus mode is active
                    let isActive = !assertions.isEmpty
                    if verbose {
                        logWithTimestamp("Focus Mode is \(isActive ? "ENABLED" : "DISABLED") (based on \(assertions.count) assertions)")
                    }
                    return isActive
                } else if verbose {
                    logWithTimestamp("No 'data' array found in JSON or wrong type")
                }
            } else if verbose {
                logWithTimestamp("Failed to parse JSON as dictionary")
            }
        } catch {
            if verbose {
                logWithTimestamp("Error reading/parsing Assertions.json: \(error.localizedDescription)")
            }
        }
        
        // If assertions file is empty or unavailable, Focus mode is not active
        if verbose {
            logWithTimestamp("Defaulting to Focus Mode DISABLED")
        }
        return false
    }
    
    /// Get the current Focus mode state synchronously
    func getCurrentState() -> Bool {
        return checkFocusModeState(verbose: false)
    }
    
    /// Helper method to log messages with timestamp
    private func logWithTimestamp(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let timestamp = formatter.string(from: Date())
        print("[\(timestamp)] [focus-mode] \(message)")
    }
}
