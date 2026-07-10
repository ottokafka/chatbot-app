import SwiftUI

// MARK: - IDs & presentation metadata

enum ChatToolID: String, CaseIterable, Identifiable {
    case prompt
    case endpoints
    case translation
    case phonics
    case speechPipeline

    var id: String { rawValue }
}

/// How the cell behaves when tapped (metadata for chrome / documentation).
enum ChatToolPresentation: Equatable {
    case sheet
    case toggle
    case modePicker
}

struct ChatToolDescriptor: Identifiable {
    let id: ChatToolID
    let systemImage: String
    /// Short grid caption.
    let title: (AppLanguage) -> String
    /// VoiceOver name (can be longer).
    let accessibilityLabel: (AppLanguage) -> String
    let presentation: ChatToolPresentation
    /// Toggle on-state / mode secondary caption source.
    var isOn: Bool? = nil
    var valueCaption: String? = nil
}

enum ChatToolsCatalog {
    /// Presentation metadata only (labels, icons, on-state display).
    /// Actions are handled in `ChatToolsMenuButton.handle(_:)`.
    static func items(
        lang: AppLanguage,
        translationOn: Bool,
        phonicsOn: Bool,
        speechMode: SpeechPipelineMode
    ) -> [ChatToolDescriptor] {
        [
            .init(
                id: .prompt,
                systemImage: "text.bubble",
                title: L10n.toolPrompt,
                accessibilityLabel: L10n.selectSystemPromptHelp,
                presentation: .sheet
            ),
            .init(
                id: .endpoints,
                systemImage: "network",
                title: L10n.toolEndpoints,
                accessibilityLabel: L10n.manageEndpointsHelp,
                presentation: .sheet
            ),
            .init(
                id: .translation,
                systemImage: "character.bubble",
                title: L10n.toolTranslation,
                accessibilityLabel: L10n.toggleMessageTranslationHelp,
                presentation: .toggle,
                isOn: translationOn
            ),
            .init(
                id: .phonics,
                systemImage: "textformat.abc",
                title: L10n.toolPhonics,
                accessibilityLabel: L10n.togglePhonicsHelp,
                presentation: .toggle,
                isOn: phonicsOn
            ),
            .init(
                id: .speechPipeline,
                systemImage: "waveform",
                title: L10n.toolSpeechMode,
                accessibilityLabel: L10n.speechPipelineModeHelp,
                presentation: .modePicker,
                valueCaption: L10n.speechPipelineLabel(speechMode, lang: lang)
            ),
        ]
    }
}

// MARK: - Panel state

enum ToolsPanel: Equatable {
    case grid
    case speechPipeline
}

// MARK: - Layout tokens

private enum ChatToolsLayout {
    static let gridColumns = [
        GridItem(.flexible(minimum: 72), spacing: 8),
        GridItem(.flexible(minimum: 72), spacing: 8),
    ]
    static let interItemSpacing: CGFloat = 8
    static let cellMinHeight: CGFloat = 56
    static let iconSize: CGFloat = 22
    static let contentPadding: CGFloat = 12
    static let cornerRadius: CGFloat = 16
    static let minWidth: CGFloat = 200
    static let idealWidth: CGFloat = 220
    static let maxWidth: CGFloat = 260
    static let maxPopoverHeight: CGFloat = 360
}

// MARK: - Menu button (toolbar)

#if os(iOS)
struct ChatToolsMenuButton: View {
    @ObservedObject var viewModel: ChatViewModel
    @Binding var isShowingPromptModal: Bool
    @Binding var isShowingEndpointModal: Bool
    @Environment(\.appLanguage) private var lang
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isToolsMenuPresented = false
    @State private var panel: ToolsPanel = .grid

