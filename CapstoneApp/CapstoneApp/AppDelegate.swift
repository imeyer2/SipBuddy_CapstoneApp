//
//  AppDelegate.swift
//  SipBuddy
//
//  AppDelegate for PostHog SDK initialization
//  PostHog must be configured before any events are sent
//

import Foundation
import UIKit
import PostHog

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Initialize PostHog SDK
        PostHogService.shared.configure()
        
        return true
    }
    
    // Handle background URL sessions if needed
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}
