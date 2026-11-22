import CoreSpotlight
import Foundation
import OSLog
import UniformTypeIdentifiers

/// Indexes public screen descriptions. Personal records and readings never enter this index.
enum SpotlightNavigation {
    private static let domain = "airq.screen"
    private static let logger = Logger(subsystem: "mahilmanoharan.airQ", category: "Spotlight")
    private static var hasStartedIndexing = false

    static func indexScreens() async {
        guard !AppServices.isUITesting, !hasStartedIndexing, CSSearchableIndex.isIndexingAvailable() else { return }
        hasStartedIndexing = true
        let index = CSSearchableIndex(name: domain, protectionClass: .completeUntilFirstUserAuthentication)
        do {
            try await index.indexSearchableItems(Screen.allCases.map(\.searchableItem))
            logger.info("Submitted airQ screen shortcuts to Spotlight.")
        } catch {
            hasStartedIndexing = false
            logger.error("Could not index airQ screen shortcuts: \(error.localizedDescription)")
        }
    }

    static func path(for activity: NSUserActivity) -> [AppRoute]? {
        guard activity.activityType == CSSearchableItemActionType,
              let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return nil }
        return Screen.allCases.first { $0.identifier == identifier }?.path
    }

    #if DEBUG
    static func testActivity(launchArgument: String) -> NSUserActivity? {
        guard AppServices.isUITesting,
              let identifier = UserDefaults.standard.string(forKey: launchArgument) else { return nil }
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: identifier]
        return activity
    }
    #endif

    private enum Screen: String, CaseIterable {
        case today, checkIn, history, report

        var identifier: String { "\(domain).\(rawValue)" }

        var path: [AppRoute] {
            switch self {
            case .today: []
            case .checkIn: [.checkIn]
            case .history: [.trends]
            case .report: [.report]
            }
        }

        var searchableItem: CSSearchableItem {
            let attributes = CSSearchableItemAttributeSet(contentType: .item)
            let title: String
            switch self {
            case .today:
                title = "airQ Today"
                attributes.contentDescription = "See today's air quality and pollen."
                attributes.keywords = ["air quality", "AQI", "pollen", "forecast"]
            case .checkIn:
                title = "airQ Check-in"
                attributes.contentDescription = "Open your daily breathing check-in."
                attributes.keywords = ["breathing", "symptoms", "daily check-in"]
            case .history:
                title = "airQ History"
                attributes.contentDescription = "See your check-ins alongside air quality and pollen."
                attributes.keywords = ["breathing history", "air quality history", "check-ins"]
            case .report:
                title = "airQ Report"
                attributes.contentDescription = "Open the report you can share with your doctor."
                attributes.keywords = ["breathing report", "doctor", "print"]
            }
            attributes.title = title
            attributes.displayName = title
            let item = CSSearchableItem(uniqueIdentifier: identifier, domainIdentifier: domain, attributeSet: attributes)
            item.expirationDate = .distantFuture
            return item
        }
    }
}
