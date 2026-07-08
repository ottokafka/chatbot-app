import SwiftUI

#if os(macOS)
import AppKit

// MARK: - macOS Selectable Text

final class SelectableFlashcardTextView: NSTextView {
    var onAddFlashcard: ((String) -> Void)?
    var addToFlashcardTitle = "Add to Flashcard"
    var addEntireMessageTitle = "Add Entire Message"

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        let selected = trimmedSelectedString()
        let title = selected.isEmpty ? addEntireMessageTitle : addToFlashcardTitle

        let item = NSMenuItem(
            title: title,
            action: #selector(handleAddFlashcard),
            keyEquivalent: "f"
        )
        item.keyEquivalentModifierMask = [.command, .shift]
        item.target = self
        menu.insertItem(item, at: 0)
        return menu
    }

    @objc private func handleAddFlashcard() {
        let selected = trimmedSelectedString()
        let textToAdd = selected.isEmpty ? string : selected
        guard !textToAdd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onAddFlashcard?(textToAdd)
    }

    private func trimmedSelectedString() -> String {
        guard let range = selectedRanges.first as? NSRange, range.length > 0 else { return "" }
        return (string as NSString).substring(with: range)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class IntrinsicTextContainer: NSView {
    let textView: SelectableFlashcardTextView

    init(textView: SelectableFlashcardTextView) {
        self.textView = textView
        super.init(frame: .zero)
        textView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return NSSize(width: NSView.noIntrinsicMetric, height: 20)
        }
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        return NSSize(width: NSView.noIntrinsicMetric, height: max(used.height, 20))
    }
}

struct SelectableMessageText: NSViewRepresentable {
    let text: String
    let addToFlashcardLabel: String
    let addEntireMessageLabel: String
    let onAddFlashcard: (String) -> Void

    func makeNSView(context: Context) -> IntrinsicTextContainer {
        let textView = SelectableFlashcardTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textColor = .labelColor
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.string = text
        textView.onAddFlashcard = onAddFlashcard
        textView.addToFlashcardTitle = addToFlashcardLabel
        textView.addEntireMessageTitle = addEntireMessageLabel

        return IntrinsicTextContainer(textView: textView)
    }

    func updateNSView(_ container: IntrinsicTextContainer, context: Context) {
        let textView = container.textView
        if textView.string != text {
            textView.string = text
        }
        textView.onAddFlashcard = onAddFlashcard
        textView.addToFlashcardTitle = addToFlashcardLabel
        textView.addEntireMessageTitle = addEntireMessageLabel
        container.invalidateIntrinsicContentSize()
    }
}

#else

// MARK: - iOS Fallback

struct SelectableMessageText: View {
    let text: String
    let addToFlashcardLabel: String
    let addEntireMessageLabel: String
    let onAddFlashcard: (String) -> Void

    var body: some View {
        Text(text)
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
            .contextMenu {
                Button(addEntireMessageLabel) {
                    onAddFlashcard(text)
                }
            }
    }
}

#endif