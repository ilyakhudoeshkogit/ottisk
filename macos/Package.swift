// swift-tools-version:5.9
// Оттиск — удобная печать с Mac поверх CUPS.
import PackageDescription

var targets: [Target] = [
    // Чистая логика без AppKit/SwiftUI: парсеры вывода CUPS, сборка аргументов lp,
    // пресеты, диапазоны страниц, план ручной двусторонней печати.
    // Собирается и тестируется и на macOS, и на Linux.
    .target(name: "OttiskCore"),
    .testTarget(name: "OttiskCoreTests", dependencies: ["OttiskCore"]),
]
var products: [Product] = [
    .library(name: "OttiskCore", targets: ["OttiskCore"]),
]

#if os(macOS)
// Само приложение (SwiftUI + PDFKit + AppKit) — только на macOS.
targets.append(.executableTarget(name: "Ottisk", dependencies: ["OttiskCore"]))
products.append(.executable(name: "Ottisk", targets: ["Ottisk"]))
#endif

let package = Package(
    name: "Ottisk",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets,
    // Режим языка Swift 5: Swift 6 compiler (Xcode 16 / CLT 16) собирает его без
    // строгой проверки конкурентности — первая сборка «мягкая». Код уже размечен
    // @MainActor там, где это важно, так что переход на .v6 позже — отдельный шаг.
    swiftLanguageVersions: [.v5]
)
