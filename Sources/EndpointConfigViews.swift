import SwiftUI

// MARK: - Endpoint Configuration
private enum EndpointConfigTemplate {
    static let stt = "wss://speech_to_text.npro.ai?silence_duration_ms=1000"
    static let llm = "https://text_gen.npro.ai/v1/chat/completions"
    static let tts = "https://text_to_speech.npro.ai/v1/audio/speech"
}

private func endpointHostSummary(from urlString: String, language: AppLanguage) -> String {
    let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    if let host = URL(string: trimmed)?.host, !host.isEmpty {
        return host
    }
    if trimmed.count > 40 {
        return String(trimmed.prefix(37)) + "..."
    }
    return trimmed.isEmpty ? L10n.noURLSet(language) : trimmed
}

// MARK: - Endpoint Configuration Modal View
struct EndpointConfigModalView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) var dismiss
    
    private var lang: AppLanguage { viewModel.appLanguage }
    @State private var selectedConfig: EndpointConfig?
    #if os(iOS)
    @State private var navigationPath = NavigationPath()
    #endif
    
    var body: some View {
        #if os(iOS)
        NavigationStack(path: $navigationPath) {
            EndpointConfigListView(viewModel: viewModel, navigationPath: $navigationPath)
                .navigationDestination(for: EndpointConfig.self) { config in
                    if let current = viewModel.endpointConfigs.first(where: { $0.id == config.id }) {
                        EndpointConfigDetailView(config: current, viewModel: viewModel)
                    } else {
                        ContentUnavailableView(
                            L10n.configurationNotFound(lang),
                            systemImage: "exclamationmark.triangle",
                            description: Text(L10n.configurationDeletedHint(lang))
                        )
                    }
                }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #else
        HStack(spacing: 0) {
            // SIDEBAR
            VStack(alignment: .leading, spacing: 16) {
                // New Config Button
                Button(action: {
                    viewModel.createEndpointConfig(
                        name: L10n.newConfigName(lang),
                        textGenURL: EndpointConfigTemplate.llm,
                        ttsURL: EndpointConfigTemplate.tts,
                        sttURL: EndpointConfigTemplate.stt
                    )
                    // Select the newly created configuration
                    if let last = viewModel.endpointConfigs.last {
                        selectedConfig = last
                    }
                }) {
                    HStack {
                        Image(systemName: "plus")
                        Text(L10n.newConfiguration(lang))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                
                Text(L10n.configurations(lang))
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.top, 8)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.endpointConfigs) { config in
                            HStack {
                                Button(action: {
                                    selectedConfig = config
                                }) {
                                    Text(config.name)
                                        .font(.body)
                                        .foregroundColor(selectedConfig?.id == config.id ? .white : .gray)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 10)
                                }
                                .buttonStyle(.plain)
                                .background(selectedConfig?.id == config.id ? Color.blue : Color.clear)
                                .cornerRadius(6)
                                
                                if !config.isActive {
                                    Button(action: {
                                        viewModel.deleteEndpointConfig(id: config.id)
                                        if selectedConfig?.id == config.id {
                                            selectedConfig = viewModel.endpointConfigs.first(where: { $0.id != config.id })
                                        }
                                    }) {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red.opacity(0.8))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.trailing, 4)
                                }
                            }
                        }
                    }
                }
                
                Spacer()
                
                // Done button at the bottom of the sidebar
                Button(action: {
                    dismiss()
                }) {
                    Text(L10n.done(lang))
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .frame(width: 240)
            .background(Color(red: 0.08, green: 0.08, blue: 0.1))
            
            Divider()
                .background(Color.gray.opacity(0.3))
            
            // DETAIL VIEW
            VStack(spacing: 0) {
                if let config = selectedConfig {
                    ScrollView {
                        EndpointConfigCard(config: config, viewModel: viewModel)
                            .id(config.id) // Resets state when config changes
                            .padding(24)
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text(L10n.noConfigurationSelected(lang))
                            .font(.headline)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.12, green: 0.12, blue: 0.14))
        }
        .frame(width: 850, height: 600)
        .preferredColorScheme(.dark)
        .onAppear {
            if selectedConfig == nil {
                selectedConfig = viewModel.activeEndpointConfig ?? viewModel.endpointConfigs.first
            }
        }
        .onChange(of: viewModel.endpointConfigs) {
            // Keep selectedConfig pointer in sync if config is deleted or updated
            if let current = selectedConfig {
                if !viewModel.endpointConfigs.contains(where: { $0.id == current.id }) {
                    selectedConfig = viewModel.activeEndpointConfig ?? viewModel.endpointConfigs.first
                }
            } else {
                selectedConfig = viewModel.activeEndpointConfig ?? viewModel.endpointConfigs.first
            }
        }
        #endif
    }
}

