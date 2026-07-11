#if DEBUG
import SwiftUI

/// Minimal DEBUG sheet to exercise the typed speaking loop without deck UI / mic.
struct SpeakingSessionDebugView: View {
    @ObservedObject var speakingVM: SpeakingSessionViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var targetsCSV: String = "hello, water, food"
    @State private var knownCSV: String = "hello, water, food, I, you, want, like, eat, drink"
    @State private var topicHint: String = "daily life"
    @State private var encourageCoverage: Bool = true
    @State private var draftInput: String = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                if speakingVM.session == nil || speakingVM.session?.status == .ended {
                    setupForm
                } else {
                    sessionPanel
                }
            }
            .padding()
            .navigationTitle("Speaking Debug (typed)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        speakingVM.endSession()
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 480)
    }

    // MARK: - Setup

    private var setupForm: some View {
        Form {
            Section("Seeds (comma-separated fronts)") {
                TextField("Targets", text: $targetsCSV)
                TextField("Known fronts", text: $knownCSV)
                TextField("Topic hint", text: $topicHint)
                Toggle("Encourage target coverage", isOn: $encourageCoverage)
            }
            Section {
                Button("Start typed session") {
                    startDebugSession()
                }
                .disabled(parseFronts(targetsCSV).isEmpty)
            }
            Section("Flag") {
                Text("speaking.enabled = \(SpeakingFeature.isEnabled ? "true" : "false")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(SpeakingFeature.isEnabled ? "Disable flag" : "Enable flag") {
                    SpeakingFeature.isEnabled.toggle()
                }
            }
        }
    }

    // MARK: - Session

    private var sessionPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let session = speakingVM.session {
                statusRow(session)
                if let err = session.lastError, !err.isEmpty {
                    errorBanner(err, session: session)
                }
                coverageChips(session)
                transcriptList(session)
                inputRow(session)
            }
            HStack {
                Button("End session") {
                    speakingVM.endSession()
                }
                Spacer()
            }
        }
    }

    private func statusRow(_ session: SpeakingSession) -> some View {
        HStack {
            Text("Status: \(String(describing: session.status))")
                .font(.headline)
            Spacer()
            if session.status == .generatingReply {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private func errorBanner(_ message: String, session: SpeakingSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
            HStack {
                if session.status == .ready {
                    Button("Retry opening") {
                        Task { await speakingVM.retryOpening() }
                    }
                }
                if speakingVM.pendingUserText != nil, session.status == .waitingUser {
                    Button("Retry last reply") {
                        Task { await speakingVM.retryLastReply() }
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func coverageChips(_ session: SpeakingSession) -> some View {
        let covered = Set(session.coveredTargetFronts.map { PracticeScaffolding.normalizeFrontKey($0) })
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(session.config.targetFronts, id: \.self) { front in
                    let isCovered = covered.contains(PracticeScaffolding.normalizeFrontKey(front))
                    Text(front)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(isCovered ? Color.green.opacity(0.25) : Color.gray.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
        }
    }

    private func transcriptList(_ session: SpeakingSession) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(session.turns) { turn in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(turn.role == .user ? "You" : "AI")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(turn.content)
                            .font(.body)
                        if !turn.targetHits.isEmpty {
                            Text("hits: \(turn.targetHits.joined(separator: ", "))")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(
                        turn.role == .user
                            ? Color.blue.opacity(0.08)
                            : Color.gray.opacity(0.08)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .frame(maxHeight: 280)
    }

    private func inputRow(_ session: SpeakingSession) -> some View {
        HStack {
            TextField("Type a reply…", text: $draftInput)
                .textFieldStyle(.roundedBorder)
                .disabled(session.status != .waitingUser)
            Button("Send") {
                let text = draftInput
                draftInput = ""
                Task { await speakingVM.sendTypedText(text) }
            }
            .disabled(session.status != .waitingUser || draftInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    // MARK: - Helpers

    private func startDebugSession() {
        let targetFronts = parseFronts(targetsCSV)
        let knownFronts = parseFronts(knownCSV)
        let cards = targetFronts.map { front in
            Flashcard(front: front, back: front, kind: .vocab)
        }
        speakingVM.prepareSetup(
            seedSource: .selectedVocab(ids: cards.map(\.id)),
            targets: cards,
            knownFronts: knownFronts,
            topicHint: topicHint,
            encourageTargetCoverage: encourageCoverage
        )
        Task {
            await speakingVM.startSession()
        }
    }

    private func parseFronts(_ csv: String) -> [String] {
        csv.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

#endif
