import AppKit
import SwiftUI
import PDFKit
import OttiskCore

/// Превью: «Оригинал» — сам файл, «Как напечатается» — собранный PDF, который уйдёт в печать.
struct PreviewView: View {
    @Environment(AppModel.self) private var model
    let document: PrintDocument

    private struct PreviewKey: Equatable {
        var document: UUID
        var settings: PrintSettings
        var watermark: Watermark
    }

    var body: some View {
        @Bindable var model = model
        let included = Set(model.selectedPages)

        VStack(spacing: 0) {
            PreviewModeBar()
            Divider()
            if model.previewMode == .original {
                HStack(spacing: 0) {
                    ThumbnailStrip(document: document, included: included, current: $model.currentPageIndex)
                        .frame(width: 132)
                    Divider()
                    PDFKitView(document: document.pdf, pageIndex: $model.currentPageIndex)
                        .overlay { WatermarkPreview(watermark: model.watermark) }
                        .overlay(alignment: .bottomTrailing) {
                            Text("\(model.currentPageIndex + 1) / \(document.pageCount)")
                                .font(.caption.monospacedDigit())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.regularMaterial, in: Capsule())
                                .padding(12)
                        }
                }
            } else {
                ResultPreview()
            }
        }
        .id(document.id)
        .navigationTitle(document.name)
        .navigationSubtitle(PagesWord.format(document.pageCount))
        .task(id: PreviewKey(document: document.id, settings: model.settings, watermark: model.watermark)) {
            // Небольшая задержка: пока крутишь степпер, PDF не пересобирается на каждый щелчок.
            try? await Task.sleep(for: .milliseconds(model.previewSource == nil ? 0 : 250))
            guard !Task.isCancelled else { return }
            await model.refreshPreview()
        }
    }
}

