import Foundation
import PDFKit
import OttiskCore

/// Документ в списке слева: исходный файл + PDF для превью и печати.
struct PrintDocument: Identifiable {
    let id = UUID()
    let sourceURL: URL
    let kind: DocumentKind
    let pdf: PDFDocument
    /// Файл, который уходит в `lp` (исходный PDF или сконвертированный временный).
    let printableURL: URL

    var name: String { sourceURL.lastPathComponent }
    /// Для фоновых миниатюр (файл, который уходит в печать).
    var thumbSource: PDFSource { .file(printableURL, key: id.uuidString) }
    var pageCount: Int { pdf.pageCount }

    var symbol: String {
        switch kind {
        case .pdf: return "doc.richtext"
        case .image: return "photo"
        case .plainText: return "doc.plaintext"
        case .richText: return "doc.text"
        case .unsupported: return "questionmark.square.dashed"
        }
    }
}

enum SidebarItem: Hashable {
    case document(UUID)
    case queue
    case batch
    case history
    case scan
}

/// Ожидание второй стороны при ручной двусторонней печати.
struct DuplexStage: Identifiable {
    let id = UUID()
    let documentName: String
    let printer: String
    var backsURL: URL
    let sheetCount: Int
    let frontJobID: String
    let historyID: UUID
    let settings: PrintSettings
    let driver: ResolvedDriverOptions
    var isPrintingBacks = false
    /// Когда отправлена первая сторона (для восстановления после перезапуска).
    var createdAt = Date()
    /// Этап восстановлен с диска после перезапуска Оттиска.
    var isRestored = false
    /// Восстановленное задание, а принтера сейчас нет в системе.
    var printerMissing = false
    /// Оборот — собранный Оттиском PDF (печатать 1:1, без масштабирования CUPS).
    var composed = false
    /// Ждём, пока первое задание уйдёт из очереди CUPS, и только потом даём печатать оборот.
    var gate: DuplexGate?
    /// Какой настройкой поворота управляется оборот (обычный или брошюра).
    var rotateKey = Prefs.rotateBacks
    /// Был ли оборот повёрнут на 180° при подготовке (nil — неизвестно, этап восстановлен с диска).
    var backsRotated: Bool?

    var canPrintBacks: Bool { gate?.canPrintBacks ?? true }
}

/// Что показывает центральное превью.
enum PreviewMode: String, CaseIterable, Hashable {
    case original
    case result
}
