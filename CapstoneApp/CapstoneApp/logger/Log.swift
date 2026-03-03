//
//  Log.swift
//  SipBuddy
//
//
// We will create a logging system

import Foundation

enum Log {
    static func d(_ msg: @autoclosure () -> String,
                  file: String = #file,
                  line: Int = #line) {
        #if DEBUG
        print("🟢 [\(Foundation.URL(fileURLWithPath: file).lastPathComponent):\(line)] \(msg())")
        #endif
    }

    static func e(_ msg: @autoclosure () -> String,
                  file: String = #file,
                  line: Int = #line) {
        // always log errors (even in release)
        print("🔴 [\(URL(fileURLWithPath: file).lastPathComponent):\(line)] \(msg())")
        // optionally forward to Crashlytics / Sentry / Datadog
//        CrashReporter.shared.logError(msg()) // TODO: Set this up
    }
}


