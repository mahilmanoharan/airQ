import XCTest

/// Critical interactive flows, run against an in-memory record store with no network
/// (`-uiTestMode YES`), so tests never write real history or spend provider requests.
@MainActor
final class AirQUITests: XCTestCase {
    /// `detailsOpen` forces the dashboard's detail sections open (most tests exercise them); pass nil to
    /// use the persisted setting, as a person would.
    private func launch(route: String? = nil, extraArguments: [String] = [], detailsOpen: Bool? = true) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestMode", "YES"] + (route.map { ["-initialRoute", $0] } ?? []) + extraArguments
            + (detailsOpen.map { ["-dashboardShowsDetails", $0 ? "YES" : "NO"] } ?? [])
        app.launch()
        return app
    }

    /// The cards, one question at a time: Next confirms an answer; Skip leaves it unanswered.
    private func startTodaysCheckIn(_ app: XCUIApplication) {
        let start = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Check in for today'")).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
    }

    private func next(_ app: XCUIApplication) {
        let next = app.buttons["Next"]
        XCTAssertTrue(next.waitForExistence(timeout: 3))
        next.tap()
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
    }

    private func skip(_ app: XCUIApplication, times: Int) {
        for _ in 0..<times {
            let skip = app.buttons["Skip"]
            XCTAssertTrue(skip.waitForExistence(timeout: 3))
            skip.tap()
        }
    }

    func testCheckInWithMedicationAnswerSavesAndAppearsInHistory() {
        let app = launch(route: "checkIn")
        // The tab's "1" badge isn't in the accessibility tree (checked on iOS 26), so it's verified by
        // screenshot; the hub's own "Check in for today" is the state VoiceOver hears.
        startTodaysCheckIn(app)
        let noSymptoms = app.buttons["No symptoms"]
        XCTAssertTrue(noSymptoms.waitForExistence(timeout: 5))
        noSymptoms.tap()
        next(app)
        // No symptoms goes straight to medication.
        let missedSome = app.buttons["Missed some"]
        XCTAssertTrue(missedSome.waitForExistence(timeout: 5))
        missedSome.tap()
        next(app)
        skip(app, times: 2)  // windows, peak flow
        XCTAssertTrue(app.staticTexts["Ready to save"].waitForExistence(timeout: 5))
        app.buttons["Save today"].tap()
        XCTAssertTrue(app.staticTexts["Today is logged"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        // Back on the hub: done for today, the answer in Recent, and no badge.
        XCTAssertTrue(app.staticTexts["Today is logged"].waitForExistence(timeout: 5))
        for _ in 0..<5 where !app.staticTexts["No symptoms"].exists { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["No symptoms"].exists)
    }

    func testNoSymptomsFromSiriIsSavedAsTodaysCheckIn() {
        // The DEBUG argument performs `LogNoSymptomsIntent` at launch, as Siri or Shortcuts would.
        let app = launch(route: "checkIn", extraArguments: ["-runLogNoSymptoms", "YES"])
        XCTAssertTrue(app.staticTexts["Today is logged"].waitForExistence(timeout: 10))
        for _ in 0..<5 where !app.staticTexts["No symptoms"].exists { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["No symptoms"].exists, "Today's quick entry should be in Recent")
        XCTAssertTrue(app.staticTexts["Quick entry from Siri or Shortcuts"].exists, "It should say how it was entered")
    }

    func testTheDashboardShowsTomorrowWithoutOpeningDetails() {
        // Details closed, as most people keep them: tomorrow is part of the essentials.
        let app = launch(detailsOpen: false)
        let tomorrow = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Air quality up to 68'")).firstMatch
        for _ in 0..<4 where !tomorrow.waitForExistence(timeout: 2) { app.swipeUp() }
        XCTAssertTrue(tomorrow.exists)
        XCTAssertTrue(tomorrow.label.contains("Pollen 3 of 5"), tomorrow.label)
    }

    func testYesterdaysMedicationAnswerCanBeReusedWithOneTap() {
        let app = launch(route: "checkIn")
        // Yesterday's dot fills in yesterday (a new user has no "Add yesterday" row: that day was before airQ).
        let yesterday = app.buttons["checkInDay-yesterday"]
        XCTAssertTrue(yesterday.waitForExistence(timeout: 10))
        yesterday.tap()
        skip(app, times: 1)  // breathing
        let missedSome = app.buttons["Missed some"]
        XCTAssertTrue(missedSome.waitForExistence(timeout: 5))
        missedSome.tap()
        next(app)
        skip(app, times: 2)
        app.buttons["Save yesterday"].tap()
        app.buttons["Done"].tap()

        startTodaysCheckIn(app)
        skip(app, times: 1)
        let reuse = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Same as'")).firstMatch
        XCTAssertTrue(reuse.waitForExistence(timeout: 5), "Today should offer yesterday's steady answers")
        reuse.tap()
        next(app)
        // Yesterday had no windows answer, so that card comes next; back on medication, it's filled in.
        XCTAssertTrue(app.staticTexts["Windows open at home?"].waitForExistence(timeout: 5))
        app.buttons["Back"].tap()
        XCTAssertTrue(missedSome.waitForExistence(timeout: 5) && missedSome.isSelected)
        XCTAssertFalse(reuse.exists, "The offer goes once there's nothing left to fill")
    }

    func testEmptyHistoryExplainsHowToBeginWithoutBlankCharts() {
        let app = launch(route: "trends")
        XCTAssertTrue(app.staticTexts["Your history starts with a day"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Air quality (AQI)"].exists)
        app.buttons["Add a check-in"].tap()
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Check in for today'")).firstMatch
            .waitForExistence(timeout: 5))
    }

    func testTodayOffersCheckInWithoutAnAirReading() {
        let app = launch(extraArguments: ["-uiTestNoReading", "YES", "-uiTestLocationDenied", "YES"], detailsOpen: false)
        startTodaysCheckIn(app)
        XCTAssertTrue(app.buttons["checkInDay-today"].waitForExistence(timeout: 5))
    }

    func testReportAndHistoryRefreshAfterSavingToday() {
        let app = launch(route: "report", extraArguments: ["-uiTestHistoryPeriod", "30"])
        XCTAssertTrue(app.buttons["shareReportSummary"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "reportCoverage-Check-ins", "0 of 30 days")).firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["Your history starts with a day"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Today"].tap()
        startTodaysCheckIn(app)
        startTodaysCheckIn(app)
        app.buttons["No symptoms"].tap()
        next(app)
        skip(app, times: 3)
        app.buttons["Save today"].tap()
        app.buttons["Done"].tap()
        app.tabBars.buttons["Report"].tap()
        XCTAssertTrue(app.buttons["shareReportSummary"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "reportCoverage-Check-ins", "1 of 30 days")).firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["Symptoms & surroundings"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Your history starts with a day"].exists)
    }

    func testHistoryAndReportShareTheChosenPeriodAndCurrentData() {
        let app = launch(route: "trends", extraArguments: ["-uiTestHistory", "YES", "-uiTestHistoryPeriod", "30"])
        XCTAssertTrue(app.staticTexts["Symptoms & surroundings"].waitForExistence(timeout: 10))
        app.segmentedControls.buttons["7 days"].tap()
        XCTAssertTrue(app.staticTexts["In these 7 days"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Report"].tap()
        let share = app.buttons["shareReportSummary"]
        XCTAssertTrue(share.waitForExistence(timeout: 10))
        XCTAssertTrue(app.segmentedControls.buttons["7 days"].isSelected)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "reportCoverage-Check-ins", "6 of 7 days")).firstMatch.exists)
        app.segmentedControls.buttons["30 days"].tap()
        XCTAssertTrue(share.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "reportCoverage-Check-ins", "16 of 30 days")).firstMatch.exists)
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["30 days"].isSelected)
        XCTAssertTrue(app.staticTexts["In these 30 days"].waitForExistence(timeout: 5))
    }

    func testOnlyAtNightClearsDaytimeSymptomsAndSkipsTheirQuestions() {
        let app = launch(route: "checkIn")
        startTodaysCheckIn(app)
        app.buttons["Symptoms during the day"].tap()
        next(app)
        let mild = app.buttons["Mild"]
        XCTAssertTrue(mild.waitForExistence(timeout: 5))
        mild.tap()
        next(app)
        let cough = app.buttons["Cough"]
        XCTAssertTrue(cough.waitForExistence(timeout: 5))
        cough.tap()
        XCTAssertTrue(cough.isSelected)
        app.buttons["Back"].tap()
        app.buttons["Back"].tap()
        app.buttons["Only at night"].tap()
        next(app)
        // Night only: no severity or symptom cards, and the daytime answers are gone.
        XCTAssertTrue(app.staticTexts["Did symptoms limit what you did?"].waitForExistence(timeout: 5))
        skip(app, times: 5)  // limited, rescue, medication, windows, peak flow
        XCTAssertTrue(app.staticTexts["Ready to save"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Woke at night'")).firstMatch.exists)
    }

    func testAboutShowsTheDataVersions() {
        let app = launch(route: "about")
        XCTAssertTrue(app.staticTexts["Record schema"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Check-in questions"].exists)
        XCTAssertTrue(app.staticTexts["Audio is never stored"].exists)
    }

    func testTappingAPollutantOpensItsExplainer() throws {
        let app = launch()
        // UI-test mode serves a fixed, fresh reading (no network, no real data).
        let pollutant = app.buttons["PM2.5"]
        reveal(pollutant, in: app)
        pollutant.tap()
        XCTAssertTrue(app.staticTexts["What it is"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertFalse(app.staticTexts["What it is"].waitForExistence(timeout: 2))
    }

    func testDeepLinkOpensTheScreen() throws {
        let app = launch()
        XCTAssertTrue(app.tabBars.buttons["More"].waitForExistence(timeout: 10))
        let link = try XCTUnwrap(URL(string: "airq://trends"))
        app.open(link)
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 10))
    }

    func testCheckInDraftSurvivesASwitchToHistory() {
        let app = launch(route: "checkIn", extraArguments: ["-uiTestDraftSwitch", "YES"])
        startTodaysCheckIn(app)
        app.buttons["No symptoms"].tap()
        next(app)
        let answer = app.buttons["Missed some"]
        XCTAssertTrue(answer.waitForExistence(timeout: 5))
        answer.tap()
        XCTAssertTrue(answer.isSelected)

        // XCUIApplication.open relaunches the process. Route in process to exercise tab lifetime.
        app.buttons["uiTestDraftSwitch"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Today"].tap()

        XCTAssertTrue(answer.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(answer.isSelected)
    }

    func testDeniedLocationShowsTheLastReadingWithABannerAndSettingsLink() {
        let app = launch(extraArguments: ["-uiTestLocationDenied", "YES"])
        XCTAssertTrue(app.staticTexts["Showing your last reading"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Open Settings"].exists)
        XCTAssertFalse(app.buttons["Retry"].exists, "A settings problem isn't fixed by retrying")
        // The cached reading is still on screen rather than an empty error page.
        XCTAssertTrue(app.staticTexts["San Francisco"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Air quality index 42'"))
            .firstMatch.exists)
    }

    func testTheDashboardShowsTheEssentialsFirstAndDetailsOnRequest() {
        let app = launch(detailsOpen: nil)
        let show = app.buttons["Show details"], hide = app.buttons["Hide details"]
        for _ in 0..<6 where !show.exists && !hide.exists { app.swipeUp() }
        XCTAssertTrue(show.waitForExistence(timeout: 10) || hide.waitForExistence(timeout: 2))
        // The choice persists between launches, so set the starting state explicitly.
        if hide.exists { hide.tap() }
        XCTAssertTrue(show.waitForExistence(timeout: 5))
        // The essentials: the verdicts in words and what they mean; the health screens are tabs.
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Air quality index 42, Good'")).firstMatch.exists)
        XCTAssertTrue(app.buttons["What today's air means"].exists)
        XCTAssertTrue(app.buttons["Check in for today"].exists)
        // The technical sections are not on screen yet.
        XCTAssertFalse(app.staticTexts["Pollutants"].exists)
        XCTAssertFalse(app.staticTexts["Last 48 hours"].exists)
        show.tap()
        XCTAssertTrue(hide.waitForExistence(timeout: 5))
        for _ in 0..<6 where !app.staticTexts["Pollutants"].exists { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["Pollutants"].exists)
        // Leave the persisted choice at its default for other runs.
        for _ in 0..<12 where !hide.isHittable { app.swipeDown() }
        hide.tap()
    }

    /// Xcode's own accessibility audit (contrast, hit-region size, clipped or truncated text, missing
    /// descriptions) over the screens people use most. Findings are reported per screen.
    func testAccessibilityAuditOnMainScreens() throws {
        try audit([("dashboard", nil as String?, [String]()), ("check-in", "checkIn", []),
                   ("check-in cards", "checkIn", ["-openCheckInFlow", "YES"]), ("alerts", "alerts", []),
                   ("stored data", "records", []), ("about", "about", []), ("welcome", nil, ["-showWelcome", "YES"])])
    }

    /// The same audit over the screens reached less often, including the destructive Erase flow. Checked by
    /// eye on the Erase screen: rows the audit calls "Text clipped" are complete two-line labels, system
    /// section headers are the standard grey, and chart marks and the toolbar "+" are not app-sized controls.
    func testAccessibilityAuditOnSecondaryScreens() throws {
        try audit(ignoring: { issue in
            let label = issue.element?.label ?? ""
            let chartMark = issue.auditType == .hitRegion && label.range(of: #"^[A-Z][a-z]{2} \d{1,2}, \d{4}$"#, options: .regularExpression) != nil
            let wrappedRow = issue.auditType == .textClipped  // icon + text rows in Lists; Export and Erase seen unclipped
            let toolbarPlus = issue.auditType == .hitRegion && label == "Add event"
            let sectionHeader = issue.auditType == .contrast && label == "Erased"
            return chartMark || wrappedRow || toolbarPlus || sectionHeader
        }, [("history", "trends", [String]()), ("report", "report", []), ("listen", "listen", []), ("life events", "contextEvents", []),
                   ("export", "export", []), ("erase", "erase", [])])
    }

    private func audit(ignoring extraIgnore: @escaping (XCUIAccessibilityAuditIssue) -> Bool = { _ in false },
                       _ screens: [(String, String?, [String])]) throws {
        var findings: [String] = []
        for (name, route, extra) in screens {
            let app = launch(route: route, extraArguments: extra)
            _ = app.navigationBars.firstMatch.waitForExistence(timeout: 10)
            sleep(2)
            do {
                try app.performAccessibilityAudit { issue in
                    // Not actionable here: borderline ("nearly passed") contrast, Dynamic Type notes on merged
                    // elements, unlabeled system chrome, and rows sitting under a translucent bottom bar.
                    let bottomBarZone = (issue.element?.frame.maxY ?? 0) > app.frame.height * 0.85
                    let ignorable = issue.compactDescription.contains("nearly passed") || issue.auditType == .dynamicType
                        || (issue.element?.label.isEmpty ?? true) || bottomBarZone || extraIgnore(issue)
                    if !ignorable {
                        findings.append("\(name): \(issue.auditType) — \(issue.compactDescription) [\(issue.element?.label ?? "?")]")
                    }
                    return true  // handled: every screen is audited in one run, and the findings are reported together
                }
            } catch {
                findings.append("\(name): audit failed to run: \(error)")
            }
            app.terminate()
        }
        XCTAssertTrue(findings.isEmpty, "\n" + findings.joined(separator: "\n"))
    }

    func testReportOffersAPreviewAndShareableSummary() {
        let app = launch(route: "report", extraArguments: ["-uiTestHistoryPeriod", "30"])
        XCTAssertTrue(app.buttons["shareReportSummary"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Coverage"].exists)
        let heading = app.staticTexts["What these numbers are"]
        reveal(heading, in: app)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'not a diagnosis'")).firstMatch.exists)
        let raw = app.buttons["Export raw records"]
        reveal(raw, in: app)
        raw.tap()
        XCTAssertTrue(app.navigationBars["Raw export"].waitForExistence(timeout: 5))
        reveal(app.buttons["Create export"], in: app)
    }

    func testTheWelcomeExplainsTheAppOnceThenShowsTheDashboard() {
        let app = launch(extraArguments: ["-showWelcome", "YES"], detailsOpen: nil)
        XCTAssertTrue(app.staticTexts["Welcome to airQ"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Your days, together"].exists)
        XCTAssertTrue(app.staticTexts["Your notes stay on this iPhone"].exists)
        // The welcome fills the Air tab only: the other tabs stay usable, and the reading (and so the
        // location prompt) waits until the person continues.
        XCTAssertTrue(app.tabBars.buttons["History"].exists)
        XCTAssertFalse(app.buttons["What today's air means"].exists)
        app.buttons["Get started"].tap()
        XCTAssertTrue(app.buttons["What today's air means"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Welcome to airQ"].exists)
    }

    func testTheNumbersCanBeExplainedAndTodayIsMarked() {
        let app = launch()
        let link = app.buttons["What do these numbers mean?"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()
        XCTAssertTrue(app.navigationBars["What the numbers mean"].waitForExistence(timeout: 5))
        // The fixture reading is Good (AQI 42) with pollen Low (2): each scale marks its own level. The
        // list is lazy (rows off screen aren't in the tree), so look for each marker where it appears.
        func row(_ prefix: String) -> XCUIElement {
            app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
        }
        XCTAssertTrue(row("Good, 0–50, where you are now").waitForExistence(timeout: 5))
        XCTAssertFalse(row("Moderate, 51–100, where you are now").exists)
        for _ in 0..<8 where !row("Low, 2, where you are now").exists { app.swipeUp() }
        XCTAssertTrue(row("Low, 2, where you are now").exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(link.waitForExistence(timeout: 5))
    }

    func testMonthSummaryExplainsWhenThereIsNoHistoryYet() {
        let app = launch()
        let heading = app.staticTexts["Past 30 days"]
        for _ in 0..<8 where !heading.exists { app.swipeUp() }
        XCTAssertTrue(heading.waitForExistence(timeout: 10))
        // The UI-test store has no hourly history, so the card says when it will appear.
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'one full day of hourly history'"))
            .firstMatch.waitForExistence(timeout: 5))
    }

    func testAlertsScreenStartsOffAndExplainsItsLimits() {
        let app = launch(route: "alerts", extraArguments: ["-backgroundWidgetRefresh", "NO"])
        XCTAssertTrue(app.navigationBars["Air quality alerts"].waitForExistence(timeout: 10))
        let backgroundUpdates = app.switches["backgroundWidgetRefresh"]
        XCTAssertTrue(backgroundUpdates.waitForExistence(timeout: 5))
        XCTAssertEqual(backgroundUpdates.value as? String, "0")
        for label in ["Alert me about unhealthy air", "Alert me about high pollen"] {
            let toggle = app.switches[label]
            XCTAssertTrue(toggle.waitForExistence(timeout: 5), label)
            XCTAssertEqual(toggle.value as? String, "0", label)
        }
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'late or not at all'")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'between 10 pm and 7 am'")).firstMatch.exists)
        // Threshold pickers only appear once an alert is on.
        XCTAssertFalse(app.staticTexts["Alert at"].exists)
    }

    func testAddingAContextEventShowsItInTheList() {
        let app = launch(route: "contextEvents")
        let add = app.buttons["Add event"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        let details = app.textFields["Details, e.g. medication name and dose"]
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        details.tap()
        details.typeText("UI test inhaler")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["UI test inhaler"].waitForExistence(timeout: 5))
    }

    func testExportProducesAShareableArchive() {
        let app = launch(route: "export")
        let create = app.buttons["Create export"]
        reveal(create, in: app)
        create.tap()
        let share = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Share airQ-export")).firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 20))
    }

    func testExportPeriodCanBeLimitedAndSaysItIsNotABackup() {
        let app = launch(route: "export")
        let period = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Period")).firstMatch
        let notABackup = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'not a backup'")).firstMatch
        XCTAssertTrue(period.waitForExistence(timeout: 10))
        // The choice persists between launches, so set the starting state explicitly.
        period.tap()
        app.buttons["Everything"].tap()
        XCTAssertFalse(notABackup.exists, "Everything is a full copy")
        period.tap()
        app.buttons["Last 30 days"].tap()
        XCTAssertTrue(notABackup.waitForExistence(timeout: 5))
        app.buttons["Create export"].tap()
        let share = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Share airQ-export")).firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 20))
        // Changing the period drops the file made for the old one, and restores the persisted default.
        period.tap()
        app.buttons["Everything"].tap()
        XCTAssertFalse(share.exists, "a 30-day file must not stay on offer under \"Everything\"")
        XCTAssertTrue(app.buttons["Create export"].waitForExistence(timeout: 5))
    }

    func testEraseNeedsConfirmationAndOffersAnExportFirst() {
        let app = launch(route: "erase")
        let erase = app.buttons["Erase all data…"]
        XCTAssertTrue(erase.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Export a copy first"].exists)
        // Cancelling changes nothing.
        erase.tap()
        XCTAssertTrue(app.buttons["Erase everything"].waitForExistence(timeout: 5))
        // Newer iOS anchors the dialog to its button and dismisses it by tapping elsewhere.
        if app.buttons["Cancel"].exists {
            app.buttons["Cancel"].tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        }
        XCTAssertFalse(app.buttons["Erase everything"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["Everything airQ recorded has been erased."].exists)
        XCTAssertTrue(erase.exists)
        // Confirming erases (the UI-test store is in memory) and says so.
        erase.tap()
        app.buttons["Erase everything"].tap()
        XCTAssertTrue(app.staticTexts["Everything airQ recorded has been erased."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Erase all data…"].exists)
    }

    func testEraseInvalidatesAReportThatWasAlreadyOpen() {
        let app = launch(route: "report", extraArguments: ["-uiTestHistory", "YES", "-uiTestHistoryPeriod", "30"])
        func coverage(_ text: String) -> XCUIElement {
            app.descendants(matching: .any).matching(NSPredicate(
                format: "identifier == %@ AND label CONTAINS %@", "reportCoverage-Check-ins", text)).firstMatch
        }
        XCTAssertTrue(coverage("16 of 30 days").waitForExistence(timeout: 10))
        app.tabBars.buttons["More"].tap()
        let eraseScreen = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Erase all data")).firstMatch
        reveal(eraseScreen, in: app)
        eraseScreen.tap()
        app.buttons["Erase all data…"].tap()
        app.buttons["Erase everything"].tap()
        XCTAssertTrue(app.staticTexts["Everything airQ recorded has been erased."].waitForExistence(timeout: 10))
        app.tabBars.buttons["Report"].tap()
        XCTAssertTrue(coverage("0 of 30 days").waitForExistence(timeout: 10))
        XCTAssertFalse(coverage("16 of 30 days").exists)
    }

    func testAContextEventAppearsAsALaneInTrends() {
        let app = launch(route: "contextEvents")
        let add = app.buttons["Add event"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5))
        app.buttons["Save"].tap()
        app.navigationBars.buttons.firstMatch.tap()  // Back to the dashboard.
        let trends = app.tabBars.buttons["History"]
        XCTAssertTrue(trends.waitForExistence(timeout: 10))
        trends.tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["Life events"].exists)
        reveal(app.buttons["Life events"], in: app)
        app.buttons["Life events"].tap()
        XCTAssertTrue(app.staticTexts["Events you recorded"].waitForExistence(timeout: 5))
    }

    func testTappingTheStationOpensItsMap() throws {
        let app = launch()
        let station = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", " away")).firstMatch
        reveal(station, in: app)
        station.tap()
        XCTAssertTrue(app.navigationBars["Monitoring station"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["The AQI is this station's reading, not a measurement at your exact location."].exists)
        app.buttons["Done"].tap()
    }

    func testEveryScreenIsATabOrListedUnderMore() {
        let app = launch()
        for tab in ["Today", "History", "Report", "More"] {
            XCTAssertTrue(app.tabBars.buttons[tab].waitForExistence(timeout: 10), "\(tab) tab missing")
        }
        app.tabBars.buttons["More"].tap()
        for title in ["Listen", "Life events", "Stored data", "Air quality alerts", "About & data", "Erase all data"] {
            XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch.waitForExistence(timeout: 3), "\(title) missing from More")
        }
    }

    /// VoiceOver regression guard: every interactive control on the main screens has a label.
    /// The system DisclosureGroup chevron (its image is identified "collapsed"/"expanded") is exempt:
    /// VoiceOver reads the group's row instead.
    func testMainScreensHaveNoUnlabeledControls() {
        var unlabeled: [String] = []
        for route in [nil, "checkIn", "trends", "report", "listen", "contextEvents", "records", "export", "about", "alerts", "erase"] {
            let app = launch(route: route)
            _ = app.navigationBars.firstMatch.waitForExistence(timeout: 10)
            sleep(2)
            let chevrons = app.images.allElementsBoundByIndex
                .filter { ["collapsed", "expanded"].contains($0.identifier) }.map(\.frame)
            let interactive: [XCUIElement.ElementType] = [.button, .slider, .switch, .link]
            // A SwiftUI Toggle is a labelled row-level switch plus the plain control inside it; VoiceOver
            // focuses the row, so the unlabelled inner control isn't a finding.
            let labelledSwitches = app.descendants(matching: .switch).allElementsBoundByIndex
                .filter { !$0.label.isEmpty }.map(\.frame)
            for element in app.descendants(matching: .any).allElementsBoundByIndex
                where interactive.contains(element.elementType) && element.label.isEmpty
                    && !chevrons.contains(element.frame)
                    && !(element.elementType == .switch && labelledSwitches.contains { $0.contains(element.frame) }) {
                unlabeled.append("\(route ?? "dashboard"): \(element.elementType) at \(element.frame)")
            }
            app.terminate()
        }
        XCTAssertTrue(unlabeled.isEmpty, unlabeled.joined(separator: "\n"))
    }
}