#if os(iOS)
// MARK: - iOS Endpoint Config List
struct EndpointConfigListView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Binding var navigationPath: NavigationPath
    @Environment(\.dismiss) private var dismiss
    
    private var lang: AppLanguage { viewModel.appLanguage }
    
    var body: some View {
        List {
            ForEach(viewModel.endpointConfigs) { config in
                NavigationLink(value: config) {
                    EndpointConfigRowView(config: config)
                }
                .deleteDisabled(config.isActive)
            }
            .onDelete(perform: deleteConfigs)
        }
        .navigationTitle(L10n.endpoints(lang))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.done(lang)) {
                    dismiss()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: createAndOpenNew) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(L10n.newConfiguration(lang))
            }
        }
    }
    
    private func createAndOpenNew() {
        viewModel.createEndpointConfig(
            name: L10n.newConfigName(lang),
            textGenURL: EndpointConfigTemplate.llm,
            ttsURL: EndpointConfigTemplate.tts,
            sttURL: EndpointConfigTemplate.stt
        )
        if let newConfig = viewModel.endpointConfigs.last {
            navigationPath.append(newConfig)
        }
    }
    
    private func deleteConfigs(at offsets: IndexSet) {
        for index in offsets {
            let config = viewModel.endpointConfigs[index]
            guard !config.isActive else { continue }
            viewModel.deleteEndpointConfig(id: config.id)
        }
    }
}

struct EndpointConfigRowView: View {
    let config: EndpointConfig
    
    @Environment(\.appLanguage) private var lang
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(config.name)
                    .font(.body)
                Text(endpointHostSummary(from: config.textGenURL, language: lang))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer(minLength: 8)
            
