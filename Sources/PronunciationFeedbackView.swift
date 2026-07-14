import SwiftUI

// MARK: - Pronunciation Mic Button

/// Large mic control: idle → recording (tap to finish) → assessing → try again.
struct PronunciationMicButton: View {
    let pronunciationState: LifePathViewModel.PronunciationState
    var isArmed: Bool = false   // true = TTS playing, recording will auto-start
    let onStart: () -> Void
    let onStop: () -> Void
    let onCancel: () -> Void

    var body: some View {
        switch pronunciationState {
        case .idle:
            if isArmed {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.blue)
                        .scaleEffect(0.85)
                    Text("Get ready…")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            } else {
                Button(action: onStart) {
                    Label("Say It", systemImage: "mic.fill")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.large)
            }

        case .recording:
            VStack(spacing: 10) {
                Button(action: onStop) {
                    HStack(spacing: 10) {
                        RecordingPulse()
                        Text("Listening… Tap when done")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)

                Button("Cancel", action: onCancel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .assessing:
            HStack(spacing: 10) {
                ProgressView()
                    .tint(.accentColor)
                Text("Checking pronunciation…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)

        case .feedback(let result):
            if result.is_correct {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Nice! Moving on…")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.green)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            } else {
                Button(action: onStart) {
                    Label("Try Again", systemImage: "arrow.counterclockwise")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.large)
            }

        case .error:
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

// MARK: - Inline phoneme-highlighted word

/// Renders the target word as colored grapheme slices from an assessment result.
struct PhonemeHighlightedWord: View {
    let result: PronunciationAssessmentResponse
    var font: Font = .system(size: 40, weight: .bold)

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(result.phonemes.enumerated()), id: \.offset) { _, phoneme in
                Text(phoneme.grapheme)
                    .font(font)
                    .foregroundStyle(color(for: phoneme))
                    .padding(.horizontal, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(color(for: phoneme).opacity(0.14))
                    )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private func color(for phoneme: PronunciationPhoneme) -> Color {
        if phoneme.score >= 0.8 { return .green }
        if phoneme.score >= 0.5 { return .orange }
        return .red
    }

    private var accessibilityLabel: String {
        result.phonemes.map { p in
            let status = p.is_correct ? "correct" : "needs work"
            return "\(p.grapheme), \(status)"
        }.joined(separator: ", ")
    }
}

// MARK: - Pronunciation Feedback View

/// Compact result panel: score, tip, and optional phoneme chips.
struct PronunciationFeedbackView: View {
    let result: PronunciationAssessmentResponse
    let targetWord: String
    var showDismiss: Bool = true
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.is_correct ? "Great pronunciation!" : "Almost — try again")
                        .font(.headline)
                    Text(result.displayFeedback)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                ScoreBadge(score: result.overall_score, isCorrect: result.is_correct)
            }

            if !result.phonemes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 10) {
                        ForEach(Array(result.phonemes.enumerated()), id: \.offset) { _, phoneme in
                            PhonemeChip(phoneme: phoneme)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            // Diagnostic line: what the model heard (helps debug always-0% / silence issues)
            if !result.is_correct {
                VStack(alignment: .leading, spacing: 4) {
                    if !result.predicted_phonemes.isEmpty {
                        Text("Heard: /\(result.predicted_phonemes.joined(separator: " "))/")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Heard: (nothing) — check mic level / silence")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if let audio = result.debug?.audio ?? result.debug?.post_trim {
                        Text(String(format: "Audio: %.0f ms · RMS %.3f%@",
                                    Double(audio.duration_ms ?? 0),
                                    audio.rms,
                                    audio.is_silent ? " · SILENT" : ""))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            if showDismiss && !result.is_correct {
                Button(action: onDismiss) {
                    Text("Dismiss")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
        .padding()
        .background(Color.platformControlBackground, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}

// MARK: - Score Badge

private struct ScoreBadge: View {
    let score: Double
    let isCorrect: Bool

    private var percentage: Int { Int((score * 100).rounded()) }

    private var badgeColor: Color {
        if percentage >= 80 { return .green }
        if percentage >= 60 { return .orange }
        return .red
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(badgeColor.opacity(0.25), lineWidth: 5)
                .frame(width: 58, height: 58)
            Circle()
                .trim(from: 0, to: min(max(score, 0), 1))
                .stroke(badgeColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .frame(width: 58, height: 58)
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.55), value: score)
            VStack(spacing: 0) {
                Text("\(percentage)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
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
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(chipColor.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(chipColor)
                        .frame(height: geo.size.height * min(max(phoneme.score, 0), 1))
                }
            }
            .frame(width: 28, height: 36)

            Text(phoneme.grapheme)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(chipColor)

            Text("/\(phoneme.phoneme)/")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 40)
    }
}
