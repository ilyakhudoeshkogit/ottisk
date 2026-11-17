import AppKit
import SwiftUI
import OttiskCore

/// «Основная надпись» в духе ЕСКД: сводка задания в строгой табличке.
struct TitleBlockView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let doc = model.currentDocument
        let pages = model.selectedPages.count
        let sheets = model.plannedSheetCount

        VStack(spacing: 0) {
            row("Документ", doc?.name ?? "—")
            line
            HStack(spacing: 0) {
                cell("Стр.", doc == nil ? "—" : "\(pages)")
                vline
                cell("Копий", "\(model.settings.copies)")
                vline
                cell("Листов", doc == nil ? "—" : "\(sheets)")
            }
            line
            row("Принтер", model.selectedPrinter?.displayName ?? "—")
            line
            HStack(spacing: 0) {
                cell("Пресет", model.activePresetTitle)
                vline
                Text("ОТТИСК")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(Theme.ink)
                    .frame(width: 84)
                    .frame(maxHeight: .infinity)
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .overlay(Rectangle().strokeBorder(Color.primary.opacity(0.6), lineWidth: 1))
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private var line: some View {
        Rectangle().fill(Color.primary.opacity(0.35)).frame(height: 0.75)
    }

    private var vline: some View {
        Rectangle().fill(Color.primary.opacity(0.35)).frame(width: 0.75)
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
                .padding(.horizontal, 6)
            vline
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
        }
        .frame(height: 22)
    }

    private func cell(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 2)
            Text(value).lineLimit(1)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .frame(height: 22)
    }
}
