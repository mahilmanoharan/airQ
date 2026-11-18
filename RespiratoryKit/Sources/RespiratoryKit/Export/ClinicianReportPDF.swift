import CoreGraphics
import CoreText
import Foundation

public extension ClinicianReport {
    /// Renders a single US Letter page without writing health data to disk.
    @concurrent
    func pdfData() async throws -> Data {
        try Task.checkCancellation()
        let buffer = NSMutableData()
        let metadata = [kCGPDFContextTitle: "airQ Respiratory Report", kCGPDFContextCreator: "airQ"] as CFDictionary
        var paper = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: buffer as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &paper, metadata) else {
            throw ReportPDFError.couldNotRender
        }
        context.beginPDFPage(nil)
        ReportPDFPage(context: context).draw(self)
        context.endPDFPage()
        context.closePDF()
        try Task.checkCancellation()
        return buffer as Data
    }
}

private enum ReportPDFError: LocalizedError {
    case couldNotRender

    var errorDescription: String? { "The printable PDF could not be prepared." }
}

private struct ReportPDFPage {
    let context: CGContext

    private let ink = CGColor(gray: 0.12, alpha: 1)
    private let secondaryInk = CGColor(gray: 0.32, alpha: 1)
    private let accent = CGColor(red: 0.06, green: 0.35, blue: 0.32, alpha: 1)
    private let outline = CGColor(gray: 0.85, alpha: 1)
    private let tableHeader = CGColor(red: 0.91, green: 0.95, blue: 0.94, alpha: 1)
    private let fontName = "Helvetica"
    private let boldFontName = "Helvetica-Bold"
    private let height: CGFloat = 792
    private let margin: CGFloat = 42
    private let width: CGFloat = 528
    private let missing = "—"

    func draw(_ report: ClinicianReport) {
        let summary = report.summary
        text("airQ Respiratory Report", at: margin, baseline: 62, size: 26, bold: true)
        text("\(summary.firstDayKey) to \(summary.lastDayKey)  |  \(summary.dayCount) days", at: margin,
             baseline: 83, size: 11, color: secondaryInk)
        rule(at: 98)

        text("Check-in overview", at: margin, baseline: 121, size: 14, color: accent, bold: true)
        let overview = [
            ("Daytime symptoms", answeredDays(summary.symptomDays, of: summary.symptomAnswered)),
            ("Night waking", answeredDays(summary.nightWakingDays, of: summary.nightWakingAnswered)),
            ("Rescue inhaler", summary.rescueAnswered > 0
             ? "\(answeredDays(summary.rescueDays, of: summary.rescueAnswered))  |  \(summary.rescueUses) total uses"
             : "No answers"),
            ("Peak flow", overviewPeakFlow(summary)),
        ]
        for (index, row) in overview.enumerated() {
            let baseline = 144 + CGFloat(index) * 21
            text(row.0, at: margin, baseline: baseline, size: 11, bold: true)
            text(row.1, at: 202, baseline: baseline, size: 11)
        }
        drawCoverage(summary)
        drawTimeline(report.weeks)
    }

    private func drawCoverage(_ summary: ClinicianSummary) {
        rule(at: 222)
        text("Coverage", at: margin, baseline: 244, size: 14, color: accent, bold: true)
        text("Check-ins  \(summary.checkInDays)/\(summary.dayCount) days", at: margin, baseline: 263, size: 10, bold: true)
        text("Air quality  \(summary.air.reported)/\(summary.dayCount) days", at: 211, baseline: 263, size: 10, bold: true)
        text("Pollen forecast  \(summary.pollenDays)/\(summary.dayCount) days", at: 379, baseline: 263, size: 10, bold: true)
        let coverage = summary.airCoverage
        if coverage.storedHours > 0 {
            let areas = coverage.places.count
            var detail = "\(coverage.storedHours) stored air hours across \(areas) saved \(areas == 1 ? "area" : "areas")."
            if coverage.ambiguousHours > 0 { detail += " \(coverage.ambiguousHours) overlapping hours excluded." }
            if coverage.unknownPlaceHours > 0 { detail += " \(coverage.unknownPlaceHours) with missing area." }
            text(detail, at: margin, baseline: 280, size: 9, color: secondaryInk)
        }
    }