            if config.isActive {
                Text(L10n.active(lang))
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - iOS Endpoint Config Detail
struct EndpointConfigDetailView: View {
    let config: EndpointConfig
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    
    private var lang: AppLanguage { viewModel.appLanguage }
    @State private var name: String = ""
    @State private var textGenURL: String = ""
    @State private var ttsURL: String = ""
    @State private var sttURL: String = ""
    
    @State private var textGenResult: String = ""
    @State private var isTestingTextGen = false
    
    @State private var ttsInputText = "Hello, this is a test of the text to speech endpoint."
    @State private var isPlayingTTS = false
    
    @State private var isTextGenExpanded = true
    @State private var isTTSExpanded = false
    @State private var isSTTExpanded = false
    
    private var currentConfig: EndpointConfig {
        viewModel.endpointConfigs.first(where: { $0.id == config.id }) ?? config
    }
    
    private var isDictating: Bool {
        viewModel.activeTestSTTConfigId == config.id
    }
    
    var body: some View {
        Form {
            Section {
                TextField(L10n.configurationName(lang), text: $name)
                
                Toggle(L10n.useThisConfiguration(lang), isOn: Binding(
                    get: { currentConfig.isActive },
                    set: { newValue in
                        if newValue {
                            viewModel.selectEndpointConfig(currentConfig)
                        }
                    }
                ))
            }
            
            Section {
                DisclosureGroup(L10n.textGeneration(lang), isExpanded: $isTextGenExpanded) {
                    TextField(L10n.textGenerationURL(lang), text: $textGenURL, axis: .vertical)
                        .lineLimit(1...4)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.system(.body, design: .monospaced))
                    
                    Button(action: runTextGenTest) {
                        HStack {
                            Spacer()
                            if isTestingTextGen {
                                ProgressView()
                            }
                            Text(isTestingTextGen ? L10n.testing(lang) : L10n.testConnection(lang))
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(isTestingTextGen || textGenURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    
                    Text(textGenResult.isEmpty ? L10n.textGenSamplePlaceholder(lang) : textGenResult)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(textGenResult.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
                        .padding(10)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            
            Section {
                DisclosureGroup(L10n.tts(lang), isExpanded: $isTTSExpanded) {
                    TextField(L10n.ttsURL(lang), text: $ttsURL, axis: .vertical)
                        .lineLimit(1...4)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.system(.body, design: .monospaced))
                    
                    if viewModel.voiceOptions.isEmpty {
                        Text(L10n.noVoicesLoaded(lang))
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    } else {
                        Picker(L10n.voice(lang), selection: $viewModel.ttsVoice) {
                            ForEach(viewModel.voiceOptions, id: \.self) { voice in
                                Text(voice).tag(voice)
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(L10n.speed(lang))
                            Spacer()
                            Text(String(format: "%.2fx", viewModel.ttsSpeed))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $viewModel.ttsSpeed, in: 0.5...2.0, step: 0.05)
                    }
                    
                    TextField(L10n.synthesizePlaceholder(lang), text: $ttsInputText, axis: .vertical)
                        .lineLimit(2...5)
                        .font(.system(.body, design: .monospaced))
                    
                    Button(action: playTTSTest) {
                        HStack {
                            Spacer()
                            if isPlayingTTS {
                                ProgressView()
                            } else {
                                Image(systemName: "play.fill")
                            }
                            Text(isPlayingTTS ? L10n.playing(lang) : L10n.playTestAudio(lang))
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(isPlayingTTS || ttsInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            
            Section {
                DisclosureGroup(L10n.stt(lang), isExpanded: $isSTTExpanded) {
                    TextField(L10n.sttURL(lang), text: $sttURL, axis: .vertical)
                        .lineLimit(1...4)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.system(.body, design: .monospaced))
                    
                    Button(action: toggleDictation) {
                        HStack {
                            Spacer()
                            Text(isDictating ? L10n.stopDictation(lang) : L10n.startDictation(lang))
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .tint(isDictating ? .red : .blue)
                    
                    Text(dictationDisplayText)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(isDictating && !viewModel.testSTTText.isEmpty ? .primary : .secondary)
                        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
                        .padding(10)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .navigationTitle(name.isEmpty ? L10n.configuration(lang) : name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(L10n.save(lang)) {
                    saveConfig()
                }
            }
            if !currentConfig.isActive {
                ToolbarItem(placement: .destructiveAction) {
                    Button(L10n.delete(lang), role: .destructive) {
                        deleteConfig()
                    }
                }
            }
        }
        .onAppear {
            syncFieldsFromConfig()
        }
        .onChange(of: config) {
            syncFieldsFromConfig()
        }
    }
    
    private var dictationDisplayText: String {
        if isDictating {
            return viewModel.testSTTText.isEmpty ? L10n.listeningSpeakNow(lang) : viewModel.testSTTText
        }
        return L10n.dictationPlaceholder(lang)
    }
    
    private func syncFieldsFromConfig() {
        let source = currentConfig
        name = source.name
        textGenURL = source.textGenURL
        ttsURL = source.ttsURL
        sttURL = source.sttURL
    }
    
    private func saveConfig() {
        viewModel.updateEndpointConfig(
            id: config.id,
            name: name,
            textGenURL: textGenURL,
            ttsURL: ttsURL,
            sttURL: sttURL
        )
    }
    
    private func deleteConfig() {
        viewModel.deleteEndpointConfig(id: config.id)
        dismiss()
    }
    
    private func runTextGenTest() {
        isTestingTextGen = true
        textGenResult = L10n.connectingAndGenerating(lang)
        Task {
            do {
                let response = try await viewModel.runTextGenTest(url: textGenURL)
                textGenResult = response
            } catch {
                textGenResult = "Error: \(error.localizedDescription)"
            }
            isTestingTextGen = false
        }
    }
    
    private func playTTSTest() {
        guard !ttsInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isPlayingTTS = true
        Task {
            do {
                try await viewModel.runTTSTest(url: ttsURL, text: ttsInputText)
            } catch {
                viewModel.log("TTS test failed: \(error.localizedDescription)", tag: "ERROR")
            }
            isPlayingTTS = false
        }
    }
    
    private func toggleDictation() {
        if isDictating {
            viewModel.stopSTTTest()
        } else {
            viewModel.startSTTTest(configId: config.id, url: sttURL)
        }
    }
}
#endif

// MARK: - Endpoint Config Card View
struct EndpointConfigCard: View {
    let config: EndpointConfig
    @ObservedObject var viewModel: ChatViewModel
    
    private var lang: AppLanguage { viewModel.appLanguage }
    @State private var name: String = ""
    @State private var textGenURL: String = ""
    @State private var ttsURL: String = ""
    @State private var sttURL: String = ""
    
    @State private var textGenResult: String = ""
    @State private var isTestingTextGen: Bool = false
    
    @State private var ttsInputText: String = "Hello, this is a test of the text to speech endpoint."
    @State private var isPlayingTTS: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: Name, Active Toggle, Delete Button
            HStack {
                HStack(spacing: 6) {
                    Text(L10n.configNameLabel(lang))
                        .font(.headline)
                        .foregroundColor(.secondary)
                    TextField(L10n.configurationName(lang), text: $name)
                        .font(.headline)
                        .textFieldStyle(.plain)
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                // Toggle ACTIVE
                HStack(spacing: 8) {
                    Toggle("", isOn: Binding(
                        get: { config.isActive },
                        set: { newValue in
                            if newValue {
                                viewModel.selectEndpointConfig(config)
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    
                    Text(config.isActive ? L10n.active(lang) : L10n.inactive(lang))
                        .font(.caption2)
                        .fontWeight(.bold)
                        .monospaced()
                        .foregroundColor(config.isActive ? .blue : .gray)
                }
            }
            
            // Text Gen Field
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.textGeneration(lang))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.gray)
                HStack(spacing: 8) {
                    TextField(L10n.textGenerationURL(lang), text: $textGenURL)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                        .font(.system(.body, design: .monospaced))
                    
                    Button(action: {
                        runTextGenTest()
                    }) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.blue)
                            
                            if isTestingTextGen {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.8)
                            } else {
                                Text(L10n.test(lang))
                                    .font(.body)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(width: 60, height: 32)
                    }
                    .buttonStyle(.plain)
                    .disabled(isTestingTextGen)
                }
                
                // Text Gen Response Box
                Text(textGenResult.isEmpty ? L10n.textGenSamplePlaceholder(lang) : textGenResult)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(textGenResult.isEmpty ? .gray : .white)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.4))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                    )
            }
            
            // TTS Field
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.tts(lang))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.gray)
                TextField(L10n.ttsURL(lang), text: $ttsURL)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    .font(.system(.body, design: .monospaced))
                
                // TTS Voice Selection Dropdown Inline
                HStack {
                    Text(L10n.ttsVoice(lang))
                        .font(.body)
                        .foregroundColor(.secondary)
                    Spacer()
                    if viewModel.voiceOptions.isEmpty {
                        Text(L10n.noVoicesLoaded(lang))
                            .font(.caption)
                            .foregroundColor(.yellow)
                    } else {
                        Picker("", selection: $viewModel.ttsVoice) {
                            ForEach(viewModel.voiceOptions, id: \.self) { voice in
                                Text(voice).tag(voice)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                }
                .padding(.vertical, 2)
                
                // TTS Speed Slider
                HStack {
                    Text(L10n.ttsSpeed(lang))
                        .font(.body)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.2fx", viewModel.ttsSpeed))
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.blue)
                        .frame(width: 48, alignment: .trailing)
                    Slider(value: $viewModel.ttsSpeed, in: 0.5...2.0, step: 0.05)
                        .frame(width: 150)
                }
                .padding(.vertical, 2)
                
                // Enter Text for Speech Section
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.enterTextForSpeech(lang))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.gray)
                    HStack(spacing: 8) {
                        TextField(L10n.synthesizePlaceholder(lang), text: $ttsInputText)
                            .textFieldStyle(.plain)
                            .padding(8)
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                            .font(.system(.body, design: .monospaced))
                        
                        Button(action: {
                            playTTSTest()
                        }) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.blue)
                                    .frame(width: 36, height: 32)
                                
                                if isPlayingTTS {
                                    ProgressView()
                                        .controlSize(.small)
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "play.fill")
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isPlayingTTS || ttsInputText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            
            // STT Field
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.stt(lang))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.gray)
                HStack(spacing: 8) {
                    TextField(L10n.sttURL(lang), text: $sttURL)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                        .font(.system(.body, design: .monospaced))
                    
                    let isDictating = viewModel.activeTestSTTConfigId == config.id
                    Button(action: {
                        if isDictating {
                            viewModel.stopSTTTest()
                        } else {
                            viewModel.startSTTTest(configId: config.id, url: sttURL)
                        }
                    }) {
                        Text(isDictating ? L10n.stopDictation(lang) : L10n.startDictation(lang))
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(isDictating ? Color.red : Color.blue)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                
                // Dictation Text Output Box
                let isDictating = viewModel.activeTestSTTConfigId == config.id
                let dictationDisplayText = isDictating ? (viewModel.testSTTText.isEmpty ? L10n.listeningSpeakNow(lang) : viewModel.testSTTText) : L10n.dictationPlaceholder(lang)
                Text(dictationDisplayText)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(isDictating && !viewModel.testSTTText.isEmpty ? .white : .gray)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.4))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                    )
            }
            
            // Save Button
            HStack {
                Spacer()
                Button(action: {
                    viewModel.updateEndpointConfig(
                        id: config.id,
                        name: name,
                        textGenURL: textGenURL,
                        ttsURL: ttsURL,
                        sttURL: sttURL
                    )
                }) {
                    Text(L10n.save(lang))
                        .font(.body)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.12))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .onAppear {
            self.name = config.name
            self.textGenURL = config.textGenURL
            self.ttsURL = config.ttsURL
            self.sttURL = config.sttURL
        }
        .onChange(of: config) {
            self.name = config.name
            self.textGenURL = config.textGenURL
            self.ttsURL = config.ttsURL
            self.sttURL = config.sttURL
        }
    }
    
    private func runTextGenTest() {
        isTestingTextGen = true
        textGenResult = L10n.connectingAndGenerating(lang)
        Task {
            do {
                let response = try await viewModel.runTextGenTest(url: textGenURL)
                textGenResult = response
            } catch {
                textGenResult = "Error: \(error.localizedDescription)"
            }
            isTestingTextGen = false
        }
    }
    
    private func playTTSTest() {
        guard !ttsInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isPlayingTTS = true
        Task {
            do {
                try await viewModel.runTTSTest(url: ttsURL, text: ttsInputText)
            } catch {
                viewModel.log("TTS test failed: \(error.localizedDescription)", tag: "ERROR")
            }
            isPlayingTTS = false
        }
    }
}
