import SwiftUI

/// Song Generation feature: generate LRC lyrics via LLM → generate music via DiffRhythm API.
struct SongGenView: View {
    @ObservedObject var nav: AppNavigationModel
    @ObservedObject var chatVM: ChatViewModel
    @StateObject private var vm = SongGenViewModel()

    @Environment(\.appLanguage) private var lang
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @State private var showHistory = true

    var onPreferSidebar: () -> Void = {}

    private var isCompact: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    var body: some View {
        // Inject LLM config on appear
        let _ = syncEndpoints()

        if isCompact {
            compactLayout
        } else {
            wideLayout
        }
    }

    // MARK: - Endpoint sync

    private func syncEndpoints() {
        if vm.llmURL.isEmpty {
            vm.llmURL = chatVM.llmURL
            vm.llmModel = chatVM.llmModel
            vm.onLog = { chatVM.log($0) }
        }
    }

    // MARK: - Wide layout (macOS / iPad)

    private var wideLayout: some View {
        VStack(spacing: 0) {
            headerView

            HStack(alignment: .top, spacing: 0) {
                // History sidebar
                if showHistory {
                    historyPanel
                        .frame(width: 240)
                    Divider()
                }

                // Left: Lyrics panel
                lyricsPanel
                    .frame(minWidth: 300, idealWidth: 400)

                Divider()

                // Right: Settings + Music generation + Player
                musicPanel
                    .frame(minWidth: 280, idealWidth: 360)
            }

            if let error = vm.errorMessage {
                errorBanner(error)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.platformControlBackground)
        #if os(iOS)
        .compactFeatureChrome(
            nav: nav,
            lang: lang,
            dueCount: 0,
            onPreferSidebar: onPreferSidebar
        )
        #endif
    }

    // MARK: - Compact layout (iPhone)

    private var compactLayout: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerView

                // Collapsible history
                compactHistorySection

                lyricsPanel

                Divider()
                    .padding(.horizontal)

                musicPanel

                if let error = vm.errorMessage {
                    errorBanner(error)
                        .padding(.horizontal)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.platformControlBackground)
        .compactFeatureChrome(
            nav: nav,
            lang: lang,
            dueCount: 0,
            onPreferSidebar: onPreferSidebar
        )
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.songGenTitle(lang))
                    .font(.largeTitle.weight(.bold))
                Text(L10n.songGenSubtitle(lang))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // History toggle (macOS)
            if !isCompact {
                Button {
                    withAnimation { showHistory.toggle() }
                } label: {
                    Image(systemName: "sidebar.left")
                        .foregroundColor(showHistory ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(showHistory ? "Hide history" : "Show history")
            }
        }
        .padding(.horizontal, isCompact ? 0 : 24)
        .padding(.top, isCompact ? 16 : 24)
        .padding(.bottom, isCompact ? 8 : 16)
    }

    // MARK: - History Panel (wide sidebar)

    private var historyPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("History")
                    .font(.headline)
                Spacer()
                if !vm.history.isEmpty {
                    Button {
                        vm.clearAllHistory()
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Clear all history")
                }
            }
            .padding(12)

            Divider()

            if vm.history.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No songs yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(vm.history) { item in
                        historyRow(item)
                            .listRowInsets(.init(top: 4, leading: 8, bottom: 4, trailing: 8))
                    }
                    .onDelete { offsets in
                        for idx in offsets {
                            vm.deleteHistoryItem(vm.history[idx])
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(Color.platformControlBackground.opacity(0.5))
    }

    // MARK: - Compact history section

    @ViewBuilder
    private var compactHistorySection: some View {
        if !vm.history.isEmpty {
            DisclosureGroup(isExpanded: $showHistory) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(vm.history) { item in
                            compactHistoryCard(item)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
                }
            } label: {
                Text("History (\(vm.history.count))")
                    .font(.subheadline.weight(.medium))
            }
        }
    }

