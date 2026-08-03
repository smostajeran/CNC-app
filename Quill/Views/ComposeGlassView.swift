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
                Button("Preflight & Run") {
                    model.applyPageToJob()
                    onContinue()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.steel)
                .disabled(model.composedPage == nil)
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 12)

            PageComposerView()
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
    }
}
