import SwiftUI

/// Flashcards feature detail shell. Hosts `FlashcardDeckView`; practice/speak sheets stay on root.
struct FlashcardsShellView: View {
    @ObservedObject var nav: AppNavigationModel
    @ObservedObject var flashcardVM: FlashcardViewModel
    @ObservedObject var speakingVM: SpeakingSessionViewModel
    var llmEndpoint: String
    var llmModel: String
    var configureSpeaking: () -> Void
    var dismissPracticeForSpeaking: () -> Void
    var endSpeakingForPractice: () -> Void
    /// Compact iOS: reveal the split-view sidebar column.
    var onPreferSidebar: () -> Void = {}
    @Environment(\.appLanguage) private var lang

    var body: some View {
        FlashcardDeckView(
            flashcardVM: flashcardVM,
            speakingVM: speakingVM,
            llmEndpoint: llmEndpoint,
            llmModel: llmModel,
            configureSpeaking: configureSpeaking,
            dismissPracticeForSpeaking: dismissPracticeForSpeaking,
            endSpeakingForPractice: endSpeakingForPractice
        )
        .compactFeatureChrome(
            nav: nav,
            lang: lang,
            dueCount: flashcardVM.dueCount,
            onPreferSidebar: onPreferSidebar
        )
    }
}
