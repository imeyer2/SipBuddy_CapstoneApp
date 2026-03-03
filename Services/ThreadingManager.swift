//
//  ThreadingManager.swift
//  SipBuddy
//
//  Centralized threading management for smooth UI performance
//  Provides dedicated queues for different workloads
//

import Foundation

/// Centralized manager for app-wide threading and dispatch queues
/// Use these queues instead of creating ad-hoc ones to ensure proper resource management
final class ThreadingManager {
    
    static let shared = ThreadingManager()
    
    // MARK: - Dedicated Work Queues
    
    /// High-priority queue for image processing (JPEG→PNG conversion, resizing)
    /// Concurrent for parallel frame processing
    let imageProcessing: DispatchQueue
    
    /// Queue for disk I/O operations (save/load incidents)
    /// Serial to prevent race conditions on file access
    let diskIO: DispatchQueue
    
    /// Queue for ML inference operations
    /// Serial + userInitiated QoS for predictable execution
    let mlInference: DispatchQueue
    
    /// Queue for notification attachment creation (GIF encoding)
    /// Background QoS since it's not time-critical
    let notificationPrep: DispatchQueue
    
    /// Queue for network/telemetry operations
    /// Concurrent for parallel requests
    let network: DispatchQueue
    
    /// Queue for BLE data parsing (FR2 assembly, header parsing)
    /// High priority serial queue for real-time data handling
    let bleDataParsing: DispatchQueue
    
    // MARK: - Coalescing Support
    
    /// Pending save work item (for coalescing rapid saves)
    private var pendingSaveWorkItem: DispatchWorkItem?
    private let saveCoalesceDelay: TimeInterval = 0.3 // 300ms debounce
    private let saveCoalesceLock = NSLock()
    
    // MARK: - Initialization
    
    private init() {
        // Create queues with appropriate QoS and attributes
        
        imageProcessing = DispatchQueue(
            label: "com.sipbuddy.imageProcessing",
            qos: .userInitiated,
            attributes: .concurrent
        )
        
        diskIO = DispatchQueue(
            label: "com.sipbuddy.diskIO",
            qos: .utility
        )
        
        mlInference = DispatchQueue(
            label: "com.sipbuddy.mlInference",
            qos: .userInitiated
        )
        
        notificationPrep = DispatchQueue(
            label: "com.sipbuddy.notificationPrep",
            qos: .background
        )
        
        network = DispatchQueue(
            label: "com.sipbuddy.network",
            qos: .utility,
            attributes: .concurrent
        )
        
        bleDataParsing = DispatchQueue(
            label: "com.sipbuddy.bleDataParsing",
            qos: .userInteractive
        )
        
        Log.d("[Threading] Manager initialized with dedicated queues")
    }
    
    // MARK: - Convenience Methods
    
    /// Execute work on main thread, avoiding dispatch if already on main
    static func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
    
    /// Execute work on main thread after a delay
    static func onMainAfter(_ delay: TimeInterval, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
    
    /// Schedule coalesced disk save - multiple rapid calls result in single save
    /// - Parameter saveBlock: The actual save operation to perform
    func scheduleCoalescedSave(_ saveBlock: @escaping () -> Void) {
        saveCoalesceLock.lock()
        defer { saveCoalesceLock.unlock() }
        
        // Cancel any pending save
        pendingSaveWorkItem?.cancel()
        
        // Create new work item
        let workItem = DispatchWorkItem { [weak self] in
            saveBlock()
            self?.saveCoalesceLock.lock()
            self?.pendingSaveWorkItem = nil
            self?.saveCoalesceLock.unlock()
        }
        
        pendingSaveWorkItem = workItem
        
        // Schedule with delay for coalescing
        diskIO.asyncAfter(deadline: .now() + saveCoalesceDelay, execute: workItem)
    }
    
    /// Force immediate save (bypasses coalescing)
    func forceImmediateSave(_ saveBlock: @escaping () -> Void) {
        saveCoalesceLock.lock()
        pendingSaveWorkItem?.cancel()
        pendingSaveWorkItem = nil
        saveCoalesceLock.unlock()
        
        diskIO.async(execute: saveBlock)
    }
    
    /// Process image data on background thread, return result on main
    /// - Parameters:
    ///   - data: Raw image data (JPEG/PNG)
    ///   - transform: Transform to apply (runs on background)
    ///   - completion: Called on main thread with result
    func processImage<T>(
        _ data: Data,
        transform: @escaping (Data) -> T?,
        completion: @escaping (T?) -> Void
    ) {
        imageProcessing.async {
            let result = transform(data)
            ThreadingManager.onMain {
                completion(result)
            }
        }
    }
    
    /// Run ML inference on dedicated queue
    func runInference(_ work: @escaping () -> Void) {
        mlInference.async(execute: work)
    }
    
    /// Prepare notification content on background
    func prepareNotification(_ work: @escaping () -> Void, then completion: @escaping () -> Void) {
        notificationPrep.async {
            work()
            ThreadingManager.onMain(completion)
        }
    }
}

// MARK: - Global Convenience Functions

/// Quick access to main thread dispatch
func onMain(_ work: @escaping () -> Void) {
    ThreadingManager.onMain(work)
}

/// Quick access to main thread dispatch with delay
func onMainAfter(_ delay: TimeInterval, _ work: @escaping () -> Void) {
    ThreadingManager.onMainAfter(delay, work)
}
