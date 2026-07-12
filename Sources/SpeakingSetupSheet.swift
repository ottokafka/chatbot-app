import SwiftUI

/// Pre-start config for Speak with AI: seeds, known count, topic, encourage + optional force coverage (D7, D22, PR5).
/// No 文/译 chrome in MVP.
struct SpeakingSetupSheet: View {
    @ObservedObject var speakingVM: SpeakingSessionViewModel
    @ObservedObject var flashcardVM: FlashcardViewModel
    @Environment(\.appLanguage) private var lang
    @Environment(\.dismiss) private var dismiss

    @State private var topicHint: String = ""
    @State private var encourageCoverage: Bool = true
    @State private var forceTargetCoverage: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.speakSetupTitle(lang))
                .font(.title2)
                .fontWeight(.bold)

            if let config = speakingVM.pendingConfig {
                setupBody(config)
            } else {
                Text(L10n.speakNoSeeds(lang))
                    .font(.body)
                    .foregroundColor(.secondary)
                Spacer()
                HStack {
                    Spacer()
                    Button(L10n.cancel(lang)) {
                        speakingVM.isShowingSetup = false
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(24)
        #if os(iOS)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        .frame(minWidth: 440, minHeight: 460)
        #endif
        .onAppear {
            if let config = speakingVM.pendingConfig {
                topicHint = config.topicHint
                encourageCoverage = config.encourageTargetCoverage
                forceTargetCoverage = config.forceTargetCoverage
            }
        }
    }

    @ViewBuilder
    private func setupBody(_ config: SpeakingSessionConfig) -> some View {
        let targets = config.targetCards
        let knownCount = config.knownFronts.count

        VStack(alignment: .leading, spacing: 8) {
            Text(
                L10n.speakSetupSeedsSummary(
                    lang,
                    count: targets.count,
                    sourceLabel: sourceLabel(for: config.seedSource)
                )
            )
            .font(.subheadline)
            .foregroundColor(.secondary)

            Text(L10n.speakSetupKnownCount(lang, count: knownCount))
                .font(.subheadline)
                .foregroundColor(.secondary)

            if knownCount == 0 {
                Label(L10n.speakSetupSparseWarning(lang), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.top, 2)
            }
        }

        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.speakSetupTopicLabel(lang))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            TextField(L10n.speakSetupTopicPlaceholder(lang), text: $topicHint)
                .textFieldStyle(.roundedBorder)
        }

        Toggle(isOn: $encourageCoverage) {
            Text(L10n.speakSetupEncourageCoverage(lang))
        }
        #if os(macOS)
        .toggleStyle(.checkbox)
        #else
        .toggleStyle(.switch)
        #endif

        Toggle(isOn: $forceTargetCoverage) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.speakSetupForceCoverage(lang))
                Text(L10n.speakSetupForceCoverageHelp(lang))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        #if os(macOS)
        .toggleStyle(.checkbox)
        #else
        .toggleStyle(.switch)
        #endif

        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.speakSetupTargetsLabel(lang))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(config.targetFronts, id: \.self) { front in
                        Text(front)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }
        }

        Spacer()

        HStack {
            Button(L10n.cancel(lang)) {
                speakingVM.isShowingSetup = false
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .disabled(speakingVM.isStartingSession)

            Spacer()

            Button {
                reapplyPendingAndStart(from: config)
            } label: {
                if speakingVM.isStartingSession {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(L10n.speakStart(lang))
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!canStart(targets: targets))
        }
    }

    private func canStart(targets: [Flashcard]) -> Bool {
        !targets.isEmpty
            && !speakingVM.isStartingSession
            && speakingVM.session == nil
            && !speakingVM.pendingSessionStart
    }

    private func reapplyPendingAndStart(from config: SpeakingSessionConfig) {
        guard canStart(targets: config.targetCards) else { return }
        speakingVM.prepareSetup(
            seedSource: config.seedSource,
            targets: config.targetCards,
            knownFronts: config.knownFronts,
            topicHint: topicHint.trimmingCharacters(in: .whitespacesAndNewlines),
            encourageTargetCoverage: encourageCoverage,
            forceTargetCoverage: forceTargetCoverage
        )
        Task {
            await speakingVM.startSession()
        }
    }

    private func sourceLabel(for source: PracticeSeedSource) -> String {
        switch source {
        case .dueVocab:
            return L10n.speakSourceDue(lang)
        case .lastStudySession:
            return L10n.speakSourceLastSession(lang)
        case .selectedVocab:
            return L10n.speakSourceSelected(lang)
        }
    }
}