/// Переключатель «Оригинал / Как напечатается» и сводка.
struct PreviewModeBar: View {
    @Environment(AppModel.self) private var model
    @AppStorage("preview.showArea") private var showArea = true

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 12) {
            Picker("Превью", selection: $model.previewMode) {
                Text("Оригинал").tag(PreviewMode.original)
                Text("Как напечатается").tag(PreviewMode.result)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            if model.previewMode == .result {
                Toggle("Показать поля", isOn: $showArea)
                    .toggleStyle(.checkbox)
                    .help("Пунктир — граница, внутри которой будет содержимое")
                Spacer()
                if model.isRenderingPreview {
                    ProgressView().controlSize(.small)
                }
                if let plan = model.previewPlan {
                    Text(summary(plan))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func summary(_ plan: LayoutPlan) -> String {
        let sides = plan.sides.count
        let twoSided = model.settings.manualDuplex || model.settings.booklet
        let sheets = plan.sheetCount(twoSided: twoSided)
        if twoSided {
            return String(localized: "Сторон: ") + "\(sides) · " + String(localized: "листов: ") + "\(sheets)"
        }
        return String(localized: "Листов: ") + "\(sheets)"
    }
}

/// «Как напечатается»: миниатюры листов слева, текущий лист справа.
struct ResultPreview: View {
    @Environment(AppModel.self) private var model
    @AppStorage("preview.showArea") private var showArea = true

    var body: some View {
        @Bindable var model = model
        if let source = model.previewSource, let plan = model.previewPlan, !plan.sides.isEmpty,
           model.previewDocumentID == model.currentDocument?.id {
            let index = min(model.previewPageIndex, plan.sides.count - 1)
            HStack(spacing: 0) {
                SideThumbnailStrip(source: source, plan: plan, current: $model.previewPageIndex)
                    .frame(width: 132)
                Divider()
                VStack(spacing: 8) {
                    ResultSheetView(source: source, index: index, side: plan.sides[index], showArea: showArea)
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                    HStack(spacing: 10) {
                        Button {
                            model.previewPageIndex = max(index - 1, 0)
                        } label: { Image(systemName: "chevron.left") }
                            .disabled(index == 0)
                        Text(SideCaption.text(index: index, plan: plan, settings: model.settings))
                            .font(.callout.monospacedDigit())
                            .frame(minWidth: 160)
                        Button {
                            model.previewPageIndex = min(index + 1, plan.sides.count - 1)
                        } label: { Image(systemName: "chevron.right") }
                            .disabled(index >= plan.sides.count - 1)
                    }
                    .buttonStyle(.borderless)
                    .padding(.bottom, 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .underPageBackgroundColor))
            }
        } else {
            VStack(spacing: 8) {
                if let error = model.previewError {
                    Text(error).foregroundStyle(.red)
                } else if model.selectedPages.isEmpty {
                    Text("В диапазоне нет страниц").foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

enum SideCaption {
    static func text(index: Int, plan: LayoutPlan, settings: PrintSettings) -> String {
        let twoSided = settings.manualDuplex || settings.booklet
        if twoSided {
            let sheet = index / 2 + 1
            let side = plan.sides[index].isBack ? String(localized: "оборот") : String(localized: "лицо")
            return String(localized: "Лист ") + "\(sheet) · \(side)"
        }
        return String(localized: "Лист ") + "\(index + 1) / \(plan.sides.count)"
    }
}

/// Один лист результата: картинка страницы из собранного PDF + пунктир полей.
struct ResultSheetView: View {
    @Environment(AppModel.self) private var model
    let source: PDFSource
    let index: Int
    let side: SideLayout
    let showArea: Bool
    @LocalState private var image: NSImage?

    private struct RenderKey: Equatable {
        var source: String
        var index: Int
        var width: Int
        var height: Int
    }

    var body: some View {
        let ratio = side.size.width / max(side.size.height, 1)
        GeometryReader { geo in
            let fit = fittedSize(container: geo.size, ratio: ratio)
            ZStack {
                Rectangle().fill(Color.white)
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .grayscale(model.isMonoPrinter ? 1 : 0)
                }
                // Экономия тонера и черновик на бумаге светлее — показываем примерно.
                Color.white.opacity(model.settings.tonerSave ? 0.35 : (model.settings.quality == .draft ? 0.2 : 0))
                if showArea {
                    MarginOverlay(side: side)
                }
            }
            .frame(width: fit.width, height: fit.height)
            .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: RenderKey(source: source.key, index: index, width: Int(fit.width), height: Int(fit.height))) {
                // Рисуем в фоне; пока рисуется — остаётся прошлая картинка, без мигания.
                let scale = NSScreen.main?.backingScaleFactor ?? 2
                let pixels = CGSize(width: (fit.width * scale).rounded(), height: (fit.height * scale).rounded())
                if let fresh = await Thumbnails.image(source, index: index, pixels: pixels, box: .mediaBox) {
                    image = fresh
                }
            }
        }
    }

    private func fittedSize(container: CGSize, ratio: Double) -> CGSize {
        guard container.width > 0, container.height > 0 else { return .zero }
        if container.width / container.height > ratio {
            return CGSize(width: container.height * ratio, height: container.height)
        }
        return CGSize(width: container.width, height: container.width / ratio)
    }
}

/// Пунктир по границе содержимого и подписи полей в миллиметрах.
struct MarginOverlay: View {
    let side: SideLayout

    var body: some View {
        Canvas { ctx, size in
            let k = size.width / side.size.width
            let a = side.area
            let rect = CGRect(x: a.x * k, y: size.height - (a.y + a.height) * k, width: a.width * k, height: a.height * k)
            ctx.stroke(Path(rect), with: .color(Theme.ink.opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            func mm(_ pt: Double) -> String { String(format: "%.0f", Units.mm(pt)) }
            let font = Font.system(size: 10, weight: .medium).monospacedDigit()
            let left = a.minX, right = side.size.width - a.maxX
            let top = side.size.height - a.maxY, bottom = a.minY
            if left > 1 {
                ctx.draw(Text(mm(left)).font(font).foregroundColor(Theme.ink), at: CGPoint(x: rect.minX / 2, y: rect.midY))
            }
            if right > 1 {
                ctx.draw(Text(mm(right)).font(font).foregroundColor(Theme.ink), at: CGPoint(x: (rect.maxX + size.width) / 2, y: rect.midY))
            }
            if top > 1 {
                ctx.draw(Text(mm(top)).font(font).foregroundColor(Theme.ink), at: CGPoint(x: rect.midX, y: rect.minY / 2))
            }
            if bottom > 1 {
                ctx.draw(Text(mm(bottom)).font(font).foregroundColor(Theme.ink), at: CGPoint(x: rect.midX, y: (rect.maxY + size.height) / 2))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Миниатюры листов результата.
struct SideThumbnailStrip: View {
    @Environment(AppModel.self) private var model
    let source: PDFSource
    let plan: LayoutPlan
    @Binding var current: Int

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(0..<plan.sides.count, id: \.self) { index in
                        SideThumbnail(source: source, index: index, side: plan.sides[index], isCurrent: index == current,
                                      caption: caption(index))
                            .id(index)
                            .onTapGesture { current = index }
                    }
                }
                .padding(.vertical, 12)
            }
            .onChange(of: current) {
                withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(current, anchor: .center) }
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func caption(_ index: Int) -> String {
        guard model.settings.manualDuplex || model.settings.booklet else { return "\(index + 1)" }
        return "\(index / 2 + 1)" + (plan.sides[index].isBack ? " " + String(localized: "об.") : "")
    }
}

struct SideThumbnail: View {
    @Environment(AppModel.self) private var model
    let source: PDFSource
    let index: Int
    let side: SideLayout
    let isCurrent: Bool
    let caption: String
    @LocalState private var image: NSImage?

    private struct RenderKey: Equatable {
        var source: String
        var index: Int
    }

    var body: some View {
        let landscape = side.size.isLandscape
        let size = landscape ? CGSize(width: 112, height: 80) : CGSize(width: 84, height: 112)
        VStack(spacing: 4) {
            ZStack {
                Rectangle().fill(Color.white)
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .grayscale(model.isMonoPrinter ? 1 : 0)
                }
            }
            .frame(width: size.width, height: size.height)
            .overlay(Rectangle().strokeBorder(isCurrent ? Theme.ink : Theme.line, lineWidth: isCurrent ? 2 : 1))
            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
            Text(caption)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .task(id: RenderKey(source: source.key, index: index)) {
            let pixels = CGSize(width: size.width * 2, height: size.height * 2)
            if let fresh = await Thumbnails.image(source, index: index, pixels: pixels, box: .mediaBox) {
                image = fresh
            }
        }
    }
}

struct ThumbnailStrip: View {
    let document: PrintDocument
    let included: Set<Int>
    @Binding var current: Int

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(0..<document.pageCount, id: \.self) { index in
                        ThumbnailCell(source: document.thumbSource, index: index, number: index + 1,
                                      isIncluded: included.contains(index + 1), isCurrent: index == current)
                            .id(index)
                            .onTapGesture { current = index }
                    }
                }
                .padding(.vertical, 12)
            }
            .onChange(of: current) {
                withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(current, anchor: .center) }
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

struct ThumbnailCell: View {
    let source: PDFSource
    let index: Int
    let number: Int
    let isIncluded: Bool
    let isCurrent: Bool
    @LocalState private var image: NSImage?

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Rectangle().fill(Color.white)
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                }
            }
            .frame(width: 84, height: 112)
            .overlay(
                Rectangle().strokeBorder(isCurrent ? Theme.ink : Theme.line, lineWidth: isCurrent ? 2 : 1)
            )
            .opacity(isIncluded ? 1 : 0.35)
            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)

            Text("\(number)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(isIncluded ? Color.primary : Color.secondary)
        }
        .help(isIncluded ? "Страница \(number)" : "Страница \(number) — не входит в диапазон")
        .task(id: "\(source.key)#\(index)") {
            // Миниатюры только для видимых ячеек (LazyVStack), рисуются в фоне и кешируются.
            image = await Thumbnails.image(source, index: index, pixels: CGSize(width: 168, height: 224), box: .cropBox)
        }
    }
}

/// PDFView из PDFKit внутри SwiftUI.
struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument
    @Binding var pageIndex: Int

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.pageShadowsEnabled = true
        view.backgroundColor = .windowBackgroundColor
        view.document = document
        context.coordinator.observe(view)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        context.coordinator.parent = self
        if view.document !== document {
            view.document = document
        }
        if let page = document.page(at: pageIndex), view.currentPage !== page {
            context.coordinator.isProgrammatic = true
            view.go(to: page)
            context.coordinator.isProgrammatic = false
        }
    }

    final class Coordinator: NSObject {
        var parent: PDFKitView
        var isProgrammatic = false
        private var token: NSObjectProtocol?

        init(_ parent: PDFKitView) { self.parent = parent }

        func observe(_ view: PDFView) {
            token = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak self] note in
                guard let self, !self.isProgrammatic,
                      let view = note.object as? PDFView,
                      let page = view.currentPage,
                      let doc = view.document else { return }
                let index = doc.index(for: page)
                MainActor.assumeIsolated {
                    if self.parent.pageIndex != index { self.parent.pageIndex = index }
                }
            }
        }

        deinit {
            if let token { NotificationCenter.default.removeObserver(token) }
        }
    }
}

/// Примерный вид водяного знака поверх превью (в PDF он рисуется на каждой странице).
struct WatermarkPreview: View {
    let watermark: Watermark

    var body: some View {
        if watermark.isActive {
            Text(watermark.trimmedText)
                .font(.system(size: 64, weight: .heavy))
                .foregroundStyle(Color.black.opacity(watermark.clampedOpacity))
                .lineLimit(1)
                .minimumScaleFactor(0.3)
                .rotationEffect(.degrees(-watermark.angle))
                .padding(60)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
