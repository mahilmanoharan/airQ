import Foundation

/// The check-in as one question per card. Which cards come depends on the answers so far, so nobody is
/// asked about severity or rescue uses on a day they said had no symptoms. Every card can be skipped; a
/// skipped question stays unanswered.
public enum CheckInFlow {
    public enum Step: String, Sendable, CaseIterable {
        case breathing, severity, symptoms, night, limited, rescue, medication, windows, peakFlow, review
    }

    /// The first card's answer, read back from the draft (nil = not answered in a way the card can show).
    public enum Breathing: String, Sendable, CaseIterable {
        /// Every symptom question answered "none" (`CheckInDraft.answerNoSymptoms`). Not `none`, which
        /// would read as `Optional.none` wherever a `Breathing?` is expected.
        case noSymptoms
        case daytime
        /// No daytime symptoms, but woke at night.
        case nightOnly
    }

    public static func breathing(of draft: CheckInDraft) -> Breathing? {
        if draft.daytimeSymptoms == true { return .daytime }
        if draft.daytimeSymptoms == false, draft.nightWaking == true { return .nightOnly }
        var none = CheckInDraft(dayKey: draft.dayKey)
        none.answerNoSymptoms()
        let symptomAnswers = (draft.daytimeSymptoms, draft.nightWaking, draft.rescueInhalerUses, draft.activityLimited)
        return symptomAnswers == (none.daytimeSymptoms, none.nightWaking, none.rescueInhalerUses, none.activityLimited)
            && draft.symptomsSelected.isEmpty ? .noSymptoms : nil
    }

    /// Sets the first card's answer. "No symptoms" answers every symptom question; the other two answer the
    /// daytime question (and night waking for night only) and leave the follow-up cards to ask the rest.
    public static func answer(_ breathing: Breathing, in draft: inout CheckInDraft) {
        switch breathing {
        case .noSymptoms:
            draft.answerNoSymptoms()
        case .daytime:
            draft.daytimeSymptoms = true
        case .nightOnly:
            draft.daytimeSymptoms = false
            draft.daytimeSeverity = nil
            draft.symptomsSelected = []
            draft.nightWaking = true
        }
    }

    /// Whether the card's question has an answer (the review card always counts as answered).
    public static func isAnswered(_ step: Step, in draft: CheckInDraft) -> Bool {
        switch step {
        case .breathing: breathing(of: draft) != nil
        case .severity: draft.daytimeSeverity != nil
        case .symptoms: !draft.symptomsSelected.isEmpty
        case .night: draft.nightWaking != nil
        case .limited: draft.activityLimited != nil
        case .rescue: draft.rescueInhalerUses != nil
        case .medication: draft.controllerAdherence != nil
        case .windows: draft.windowsOpen != nil
        case .peakFlow: draft.peakFlowLPM != nil
        case .review: true
        }
    }

    public static func steps(for draft: CheckInDraft) -> [Step] {
        var steps: [Step] = [.breathing]
        switch breathing(of: draft) {
        case .daytime?: steps += [.severity, .symptoms, .night, .limited, .rescue]
        case .nightOnly?: steps += [.limited, .rescue]
        case .noSymptoms?, nil: break
        }
        return steps + [.medication, .windows, .peakFlow, .review]
    }

    /// The card after `step` for this draft (the flow can change under it: answering the first card
    /// adds or removes follow-ups). Nil at the end.
    public static func step(after step: Step, for draft: CheckInDraft) -> Step? {
        let steps = steps(for: draft)
        guard let index = steps.firstIndex(of: step) else { return steps.first }
        return steps.indices.contains(index + 1) ? steps[index + 1] : nil
    }

    public static func step(before step: Step, for draft: CheckInDraft) -> Step? {
        let steps = steps(for: draft)
        guard let index = steps.firstIndex(of: step), index > 0 else { return nil }
        return steps[index - 1]
    }
}
