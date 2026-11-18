import RespiratoryKit

enum CheckInLabels {
    static func symptom(_ raw: String) -> String {
        switch raw {
        case "cough": "Cough"
        case "wheeze": "Wheeze"
        case "shortnessOfBreath": "Short of breath"
        case "chestTightness": "Chest tightness"
        case "sneezing": "Sneezing"
        case "runnyOrBlockedNose": "Runny/blocked nose"
        case "itchyEyes": "Itchy eyes"
        case "soreThroat": "Sore throat"
        default: raw
        }
    }

    static func severity(_ severity: CheckInQuestionSet.Severity) -> String {
        switch severity {
        case .mild: "Mild"
        case .moderate: "Moderate"
        case .severe: "Severe"
        }
    }

    static func adherence(_ answer: CheckInQuestionSet.ControllerAdherence) -> String {
        switch answer {
        case .yes: "Yes"
        case .partly: "Missed some"
        case .no: "No"
        case .notPrescribed: "None prescribed"
        }
    }

    /// "Controller: None prescribed · Windows: No", only the parts that were answered.
    static func stable(_ answers: CheckInViewModel.StableAnswers) -> String {
        [answers.controllerAdherence.flatMap(CheckInQuestionSet.ControllerAdherence.init).map { "Controller: \(adherence($0))" },
         answers.windowsOpen.flatMap(CheckInQuestionSet.WindowsOpen.init).map { "Windows open: \(windows($0))" }]
            .compactMap(\.self).joined(separator: " · ")
    }

    /// How the check-in's first card reads for today or yesterday.
    static func breathing(_ answer: CheckInFlow.Breathing) -> String {
        switch answer {
        case .noSymptoms: "No symptoms"
        case .daytime: "Symptoms during the day"
        case .nightOnly: "Only at night"
        }
    }

    static func windows(_ answer: CheckInQuestionSet.WindowsOpen) -> String {
        switch answer {
        case .yes: "Yes"
        case .no: "No"
        case .partly: "Partly"
        }
    }

    static func summary(_ draft: CheckInDraft) -> String {
        switch draft.daytimeSymptoms {
        case false? where draft.nightWaking == true: return "Woke at night"
        case false?: return "No symptoms"
        case nil: return draft.answeredCount == 0 ? "Peak flow only" : "Partly answered"
        case true?:
            let severity = draft.daytimeSeverity.flatMap(CheckInQuestionSet.Severity.init).map(severity) ?? "Symptoms"
            let chips = draft.symptomsSelected.map(symptom).joined(separator: ", ")
            return chips.isEmpty ? severity : "\(severity): \(chips)"
        }
    }
}
