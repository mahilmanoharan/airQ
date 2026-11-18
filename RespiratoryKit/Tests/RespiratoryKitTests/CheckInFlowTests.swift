import Foundation
import Testing
@testable import RespiratoryKit

@Suite("Check-in, one question per card")
struct CheckInFlowTests {
    private let blank = CheckInDraft(dayKey: "2026-09-20")

    @Test("Unanswered or no symptoms: straight from breathing to medication; follow-ups only when they apply")
    func steps() {
        #expect(CheckInFlow.steps(for: blank) == [.breathing, .medication, .windows, .peakFlow, .review])
        var none = blank
        CheckInFlow.answer(.noSymptoms, in: &none)
        #expect(CheckInFlow.steps(for: none) == [.breathing, .medication, .windows, .peakFlow, .review])
        var day = blank
        CheckInFlow.answer(.daytime, in: &day)
        #expect(CheckInFlow.steps(for: day) == [.breathing, .severity, .symptoms, .night, .limited, .rescue,
                                                 .medication, .windows, .peakFlow, .review])
        var night = blank
        CheckInFlow.answer(.nightOnly, in: &night)
        #expect(CheckInFlow.steps(for: night) == [.breathing, .limited, .rescue, .medication, .windows, .peakFlow, .review])
    }

    @Test("The first card's answers write the same values the form did, and read back")
    func answers() {
        var draft = blank
        CheckInFlow.answer(.noSymptoms, in: &draft)
        var expected = blank
        expected.answerNoSymptoms()
        #expect(draft == expected && CheckInFlow.breathing(of: draft) == .noSymptoms)

        draft.symptomsSelected = ["cough"]
        draft.daytimeSymptoms = true
        draft.daytimeSeverity = 2
        CheckInFlow.answer(.nightOnly, in: &draft)
        // Night only clears the daytime detail, so the draft never says "no daytime symptoms" with chips.
        #expect(draft.daytimeSymptoms == false && draft.daytimeSeverity == nil && draft.symptomsSelected.isEmpty)
        #expect(draft.nightWaking == true && CheckInFlow.breathing(of: draft) == .nightOnly)
        #expect(CheckInFlow.breathing(of: blank) == nil)
    }

    @Test("Next and back follow the current answers, and stop at the ends")
    func navigation() {
        var day = blank
        CheckInFlow.answer(.daytime, in: &day)
        #expect(CheckInFlow.step(after: .breathing, for: day) == .severity)
        #expect(CheckInFlow.step(after: .breathing, for: blank) == .medication)
        #expect(CheckInFlow.step(before: .medication, for: day) == .rescue)
        #expect(CheckInFlow.step(before: .breathing, for: day) == nil)
        #expect(CheckInFlow.step(after: .review, for: day) == nil)
    }

    @Test("A card counts as answered only when its own question is")
    func answered() {
        var draft = blank
        #expect(!CheckInFlow.isAnswered(.breathing, in: draft) && CheckInFlow.isAnswered(.review, in: draft))
        CheckInFlow.answer(.daytime, in: &draft)
        #expect(CheckInFlow.isAnswered(.breathing, in: draft) && !CheckInFlow.isAnswered(.severity, in: draft))
        draft.windowsOpen = "no"
        #expect(CheckInFlow.isAnswered(.windows, in: draft) && !CheckInFlow.isAnswered(.medication, in: draft))
    }
}