    private func drawTimeline(_ weeks: [ClinicianReport.Week]) {
        text("Weekly timeline", at: margin, baseline: 321, size: 14, color: accent, bold: true)
        let columns: [CGFloat] = [50, 175, 227, 290, 341, 391, 457, 519]
        let headings = ["Dates", "Check-ins", "Symptoms", "Waking", "Rescue", "Peak flow", "Air", "Pollen"]
        context.setFillColor(tableHeader)
        context.fill(CGRect(x: margin, y: height - 348, width: width, height: 19))
        for (heading, x) in zip(headings, columns) {
            text(heading, at: x, baseline: 342, size: 9, bold: true)
        }
        for (index, week) in weeks.enumerated() {
            let cells = [
                "\(week.firstDayKey) to \(week.lastDayKey)", "\(week.checkInDays)/\(week.dayCount)",
                count(week.symptoms), count(week.nightWaking), count(week.rescueInhaler),
                peakFlow(week.peakFlow), week.highestAQI.map { "\($0) (\(week.airDays)/\(week.dayCount))" } ?? missing,
                week.pollenDays > 0 ? "\(week.pollenAtLeastModerateDays)/\(week.pollenDays)" : missing,
            ]
            let baseline = 361 + CGFloat(index) * 19
            for (value, x) in zip(cells, columns) {
                text(value, at: x, baseline: baseline, size: 9)
            }
            rule(at: baseline + 6)
        }
        let notes = [
            "Symptoms, waking and rescue show days with symptoms or use out of days answered. A dash means missing.",
            "Peak flow is self-measured in L/min. Air shows peak US AQI and days with at least \(DailyPeaks.minimumHours) usable stored hours.",
            "Pollen counts days at index 3 or above out of forecast days. Older records may use the local request date.",
            "Air readings and pollen forecasts are from Google. Saved area histories describe local air conditions.",
        ]
        let firstNoteBaseline = 373 + CGFloat(weeks.count) * 19
        for (index, note) in notes.enumerated() {
            text(note, at: margin, baseline: firstNoteBaseline + CGFloat(index) * 14, size: 9, color: secondaryInk)
        }
    }

    private func answeredDays(_ positive: Int, of answered: Int) -> String {
        answered > 0 ? "\(positive) of \(answered) answered days" : "No answers"
    }

    private func count(_ answers: ClinicianReport.AnsweredDays) -> String {
        answers.answered > 0 ? "\(answers.positive)/\(answers.answered)" : missing
    }

    private func overviewPeakFlow(_ summary: ClinicianSummary) -> String {
        guard let low = summary.peakFlowLowest, let high = summary.peakFlowHighest else { return "No readings" }
        let readings = summary.peakFlowReadings == 1 ? "1 reading" : "\(summary.peakFlowReadings) readings"
        return "\(peakFlow(low...high)) L/min  |  \(readings)"
    }

    private func peakFlow(_ readings: ClosedRange<Int>?) -> String {
        guard let readings else { return missing }
        return readings.lowerBound == readings.upperBound ? String(readings.lowerBound)
            : "\(readings.lowerBound)-\(readings.upperBound)"
    }

    private func text(_ value: String, at x: CGFloat, baseline: CGFloat, size: CGFloat,
                      color: CGColor? = nil, bold: Bool = false) {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(
                (bold ? boldFontName : fontName) as CFString, size, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color ?? ink,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: attributes))
        context.textPosition = CGPoint(x: x, y: height - baseline)
        CTLineDraw(line, context)
    }

    private func rule(at top: CGFloat) {
        context.setStrokeColor(outline)
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: margin, y: height - top))
        context.addLine(to: CGPoint(x: margin + width, y: height - top))
        context.strokePath()
    }
}
