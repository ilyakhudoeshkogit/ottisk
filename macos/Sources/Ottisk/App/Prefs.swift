import AppKit
import SwiftUI
import OttiskCore

/// Ключи UserDefaults.
enum Prefs {
    static let showMenuBarExtra = "showMenuBarExtra"
    static let reverseBacks = "duplex.reverseBacks"
    static let rotateBacks = "duplex.rotateBacks"
    static let defaultPreset = "defaultPreset"
    static let lastPrinter = "lastPrinter"
    static let refreshSeconds = "refreshSeconds"
    static let showCommand = "showCommand"
    static let notifyOnFinish = "notifyOnFinish"
    static let bookletRotateBacks = "booklet.rotateBacks"
    /// Значение defaultPreset для своего пресета: "custom:<UUID>".
    static let customPresetPrefix = "custom:"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            showMenuBarExtra: true,
            reverseBacks: true,
            rotateBacks: false,
            defaultPreset: "normal",
            refreshSeconds: 3.0,
            showCommand: false,
            notifyOnFinish: true,
            bookletRotateBacks: true,
        ])
    }
}

extension String {
    /// Перевод строки, пришедшей из OttiskCore (названия пресетов, состояния принтера).
    var loc: String { NSLocalizedString(self, comment: "") }
}

extension PrinterOption {
    var defaultLabel: String { defaultChoice ?? "—" }
}

enum Theme {
    /// «Чертёжные чернила» — спокойный синий как акцент в духе ЕСКД.
    static let ink = Color(red: 0.17, green: 0.36, blue: 0.66)
    static let line = Color(nsColor: .separatorColor)
    static let paper = Color(nsColor: .textBackgroundColor)

    static func color(for condition: PrinterCondition) -> Color {
        switch condition.severity {
        case 0: return .green
        case 1: return .orange
        default: return .red
        }
    }
}

enum SystemLinks {
    @MainActor
    static func openPrinterSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.Print-Scan-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.printfax",
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
}
