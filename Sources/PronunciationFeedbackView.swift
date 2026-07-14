import SwiftUI

// MARK: - Pronunciation Mic Button

/// A large mic button that cycles through idle → recording → stop → assessing states.
struct PronunciationMicButton: View {
    let pronunciationState: LifePathViewModel.PronunciationState
    let onStart: () -> Void
    let onStop: () -> Void
    let onCancel: () -> Void

    var body: some View {
        switch pronunciationState {
        case .idle:
            Button(action: onStart) {
                Label("Say It", systemImage: "mic.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.blue)
            .controlSize(.large)

        case .recording:
            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)

                Button(action: onStop) {
                    HStack {
                        RecordingPulse()
                        Text("Stop Recording")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
            }

        case .assessing:
            HStack {
                ProgressView()
                    .tint(.accentColor)
                Text("Analyzing…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

        case .feedback, .error:
            Button(action: onStart) {
                Label("Try Again", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.blue)
            .controlSize(.large)
        }
    }
}

// MARK: - Recording Pulse Indicator

private struct RecordingPulse: View {
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(Color.white)
            .frame(width: 10, height: 10)
            .scaleEffect(pulsing ? 1.4 : 1.0)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulsing)
            .onAppear { pulsing = true }
    }
}

// MARK: - Pronunciation Feedback View

/// Shows the result of pronunciation assessment: overall score, pass/fail badge,
/// and per-grapheme phoneme breakdown.
struct PronunciationFeedbackView: View {
    let result: PronunciationAssessmentResponse
    let targetWord: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header: word + overall badge
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(targetWord)
                        .font(.title.bold())
                    Text(result.is_correct ? "Great pronunciation!" : "Keep practicing!")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ScoreBadge(score: result.overall_score, isCorrect: result.is_correct)
            }

            // Grapheme / phoneme breakdown
            if !result.phonemes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("PHONEME BREAKDOWN")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 2)

                    // Scrollable row of phoneme chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .bottom, spacing: 10) {
                            ForEach(Array(result.phonemes.enumerated()), id: \.offset) { _, phoneme in
                                PhonemeChip(phoneme: phoneme)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            // Target vs predicted phonemes (compact)
            targetVsPredictedRow

            // Dismiss button
            Button(action: onDismiss) {
                Text("Dismiss")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        .padding()
        .background(Color.platformControlBackground, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - Sub-views

    private var targetVsPredictedRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !result.target_phonemes.isEmpty {
                phonemeRow(label: "Target", phonemes: result.target_phonemes, color: .blue)
            }
            if !result.predicted_phonemes.isEmpty {
                phonemeRow(label: "Heard", phonemes: result.predicted_phonemes, color: result.is_correct ? .green : .orange)
            }
        }
    }

    private func phonemeRow(label: String, phonemes: [String], color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label + ":")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(phonemes.enumerated()), id: \.offset) { _, p in
                        Text("/\(p)/")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(color)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
        }
    }
}

// MARK: - Score Badge

private struct ScoreBadge: View {
    let score: Double
    let isCorrect: Bool

    private var percentage: Int { Int(score * 100) }

    private var badgeColor: Color {
        if percentage >= 80 { return .green }
        if percentage >= 60 { return .orange }
        return .red
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(badgeColor.opacity(0.25), lineWidth: 5)
                .frame(width: 62, height: 62)
            Circle()
                .trim(from: 0, to: score)
                .stroke(badgeColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .frame(width: 62, height: 62)
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: score)
            VStack(spacing: 0) {
                Text("\(percentage)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(badgeColor)
                Text("%")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Phoneme Chip

private struct PhonemeChip: View {
    let phoneme: PronunciationPhoneme

    private var chipColor: Color {
        if phoneme.score >= 0.8 { return .green }
        if phoneme.score >= 0.5 { return .orange }
        return .red
    }

    var body: some View {
        VStack(spacing: 4) {
            // Score bar
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(chipColor.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(chipColor)
                        .frame(height: geo.size.height * phoneme.score)
                }
            }
            .frame(width: 30, height: 40)

            // Grapheme
            Text(phoneme.grapheme)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(chipColor)

            // Phoneme symbol
            Text("/\(phoneme.phoneme)/")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(width: 40)
    }
}
