// ReadbackDebug.swift
// Explicit logging and debug UI for NASR load and ReadbackEngine.process. Grep for [READBACK_DEBUG].

import Combine
import CoreLocation
import Foundation
import SwiftUI

private let debugLoggingEnabledKey = "ReadbackDebug.loggingEnabled"

/// Set to false to disable [READBACK_DEBUG] logs (e.g. via UserDefaults or default true in DEBUG).
var debugLoggingEnabled: Bool {
    get {
        (UserDefaults.standard.object(forKey: debugLoggingEnabledKey) as? Bool) ?? true
    }
    set {
        UserDefaults.standard.set(newValue, forKey: debugLoggingEnabledKey)
    }
}

enum ReadbackDebugLog {
    static func log(_ message: String) {
        guard debugLoggingEnabled else { return }
        // NSLog ensures output appears in Xcode console and system log (Console.app)
        NSLog("[READBACK_DEBUG] %@", message)
    }
}

/// Shared state for the tiny on-screen debug indicator (NASR loaded, last confidence). Main thread only for UI.
final class ReadbackDebugState: ObservableObject {
    static let shared = ReadbackDebugState()

    @Published var nasrLoaded: Bool = false
    @Published var lastConfidence: Double?

    private init() {}
}

#if DEBUG
struct ReadbackDebugOverlay: View {
    @ObservedObject private var debugState = ReadbackDebugState.shared
    @ObservedObject private var locationManager = LocationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(debugState.nasrLoaded ? "NASR: Loaded" : "NASR: Not loaded")
                .font(.caption2)
                .foregroundStyle(debugState.nasrLoaded ? .green : .orange)
            if let loc = locationManager.effectiveLocation {
                let simLabel = locationManager.isUsingSimulatedLocation ? " (SIM)" : " (REAL)"
                Text("GPS: \(String(format: "%.2f", loc.coordinate.latitude)),\(String(format: "%.2f", loc.coordinate.longitude))\(simLabel)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("GPS: Not available")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            if let c = debugState.lastConfidence {
                Text(String(format: "conf: %.2f", c))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(6)
        .background(Color(.systemBackground).opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
#endif