    @ViewBuilder
    private func compactHistoryCard(_ item: SongHistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.displayTitle)
                .font(.caption.weight(.medium))
                .lineLimit(2)
            HStack(spacing: 4) {
                Text(item.displayGenre.capitalized)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color.accentColor.opacity(0.15))
                    )
                Text(formatDuration(item.duration))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Button {
                    vm.selectHistoryItem(item)
                    if vm.generatedAudioData != nil { vm.playAudio() }
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)

                Button {
                    vm.deleteHistoryItem(item)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(width: 160)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.platformWindowBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .onTapGesture {
            vm.selectHistoryItem(item)
        }
    }

    // MARK: - History row (wide sidebar)

    @ViewBuilder
    private func historyRow(_ item: SongHistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.displayTitle)
                .font(.caption.weight(.medium))
                .lineLimit(2)

            HStack(spacing: 4) {
                Text(item.displayGenre.capitalized)
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(Color.accentColor.opacity(0.12))
                    )

                Text(formatDuration(item.duration))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(item.timestamp, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 8) {
                Button {
                    vm.selectHistoryItem(item)
                    if vm.generatedAudioData != nil { vm.playAudio() }
                } label: {
                    Image(systemName: "play.circle")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .help("Play")

                Button {
                    vm.selectHistoryItem(item)
                } label: {
                    Image(systemName: "arrow.up.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Load lyrics & settings")
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            vm.selectHistoryItem(item)
        }
    }

    // MARK: - Lyrics Panel (left side)

    private var lyricsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Topic input
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.songTopicLabel(lang))
                    .font(.headline)

                TextField(L10n.songTopicPlaceholder(lang), text: $vm.songTopic)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.platformWindowBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
            }

            // Generate Lyrics button
            Button {
                Task { await vm.generateLyrics() }
            } label: {
                HStack(spacing: 8) {
                    if vm.isGeneratingLyrics {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 16, height: 16)
                        Text(L10n.generatingLyrics(lang))
                    } else {
                        Image(systemName: "sparkles")
                        Text(L10n.generateLyrics(lang))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isGeneratingLyrics || vm.isGeneratingMusic)

            // Lyrics editor
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.lyricsLabel(lang))
                    .font(.headline)

                TextEditor(text: $vm.lyrics)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.platformWindowBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .frame(minHeight: 200)
            }
        }
        .padding(isCompact ? 0 : 24)
    }

    // MARK: - Music Panel (right side)

    private var musicPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Music API URL
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.musicAPIURL(lang))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("https://song.npro.ai", text: $vm.musicAPIURL)
                    .textFieldStyle(.plain)
                    .font(.caption.monospaced())
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.platformWindowBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
            }

            Divider()

            // Settings
            Text(L10n.musicSettings(lang))
                .font(.headline)

            // Duration slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L10n.songDuration(lang))
                        .font(.subheadline)
                    Spacer()
                    Text("\(Int(vm.duration))s")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $vm.duration, in: 5...90, step: 1)
            }

            // Steps slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L10n.diffusionSteps(lang))
                        .font(.subheadline)
                    Spacer()
                    Text("\(vm.steps)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: .init(
                    get: { Double(vm.steps) },
                    set: { vm.steps = Int($0) }
                ), in: 10...100, step: 5)
            }

            // Genre picker
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.songGenre(lang))
                    .font(.subheadline)
                Picker("", selection: $vm.genre) {
                    Text(L10n.genreAuto(lang)).tag("")
                    ForEach(SongGenViewModel.genres, id: \.self) { genre in
                        Text(genre.capitalized).tag(genre)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            // Generate Music button
            Button {
                Task { await vm.generateMusic() }
            } label: {
                HStack(spacing: 8) {
                    if vm.isGeneratingMusic {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 16, height: 16)
                        Text(L10n.generatingMusic(lang))
                    } else {
                        Image(systemName: "music.note")
                        Text(L10n.generateMusic(lang))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isGeneratingLyrics || vm.isGeneratingMusic || vm.lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            // Player section
            if vm.generatedAudioData != nil {
                playerSection
            }
        }
        .padding(isCompact ? 0 : 24)
    }

    // MARK: - Player

    private var playerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(L10n.songReady(lang))
                    .font(.headline)
                    .foregroundStyle(.green)
            }

            HStack(spacing: 12) {
                Button {
                    if vm.isPlaying {
                        vm.stopAudio()
                    } else {
                        vm.playAudio()
                    }
                } label: {
                    Label(
                        vm.isPlaying
                            ? L10n.stopPlayback(lang)
                            : L10n.playSong(lang),
                        systemImage: vm.isPlaying ? "stop.fill" : "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)

                #if os(macOS)
                Button {
                    vm.saveSong()
                } label: {
                    Label(L10n.saveSong(lang), systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                #endif
            }

            if vm.isPlaying {
                HStack(spacing: 2) {
                    ForEach(0..<20, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.accentColor)
                            .frame(width: 3, height: CGFloat.random(in: 8...24))
                            .animation(
                                .easeInOut(duration: 0.3)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.05),
                                value: vm.isPlaying
                            )
                    }
                }
                .frame(height: 32)
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ d: Double) -> String {
        "\(Int(d))s"
    }

    // MARK: - Error banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.callout)
                .foregroundStyle(.red)
            Spacer()
            Button {
                vm.errorMessage = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.opacity(0.1))
        )
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
