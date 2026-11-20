import SwiftUI
import AudioRouterCore

/// Design tokens. Change the look of the whole app from here.
enum Theme {
    static let panelWidth: CGFloat = 360
    static let cornerRadius: CGFloat = 12
    static let brand = LinearGradient(colors: [Color(red: 0.42, green: 0.36, blue: 1.0),
                                               Color(red: 0.93, green: 0.33, blue: 0.62)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
    static let accent = Color(red: 0.55, green: 0.42, blue: 1.0)
    static let live = Color(red: 0.20, green: 0.80, blue: 0.55)
    static let warning = Color.orange
    static let danger = Color.red
    static let cardFill = Color.primary.opacity(0.045)
    static let cardHover = Color.primary.opacity(0.08)
}

extension DeviceKind {
    var label: String {
        switch self {
        case .builtIn: "Built-in"
        case .bluetooth: "Bluetooth"
        case .usb: "USB"
        case .airPlay: "AirPlay"
        case .display: "Display"
        case .virtual: "Virtual"
        case .other: "Output"
        }
    }
}
