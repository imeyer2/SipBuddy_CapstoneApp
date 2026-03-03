//
//  PerformanceLogger.swift
//  SipBuddy
//
//  Performance measurement and logging for threading optimizations
//  Tracks main thread blocking, queue execution times, and overall responsiveness
//

import Foundation
import QuartzCore
import UIKit

/// Centralized performance logging for tracking threading optimizations
final class PerformanceLogger {
    
    static let shared = PerformanceLogger()
    
    // MARK: - Configuration
    
    /// Enable/disable performance logging (disable in production for performance)
    #if DEBUG
    var isEnabled = true
    #else
    var isEnabled = false
    #endif
    
    /// Threshold in ms above which we log a warning for main thread blocks
    var mainThreadBlockThresholdMs: Double = 16.0 // 1 frame at 60fps
    
    /// Threshold in ms above which we log a warning for any operation
    var operationWarningThresholdMs: Double = 100.0
    
    // MARK: - Statistics Tracking
    
    private let statsLock = NSLock()
    private var operationStats: [String: OperationStats] = [:]
    
    private struct OperationStats {
        var totalTime: Double = 0
        var count: Int = 0
        var maxTime: Double = 0
        var minTime: Double = Double.greatestFiniteMagnitude
        
        var avgTime: Double { count > 0 ? totalTime / Double(count) : 0 }
    }
    
    private init() {
        Log.d("[Perf] Performance logger initialized (enabled: \(isEnabled))")
    }
    
    // MARK: - Main Thread Monitoring
    
    /// Check if we're on the main thread and log if blocking
    func checkMainThread(context: String) {
        guard isEnabled else { return }
        if Thread.isMainThread {
            Log.d("[Perf] ⚠️ \(context) running on MAIN thread - consider moving to background")
        }
    }
    
    /// Measure time spent on main thread
    func measureMainThreadBlock(_ operation: String, _ work: () -> Void) {
        guard isEnabled else { 
            work()
            return 
        }
        
        let isMain = Thread.isMainThread
        let start = CACurrentMediaTime()
        work()
        let elapsed = (CACurrentMediaTime() - start) * 1000 // Convert to ms
        
        if isMain && elapsed > mainThreadBlockThresholdMs {
            Log.d("[Perf] ⚠️ MAIN THREAD BLOCKED: \(operation) took \(String(format: "%.2f", elapsed))ms")
        }
        
        recordStat(for: operation, time: elapsed)
    }
    
    // MARK: - Operation Timing
    
    /// Start timing an operation, returns a token to pass to `endTiming`
    func startTiming(_ operation: String) -> TimingToken {
        TimingToken(operation: operation, startTime: CACurrentMediaTime())
    }
    
    /// End timing and log result
    func endTiming(_ token: TimingToken) {
        guard isEnabled else { return }
        
        let elapsed = (CACurrentMediaTime() - token.startTime) * 1000
        let queueType = Thread.isMainThread ? "main" : "background"
        
        if elapsed > operationWarningThresholdMs {
            Log.d("[Perf] ⏱️ \(token.operation) took \(String(format: "%.2f", elapsed))ms on \(queueType) queue")
        }
        
        recordStat(for: token.operation, time: elapsed)
    }
    
    /// Convenience method to measure a block and return its result
    func measure<T>(_ operation: String, _ work: () -> T) -> T {
        guard isEnabled else { return work() }
        
        let token = startTiming(operation)
        let result = work()
        endTiming(token)
        return result
    }
    
    /// Async version for completion-based APIs
    func measureAsync(_ operation: String, work: @escaping (@escaping () -> Void) -> Void) {
        guard isEnabled else {
            work({})
            return
        }
        
        let token = startTiming(operation)
        work { [weak self] in
            self?.endTiming(token)
        }
    }
    
    // MARK: - Queue-Specific Logging
    
    /// Log when work is dispatched to a specific queue
    func logQueueDispatch(queue: String, operation: String) {
        guard isEnabled else { return }
        Log.d("[Perf] 📤 Dispatching '\(operation)' to \(queue) queue")
    }
    
