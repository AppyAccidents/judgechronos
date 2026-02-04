import AppKit
import Foundation
import SwiftUI

struct ActivityEvent: Identifiable, Hashable {
    let id: UUID
    let eventKey: String
    let appName: String
    let startTime: Date
    let endTime: Date
    let duration: TimeInterval
    var categoryId: UUID?
    let isIdle: Bool
}

struct Category: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var colorHex: String
}

struct Rule: Identifiable, Codable, Hashable {
    let id: UUID
    var pattern: String
    var categoryId: UUID
}

struct LocalData: Codable {
    var categories: [Category]
    var rules: [Rule]
    var assignments: [String: UUID]
}

enum ActivityEventKey {
    static func make(appName: String, startTime: Date, endTime: Date) -> String {
        let start = Int(startTime.timeIntervalSince1970)
        let end = Int(endTime.timeIntervalSince1970)
        return "event|\(start)|\(end)|\(appName)"
    }
}

extension Color {
    init?(hex: String) {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard sanitized.count == 6 else { return nil }
        let scanner = Scanner(string: sanitized)
        var rgb: UInt64 = 0
        guard scanner.scanHexInt64(&rgb) else { return nil }
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }

    func toHex() -> String {
        let nsColor = NSColor(self)
        guard let rgbColor = nsColor.usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int(round(rgbColor.redComponent * 255))
        let g = Int(round(rgbColor.greenComponent * 255))
        let b = Int(round(rgbColor.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
