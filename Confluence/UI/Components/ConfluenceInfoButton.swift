import SwiftUI
import UIKit

/// Unified, zero-clipping, scrollable, opaque `(i)` info popover button used across the entire app.
///
/// Uses deterministic `NSAttributedString.boundingRect` height measurement so iPhone compact popovers
/// never clip text or bleed underlying List/Form rows through translucent glass.
public struct ConfluenceInfoButton: View {
    public let title: String?
    public let message: String

    @State private var isPresented = false

    private static let popoverWidth: CGFloat = 290
    private static let innerPadding: CGFloat = 16
    private static let maxPopoverHeight: CGFloat = 260
    private static let minPopoverHeight: CGFloat = 84

    public init(title: String? = nil, message: String) {
        self.title = title
        self.message = message
    }

    public init(_ key: SettingHelpKey) {
        let copy = key.copy
        self.title = copy.label
        self.message = copy.helpText
    }

    private var measuredLayout: (height: CGFloat, needsScroll: Bool) {
        let innerWidth = Self.popoverWidth - (Self.innerPadding * 2) // 258pt
        let constraint = CGSize(width: innerWidth, height: .greatestFiniteMagnitude)
        let options: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]

        let messageRect = NSAttributedString(
            string: message,
            attributes: [.font: UIFont.preferredFont(forTextStyle: .subheadline)]
        ).boundingRect(with: constraint, options: options, context: nil)

        var measuredHeight = ceil(messageRect.height)

        if let title, !title.isEmpty {
            let titleRect = NSAttributedString(
                string: title,
                attributes: [.font: UIFont.preferredFont(forTextStyle: .headline)]
            ).boundingRect(with: constraint, options: options, context: nil)
            // Reserve at least 24pt for title + 8pt VStack spacing
            measuredHeight += max(24, ceil(titleRect.height)) + 8
        }

        // Vertical padding (32pt) + safety margin (16pt)
        measuredHeight += (Self.innerPadding * 2) + 16

        let finalHeight = min(max(ceil(measuredHeight), Self.minPopoverHeight), Self.maxPopoverHeight)
        let needsScroll = measuredHeight > Self.maxPopoverHeight
        return (finalHeight, needsScroll)
    }

    public var body: some View {
        let layout = measuredLayout

        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(title.map { "About \($0)" } ?? "More information")
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            ScrollView(.vertical, showsIndicators: layout.needsScroll) {
                VStack(alignment: .leading, spacing: 8) {
                    if let title, !title.isEmpty {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .textCase(nil)
                    }
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .textCase(nil)
                }
                .padding(Self.innerPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: Self.popoverWidth, height: layout.height)
            .presentationBackground(Color(.secondarySystemGroupedBackground))
            .presentationCompactAdaptation(.popover)
        }
    }
}
