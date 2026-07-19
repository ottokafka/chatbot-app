import SwiftUI

/// Full-screen Life Path song mini-game break (loading / karaoke / error).
struct LifePathSongBreakView: View {
    @ObservedObject var service: LifePathSongService
    let lang: AppLanguage
    let wordChips: [LifePathSongBank.DisplayWord]
    var onSkip: () -> Void
    var onFinished: () -> Void
    var onEndSession: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var autoContinueTask: Task<Void, Never>?
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.lifePathSongSkip(lang)) {
                        autoContinueTask?.cancel()
                        onSkip()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(L10n.lifePathEndRound(lang)) {
                        autoContinueTask?.cancel()
                        onEndSession()
                    }
                }
            }
        }
        .onAppear {
            startSlowHintTimer()
            // Auto-play when already ready
            if case .ready = service.phase {
                service.play()
            }
        }
        .onChange(of: service.phase) { _, newPhase in
            switch newPhase {
            case .ready:
                service.play()
            case .playing:
                break
            default:
                autoContinueTask?.cancel()
            }
        }
        .onChange(of: service.isKaraokePlaying) { _, playing in
            if !playing, case .ready = service.phase, service.playbackProgress >= 0.98 {
                scheduleAutoContinue()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                service.pause()
            }
        }
        .onDisappear {
            autoContinueTask?.cancel()
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
            Button(L10n.lifePathSongSkip(lang)) {
                onSkip()
            }
            .buttonStyle(.bordered)
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

            // Optional reference strip (front + translation); primary gloss is under lyrics.
            wordChipsView
                .padding(.horizontal, 16)

            HStack(spacing: 16) {
                Button {
                    service.replay()
                } label: {
                    Label(L10n.lifePathSongReplay(lang), systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)

                if service.isKaraokePlaying {
                    Button {
                        service.pause()
                    } label: {
                        Label(L10n.lifePathSongPause(lang), systemImage: "pause.fill")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        service.play()
                    } label: {
                        Label(L10n.lifePathSongPlay(lang), systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button {
                    autoContinueTask?.cancel()
                    onFinished()
                } label: {
                    Text(L10n.lifePathSongContinue(lang))
                }
                .buttonStyle(.borderedProminent)
            }
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
            VStack(spacing: 12) {
                Button {
                    Task {
                        _ = await service.retryGenerate()
                    }
                } label: {
                    Text(L10n.lifePathSongRetry(lang))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    onFinished()
                } label: {
                    Text(L10n.lifePathSongContinue(lang))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Chips

    private var wordChipsView: some View {
        FlowWordChips(words: wordChips)
    }

    private func scheduleAutoContinue() {
        autoContinueTask?.cancel()
        autoContinueTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            onFinished()
        }
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

/// Wrapping chip row: study word on top, translation (e.g. Chinese) underneath.
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
