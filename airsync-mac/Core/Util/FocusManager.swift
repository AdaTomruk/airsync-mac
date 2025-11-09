//
//  FocusManager.swift
//  airsync-mac
//
//  Created by Gemini on 2025-11-09.
//  Refactored on 2025-11-09 to fix compiler errors.
//
//  This is the official, Apple-supported way to monitor Focus Mode.
//  It uses DistributedNotificationCenter to detect changes and
//  INFocusStatusCenter to read the official state.
//
//  This method requires:
//  1. The `Intents` framework.
//  2. The "Privacy - Focus Status Usage Description" key in your Info.plist.
//
//  It does NOT require Full Disk Access and works with App Sandbox.
//

import Foundation
import Intents
internal import Combine // <-- FIXED: Explicitly mark import as internal
import os.log

/// Monitors macOS Focus Mode (Do Not Disturb) state changes using the official `INFocusStatusCenter` API.
/// It listens for system notifications and then queries the INFocusStatusCenter for the new state.
@available(macOS 12.0, *) // <-- ADDED: Ensures all APIs are available
class FocusManager: NSObject {
    
    // A logger for clean, filterable console output.
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.unknown", category: "FocusManager")
    
    /// The shared `INFocusStatusCenter` instance.
    private let center = INFocusStatusCenter.default
    
    /// A simple, thread-safe way to store the last known state.
    @Published private(set) var isFocusModeEnabled: Bool = false
    
    /// Callback to be invoked on the main thread when Focus mode state changes.
    var onFocusModeChanged: ((_ isEnabled: Bool) -> Void)?
    
    // --- REPLACED DELEGATE WITH NOTIFICATION OBSERVERS ---
    private var focusModeObserver: NSObjectProtocol?
    private var dndObserver: NSObjectProtocol?
    
    override init() {
        super.init()
        logger.info("FocusManager initialized.")
        // We will request permission, and if granted, setup observers then.
    }
    
    /// Requests authorization from the user to access Focus Mode status.
    /// This should be called when your app starts.
    func requestPermission() {
        logger.debug("Requesting Focus Status authorization...")
        
        center.requestAuthorization { [weak self] (status) in
            // Ensure we update UI/state on the main thread
            DispatchQueue.main.async {
                self?.handleAuthorizationStatus(status)
            }
        }
    }
    
    /// Handles the result of the permission request.
    private func handleAuthorizationStatus(_ status: INFocusStatusAuthorizationStatus) {
        switch status {
        case .authorized:
            logger.info("Focus Status permission granted.")
            // Now that we have permission, check the initial state
            self.checkCurrentStatus()
            // And set up the observers to listen for changes
            self.setupObservers()
        case .denied:
            logger.warning("Focus Status permission was denied by the user.")
        case .notDetermined:
            logger.info("Focus Status permission not determined (user hasn't been asked yet).")
        @unknown default:
            logger.error("An unknown authorization status was returned.")
        }
    }
    
    /// Sets up the DistributedNotificationCenter observers on the main thread.
    private func setupObservers() {
        logger.debug("Setting up notification observers...")
        
        focusModeObserver = DistributedNotificationCenter.default().addObserver(
            forName: .focusModesChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.logger.debug("Received notification: .focusModesChanged. Checking status...")
            self?.checkCurrentStatus()
        }
        
        dndObserver = DistributedNotificationCenter.default().addObserver(
            forName: .dndToggled,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.logger.debug("Received notification: .dndToggled. Checking status...")
            self?.checkCurrentStatus()
        }
    }
    
    /// Checks the current Focus Mode state by querying the API.
    func checkCurrentStatus() {
        // Ensure we are authorized before checking
        guard center.authorizationStatus == .authorized else {
            logger.warning("Attempted to check status, but app is not authorized.")
            // You could re-request permission here if it's .notDetermined
            if center.authorizationStatus == .notDetermined {
                requestPermission()
            }
            return
        }
        
        // --- FIXED: Safely unwrap the optional Bool? ---
        // Coalesce nil (unknown) to false (not focused)
        let isFocused = center.focusStatus.isFocused ?? false
        logger.info("Checked current state: Focus Mode is \(isFocused ? "ON" : "OFF")")
        
        // Update our internal state and fire the callback
        self.updateState(isFocused)
    }
    
    /// A private helper to update the state and notify listeners.
    /// Ensures callbacks are on the main thread.
    private func updateState(_ isEnabled: Bool) {
        // No need to update if the state is the same
        guard self.isFocusModeEnabled != isEnabled else { return }
        
        self.isFocusModeEnabled = isEnabled
        
        // Ensure the external callback is on the main thread
        DispatchQueue.main.async {
            self.onFocusModeChanged?(isEnabled)
        }
    }
    
    deinit {
        // Clean up observers
        if let observer = focusModeObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        if let observer = dndObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }
}

// MARK: - Notification Names
private extension NSNotification.Name {
    static let focusModesChanged = NSNotification.Name("com.apple.controlcenter.FocusModes.changed")
    static let dndToggled = NSNotification.Name("com.apple.notificationcenterui.dndswitchtoggled")
}
