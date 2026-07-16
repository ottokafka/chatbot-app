import SwiftUI

// MARK: - Pronunciation Mic Button

/// Mic control for continuous listen-until-correct flow.
/// Wrong attempts keep results on screen; the mic re-opens automatically (no “Try Again”).
struct PronunciationMicButton: View {
    let pronunciationState: LifePathViewModel.PronunciationState
    var isArmed: Bool = false   // true = TTS playing, recording will auto-start
    /// True when a previous miss is still shown while we listen again.
    var hasStickyResult: Bool = false
    /// Client-side passing threshold for isPassing checks.
    var threshold: Double = LifePathViewModel.defaultPronThreshold
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
                        Text(hasStickyResult ? "Keep going… Tap when done" : "Listening… Tap when done")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(hasStickyResult ? .orange : .red)
                .controlSize(.large)

                Button("Cancel", action: onCancel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .assessing:
            HStack(spacing: 10) {
                ProgressView()
                    .tint(.accentColor)
                Text(hasStickyResult ? "Checking again…" : "Checking pronunciation…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)

        case .feedback(let result):
            if result.isPassing(threshold: threshold) {
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
                // Results stay visible in the panel below; mic reopens automatically.
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.orange)
                        .scaleEffect(0.85)
                    Text("Listen again…")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.orange)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }

        case .error(let msg):
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.85)
                    Text("Still listening…")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Text(msg)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                Button("Cancel", action: onCancel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
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

// MARK: - Simple target word display

/// Displays the target word for pronunciation (no per-letter breakdown in v2.2+).
struct TargetWordDisplay: View {
    let word: String
    let isCorrect: Bool
    var font: Font = .system(size: 40, weight: .bold)

    var body: some View {
        Text(word)
            .font(font)
            .foregroundStyle(isCorrect ? .green : .primary)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isCorrect ? Color.green.opacity(0.14) : Color.clear)
            )
    }
}

// MARK: - Pronunciation Feedback View

/// Compact result panel: score, tip, and word-level feedback.
/// For misses this stays on screen while the mic keeps listening.
struct PronunciationFeedbackView: View {
    let result: PronunciationAssessmentResponse
    let targetWord: String
    /// Client-side passing threshold (e.g. 0.51 = 51%).
    let threshold: Double
    /// When true, learner is still in the listen loop (miss / re-recording).
    var isListeningLoop: Bool = false
    var showDismiss: Bool = false
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(headerTitle)
                        .font(.headline)
                    Text(result.displayFeedback)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if isListeningLoop && !result.isPassing(threshold: threshold) {
                        Text("Keep saying the word — I’ll check each try.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer(minLength: 8)
                ScoreBadge(score: result.overall_score, isCorrect: result.isPassing(threshold: threshold))
            }

            // Diagnostic line: what the model heard
            if !result.isPassing(threshold: threshold) {
                VStack(alignment: .leading, spacing: 4) {
                    if !result.predicted_phonemes.isEmpty {
                        Text("Heard: /\(result.predicted_phonemes.joined(separator: " "))/")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Heard: (nothing) — speak a bit louder")
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

            if showDismiss && !result.isPassing(threshold: threshold) {
                Button(action: onDismiss) {
                    Text("Stop listening")
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

    private var headerTitle: String {
        if result.isPassing(threshold: threshold) { return "Great pronunciation!" }
        if isListeningLoop { return "Almost — keep going" }
        return "Almost — try again"
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


