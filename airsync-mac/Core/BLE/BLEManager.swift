//
//  BLEManager.swift
//  airsync-mac
//
//  Manages Bluetooth Low Energy communication with Android devices
//  to trigger hotspot functionality.
//

import Foundation
import CoreBluetooth
internal import Combine

/// Custom BLE service UUID for AirSync hotspot trigger
/// This UUID should match the one used in the Android AirSync app
let AIRSYNC_SERVICE_UUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
/// Characteristic UUID for writing hotspot commands
let HOTSPOT_CHARACTERISTIC_UUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")

/// Manages BLE communication for triggering hotspot on Android devices
class BLEManager: NSObject, ObservableObject {
    static let shared = BLEManager()
    
    private var centralManager: CBCentralManager!
    private var discoveredPeripheral: CBPeripheral?
    private var hotspotCharacteristic: CBCharacteristic?
    
    @Published var isBluetoothEnabled: Bool = false
    @Published var isScanning: Bool = false
    @Published var isConnected: Bool = false
    @Published var connectionStatus: String = "Not connected"
    @Published var lastError: String?
    
    private var scanTimer: Timer?
    private let scanTimeout: TimeInterval = 10.0
    
    // Callback for when hotspot trigger completes
    private var hotspotTriggerCompletion: ((Bool, String?) -> Void)?
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // MARK: - Public Interface
    
    /// Triggers the hotspot on the connected Android device
    /// - Parameter completion: Callback with success status and optional error message
    func triggerHotspot(completion: @escaping (Bool, String?) -> Void) {
        guard isBluetoothEnabled else {
            completion(false, "Bluetooth is not enabled")
            return
        }
        
        hotspotTriggerCompletion = completion
        
        if isConnected, let characteristic = hotspotCharacteristic, let peripheral = discoveredPeripheral {
            sendHotspotCommand(to: peripheral, characteristic: characteristic)
        } else {
            // Start scanning for the device
            startScanning()
        }
    }
    
    /// Starts scanning for AirSync BLE peripherals
    func startScanning() {
        guard isBluetoothEnabled else {
            print("[BLE] Cannot scan - Bluetooth not enabled")
            lastError = "Bluetooth is not enabled"
            return
        }
        
        guard !isScanning else {
            print("[BLE] Already scanning")
            return
        }
        
        print("[BLE] Starting scan for AirSync peripherals...")
        connectionStatus = "Scanning..."
        isScanning = true
        
        centralManager.scanForPeripherals(withServices: [AIRSYNC_SERVICE_UUID], options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
        
        // Set a timeout for scanning
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: scanTimeout, repeats: false) { [weak self] _ in
            self?.stopScanning(reason: "Scan timeout - no device found")
        }
    }
    
    /// Stops scanning for peripherals
    func stopScanning(reason: String? = nil) {
        guard isScanning else { return }
        
        centralManager.stopScan()
        isScanning = false
        scanTimer?.invalidate()
        scanTimer = nil
        
        if let reason = reason {
            print("[BLE] Stopped scanning: \(reason)")
            connectionStatus = reason
            lastError = reason
            hotspotTriggerCompletion?(false, reason)
            hotspotTriggerCompletion = nil
        } else {
            print("[BLE] Stopped scanning")
        }
    }
    
    /// Disconnects from the connected peripheral
    func disconnect() {
        if let peripheral = discoveredPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        cleanup()
    }
    
    // MARK: - Private Implementation
    
    private func cleanup() {
        discoveredPeripheral = nil
        hotspotCharacteristic = nil
        isConnected = false
        connectionStatus = "Disconnected"
    }
    
