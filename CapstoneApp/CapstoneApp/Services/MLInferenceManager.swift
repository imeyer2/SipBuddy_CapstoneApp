//
//  MLInferenceManager.swift
//  SipBuddy
//
//  On-device ML inference for incident classification
//  Runs models on frame sequences after BLE transfer completes
//

import Foundation
import UIKit
import CoreML
import Vision
import Metal

/// Manages on-device ML inference for incident analysis
final class MLInferenceManager {
    
    static let shared = MLInferenceManager()
    
    private init() {
        Log.d("[ML] Inference manager initialized")
        logSystemCapabilities()
    }
    
    // MARK: - Public Interface
    
    /// Run inference on a sequence of frames (incident clip)
    /// - Parameters:
    ///   - frames: Array of PNG data from incident
    ///   - incidentID: UUID for logging/tracking
    func runInference(on frames: [Data], incidentID: UUID) {
        Log.d("[ML] Starting inference on \(frames.count) frames for incident \(incidentID)")
        
        // Convert frames to tensor-like format
        guard let frameTensor = prepareFrameTensor(from: frames) else {
            Log.e("[ML] Failed to prepare frame tensor")
            return
        }
        
        Log.d("[ML] Frame tensor prepared: \(frameTensor.count) frames, \(frameTensor.first?.count ?? 0) pixels each")
        
        // TODO: Run actual model when ready
        // For now, simulate inference
        let prediction = simulateInference(frameTensor: frameTensor)
        
        // Log results (not user-facing)
        logPrediction(prediction, for: incidentID)
    }
    
    // MARK: - Frame Processing
    
    /// Convert raw frame data into tensor format (list of arrays)
    /// Returns: Array of normalized pixel arrays [frame][pixel_values]
    private func prepareFrameTensor(from frames: [Data]) -> [[Float]]? {
        var tensor: [[Float]] = []
        
        for (index, frameData) in frames.enumerated() {
            guard let image = UIImage(data: frameData) else {
                Log.e("[ML] Failed to decode frame \(index)")
                continue
            }
            
            // Resize to model input size (adjust as needed for your model)
            let targetSize = CGSize(width: 224, height: 224) // Common for many models
            guard let resized = resizeImage(image, to: targetSize) else {
                Log.e("[ML] Failed to resize frame \(index)")
                continue
            }
            
            // Extract normalized pixel values
            if let pixelArray = extractPixelArray(from: resized) {
                tensor.append(pixelArray)
                Log.d("[ML] Frame \(index) processed: \(pixelArray.count) values")
            }
        }
        
        return tensor.isEmpty ? nil : tensor
    }
    
    /// Resize image to target dimensions
    private func resizeImage(_ image: UIImage, to size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        defer { UIGraphicsEndImageContext() }
        image.draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
    
    /// Extract normalized pixel array from image
    /// Returns: Flattened array of normalized RGB values [0, 1]
    private func extractPixelArray(from image: UIImage) -> [Float]? {
        guard let cgImage = image.cgImage else { return nil }
        
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        
        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )
        
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Convert to normalized float array (RGB only, skip alpha)
        var normalized: [Float] = []
        normalized.reserveCapacity(width * height * 3)
        
        for i in stride(from: 0, to: pixelData.count, by: bytesPerPixel) {
            let r = Float(pixelData[i]) / 255.0
            let g = Float(pixelData[i + 1]) / 255.0
            let b = Float(pixelData[i + 2]) / 255.0
            normalized.append(contentsOf: [r, g, b])
        }
        
        return normalized
    }
    
    // MARK: - Model Inference (Placeholder)
    
    /// Simulate ML inference (replace with actual model)
    /// In the future, this will call CoreML or TensorFlow Lite model
    private func simulateInference(frameTensor: [[Float]]) -> MLPrediction {
        // Simulate processing time
        Thread.sleep(forTimeInterval: 0.1)
        
        // Mock prediction
        let confidence = Float.random(in: 0.5...0.99)
        let isIncident = confidence > 0.75
        
        return MLPrediction(
            isIncident: isIncident,
            confidence: confidence,
            label: isIncident ? "incident_detected" : "false_alarm",
            processingTime: 0.1,
            frameCount: frameTensor.count
        )
    }
    
    // MARK: - Results Logging
    
    private func logPrediction(_ prediction: MLPrediction, for incidentID: UUID) {
        Log.d("""
        [ML] ========================================
        [ML] Incident: \(incidentID)
        [ML] Prediction: \(prediction.label)
        [ML] Is Incident: \(prediction.isIncident)
        [ML] Confidence: \(String(format: "%.2f%%", prediction.confidence * 100))
        [ML] Frames Analyzed: \(prediction.frameCount)
        [ML] Processing Time: \(String(format: "%.3fs", prediction.processingTime))
        [ML] ========================================
        """)
    }
    
    // MARK: - Future: Real Model Integration
    
