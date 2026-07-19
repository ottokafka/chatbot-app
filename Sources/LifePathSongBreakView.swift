import SwiftUI

/// Full-screen Life Path song mini-game break (loading / karaoke / error).
/// Controls: **Play/Pause** + **Continue studying** only.
struct LifePathSongBreakView: View {
    @ObservedObject var service: LifePathSongService
    let lang: AppLanguage
    let wordChips: [LifePathSongBank.DisplayWord]
    /// Leave the break and resume the Life Path session.
    var onContinue: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var showSlowHint = false
    @State private var slowHintTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.platformControlBackground)
            .navigationTitle(L10n.lifePathSongTitle(lang))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .onAppear {
            startSlowHintTimer()
            if case .ready = service.phase {
                service.play()
            }
        }
        .onChange(of: service.phase) { oldPhase, newPhase in
            // Auto-start only after generation — never auto-dismiss.
            if case .ready = newPhase {
                switch oldPhase {
                case .generatingLyrics, .generatingMusic, .idle:
                    service.play()
                default:
                    break
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                service.pause()
            }
        }
        .onDisappear {
            slowHintTask?.cancel()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch service.phase {
        case .idle, .generatingLyrics, .generatingMusic:
            loadingView
        case .ready, .playing:
            playingView
        case .failed(let message):
            errorView(message)
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text(L10n.lifePathSongMaking(lang))
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            if showSlowHint {
                Text(L10n.lifePathSongStillWorking(lang))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            wordChipsView
            Spacer()
            continueButton
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Playing

    private var playingView: some View {
        VStack(spacing: 16) {
            ProgressView(value: service.playbackProgress)
                .padding(.horizontal, 24)
                .padding(.top, 12)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(service.currentGlossLines) { line in
                            let isActive = line.index == service.activeLineIndex
                            VStack(alignment: .leading, spacing: 4) {
                                Text(line.text)
                                    .font(isActive ? .title3.weight(.bold) : .body)
                                    .foregroundStyle(isActive
                                                     ? Color.accentColor
                                                     : Color.primary.opacity(0.8))
                                if !line.translation.isEmpty {
                                    Text(line.translation)
                                        .font(isActive ? .body.weight(.medium) : .subheadline)
                                        .foregroundStyle(isActive
                                                         ? Color.accentColor.opacity(0.85)
                                                         : Color.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                            .id(line.index)
                            .animation(.easeInOut(duration: 0.15), value: service.activeLineIndex)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(
                                line.translation.isEmpty
                                    ? line.text
                                    : "\(line.text). \(line.translation)"
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                }
                .onChange(of: service.activeLineIndex) { _, idx in
                    guard idx >= 0 else { return }
                    withAnimation {
                        proxy.scrollTo(idx, anchor: .center)
                    }
                }
            }

            wordChipsView
                .padding(.horizontal, 16)

            HStack(spacing: 16) {
                playPauseButton
                continueButton
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text(L10n.lifePathSongErrorTitle(lang))
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
            // Generation failed — only way out is continue (no Retry clutter).
            continueButton
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
    }

    // MARK: - Controls (exactly two actions in the play state)

    private var playPauseButton: some View {
        Button {
            togglePlayPause()
        } label: {
            Label(
                service.isKaraokePlaying
                    ? L10n.lifePathSongPause(lang)
                    : L10n.lifePathSongPlay(lang),
                systemImage: service.isKaraokePlaying ? "pause.fill" : "play.fill"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityLabel(
            service.isKaraokePlaying
                ? L10n.lifePathSongPause(lang)
                : L10n.lifePathSongPlay(lang)
        )
    }

    private var continueButton: some View {
        Button {
            onContinue()
        } label: {
            Text(L10n.lifePathSongContinue(lang))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    /// Play when stopped/paused/ended; pause when playing.
    private func togglePlayPause() {
        if service.isKaraokePlaying {
            service.pause()
        } else {
            // Resume mid-song, or restart from the beginning if finished / ready.
            service.play()
        }
    }

    // MARK: - Chips

    private var wordChipsView: some View {
        FlowWordChips(words: wordChips)
    }

    private func startSlowHintTimer() {
        slowHintTask?.cancel()
        showSlowHint = false
        slowHintTask = Task {
            let ns = UInt64(LifePathSongConfig.maxPresentWait * 1_000_000_000)
            try? await Task.sleep(nanoseconds: ns)
            guard !Task.isCancelled else { return }
            showSlowHint = true
        }
    }
}

/// Wrapping chip row: study word on top, translation underneath.
private struct FlowWordChips: View {
    let words: [LifePathSongBank.DisplayWord]

    var body: some View {
        let shown = Array(words.prefix(12))
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 88), spacing: 8)],
            spacing: 8
        ) {
            ForEach(shown) { word in
                VStack(spacing: 2) {
                    Text(word.front)
                        .font(.caption.weight(.semibold))
                        .multilineTextAlignment(.center)
                    if !word.translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(word.translation)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
