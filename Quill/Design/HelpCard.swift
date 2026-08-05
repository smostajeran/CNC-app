import SwiftUI

enum HelpTone {
    case info, caution, danger, ok

    var color: Color {
        switch self {
        case .info: return Theme.steel
        case .caution: return Theme.caution
        case .danger: return Theme.danger
        case .ok: return Theme.ok
        }
    }

    var symbol: String {
        switch self {
        case .info: return "info.circle.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .danger: return "xmark.octagon.fill"
        case .ok: return "checkmark.seal.fill"
        }
    }
}

struct HelpCard: View {
    let title: String
    let message: String
    var tone: HelpTone = .info
    var actionTitle: String? = nil
    var onAction: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: tone.symbol)
                .foregroundStyle(tone.color)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                Text(message)
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle, let onAction {
                Button(actionTitle, action: onAction)
                    .buttonStyle(.borderedProminent)
                    .tint(tone.color)
                    .controlSize(.small)
            }
            if let onDismiss {
                Button("OK", action: onDismiss)
                    .buttonStyle(.borderless)
            }
        }
        .padding(14)
        .quillGlass(tint: tone.color.opacity(0.35), shape: .rect(cornerRadius: 16))
    }
}

/// Centered empty-canvas prompt used on Draw / Run when nothing is loaded.
struct EmptyCanvasHint: View {
    let title: String
    let message: String
    var primaryTitle: String
    var primaryAction: () -> Void
    var secondaryTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 36, weight: .light, design: .rounded))
                .foregroundStyle(Theme.steel)
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text(message)
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.inkMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            HStack(spacing: 10) {
                Button(primaryTitle, action: primaryAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.steel)
                if let secondaryTitle, let secondaryAction {
                    Button(secondaryTitle, action: secondaryAction)
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }
}
