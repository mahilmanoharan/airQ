import SwiftUI
import AirQualityKit
import RespiratoryKit
import WidgetKit
import SwiftData
import UserNotifications

extension EnvironmentValues {
    @Entry var detectionStore: DetectionStore? = nil
    @Entry var recordStore: RecordStore? = nil
    @Entry var respiratoryContainer: ModelContainer? = nil
    @Entry var detectionStoreError: String? = nil
    /// Its `revision` increments after each environmental attempt is saved, so record-backed views can reload.
    /// The recorder itself is passed (not the number) so only views that read `revision` re-render.
    @Entry var environmentRecorder: EnvironmentRecorder? = nil
    /// One check-in model for the whole app, so the tab's badge and the Check-in tab agree.
    @Entry var checkInModel: CheckInViewModel? = nil
}

@main
struct airQApp: App {
    init() {
        UNUserNotificationCenter.current().delegate = AlertTapRouter.shared
        // Controls (Control Center, Lock Screen, Action button) open a screen through the same router as Siri.
        ControlNavigation.open = { screen in
            NavigationRouter.shared.pendingPath = AppRoute(rawValue: screen.rawValue).map { [$0] } ?? []
        }
        assert(ControlScreen.allCases.allSatisfy { $0 == .dashboard || AppRoute(rawValue: $0.rawValue) != nil },
               "Every control screen must be an AppRoute (or the dashboard)")
    }

    var body: some Scene {
        WindowGroup { AppRootView() }
            .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) { await BackgroundRefresh.run() }
    }
}

private struct AppRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var dashboard: DashboardViewModel?
    @State private var services: RecordServices?
    @State private var store: DetectionStore?
    @State private var storeError: String?
    @State private var container: ModelContainer?
    @State private var checkIn: CheckInViewModel?
    @State private var tab: AppTab
    @State private var airPath: [AppRoute] = []
    @State private var listenPath: [ListenDestination] = []
    @State private var morePath: [AppRoute]
    @State private var reportPath: [AppRoute]
    @State private var recordActivation = 0
    @AppStorage("historyPeriodDays") private var historyPeriod = HistoryPeriod.month
    /// Decided once per launch, so tapping "Get started" ends it even if a debug flag forced it.
    @State private var isWelcoming = WelcomeView.shouldShow()
    /// The message the person dismissed; a different message shows again.
    @State private var dismissedError: String?

    init() {
        let initial = TabDestination(AppRoute.initialPath)
        _tab = State(initialValue: initial.tab)
        _morePath = State(initialValue: initial.tab == .more ? initial.path : [])
        _airPath = State(initialValue: initial.tab == .air ? initial.path : [])
        _reportPath = State(initialValue: initial.tab == .report ? initial.path : [])
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Today", systemImage: "aqi.medium", value: AppTab.air) {
                NavigationStack(path: $airPath) {
                    Group {
                        if isWelcoming {
                            // Only this tab: the rest of the app is usable, and the location prompt waits for it.
                            WelcomeView {
                                WelcomeView.markSeen()
                                isWelcoming = false
                            }
                        } else if let dashboard {
                            DashboardView(model: dashboard)
                        } else {
                            ProgressView("Starting airQ…")
                        }
                    }
                    .navigationDestination(for: AppRoute.self) { $0.destination }
                }
                .modifier(recordingErrorBar)
            }
            Tab("Listen", systemImage: "waveform", value: AppTab.listen) {
                NavigationStack(path: $listenPath) { AppRoute.listen.destination }
                    .id(AppServices.shared.eraseRevision)
                    .modifier(recordingErrorBar)
            }
            Tab("History", systemImage: "chart.xyaxis.line", value: AppTab.trends) {
                NavigationStack { AppRoute.trends.destination }.modifier(recordingErrorBar)
            }
            Tab("Report", systemImage: "doc.text", value: AppTab.report) {
                NavigationStack(path: $reportPath) {
                    AppRoute.report.destination.navigationDestination(for: AppRoute.self) { $0.destination }
                }
                .modifier(recordingErrorBar)
            }
            Tab("More", systemImage: "ellipsis", value: AppTab.more) {
                NavigationStack(path: $morePath) {
                    MoreView().navigationDestination(for: AppRoute.self) { $0.destination }
                }
                .modifier(recordingErrorBar)
            }
        }
        .tint(AirQStyle.accent)
        .disabled(AppServices.shared.isErasing)
        .environment(\.selectedTab, tab)
        .environment(\.openTab) { tab = $0 }
        .environment(\.openRoute) { open([$0]) }
        .environment(\.historyPeriod, historyPeriod)
        .environment(\.setHistoryPeriod) { historyPeriod = $0 }
        .environment(\.recordRevision, RecordRevision(provider: services?.recorder.revision ?? 0,
                                                       checkIn: checkIn?.lastSavedAt, activation: recordActivation))
        .environment(\.detectionStore, store)
        .environment(\.recordStore, services?.recordStore)
        .environment(\.respiratoryContainer, container)
        .environment(\.detectionStoreError, storeError)
        .environment(\.environmentRecorder, services?.recorder)
        .environment(\.checkInModel, checkIn)
        .task {
            #if DEBUG
            // Simulator verification of the Siri/Shortcuts entry, before any screen gets the store: `-runLogNoSymptoms YES`.
            if UserDefaults.standard.bool(forKey: "runLogNoSymptoms") { _ = try? await LogNoSymptomsIntent().perform() }
            #endif
            await start()
            #if DEBUG
            // Simulator verification of the background path: `-runBackgroundRefresh YES`.
            if UserDefaults.standard.bool(forKey: "runBackgroundRefresh") { await BackgroundRefresh.run() }
            #endif
        }
        .onOpenURL { url in
            if let linked = AppRoute.path(for: url) { open(linked) }
        }
        .onChange(of: NavigationRouter.shared.pendingPath, initial: true) { _, pending in
            guard let pending else { return }
            open(pending)
            NavigationRouter.shared.pendingPath = nil
        }
        .onChange(of: dashboard?.snapshot?.lastUpdated, initial: true) {
            guard scenePhase == .active, !AppServices.shared.isErasing,
                  let coordinate = dashboard?.snapshot?.coordinate, let services else { return }
            services.collectHistory(at: coordinate)
        }
        .onChange(of: AppServices.shared.eraseRevision) {
            // Drop prior drafts and destinations that could still hold pre-erase results.
            airPath = []
            listenPath = []
            reportPath = []
            if let records = services?.recordStore {
                checkIn = CheckInViewModel(store: records, appVersion: AppVersion.current)
            }
            recordActivation += 1
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                services?.cancelCollection()
                BackgroundRefresh.schedule()
            }
            guard phase == .active, !isWelcoming, !AppServices.shared.isErasing else { return }
            recordActivation += 1
            // Returning from Settings or after a while: a fresh same-place cache means no request.
            // (Not during the welcome: the location prompt must come after it.)
            if let dashboard { Task { await dashboard.load() } }
            // A new day, or a Siri entry made in the background, updates today's check-in.
            if let checkIn { Task { await checkIn.load() } }
            guard let services else { return }
            Task {
                guard !AppServices.shared.isErasing else { return }
                await services.recorder.markToday()
            }
        }
    }

    /// Pinned under every tab's screens until dismissed (and not over the welcome).
    private var recordingErrorBar: RecordingErrorInset {
        RecordingErrorInset(message: isWelcoming ? nil : services?.recorder.lastError, dismissed: $dismissedError)
    }

    /// A link, Siri, a control or an alert tap opens the requested screen in its tab.
    private func open(_ linked: [AppRoute]) {
        guard !AppServices.shared.isErasing else { return }
        let destination = TabDestination(linked)
        tab = destination.tab
        switch destination.tab {
        case .air: airPath = destination.path
        case .listen: listenPath = []
        case .trends: break
        case .report: reportPath = destination.path
        case .more: morePath = destination.path
        }
    }

    private func start() async {
        guard dashboard == nil else { return }
        let prepared = await AppServices.shared.prepare()
        store = prepared.store
        container = prepared.container
        storeError = prepared.storeError
        services = prepared.services
        dashboard = prepared.dashboard
        if let records = prepared.services?.recordStore {
            let model = CheckInViewModel(store: records, appVersion: AppVersion.current)
            checkIn = model
            await model.load()
        }
        // Only the foreground marks a day (a headless background launch is not a chance to record),
        // and it needn't hold up the first reading.
        await prepared.services?.recorder.markToday()
    }
}

