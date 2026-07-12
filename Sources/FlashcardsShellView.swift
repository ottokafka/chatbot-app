import SwiftUI

/// Flashcards feature detail shell. Hosts `FlashcardDeckView`; practice/speak sheets stay on root.
struct FlashcardsShellView: View {
    @ObservedObject var flashcardVM: FlashcardViewModel
    @ObservedObject var speakingVM: SpeakingSessionViewModel
    var llmEndpoint: String
    var llmModel: String
    var configureSpeaking: () -> Void
    var dismissPracticeForSpeaking: () -> Void
    var endSpeakingForPractice: () -> Void

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
    }
}