    private func sendHotspotCommand(to peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        // Create hotspot trigger command
        let command = "HOTSPOT_TOGGLE"
        guard let data = command.data(using: .utf8) else {
            print("[BLE] Failed to encode hotspot command")
            hotspotTriggerCompletion?(false, "Failed to encode command")
            hotspotTriggerCompletion = nil
            return
        }
        
        print("[BLE] Sending hotspot command...")
        connectionStatus = "Sending command..."
        
        // Write the command to the characteristic
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("[BLE] Bluetooth is powered on")
            isBluetoothEnabled = true
            lastError = nil
        case .poweredOff:
            print("[BLE] Bluetooth is powered off")
            isBluetoothEnabled = false
            connectionStatus = "Bluetooth is off"
            cleanup()
        case .unauthorized:
            print("[BLE] Bluetooth access unauthorized")
            isBluetoothEnabled = false
            connectionStatus = "Bluetooth unauthorized"
            lastError = "Bluetooth access not authorized"
        case .unsupported:
            print("[BLE] Bluetooth LE is not supported")
            isBluetoothEnabled = false
            connectionStatus = "BLE not supported"
            lastError = "Bluetooth LE not supported on this device"
        case .resetting:
            print("[BLE] Bluetooth is resetting")
            cleanup()
        case .unknown:
            print("[BLE] Bluetooth state unknown")
        @unknown default:
            print("[BLE] Unknown Bluetooth state")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        print("[BLE] Discovered peripheral: \(peripheral.name ?? "Unknown") RSSI: \(RSSI)")
        
        // Stop scanning once we find a device
        stopScanning()
        
        // Store reference and connect
        discoveredPeripheral = peripheral
        peripheral.delegate = self
        
        connectionStatus = "Connecting to \(peripheral.name ?? "device")..."
        centralManager.connect(peripheral, options: nil)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("[BLE] Connected to peripheral: \(peripheral.name ?? "Unknown")")
        isConnected = true
        connectionStatus = "Connected to \(peripheral.name ?? "device")"
        
        // Discover services
        peripheral.discoverServices([AIRSYNC_SERVICE_UUID])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("[BLE] Failed to connect: \(error?.localizedDescription ?? "Unknown error")")
        connectionStatus = "Connection failed"
        lastError = error?.localizedDescription ?? "Connection failed"
        hotspotTriggerCompletion?(false, lastError)
        hotspotTriggerCompletion = nil
        cleanup()
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("[BLE] Disconnected from peripheral: \(peripheral.name ?? "Unknown")")
        if let error = error {
            print("[BLE] Disconnect error: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
        cleanup()
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("[BLE] Error discovering services: \(error.localizedDescription)")
            lastError = error.localizedDescription
            hotspotTriggerCompletion?(false, error.localizedDescription)
            hotspotTriggerCompletion = nil
            return
        }
        
        guard let services = peripheral.services else {
            print("[BLE] No services discovered")
            return
        }
        
        for service in services {
            print("[BLE] Discovered service: \(service.uuid)")
            if service.uuid == AIRSYNC_SERVICE_UUID {
                peripheral.discoverCharacteristics([HOTSPOT_CHARACTERISTIC_UUID], for: service)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("[BLE] Error discovering characteristics: \(error.localizedDescription)")
            lastError = error.localizedDescription
            hotspotTriggerCompletion?(false, error.localizedDescription)
            hotspotTriggerCompletion = nil
            return
        }
        
        guard let characteristics = service.characteristics else {
            print("[BLE] No characteristics discovered")
            return
        }
        
        for characteristic in characteristics {
            print("[BLE] Discovered characteristic: \(characteristic.uuid)")
            if characteristic.uuid == HOTSPOT_CHARACTERISTIC_UUID {
                hotspotCharacteristic = characteristic
                print("[BLE] Found hotspot characteristic")
                
                // If we have a pending hotspot trigger, send it now
                if hotspotTriggerCompletion != nil {
                    sendHotspotCommand(to: peripheral, characteristic: characteristic)
                }
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("[BLE] Error writing characteristic: \(error.localizedDescription)")
            connectionStatus = "Command failed"
            lastError = error.localizedDescription
            hotspotTriggerCompletion?(false, error.localizedDescription)
        } else {
            print("[BLE] Successfully sent hotspot command")
            connectionStatus = "Hotspot triggered"
            hotspotTriggerCompletion?(true, nil)
            
            // Post notification
            AppState.shared.postNativeNotification(
                id: "ble_hotspot_\(UUID().uuidString)",
                appName: "AirSync",
                title: "Hotspot",
                body: "Hotspot toggle command sent to Android device"
            )
        }
        hotspotTriggerCompletion = nil
    }
}
