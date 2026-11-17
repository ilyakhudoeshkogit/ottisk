import AppKit
import ImageCaptureCore
import PDFKit
import Observation
import OttiskCore

/// Сканирование через ImageCaptureCore — тот же механизм, что у «Захвата изображений».
///
/// ⚠️ Не проверено на MF3010: macOS увидит сканер, только если для него установлен
/// драйвер сканера Canon (ICA). Без драйвера список будет пустым — это честно показываем.
///
/// Делегаты ImageCaptureCore вызываются на главном потоке, поэтому класс не помечен
/// `@MainActor` (иначе в Swift 6 придётся воевать с изоляцией протоколов ObjC).
@Observable
final class ScanModel: NSObject {
    static let shared = ScanModel()

    var scanners: [ICScannerDevice] = []
    var selectedScannerName: String?
    var status = String(localized: "Ищу сканеры…")
    var isSessionOpen = false
    var isScanning = false
    var supportedDPI: [Int] = []
    var options = ScanOptions()
    var lastScans: [URL] = []
    var errorMessage: String?
    /// Собирать несколько сканов в один PDF (листы договора, паспорт с двух сторон…).
    var combineIntoOnePDF = false
    /// Сколько страниц уже в собираемом PDF.
    var combinedPageCount = 0
    @ObservationIgnored private var combined = PDFDocument()

    private var isCombining: Bool { combineIntoOnePDF && options.format == .pdf }

    @ObservationIgnored private let browser = ICDeviceBrowser()
    @ObservationIgnored private var started = false
    @ObservationIgnored private var pendingScan = false

    static var outputDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents")
        let dir = docs.appendingPathComponent("Ottisk Scans", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var selectedScanner: ICScannerDevice? {
        scanners.first { $0.name == selectedScannerName }
    }

    var offeredDPI: [Int] { ScanOptions.offeredDPI(supported: supportedDPI) }

    func start() {
        guard !started else { return }
        started = true
        browser.delegate = self
        let raw = ICDeviceTypeMask.scanner.rawValue
            | ICDeviceLocationTypeMask.local.rawValue
            | ICDeviceLocationTypeMask.shared.rawValue
            | ICDeviceLocationTypeMask.bonjour.rawValue
        let mask: ICDeviceTypeMask? = ICDeviceTypeMask(rawValue: raw)
        if let mask { browser.browsedDeviceTypeMask = mask }
        browser.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self, self.scanners.isEmpty else { return }
            self.status = String(localized: "Сканер не найден. Нужен драйвер сканера Canon для macOS (см. README).")
        }
    }

    func select(_ name: String?) {
        if let current = selectedScanner, current.hasOpenSession {
            current.requestCloseSession()
        }
        selectedScannerName = name
        isSessionOpen = false
        supportedDPI = []
        guard let scanner = selectedScanner else { return }
        scanner.delegate = self
        status = String(localized: "Подключаюсь к сканеру…")
        scanner.requestOpenSession()
    }

