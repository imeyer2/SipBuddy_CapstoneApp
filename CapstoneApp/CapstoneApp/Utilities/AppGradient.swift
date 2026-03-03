//
//  AppGradient.swift
//  SipBuddy
//
//  Shared gradient background styling inspired by Oura Ring's subtle gradients
//

import SwiftUI

/// App-wide gradient theme - soft, subtle gradients similar to Oura Ring
struct AppGradient {
    
    // MARK: - Gradient Colors
    
    /// Soft purple/violet accent for top of gradients
    static let accentTop = Color(red: 0.25, green: 0.15, blue: 0.35) // Muted purple
    
    /// Deep dark for bottom of gradients
    static let accentBottom = Color(red: 0.05, green: 0.05, blue: 0.08) // Near black
    
    /// Alternative: warmer tone
    static let warmTop = Color(red: 0.28, green: 0.12, blue: 0.22) // Muted magenta
    
    /// Alternative: cooler tone
    static let coolTop = Color(red: 0.12, green: 0.15, blue: 0.28) // Muted blue
    
    // MARK: - Pre-built Gradients
    
    /// Default page background gradient (purple to black)
    static var pageBackground: LinearGradient {
        LinearGradient(
            colors: [accentTop, accentBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    /// Subtle version with less color (for lighter content)
    static var subtleBackground: LinearGradient {
        LinearGradient(
            colors: [accentTop.opacity(0.6), accentBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    /// Card/overlay gradient
    static var cardGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(white: 0.15).opacity(0.8),
                Color(white: 0.08).opacity(0.9)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - View Extension for Easy Application

extension View {
    /// Apply the app's signature gradient background
    func appGradientBackground(style: GradientStyle = .default) -> some View {
        self.background(
            Group {
                switch style {
                case .default:
                    AppGradient.pageBackground
                case .subtle:
                    AppGradient.subtleBackground
                case .solid:
                    Color(red: 0.05, green: 0.05, blue: 0.08)
                }
            }
            .ignoresSafeArea()
        )
    }
}

enum GradientStyle {
    case `default`
    case subtle
    case solid
}

// MARK: - Gradient Background View (for ZStack usage)

struct GradientBackground: View {
    var style: GradientStyle = .default
    
    var body: some View {
        Group {
            switch style {
            case .default:
                AppGradient.pageBackground
            case .subtle:
                AppGradient.subtleBackground
            case .solid:
                Color(red: 0.05, green: 0.05, blue: 0.08)
            }
        }
        .ignoresSafeArea()
    }
}

#Preview("Gradient Styles") {
    VStack(spacing: 20) {
        Text("Default Gradient")
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .appGradientBackground(style: .default)
        
        Text("Subtle Gradient")
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .appGradientBackground(style: .subtle)
    }
}