    /// Load CoreML model (implement when model is ready)
    private func loadModel() -> MLModel? {
        // TODO: Load your .mlmodel file
        // guard let modelURL = Bundle.main.url(forResource: "IncidentClassifier", withExtension: "mlmodelc") else {
        //     Log.e("[ML] Model file not found")
        //     return nil
        // }
        // return try? MLModel(contentsOf: modelURL)
        return nil
    }
    
    /// Run CoreML inference (implement when model is ready)
    private func runCoreMLInference(model: MLModel, input: MLFeatureProvider) -> MLPrediction? {
        // TODO: Implement CoreML prediction
        // let prediction = try? model.prediction(from: input)
        // return parsePrediction(prediction)
        return nil
    }
}

// MARK: - Prediction Result

struct MLPrediction {
    let isIncident: Bool
    let confidence: Float
    let label: String
    let processingTime: TimeInterval
    let frameCount: Int
}

// MARK: - Integration Helper

extension MLInferenceManager {
    /// Convenience method for running inference from Incident object
    func analyzeIncident(_ incident: Incident) {
        runInference(on: incident.framesPNG, incidentID: incident.id)
    }
    
    // MARK: - System Capabilities
    
    /// Log available ML hardware and memory at startup
    private func logSystemCapabilities() {
        Log.d("[ML] ========================================")
        Log.d("[ML] System ML Capabilities")
        Log.d("[ML] ========================================")
        
        // Device info
        let device = UIDevice.current
        Log.d("[ML] Device: \(device.model)")
        Log.d("[ML] System: \(device.systemName) \(device.systemVersion)")
        
        // Physical memory
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let memoryGB = Double(physicalMemory) / 1_073_741_824 // Convert to GB
        Log.d("[ML] Physical RAM: \(String(format: "%.2f GB", memoryGB))")
        
        // Available memory
        if let availableMemory = getAvailableMemory() {
            let availableGB = Double(availableMemory) / 1_073_741_824
            Log.d("[ML] Available RAM: \(String(format: "%.2f GB", availableGB))")
        }
        
        // Neural Engine availability (A11+ chip)
        let hasNeuralEngine = checkNeuralEngineAvailability()
        Log.d("[ML] Neural Engine: \(hasNeuralEngine ? "Available" : "Not Available")")
        
        // CoreML compute units
        let computeUnits = getAvailableComputeUnits()
        Log.d("[ML] Compute Units: \(computeUnits.joined(separator: ", "))")
        
        // CPU info
        let cpuCount = ProcessInfo.processInfo.processorCount
        Log.d("[ML] CPU Cores: \(cpuCount)")
        
        // GPU info (Metal)
        if let gpuName = getGPUName() {
            Log.d("[ML] GPU: \(gpuName)")
        }
        
        // Thermal state
        let thermalState = ProcessInfo.processInfo.thermalState
        Log.d("[ML] Thermal State: \(getThermalStateName(thermalState))")
        
        // Low power mode
        let lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        Log.d("[ML] Low Power Mode: \(lowPowerMode ? "ON" : "OFF")")
        
        Log.d("[ML] ========================================")
    }
    
    /// Get available memory in bytes
    private func getAvailableMemory() -> UInt64? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else { return nil }
        
        // Get total available memory
        var stats = vm_statistics64()
        var statsCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        
        let hostResult = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(statsCount)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &statsCount)
            }
        }
        
        guard hostResult == KERN_SUCCESS else { return nil }
        
        let pageSize = UInt64(vm_kernel_page_size)
        let freeMemory = UInt64(stats.free_count) * pageSize
        let inactiveMemory = UInt64(stats.inactive_count) * pageSize
        
        return freeMemory + inactiveMemory
    }
    
    /// Check if Neural Engine is available
    private func checkNeuralEngineAvailability() -> Bool {
        // Neural Engine available on A11 Bionic and later (iPhone 8/X+, iPad Pro 2018+)
        // Indirect check: see if we can create an MLModel with .all compute units
        if #available(iOS 13.0, *) {
            // If device supports ANE, CoreML will use it
            let config = MLModelConfiguration()
            config.computeUnits = .all
            return true // Assume available on iOS 13+
        }
        return false
    }
    
    /// Get available CoreML compute units
    private func getAvailableComputeUnits() -> [String] {
        var units: [String] = []
        
        if #available(iOS 13.0, *) {
            units.append("CPU")
            units.append("GPU")
            units.append("Neural Engine (ANE)")
        } else {
            units.append("CPU")
            units.append("GPU")
        }
        
        return units
    }
    
    /// Get GPU name via Metal
    private func getGPUName() -> String? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return device.name
    }
    
    /// Get human-readable thermal state
    private func getThermalStateName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:
            return "Nominal (Normal)"
        case .fair:
            return "Fair (Slightly Elevated)"
        case .serious:
            return "Serious (High Temperature)"
        case .critical:
            return "Critical (Throttling)"
        @unknown default:
            return "Unknown"
        }
    }
}
