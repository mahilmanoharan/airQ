import AppIntents
import RespiratoryKit

/// "No symptoms today" from Siri, Shortcuts or the Action button, without opening the form. Runs in the app's
/// process on the one shared record container; it never replaces a check-in that records symptoms.
struct LogNoSymptomsIntent: AppIntent {
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let title: LocalizedStringResource = "Log No Symptoms Today"
    static let description = IntentDescription(
        "Saves today's check-in as no symptoms, keeping any medication, windows or peak-flow answers. It won't change a check-in that records symptoms.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let records = await AppServices.shared.prepare().services?.recordStore else {
            return .result(dialog: "airQ couldn't open its health records, so nothing was saved.")
        }
        guard !AppServices.shared.isErasing else {
            return .result(dialog: "airQ is erasing its records. Try your check-in again when it finishes.")
        }
        let outcome = try await records.logNoSymptoms(at: .now, timeZone: .current, appVersion: AppVersion.current)
        let dialog: IntentDialog = switch outcome {
        case .saved: "Saved: no symptoms today. Open the check-in to add anything else."
        case .alreadyLogged: "Today's check-in already says no symptoms."
        case .todayHasSymptoms: "Today's check-in records symptoms, so nothing was changed. Open the check-in to edit it."
        }
        return .result(dialog: dialog)
    }
}
