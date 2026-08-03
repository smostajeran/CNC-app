import SwiftUI

/// Page & Batch Composer wrapped in the Liquid Glass shell.
struct ComposeGlassView: View {
    @EnvironmentObject private var model: AppModel
    var onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Compose")
                        .font(Theme.stepTitleFont)
                        .foregroundStyle(Theme.ink)
                    Text("Lay out a true-size page on the bed — artwork, text, pens, and batch data.")
                        .font(Theme.bodyFont)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    Button("Open") { model.openProject() }
                    Button("Save") { model.saveProject() }
                    Button("Save As") {
                        model.projectURL = nil
                        model.saveProject()
                    }
                    Button("Undo") { model.undoDocument() }
                        .disabled(!model.canUndo)
                    Button("Redo") { model.redoDocument() }
                        .disabled(!model.canRedo)
                    Button("Export SVG") { model.exportComposedSVG() }
                        .disabled(model.composedPage == nil)
                }
                .font(.caption)
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 12)

            PageComposerView(onPreflightRun: onContinue)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .quillGlass(tint: Theme.steel.opacity(0.08), shape: .rect(cornerRadius: 22))
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
        .onAppear {
            if model.composedPage == nil && !model.page.elements.isEmpty {
                model.recomposePage()
            }
        }
        .alert("Recover autosave?", isPresented: $model.showAutosaveRecoveryAlert) {
            Button("Recover") { model.acceptAutosaveRecovery() }
            Button("Discard", role: .destructive) { model.discardAutosaveRecovery() }
        } message: {
            Text("A newer autosave was found. Recover unsaved work, or discard it?")
        }
    }
}