    func scan() {
        guard let scanner = selectedScanner, !isScanning else { return }
        errorMessage = nil
        guard isSessionOpen else {
            pendingScan = true
            select(scanner.name)
            return
        }
        let maybeUnit: ICScannerFunctionalUnit? = scanner.selectedFunctionalUnit
        guard let unit = maybeUnit else {
            errorMessage = String(localized: "Сканер не готов: нет планшета.")
            return
        }
        unit.measurementUnit = .inches
        unit.resolution = ScanOptions.nearestSupported(options.dpi, supported: supportedDPI)
        let size = unit.physicalSize
        unit.scanArea = NSRect(x: 0, y: 0, width: size.width, height: size.height)
        switch options.colorMode {
        case .color:
            unit.pixelDataType = .RGB
            unit.bitDepth = .depth8Bits
        case .gray:
            unit.pixelDataType = .gray
            unit.bitDepth = .depth8Bits
        case .blackWhite:
            unit.pixelDataType = .BW
            unit.bitDepth = .depth1Bit
        }

        // При сборке в один PDF отдельные сканы идут во временную папку.
        let dir = isCombining ? TempFiles.directory : Self.outputDirectory
        let existing = Set((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
        let fileName = ScanOptions.uniqueName(base: ScanOptions.baseName(for: Date()),
                                              ext: options.format.fileExtension, existing: existing)
        scanner.transferMode = .fileBased
        scanner.downloadsDirectory = dir
        scanner.documentName = (fileName as NSString).deletingPathExtension
        scanner.documentUTI = options.format.uti
        isScanning = true
        status = String(localized: "Сканирую…")
        scanner.requestScan()
    }

    func cancel() {
        selectedScanner?.cancelScan()
    }

    /// Сохранить собранный PDF в ~/Documents/Ottisk Scans и начать новый.
    func saveCombined() {
        guard combined.pageCount > 0 else { return }
        let dir = Self.outputDirectory
        let existing = Set((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
        let name = ScanOptions.uniqueName(base: ScanOptions.baseName(for: Date()), ext: "pdf", existing: existing)
        let url = dir.appendingPathComponent(name)
        if combined.write(to: url) {
            lastScans.insert(url, at: 0)
            discardCombined()
        } else {
            errorMessage = String(localized: "Не получилось сохранить PDF.")
        }
    }

    func discardCombined() {
        combined = PDFDocument()
        combinedPageCount = 0
    }

    func revealOutputFolder() {
        NSWorkspace.shared.open(Self.outputDirectory)
    }
}

extension ScanModel: ICDeviceBrowserDelegate {
    func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        guard let scanner = device as? ICScannerDevice else { return }
        if !scanners.contains(where: { $0 === scanner }) { scanners.append(scanner) }
        status = String(localized: "Сканер найден")
        if selectedScannerName == nil {
            // MF3010 — в приоритете, иначе первый попавшийся.
            let preferred = scanners.first { ($0.name ?? "").lowercased().contains("mf3010") } ?? scanners.first
            select(preferred?.name)
        }
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        scanners.removeAll { $0 === device }
        if selectedScanner == nil {
            selectedScannerName = nil
            isSessionOpen = false
            status = scanners.isEmpty ? String(localized: "Сканер отключён") : status
        }
    }
}

extension ScanModel: ICScannerDeviceDelegate {
    func didRemove(_ device: ICDevice) {
        scanners.removeAll { $0 === device }
    }

    func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
        if let error {
            status = String(localized: "Не удалось подключиться к сканеру")
            errorMessage = error.localizedDescription
            pendingScan = false
            return
        }
        isSessionOpen = true
        status = String(localized: "Сканер подключён")
    }

    func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {
        isSessionOpen = false
    }

    func scannerDeviceDidBecomeAvailable(_ scanner: ICScannerDevice) {
        // MF3010 — планшетный сканер, автоподатчика нет.
        scanner.requestSelect(.flatbed)
    }

    func scannerDevice(_ scanner: ICScannerDevice, didSelect functionalUnit: ICScannerFunctionalUnit, error: Error?) {
        if let error {
            errorMessage = error.localizedDescription
            return
        }
        supportedDPI = Array(functionalUnit.supportedResolutions)
        if !supportedDPI.isEmpty {
            options.dpi = ScanOptions.nearestSupported(options.dpi, supported: supportedDPI)
        }
        status = String(localized: "Готов к сканированию")
        if pendingScan {
            pendingScan = false
            scan()
        }
    }

    func scannerDevice(_ scanner: ICScannerDevice, didScanTo url: URL) {
        if isCombining, let scanned = PDFDocument(url: url) {
            for index in 0..<scanned.pageCount {
                if let page = scanned.page(at: index)?.copy() as? PDFPage {
                    combined.insert(page, at: combined.pageCount)
                }
            }
            combinedPageCount = combined.pageCount
            try? FileManager.default.removeItem(at: url)
        } else {
            lastScans.insert(url, at: 0)
        }
    }

    func scannerDevice(_ scanner: ICScannerDevice, didCompleteScanWithError error: Error?) {
        isScanning = false
        if let error {
            status = String(localized: "Скан не удался")
            errorMessage = error.localizedDescription
        } else {
            status = String(localized: "Готово")
            Task { @MainActor in
                Notifier.shared.post(title: String(localized: "Скан готов"),
                                     body: ScanModel.outputDirectory.lastPathComponent)
            }
        }
    }
}
