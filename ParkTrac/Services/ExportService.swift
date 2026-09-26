import Foundation
import CoreTransferable
import UniformTypeIdentifiers

// MARK: - CSV

enum CSV {
    /// RFC 4180 quoting: wrap in quotes when the field has a comma, quote or newline;
    /// double any quotes inside.
    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func make(header: [String], rows: [[String]]) -> String {
        ([header] + rows)
            .map { $0.map(escape).joined(separator: ",") }
            .joined(separator: "\n") + "\n"
    }

    /// Locale-independent timestamp so spreadsheets parse it the same everywhere.
    static let timestamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
}

/// A CSV the share sheet can save to Files, AirDrop, or open in Numbers.
struct CSVFile: Transferable {
    let fileName: String
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { Data($0.text.utf8) }
            .suggestedFileName { $0.fileName }
    }
}

enum DataExport {
    static func rideLog(_ logs: [RideLog]) -> CSVFile {
        let rows = logs.sorted { $0.riddenAt < $1.riddenAt }.map { log in
            [CSV.timestamp.string(from: log.riddenAt), log.resort, log.parkName, log.rideName,
             log.waitMinutes.map(String.init) ?? "", log.actualWaitMinutes.map(String.init) ?? "",
             log.notes]
        }
        return CSVFile(
            fileName: "ThrillTrack Rides.csv",
            text: CSV.make(header: ["Date", "Resort", "Park", "Ride", "Posted Wait (min)",
                                    "Actual Wait (min)", "Notes"], rows: rows))
    }

    static func purchases(_ purchases: [PurchaseLog]) -> CSVFile {
        let rows = purchases.sorted { $0.date < $1.date }.map { p in
            [CSV.timestamp.string(from: p.date), p.resort, p.category,
             String(format: "%.2f", p.amount), p.note]
        }
        return CSVFile(
            fileName: "ThrillTrack Spending.csv",
            text: CSV.make(header: ["Date", "Resort", "Category", "Amount", "Note"], rows: rows))
    }
}

// MARK: - Day summary

/// Plain-text recap of a park day for Messages / Notes.
enum DaySummary {
    struct Ride {
        let name: String
        let postedWait: Int?
        let actualWait: Int?
    }

    static func text(date: Date, resort: String, rides: [Ride],
                     planDone: Int, planTotal: Int, spent: Double,
                     currencyCode: String = "USD") -> String {
        var lines = ["🎢 ThrillTrack · \(date.formatted(date: .abbreviated, time: .omitted)) · \(resort)"]

        if rides.isEmpty {
            lines.append("No rides logged yet.")
        } else {
            lines.append("")
            lines.append("Rides (\(rides.count)):")
            for ride in rides {
                switch (ride.postedWait, ride.actualWait) {
                case let (posted?, actual?):
                    lines.append("• \(ride.name) — posted \(posted) min, waited \(actual)")
                case let (posted?, nil):
                    lines.append("• \(ride.name) — posted \(posted) min")
                case let (nil, actual?):
                    lines.append("• \(ride.name) — waited \(actual) min")
                case (nil, nil):
                    lines.append("• \(ride.name)")
                }
            }
            let saved = rides.compactMap { r -> Int? in
                guard let p = r.postedWait, let a = r.actualWait else { return nil }
                return p - a
            }
            if !saved.isEmpty {
                let total = saved.reduce(0, +)
                lines.append(total >= 0
                    ? "Beat the posted waits by \(total) min total."
                    : "Waited \(-total) min longer than posted in total.")
            }
        }

        if planTotal > 0 {
            lines.append("")
            lines.append("Plan: \(planDone) of \(planTotal) done")
        }
        if spent > 0 {
            lines.append("Spent: \(spent.formatted(.currency(code: currencyCode)))")
        }
        return lines.joined(separator: "\n")
    }
}
