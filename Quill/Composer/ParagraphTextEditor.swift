import SwiftUI
import AppKit

/// Multiline paragraph editor sized for letters and long copy.
/// Return inserts a newline; Command–Return invokes `onCommandReturn` when provided
/// (single mechanism — do not also attach ⌘↩ to a sibling button).
struct ParagraphTextEditor: View {
    let label: String
    @Binding var text: String
    var placeholder: String = "Type or paste a letter, address or paragraph…"
    var minHeight: CGFloat = 140
    var idealHeight: CGFloat = 180
    var maxHeight: CGFloat = 260
    var onCommandReturn: (() -> Void)? = nil
    /// Called when the expand sheet commits with Done (text already written through the binding).
    var onExpandCommitted: (() -> Void)? = nil
    /// Called when expand Cancel restores the pre-expand snapshot.
    var onExpandCancelled: (() -> Void)? = nil
    /// Called when the inline paragraph editor resigns focus.
    var onTextFocusLost: (() -> Void)? = nil

    @State private var showExpanded = false
    @State private var expandDraft = ""
    @State private var expandSnapshot = ""
    @FocusState private var isEditorFocused: Bool

    private var characterCount: Int { text.count }
    private var lineCount: Int {
        if text.isEmpty { return 0 }
        return text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(characterCount) characters · \(lineCount) lines")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("Expand") {
                    expandSnapshot = text
                    expandDraft = text
                    showExpanded = true
                }
                .font(.caption)
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(minHeight: minHeight, idealHeight: idealHeight, maxHeight: maxHeight)
                    .background(Color(nsColor: .textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.secondary.opacity(0.28), lineWidth: 1)
                    )
                    .focused($isEditorFocused)

                if text.isEmpty {
                    Text(placeholder)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: minHeight, idealHeight: idealHeight, maxHeight: maxHeight)
            .clipped()

            if onCommandReturn != nil {
                Text("Return = new line · ⌘↩ = add to page")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .background(CommandReturnCatcher(
            enabled: onCommandReturn != nil && isEditorFocused && !showExpanded,
            action: { onCommandReturn?() }
        ))
        .onChange(of: isEditorFocused) { focused in
            if !focused {
                onTextFocusLost?()
            }
        }
        .sheet(isPresented: $showExpanded) {
            expandedSheet
        }
    }

    private var expandedSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(label)
                    .font(.title2.weight(.semibold))
                Spacer()
                Text("\(expandDraft.count) characters · \(expandLineCount) lines")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: Binding(
                get: { expandDraft },
                set: { newValue in
                    expandDraft = newValue
                    // Keep the page preview / overflow / auto-height in sync while expanded.
                    text = newValue
                }
            ))
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.secondary.opacity(0.28), lineWidth: 1)
                )
                .frame(minWidth: 520, minHeight: 360)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Text("Style controls stay in the inspector. Editing here updates the same paragraph text.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") {
                    expandDraft = expandSnapshot
                    text = expandSnapshot
                    showExpanded = false
                    onExpandCancelled?()
                }
                .keyboardShortcut(.cancelAction)
                Button("Done") {
                    text = expandDraft
                    showExpanded = false
                    onExpandCommitted?()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 480)
    }

    private var expandLineCount: Int {
        if expandDraft.isEmpty { return 0 }
        return expandDraft.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
    }
}

/// Invisible helper that fires when ⌘↩ is pressed while this editor is focused.
/// Sole Command–Return mechanism for adding a paragraph — do not pair with a Button shortcut.
private struct CommandReturnCatcher: NSViewRepresentable {
    var enabled: Bool
    var action: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = CatcherView()
        view.enabled = enabled
        view.action = action
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? CatcherView else { return }
        view.enabled = enabled
        view.action = action
    }

    final class CatcherView: NSView {
        var enabled = false
        var action: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.enabled else { return event }
                guard event.window === self.window else { return event }
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                // Return / keypad Enter with Command
                if flags.contains(.command), event.keyCode == 36 || event.keyCode == 76 {
                    self.action?()
                    return nil
                }
                return event
            }
        }

        deinit { removeMonitor() }

        private func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}