    var body: some View {
        Button {
            isToolsMenuPresented = true
        } label: {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
                .padding(6)
                .background(Circle().fill(Color.gray.opacity(0.12)))
                .overlay(Circle().stroke(Color.gray.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.chatTools(lang))
        .accessibilityHint(L10n.chatToolsHint(lang))
        .popover(isPresented: $isToolsMenuPresented, arrowEdge: .top) {
            ChatToolsPopoverView(
                panel: $panel,
                viewModel: viewModel,
                onSelectTool: handle,
                reduceMotion: reduceMotion
            )
            .presentationCompactAdaptation(.popover)
            .frame(
                minWidth: ChatToolsLayout.minWidth,
                idealWidth: ChatToolsLayout.idealWidth,
                maxWidth: ChatToolsLayout.maxWidth
            )
        }
        .onChange(of: isToolsMenuPresented) { _, presented in
            if !presented {
                panel = .grid
            }
        }
    }

    // MARK: Actions

    /// Sole action dispatch. Catalog does not embed closures.
    @MainActor
    private func handle(_ id: ChatToolID) {
        switch id {
        case .prompt:
            presentSheetAfterClosingMenu($isShowingPromptModal)
        case .endpoints:
            presentSheetAfterClosingMenu($isShowingEndpointModal)
        case .translation:
            viewModel.isTranslationEnabled.toggle()
            // Stay open — do not set isToolsMenuPresented = false
        case .phonics:
            viewModel.isPhonicsEnabled.toggle()
        case .speechPipeline:
            panel = .speechPipeline
        }
    }

    /// Dismiss the tools popover, then present a ContentView-owned sheet.
    @MainActor
    private func presentSheetAfterClosingMenu(_ present: Binding<Bool>) {
        panel = .grid
        isToolsMenuPresented = false
        Task { @MainActor in
            await Task.yield()
            present.wrappedValue = true
        }
    }
}

// MARK: - Popover content

struct ChatToolsPopoverView: View {
    @Binding var panel: ToolsPanel
    @ObservedObject var viewModel: ChatViewModel
    let onSelectTool: (ChatToolID) -> Void
    var reduceMotion: Bool = false

    @Environment(\.appLanguage) private var lang

    private var items: [ChatToolDescriptor] {
        ChatToolsCatalog.items(
            lang: lang,
            translationOn: viewModel.isTranslationEnabled,
            phonicsOn: viewModel.isPhonicsEnabled,
            speechMode: viewModel.speechPipelineMode
        )
    }

    var body: some View {
        Group {
            switch panel {
            case .grid:
                toolsGrid
            case .speechPipeline:
                modeList
            }
        }
        .animation(reduceMotion ? nil : .default, value: panel)
        .frame(
            minWidth: ChatToolsLayout.minWidth,
            idealWidth: ChatToolsLayout.idealWidth,
            maxWidth: ChatToolsLayout.maxWidth
        )
    }

    private var toolsGrid: some View {
        let content = LazyVGrid(
            columns: ChatToolsLayout.gridColumns,
            spacing: ChatToolsLayout.interItemSpacing
        ) {
            ForEach(items) { item in
                ChatToolGridCell(descriptor: item, lang: lang) {
                    onSelectTool(item.id)
                }
            }
        }
        .padding(ChatToolsLayout.contentPadding)

        return ScrollView {
            content
        }
        .frame(maxHeight: ChatToolsLayout.maxPopoverHeight)
    }

    private var modeList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button {
                    panel = .grid
                } label: {
                    Label(L10n.toolsBack(lang), systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.toolsBack(lang))

                Spacer()

                Text(L10n.toolSpeechMode(lang))
                    .font(.subheadline.weight(.semibold))

                Spacer()
                // Balance the back button width roughly
                Color.clear.frame(width: 56, height: 1)
            }
            .padding(.horizontal, ChatToolsLayout.contentPadding)
            .padding(.top, ChatToolsLayout.contentPadding)
            .padding(.bottom, 8)

            Divider()

            VStack(spacing: 0) {
                ForEach(SpeechPipelineMode.allCases) { mode in
                    Button {
                        viewModel.speechPipelineMode = mode
                        panel = .grid
                    } label: {
                        HStack {
                            Text(L10n.speechPipelineLabel(mode, lang: lang))
                                .foregroundStyle(.primary)
                            Spacer()
                            if viewModel.speechPipelineMode == mode {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .padding(.horizontal, ChatToolsLayout.contentPadding)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.speechPipelineLabel(mode, lang: lang))
                    .accessibilityAddTraits(
                        viewModel.speechPipelineMode == mode ? [.isSelected] : []
                    )
                }
            }
            .padding(.bottom, 8)
        }
        .frame(minWidth: ChatToolsLayout.minWidth, idealWidth: ChatToolsLayout.idealWidth)
    }
}

// MARK: - Grid cell

struct ChatToolGridCell: View {
    let descriptor: ChatToolDescriptor
    let lang: AppLanguage
    let action: () -> Void

    private var isOn: Bool {
        descriptor.isOn == true
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: descriptor.systemImage)
                        .font(.system(size: ChatToolsLayout.iconSize))
                        .foregroundStyle(isOn ? Color.blue : Color.primary)
                        .frame(width: 36, height: 36)

                    if isOn {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.blue)
                            .offset(x: 4, y: -2)
                            .accessibilityHidden(true)
                    }
                }

                Text(descriptor.title(lang))
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)

                if let caption = descriptor.valueCaption, descriptor.presentation == .modePicker {
                    Text(caption)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: ChatToolsLayout.cellMinHeight)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isOn ? Color.blue.opacity(0.12) : Color.gray.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isOn ? Color.blue.opacity(0.55) : Color.gray.opacity(0.2), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel(descriptor.accessibilityLabel(lang))
        .accessibilityValue(toggleAccessibilityValue)
        .accessibilityHint(modePickerHint)
    }

    private var toggleAccessibilityValue: Text {
        guard descriptor.presentation == .toggle else {
            return Text("")
        }
        return Text(isOn ? L10n.a11yOn(lang) : L10n.a11yOff(lang))
    }

    private var modePickerHint: Text {
        if descriptor.presentation == .modePicker, let caption = descriptor.valueCaption {
            return Text(caption)
        }
        return Text("")
    }
}

#Preview("Tools grid") {
    ChatToolsPopoverView(
        panel: .constant(.grid),
        viewModel: ChatViewModel(),
        onSelectTool: { _ in }
    )
    .environment(\.appLanguage, .en)
}

#Preview("Speech panel") {
    ChatToolsPopoverView(
        panel: .constant(.speechPipeline),
        viewModel: ChatViewModel(),
        onSelectTool: { _ in }
    )
    .environment(\.appLanguage, .en)
}
#endif
