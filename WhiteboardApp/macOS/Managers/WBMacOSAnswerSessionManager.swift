import Foundation
import Observation

/// Owns the Home question session: the question text, the in-flight request, and the answer
/// state. Fetching lives here — not in the view model — so the request lifecycle and the
/// state it produces stay together and survive the Home column being torn down (switching
/// sidebar destinations recreates the view model, which simply reads this manager again).
@Observable
final class WBMacOSAnswerSessionManager {

    private let answerProvider: WBMacOSAnswerProviding
    private let selectionManager: WBMacOSSelectionManager
    private var answerTask: Task<Void, Never>?

    var searchText = ""

    private(set) var answerState = WBMacOSLoadState<WBMacOSAnswer>.idle

    init(
        answerProvider: WBMacOSAnswerProviding,
        selectionManager: WBMacOSSelectionManager
    ) {
        self.answerProvider = answerProvider
        self.selectionManager = selectionManager
    }

    func submit(question: String) {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty else {
            return
        }
        answerTask?.cancel()
        answerTask = Task {
            await load(question: trimmedQuestion)
        }
    }

    private func load(question: String) async {
        answerState = .loading
        do {
            let answer = try await answerProvider.answer(toQuestion: question)
            guard !Task.isCancelled else {
                return
            }
            answerState = .loaded(answer)
            // Results stay full-screen — the detail inspector only opens when the user
            // picks a result, so clear any selection left from a previous search.
            selectionManager.select(nil)
        } catch is CancellationError {
            // A newer search superseded this one — never surface it as a failure.
            return
        } catch {
            guard !Task.isCancelled else {
                return
            }
            answerState = .failed(error.localizedDescription)
            selectionManager.select(nil)
        }
    }
}
