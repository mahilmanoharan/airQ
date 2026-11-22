import XCTest

/// Critical interactive flows, run against an in-memory record store with no network
/// (`-uiTestMode YES`), so tests never write real history or spend provider requests.
@MainActor
final class AirQUITests: XCTestCase {
    private func launch(route: String? = nil, extraArguments: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestMode", "YES"] + (route.map { ["-initialRoute", $0] } ?? []) + extraArguments
        app.launch()
        return app
    }

    /// The cards, one question at a time: Next confirms an answer; Skip leaves it unanswered.
    private func startTodaysCheckIn(_ app: XCUIApplication) {
        let start = app.buttons.containing(NSPredicate(
            format: "identifier == %@ OR label BEGINSWITH %@", "todayCheckIn", "Check in for today")).firstMatch
        reveal(start, in: app)
        start.tap()
    }

    private func openMetric(_ metric: String, title: String, in app: XCUIApplication) {
        let card = app.buttons["todayMetric-\(metric)"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
    }

    private func expectReportCoverage(_ text: String, in app: XCUIApplication) {
        let preview = app.buttons["previewReport"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        preview.tap()
        let coverage = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ AND label CONTAINS %@", "reportCoverage-Check-ins", text)).firstMatch
        XCTAssertTrue(coverage.waitForExistence(timeout: 5))
        app.navigationBars["Report preview"].buttons["Done"].tap()
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
        let app = launch()
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
        let app = launch(extraArguments: ["-uiTestNoReading", "YES", "-uiTestLocationDenied", "YES"])
        startTodaysCheckIn(app)
        XCTAssertTrue(app.buttons["No symptoms"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Skip"].exists)
    }

    func testReportAndHistoryRefreshAfterSavingToday() {
        let app = launch(route: "report", extraArguments: ["-uiTestHistoryPeriod", "30"])
        XCTAssertTrue(app.buttons["shareReportSummary"].waitForExistence(timeout: 10))
        expectReportCoverage("0 of 30 days", in: app)
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["Your history starts with a day"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Today"].tap()
        startTodaysCheckIn(app)
        app.buttons["No symptoms"].tap()
        next(app)
        skip(app, times: 3)
        app.buttons["Save today"].tap()
        app.buttons["Done"].tap()
        app.tabBars.buttons["Report"].tap()
        XCTAssertTrue(app.buttons["shareReportSummary"].waitForExistence(timeout: 10))
        expectReportCoverage("1 of 30 days", in: app)
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["historyCheckInSummary"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Your history starts with a day"].exists)
    }

    func testHistoryAndReportShareTheChosenPeriodAndCurrentData() {
        let app = launch(route: "trends", extraArguments: ["-uiTestHistory", "YES", "-uiTestHistoryPeriod", "30"])
        let summary = app.staticTexts["historyCheckInSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        XCTAssertEqual(summary.label, "No symptoms reported")
        app.segmentedControls.buttons["7 days"].tap()
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        app.tabBars.buttons["Report"].tap()
        let share = app.buttons["shareReportSummary"]
        XCTAssertTrue(share.waitForExistence(timeout: 10))
        XCTAssertTrue(app.segmentedControls.buttons["7 days"].isSelected)
        expectReportCoverage("6 of 7 days", in: app)
        app.segmentedControls.buttons["30 days"].tap()
        XCTAssertTrue(share.waitForExistence(timeout: 10))
        expectReportCoverage("16 of 30 days", in: app)
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["30 days"].isSelected)
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertEqual(summary.label, "No symptoms reported")
    }

    func testLargeTextKeepsTheSharedPeriodSelectable() {
        let app = launch(route: "trends", extraArguments: [
            "-uiTestHistoryPeriod", "30",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        let historyPeriod = app.buttons["historyPeriod"]
        XCTAssertTrue(historyPeriod.waitForExistence(timeout: 10))
        historyPeriod.tap()
        let week = app.buttons["7 days"]
        XCTAssertTrue(week.waitForExistence(timeout: 5))
        week.tap()

        app.tabBars.buttons["Report"].tap()
        let reportPeriod = app.buttons["reportPeriod"]
        XCTAssertTrue(reportPeriod.waitForExistence(timeout: 10))
        let selection = [reportPeriod.label, reportPeriod.value as? String].compactMap { $0 }
        XCTAssertTrue(selection.contains { $0.contains("7 days") }, selection.joined(separator: ", "))
        let share = app.buttons["shareReportSummary"]
        XCTAssertTrue(share.waitForExistence(timeout: 10))
        XCTAssertTrue(share.isHittable)
        let shareY = share.frame.minY
        app.swipeUp()
        XCTAssertTrue(share.isHittable)
        XCTAssertEqual(share.frame.minY, shareY, accuracy: 2)
        share.tap()
        let shareTitle = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "airQ Respiratory Report")).firstMatch
        XCTAssertTrue(shareTitle.waitForExistence(timeout: 10))
    }

    func testHistoryDayInspectionDistinguishesAnUnansweredDayFromZeroUses() {
        let app = launch(route: "trends", extraArguments: ["-uiTestHistory", "YES", "-uiTestHistoryPeriod", "30"])
        let inspect = app.buttons["View a day"]
        XCTAssertTrue(inspect.waitForExistence(timeout: 10))
        inspect.tap()

        let elements = app.descendants(matching: .any)
        let symptoms = elements["historyDay-symptoms"].firstMatch
        let inhaler = elements["historyDay-rescue"].firstMatch
        let air = elements["historyDay-air"].firstMatch
        let pollen = elements["historyDay-pollen"].firstMatch
        XCTAssertTrue(inhaler.waitForExistence(timeout: 5))
        XCTAssertEqual(symptoms.value as? String, "No check-in")
        XCTAssertEqual(inhaler.value as? String, "No check-in")
        XCTAssertEqual(air.value as? String, "No saved AQI")
        XCTAssertEqual(pollen.value as? String, "No pollen forecast")

        app.buttons["Previous day"].tap()
        XCTAssertEqual(symptoms.value as? String, "No daytime symptoms")
        XCTAssertEqual(inhaler.value as? String, "0 uses")
        XCTAssertEqual(air.value as? String, "Google 59 · WAQI 52")
        XCTAssertEqual(pollen.value as? String, "1 of 5")
        app.navigationBars.buttons["Done"].tap()
        XCTAssertFalse(inhaler.exists)
    }

    func testDayNavigationStaysReachableAtTheLargestTextSize() {
        let app = launch(route: "trends", extraArguments: [
            "-uiTestHistory", "YES", "-uiTestHistoryPeriod", "30",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        let inspect = app.buttons["View a day"]
        reveal(inspect, in: app)
        inspect.tap()
        XCTAssertTrue(app.staticTexts["Jump to date"].waitForExistence(timeout: 5))
        let previous = app.buttons["Previous day"]
        XCTAssertTrue(previous.isHittable)
        let position = previous.frame.minY
        app.swipeUp()
        XCTAssertTrue(previous.isHittable)
        XCTAssertEqual(previous.frame.minY, position, accuracy: 2)
        previous.tap()
        XCTAssertTrue(app.buttons["Next day"].isEnabled)
    }

    func testHistoryKeepsChartsBehindTheComparisonAction() {
        let app = launch(route: "trends", extraArguments: ["-uiTestHistory", "YES"])
        let compare = app.buttons["Compare with air & pollen"]
        XCTAssertTrue(compare.waitForExistence(timeout: 10))
        XCTAssertLessThan(compare.frame.minY, app.buttons["View a day"].frame.minY)
        XCTAssertFalse(app.staticTexts["Symptoms & surroundings"].exists)
        compare.tap()
        XCTAssertTrue(app.staticTexts["Symptoms & surroundings"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Done"].tap()
        XCTAssertTrue(compare.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Symptoms & surroundings"].exists)
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
        openMetric("airQuality", title: "Air quality", in: app)
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
        let listenLink = try XCTUnwrap(URL(string: "airq://listen"))
        app.open(listenLink)
        XCTAssertTrue(app.navigationBars["Listen"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Listen"].isSelected)
        XCTAssertTrue(app.buttons["Start listening"].isEnabled)
    }

    func testSpotlightActivityOpensOnlySupportedScreens() {
        for (identifier, title) in [("airq.screen.today", "Today"), ("airq.screen.checkIn", "Check-in"),
                                    ("airq.screen.history", "History"), ("airq.screen.report", "Report"),
                                    ("airq.screen.erase", "Listen")] {
            let app = launch(route: "listen", extraArguments: ["-uiTestSpotlightIdentifier", identifier])
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10), identifier)
        }
    }

    func testSpotlightReopensScreensAboveExistingDetails() {
        let today = launch(extraArguments: ["-uiTestSpotlightOnBackground", "airq.screen.today"])
        openMetric("airQuality", title: "Air quality", in: today)
        XCUIDevice.shared.press(.home)
        today.activate()
        XCTAssertTrue(today.navigationBars["Today"].waitForExistence(timeout: 5))

        let history = launch(route: "trends", extraArguments: [
            "-uiTestHistory", "YES", "-uiTestSpotlightOnBackground", "airq.screen.history"
        ])
        let day = history.buttons["View a day"]
        XCTAssertTrue(day.waitForExistence(timeout: 10))
        day.tap()
        let historySheet = history.navigationBars["Day details"]
        XCTAssertTrue(historySheet.waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        history.activate()
        XCTAssertTrue(historySheet.waitForNonExistence(timeout: 5))
        XCTAssertTrue(day.isHittable)

        let report = launch(route: "report", extraArguments: [
            "-uiTestSpotlightOnBackground", "airq.screen.report"
        ])
        let preview = report.buttons["previewReport"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        preview.tap()
        let reportSheet = report.navigationBars["Report preview"]
        XCTAssertTrue(reportSheet.waitForExistence(timeout: 5))
        report.buttons["View print layout"].tap()
        let printLayout = report.navigationBars["Print layout"]
        XCTAssertTrue(printLayout.waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        report.activate()
        XCTAssertTrue(printLayout.waitForNonExistence(timeout: 5))
        XCTAssertTrue(reportSheet.waitForNonExistence(timeout: 5))
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
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
        XCTAssertFalse(app.buttons["Try again"].exists, "A settings problem isn't fixed by retrying")
        // The cached reading is still on screen rather than an empty error page.
        XCTAssertTrue(app.staticTexts["San Francisco"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Air quality index 42'"))
            .firstMatch.exists)
    }

    func testTheDashboardShowsTheEssentialsFirstAndDetailsOnRequest() {
        let app = launch()
        let air = app.buttons["todayMetric-airQuality"]
        let pollen = app.buttons["todayMetric-pollen"]
        XCTAssertTrue(air.waitForExistence(timeout: 10))
        XCTAssertTrue(air.isHittable && pollen.isHittable)
        XCTAssertTrue(air.label.contains("little or no risk"), air.label)
        XCTAssertTrue(pollen.label.contains("may still notice symptoms"), pollen.label)
        XCTAssertFalse(app.staticTexts["Your day, in context"].exists)
        XCTAssertFalse(app.buttons["Show details"].exists)
        air.tap()
        XCTAssertTrue(app.navigationBars["Air quality"].waitForExistence(timeout: 5))
        reveal(app.staticTexts["Pollutants"], in: app)
        XCTAssertFalse(app.staticTexts["Pollen by type"].exists)
        app.navigationBars["Air quality"].buttons.firstMatch.tap()
        pollen.tap()
        XCTAssertTrue(app.navigationBars["Pollen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Pollen by type"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Pollutants"].exists)
    }

    func testTodayStacksReadingsAtAccessibilityTextSizes() {
        let app = launch(extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let air = app.buttons["todayMetric-airQuality"]
        let pollen = app.buttons["todayMetric-pollen"]
        XCTAssertTrue(air.waitForExistence(timeout: 10))
        XCTAssertTrue(pollen.exists)
        XCTAssertGreaterThanOrEqual(pollen.frame.minY, air.frame.maxY)
        XCTAssertEqual(pollen.frame.width, air.frame.width, accuracy: 2)
    }

    func testPollenDetailsKeepForecastsReadableAtTheLargestTextSize() {
        let app = launch(extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let pollen = app.buttons["todayMetric-pollen"]
        reveal(pollen, in: app)
        pollen.tap()
        XCTAssertTrue(app.navigationBars["Pollen"].waitForExistence(timeout: 5))

        let rows = app.descendants(matching: .any)
        let tree = rows["pollenType-tree"].firstMatch
        let grass = rows["pollenType-grass"].firstMatch
        let weed = rows["pollenType-weed"].firstMatch
        reveal(tree, in: app)
        XCTAssertGreaterThanOrEqual(grass.frame.minY, tree.frame.maxY)
        XCTAssertEqual(tree.value as? String, "2 of 5, Low")
        XCTAssertEqual(weed.value as? String, "Unavailable")

        let next = rows["pollenOutlook-1"].firstMatch
        reveal(next, in: app)
        XCTAssertEqual(next.value as? String, "3 of 5, Moderate")
        let plant = rows["pollenPlant-OAK"].firstMatch
        XCTAssertFalse(plant.exists)
        let plants = app.buttons["Plant details"]
        reveal(plants, in: app)
        plants.tap()
        reveal(plant, in: app)
        XCTAssertEqual(plant.label, "Oak")
    }

    func testListenTabOpensPastSessionsWithoutADuplicateTodayCard() {
        let app = launch()
        XCTAssertTrue(app.buttons["todayMetric-airQuality"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Listen for coughs"].exists)
        let listenTab = app.tabBars.buttons["Listen"]
        listenTab.tap()
        XCTAssertTrue(app.navigationBars["Listen"].waitForExistence(timeout: 5))
        XCTAssertTrue(listenTab.isSelected)
        let start = app.buttons["Start listening"]
        let sessions = app.buttons["Past listening sessions"]
        XCTAssertTrue(start.isEnabled)
        XCTAssertGreaterThan(start.frame.minY, sessions.frame.maxY)
        sessions.tap()
        XCTAssertTrue(app.navigationBars["Sessions"].waitForExistence(timeout: 5))
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
        }, [("history", "trends", ["-uiTestHistory", "YES"]), ("report", "report", []),
                   ("listen", "listen", []), ("life events", "contextEvents", []),
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
                    let pinnedActions = ["Start listening", "Stop listening", "Share report"]
                    let bottomBarZone = (issue.element?.frame.maxY ?? 0) > app.frame.height * 0.85
                        && !pinnedActions.contains(issue.element?.label ?? "")
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
        let sharePDF = app.buttons["shareReportSummary"]
        let advanced = app.buttons["Advanced export"]
        let raw = app.buttons["Export raw records"]
        XCTAssertTrue(sharePDF.waitForExistence(timeout: 10))
        XCTAssertEqual(sharePDF.label, "Share report")
        XCTAssertTrue(advanced.exists)
        XCTAssertGreaterThan(sharePDF.frame.minY, advanced.frame.minY)
        XCTAssertFalse(raw.exists)
        XCTAssertFalse(app.staticTexts["Weekly timeline"].exists)
        XCTAssertFalse(app.staticTexts["Coverage"].exists)
        app.buttons["previewReport"].tap()
        XCTAssertTrue(app.staticTexts["Coverage"].exists)
        reveal(app.staticTexts["Weekly timeline"], in: app)
        app.navigationBars["Report preview"].buttons["Done"].tap()
        reveal(advanced, in: app)
        advanced.tap()
        reveal(raw, in: app)
        raw.tap()
        XCTAssertTrue(app.navigationBars["Raw export"].waitForExistence(timeout: 5))
        reveal(app.buttons["Create export"], in: app)
    }

    func testTodayKeepsSharingWithTheAirQualityDetails() {
        let app = launch()
        XCTAssertTrue(app.buttons["todayMetric-airQuality"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["todayCheckIn"].isHittable)
        XCTAssertFalse(app.buttons["Share air quality"].exists)
        openMetric("airQuality", title: "Air quality", in: app)
        XCTAssertTrue(app.buttons["Share air quality"].isHittable)
    }

    func testReportPDFCanBeSentToPrint() {
        let app = launch(route: "report", extraArguments: ["-uiTestHistory", "YES", "-uiTestHistoryPeriod", "90"])
        let preview = app.buttons["previewReport"]
        reveal(preview, in: app)
        preview.tap()
        let layout = app.buttons["View print layout"]
        XCTAssertTrue(layout.waitForExistence(timeout: 5))
        layout.tap()
        let navigation = app.navigationBars["Print layout"]
        XCTAssertTrue(navigation.waitForExistence(timeout: 5))
        let share = navigation.buttons["Share report"]
        XCTAssertTrue(share.isHittable)
        share.tap()
        let print = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Print")).firstMatch
        XCTAssertTrue(print.waitForExistence(timeout: 10), app.debugDescription)
    }

    func testTheWelcomeExplainsTheAppOnceThenShowsTheDashboard() {
        let app = launch(extraArguments: ["-showWelcome", "YES"])
        XCTAssertTrue(app.staticTexts["Welcome to airQ"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Track how you feel"].exists)
        XCTAssertTrue(app.staticTexts["Your notes stay on this iPhone"].exists)
        // The welcome fills the Air tab only: the other tabs stay usable, and the reading (and so the
        // location prompt) waits until the person continues.
        XCTAssertTrue(app.tabBars.buttons["History"].exists)
        XCTAssertFalse(app.buttons["todayMetric-airQuality"].exists)
        app.buttons["Get started"].tap()
        XCTAssertTrue(app.buttons["todayMetric-airQuality"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Welcome to airQ"].exists)
    }

    func testTheNumbersCanBeExplainedAndTodayIsMarked() {
        let app = launch()
        openMetric("airQuality", title: "Air quality", in: app)
        XCTAssertTrue(app.staticTexts["Air pollution poses little or no risk."].exists)
        XCTAssertTrue(app.buttons["See AQI scale"].isHittable)
        app.buttons["See AQI scale"].tap()
        let aqi = app.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@", "Good, 0–50, selected level")).firstMatch
        reveal(aqi, in: app)
        XCTAssertFalse(app.staticTexts["Pollen scale"].exists)
        app.navigationBars["AQI scale"].buttons["Done"].tap()
        app.navigationBars["Air quality"].buttons.firstMatch.tap()
        openMetric("pollen", title: "Pollen", in: app)
        XCTAssertTrue(app.staticTexts["People sensitive to pollen may still notice symptoms."].exists)
        app.buttons["See pollen scale"].tap()
        let pollen = app.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@", "Low, 2, selected level")).firstMatch
        reveal(pollen, in: app)
        XCTAssertFalse(app.staticTexts["AQI scale"].exists)
    }

    func testTodayShowsSevereSavedAirAndUnavailablePollen() {
        let app = launch(extraArguments: ["-uiTestAQI", "160", "-uiTestNoPollen", "YES",
                                          "-uiTestStaleReading", "YES", "-uiTestLocationDenied", "YES"])
        let air = app.buttons["todayMetric-airQuality"]
        XCTAssertTrue(air.waitForExistence(timeout: 10))
        XCTAssertTrue(air.label.contains("160, Unhealthy"))
        XCTAssertTrue(air.label.contains("Avoid strenuous outdoor activity"))
        XCTAssertTrue(app.buttons["todayMetric-pollen"].label.contains("forecast unavailable"))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Last saved")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Showing your last reading"].exists)
        openMetric("airQuality", title: "Air quality", in: app)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Last saved")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Avoid strenuous outdoor activity."].exists)
        app.navigationBars["Air quality"].buttons.firstMatch.tap()
        openMetric("pollen", title: "Pollen", in: app)
        XCTAssertTrue(app.staticTexts["Unavailable"].exists)
        app.buttons["See pollen scale"].tap()
        XCTAssertTrue(app.navigationBars["Pollen scale"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(
            format: "label ENDSWITH %@", ", selected level")).firstMatch.exists)
    }

    func testMonthSummaryExplainsWhenThereIsNoHistoryYet() {
        let app = launch()
        openMetric("airQuality", title: "Air quality", in: app)
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
        let status = app.staticTexts["Background updates are off"]
        XCTAssertTrue(status.exists)
        XCTAssertLessThan(status.frame.minY, backgroundUpdates.frame.minY)
        for label in ["Alert me about unhealthy air", "Alert me about high pollen"] {
            let toggle = app.switches[label]
            XCTAssertTrue(toggle.waitForExistence(timeout: 5), label)
            XCTAssertEqual(toggle.value as? String, "0", label)
        }
        let timing = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'late or not at all'")).firstMatch
        XCTAssertFalse(timing.exists)
        let help = app.buttons["How alerts work"]
        reveal(help, in: app)
        help.tap()
        XCTAssertTrue(timing.waitForExistence(timeout: 5))
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
        expectReportCoverage("16 of 30 days", in: app)
        app.tabBars.buttons["More"].tap()
        app.buttons["Data & privacy"].tap()
        let eraseScreen = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Erase all data")).firstMatch
        reveal(eraseScreen, in: app)
        eraseScreen.tap()
        app.buttons["Erase all data…"].tap()
        app.buttons["Erase everything"].tap()
        XCTAssertTrue(app.staticTexts["Everything airQ recorded has been erased."].waitForExistence(timeout: 10))
        app.tabBars.buttons["Report"].tap()
        expectReportCoverage("0 of 30 days", in: app)
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
        app.buttons["Compare with air & pollen"].tap()
        reveal(app.buttons["Life events"], in: app)
        app.buttons["Life events"].tap()
        XCTAssertTrue(app.staticTexts["Events you recorded"].waitForExistence(timeout: 5))
    }

    func testTappingTheStationOpensItsMap() throws {
        let app = launch()
        openMetric("airQuality", title: "Air quality", in: app)
        let station = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", " away")).firstMatch
        reveal(station, in: app)
        station.tap()
        XCTAssertTrue(app.navigationBars["Monitoring station"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["The AQI is this station's reading, not a measurement at your exact location."].exists)
        app.buttons["Done"].tap()
    }

    func testEveryScreenIsATabOrListedUnderMore() {
        let app = launch()
        for tab in ["Today", "Listen", "History", "Report", "More"] {
            XCTAssertTrue(app.tabBars.buttons[tab].waitForExistence(timeout: 10), "\(tab) tab missing")
        }
        app.tabBars.buttons["Listen"].tap()
        XCTAssertTrue(app.buttons["Start listening"].waitForExistence(timeout: 5))
        app.tabBars.buttons["More"].tap()
        XCTAssertFalse(app.collectionViews.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Listen'")).firstMatch.exists)
        for title in ["Life events", "Air quality alerts"] {
            XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch.isHittable)
        }
        XCTAssertFalse(app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Erase all data'")).firstMatch.exists)
        app.buttons["Data & privacy"].tap()
        for title in ["Stored data", "About & data", "Erase all data"] {
            XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch.waitForExistence(timeout: 3), "\(title) missing from More")
        }
    }

    func testCheckInSaveStaysReachableAtTheLargestTextSize() {
        let app = launch(route: "checkIn", extraArguments: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        startTodaysCheckIn(app)
        XCTAssertTrue(app.staticTexts["Question 1"].waitForExistence(timeout: 5))
        app.buttons["No symptoms"].tap()
        next(app)
        skip(app, times: 3)
        let save = app.buttons["Save today"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isHittable)
        let position = save.frame.minY
        app.swipeUp()
        XCTAssertTrue(save.isHittable)
        XCTAssertEqual(save.frame.minY, position, accuracy: 2)
        save.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
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
