import SwiftUI
import RespiratoryKit

/// The check-in as one question per card. Choose an answer, then Next; Back and Skip are always
/// there, a skipped question stays unanswered, and the dots fill as the day's check-in takes shape.
struct CheckInFlowView: View {
    @Bindable var model: CheckInViewModel
    let target: CheckInViewModel.Target
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if DEBUG
    @Environment(\.openRoute) private var openRoute
    #endif
    @State private var hasBegun = false
    @State private var step = CheckInFlow.Step.breathing
    @State private var isDone = false

    var body: some View {
        VStack(spacing: 0) {
            if isDone {
                CheckInDoneView(target: target) { dismiss() }
            } else {
                ProgressDots(steps: CheckInFlow.steps(for: model.draft), current: step)
                ScrollView {
                    card
                        .padding()
                        .id(step)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                removal: .opacity))
                }
                bottomBar
            }
        }
        .navigationTitle(target == .today ? "Today" : "Yesterday")
        .navigationBarTitleDisplayMode(.inline)
        // One job on screen: no tab bar, and one clear way out ("Back" below is for the previous card).
        .toolbar(.hidden, for: .tabBar)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", systemImage: "xmark") { dismiss() }
            }
            #if DEBUG
            if AppServices.isUITesting && UserDefaults.standard.bool(forKey: "uiTestDraftSwitch") {
                ToolbarItem(placement: .primaryAction) {
                    Button("Switch to History for test") { openRoute(.trends) }
                        .accessibilityIdentifier("uiTestDraftSwitch")
                }
            }
            #endif
        }
        .onAppear {
            guard !hasBegun else { return }
            hasBegun = true
            model.begin(target)
        }
        .animation(reduceMotion ? nil : .snappy, value: step)
        .animation(reduceMotion ? nil : .snappy, value: isDone)
        .sensoryFeedback(.selection, trigger: model.draft)
        .sensoryFeedback(.success, trigger: isDone) { _, done in done }
    }

    private var dayWord: String { target == .today ? "today" : "yesterday" }

    @ViewBuilder private var card: some View {
        switch step {
        case .breathing:
            QuestionCard("How was your breathing \(dayWord)?", hint: "Breathing or allergy symptoms, day or night.") {
                ForEach(CheckInFlow.Breathing.allCases, id: \.self) { answer in
                    AnswerButton(title: CheckInLabels.breathing(answer),
                                 isSelected: CheckInFlow.breathing(of: model.draft) == answer) {
                        CheckInFlow.answer(answer, in: &model.draft)

                    }
                }
            }
        case .severity:
            QuestionCard("How bad was it at worst?") {
                choices(CheckInQuestionSet.Severity.allCases.map { ($0.rawValue, CheckInLabels.severity($0)) },
                        selection: $model.draft.daytimeSeverity)
            }
        case .symptoms:
            QuestionCard("Which ones?", hint: "Pick any that apply, then Next.") {
                FlowLayout {
                    ForEach(CheckInQuestionSet.symptoms, id: \.self) { symptom in
                        SymptomChip(title: CheckInLabels.symptom(symptom),
                                    isSelected: model.draft.symptomsSelected.contains(symptom)) { model.toggleSymptom(symptom) }
                    }
                }
            }
        case .night:
            QuestionCard("Did cough or breathing wake you the night before?") {
                choices([(true, "Yes"), (false, "No")], selection: $model.draft.nightWaking)
            }
        case .limited:
            QuestionCard("Did symptoms limit what you did?") {
                choices([(true, "Yes"), (false, "No")], selection: $model.draft.activityLimited)
            }
        case .rescue:
            QuestionCard("Rescue inhaler uses \(dayWord)?") {
                choices([(0, "None"), (1, "1"), (2, "2"), (3, "3")], selection: $model.draft.rescueInhalerUses)
                Stepper(value: Binding(get: { model.draft.rescueInhalerUses ?? 3 }, set: { model.draft.rescueInhalerUses = $0 }),
                        in: CheckInQuestionSet.rescueUsesRange) {
                    Text((model.draft.rescueInhalerUses ?? 0) > 3 ? "\(model.draft.rescueInhalerUses ?? 0) uses" : "More than 3")
                }
            }
        case .medication:
            QuestionCard("Took your controller (preventer) medication \(dayWord) as prescribed?") {
                if model.canReusePreviousAnswers, let previous = model.previousStableAnswers {
                    AnswerButton(title: "Same as \(DayKeys.display(previous.dayKey, style: .dateTime.weekday(.wide)))",
                                 detail: CheckInLabels.stable(previous), isSelected: false) {
                        model.reusePreviousAnswers()
                    }
                    Divider().padding(.vertical, 4)
                }
                choices(CheckInQuestionSet.ControllerAdherence.allCases.map { ($0.rawValue, CheckInLabels.adherence($0)) },
                        selection: $model.draft.controllerAdherence)
            }
        case .windows:
            QuestionCard("Windows open at home?") {
                choices(CheckInQuestionSet.WindowsOpen.allCases.map { ($0.rawValue, CheckInLabels.windows($0)) },
                        selection: $model.draft.windowsOpen)
            }
        case .peakFlow:
            QuestionCard("Peak flow", hint: "Only if you use a peak-flow meter. Skip otherwise.") {
                PeakFlowField(value: model.draft.peakFlowLPM) { model.setPeakFlow($0) }
            }
        case .review:
            CheckInReview(model: model, target: target) {
                Task { if await model.save() { isDone = true } }
            }
        }
    }

    /// One answer per button; tapping the chosen one again clears it back to unanswered.
    private func choices<Value: Hashable>(_ options: [(Value, String)], selection: Binding<Value?>) -> some View {
        ForEach(options, id: \.0) { value, title in
            AnswerButton(title: title, isSelected: selection.wrappedValue == value) {
                if selection.wrappedValue == value {
                    selection.wrappedValue = nil
                } else {
                    selection.wrappedValue = value

                }
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            if let previous = CheckInFlow.step(before: step, for: model.draft) {
                Button("Back", systemImage: "chevron.left") { step = previous }
            }
            Spacer()
            if step != .review {
                let steps = CheckInFlow.steps(for: model.draft)
                Button(CheckInFlow.isAnswered(step, in: model.draft) ? "Next" : "Skip") { advance() }
                    .buttonStyle(.borderedProminent)
                .foregroundStyle(AirQStyle.onAccent)
                    .controlSize(.large)
                    .frame(minWidth: 88, minHeight: 44)
                    .accessibilityHint("Question \((steps.firstIndex(of: step) ?? 0) + 1) of \(steps.count)")
            }
        }
        .padding()
        .background(.bar)
    }

    private func advance() {
        if let next = CheckInFlow.step(after: step, for: model.draft) { step = next }
    }


}