    /// Log when work completes on a specific queue
    func logQueueComplete(queue: String, operation: String, timeMs: Double) {
        guard isEnabled else { return }
        let emoji = timeMs > operationWarningThresholdMs ? "⚠️" : "✅"
        Log.d("[Perf] \(emoji) '\(operation)' completed on \(queue) queue in \(String(format: "%.2f", timeMs))ms")
    }
    
    // MARK: - Statistics
    
    private func recordStat(for operation: String, time: Double) {
        statsLock.lock()
        defer { statsLock.unlock() }
        
        var stats = operationStats[operation] ?? OperationStats()
        stats.totalTime += time
        stats.count += 1
        stats.maxTime = max(stats.maxTime, time)
        stats.minTime = min(stats.minTime, time)
        operationStats[operation] = stats
    }
    
    /// Print summary of all tracked operations
    func printStatsSummary() {
        guard isEnabled else { return }
        
        statsLock.lock()
        let stats = operationStats
        statsLock.unlock()
        
        Log.d("[Perf] ═══════════════════════════════════════")
        Log.d("[Perf] Performance Statistics Summary")
        Log.d("[Perf] ═══════════════════════════════════════")
        
        for (operation, stat) in stats.sorted(by: { $0.value.avgTime > $1.value.avgTime }) {
            Log.d("[Perf] \(operation):")
            Log.d("[Perf]   Count: \(stat.count)")
            Log.d("[Perf]   Avg: \(String(format: "%.2f", stat.avgTime))ms")
            Log.d("[Perf]   Min: \(String(format: "%.2f", stat.minTime))ms")
            Log.d("[Perf]   Max: \(String(format: "%.2f", stat.maxTime))ms")
        }
        
        Log.d("[Perf] ═══════════════════════════════════════")
    }
    
    /// Reset all statistics
    func resetStats() {
        statsLock.lock()
        operationStats.removeAll()
        statsLock.unlock()
    }
    
    // MARK: - Frame Drop Detection
    
    private var lastFrameTime: CFTimeInterval = 0
    private var frameDropCount = 0
    
    /// Call this from a CADisplayLink to detect frame drops
    func checkFrameRate(displayLinkTimestamp: CFTimeInterval) {
        guard isEnabled else { return }
        
        if lastFrameTime > 0 {
            let elapsed = displayLinkTimestamp - lastFrameTime
            let expectedFrameTime = 1.0 / 60.0 // 60fps target
            
            // If we took more than 1.5x expected frame time, we dropped a frame
            if elapsed > expectedFrameTime * 1.5 {
                frameDropCount += 1
                Log.d("[Perf] 🔴 Frame drop detected! Took \(String(format: "%.1f", elapsed * 1000))ms (expected ~\(String(format: "%.1f", expectedFrameTime * 1000))ms)")
            }
        }
        lastFrameTime = displayLinkTimestamp
    }
    
    /// Get total frame drops since app start
    var totalFrameDrops: Int { frameDropCount }
}

// MARK: - Timing Token

struct TimingToken {
    let operation: String
    let startTime: CFTimeInterval
}

// MARK: - Convenience Extensions

extension ThreadingManager {
    
    /// Execute work on queue with performance logging
    func performWithLogging(
        on queue: DispatchQueue,
        queueName: String,
        operation: String,
        work: @escaping () -> Void
    ) {
        PerformanceLogger.shared.logQueueDispatch(queue: queueName, operation: operation)
        let start = CACurrentMediaTime()
        
        queue.async {
            work()
            let elapsed = (CACurrentMediaTime() - start) * 1000
            PerformanceLogger.shared.logQueueComplete(queue: queueName, operation: operation, timeMs: elapsed)
        }
    }
    
    /// Timed image processing with logging
    func processImageWithLogging(
        _ data: Data,
        operation: String,
        transform: @escaping (Data) -> UIImage?,
        completion: @escaping (UIImage?) -> Void
    ) {
        PerformanceLogger.shared.logQueueDispatch(queue: "imageProcessing", operation: operation)
        let start = CACurrentMediaTime()
        
        imageProcessing.async {
            let result = transform(data)
            let elapsed = (CACurrentMediaTime() - start) * 1000
            PerformanceLogger.shared.logQueueComplete(queue: "imageProcessing", operation: operation, timeMs: elapsed)
            
            ThreadingManager.onMain {
                completion(result)
            }
        }
    }
}