/// Shows `RecordingErrorBar` above the tab bar while there's a message the person hasn't dismissed.
private struct RecordingErrorInset: ViewModifier {
    let message: String?
    @Binding var dismissed: String?

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom) {
            if let message, message != dismissed {
                RecordingErrorBar(message: message) { dismissed = message }
            }
        }
    }
}

/// A recording failure (an observation or today's day row couldn't be saved), pinned above the home indicator
/// on every screen until dismissed.
private struct RecordingErrorBar: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Dismiss", systemImage: "xmark.circle.fill", action: dismiss)
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.bar)
    }
}

/// Trends need the record store; detections draw only if their store also opened.
struct TrendsDestinationView: View {
    @Environment(\.detectionStore) private var detections

    var body: some View {
        StoreGate(\.recordStore) { TrendsView(records: $0, detections: detections) }
    }
}

/// Shows a respiratory screen once the store it needs (read from the environment) has opened, or the
/// shared storage failure. A failure disables these screens only; the dashboard keeps working and no
/// history is deleted.
struct StoreGate<Store, Content: View>: View {
    @Environment private var store: Store?
    @Environment(\.detectionStoreError) private var storeError
    private let content: (Store) -> Content

    init(_ store: KeyPath<EnvironmentValues, Store?>, @ViewBuilder content: @escaping (Store) -> Content) {
        _store = Environment(store)
        self.content = content
    }

    var body: some View {
        if let store {
            content(store)
        } else if let storeError {
            ContentUnavailableView("History unavailable", systemImage: "externaldrive.badge.exclamationmark",
                                   description: Text("\(storeError) Restart airQ to retry; existing history has not been deleted."))
        } else {
            ProgressView("Opening health records…")
        }
    }
}