private struct QuestionCard<Answers: View>: View {
    let question: String
    var hint: String?
    @ViewBuilder let answers: () -> Answers

    init(_ question: String, hint: String? = nil, @ViewBuilder answers: @escaping () -> Answers) {
        self.question = question
        self.hint = hint
        self.answers = answers
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(question).font(.title2.weight(.semibold))
            if let hint { Text(hint).font(.subheadline).foregroundStyle(.secondary) }
            answers()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One dot per card: filled up to the current one. The number of dots follows the answers.
private struct ProgressDots: View {
    let steps: [CheckInFlow.Step]
    let current: CheckInFlow.Step

    var body: some View {
        let index = steps.firstIndex(of: current) ?? 0
        HStack(spacing: 6) {
            ForEach(Array(steps.enumerated()), id: \.element) { offset, _ in
                Capsule()
                    .fill(offset <= index ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                    .frame(width: offset == index ? 22 : 8, height: 8)
            }
        }
        .padding(.vertical, 12)
        // Decorative: VoiceOver hears the position on the Next/Skip button instead of a separate stop.
        .accessibilityHidden(true)
    }
}

/// The last card: what will be saved, in words, and the one Save button.
private struct CheckInReview: View {
    let model: CheckInViewModel
    let target: CheckInViewModel.Target
    let save: () -> Void

    var body: some View {
        let draft = model.draft
        VStack(alignment: .leading, spacing: 14) {
            Text("Ready to save").font(.title2.weight(.semibold))
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Symptoms", value: draft.daytimeSymptoms == nil && draft.nightWaking == nil
                               ? "Not answered" : CheckInLabels.summary(draft))
                LabeledContent("Controller medication", value: draft.controllerAdherence
                    .flatMap(CheckInQuestionSet.ControllerAdherence.init).map(CheckInLabels.adherence) ?? "Not answered")
                LabeledContent("Windows open", value: draft.windowsOpen
                    .flatMap(CheckInQuestionSet.WindowsOpen.init).map(CheckInLabels.windows) ?? "Not answered")
                if let peakFlow = draft.peakFlowLPM { LabeledContent("Peak flow", value: "\(peakFlow) L/min") }
            }
            .font(.subheadline)
            Text("Unanswered questions stay unanswered; they're never counted as \"no\".")
                .font(.footnote).foregroundStyle(.secondary)
            if let message = model.errorMessage { Text(message).foregroundStyle(.red) }
            Button(action: save) {
                Text("Save \(target == .today ? "today" : "yesterday")").font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
                .foregroundStyle(AirQStyle.onAccent)
            .disabled(model.isSaving || draft.answeredCount == 0 && draft.peakFlowLPM == nil)
        }
    }
}

private struct CheckInDoneView: View {
    let target: CheckInViewModel.Target
    let done: () -> Void
    @State private var appeared = false
    @Environment(\.openTab) private var openTab

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: appeared)
                .accessibilityHidden(true)
            Text(target == .today ? "Today is logged" : "Yesterday is logged").font(.title2.weight(.semibold))
            Text("It's in History now, next to the air that day.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button(action: done) { Text("Done").frame(maxWidth: .infinity, minHeight: 52) }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(AirQStyle.onAccent)
            Button("See it in History", systemImage: "chart.xyaxis.line") {
                done()
                openTab(.trends)
            }
        }
        .padding()
        .onAppear { appeared = true }
    }
}
