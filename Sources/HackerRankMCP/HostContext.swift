import Foundation
import HackerRankKit

/// A current snapshot of a host application's accounts and selection.
public struct HackerRankMCPContext: Sendable {
    public let accounts: [HackerRankMCPAccount]
    public let currentAccountID: UUID?
    public let isMergedView: Bool

    public init(accounts: [HackerRankMCPAccount], currentAccountID: UUID?, isMergedView: Bool = false) {
        self.accounts = accounts
        self.currentAccountID = currentAccountID
        self.isMergedView = isMergedView
    }

    var currentAccount: HackerRankMCPAccount? {
        guard !isMergedView else { return nil }

        return accounts.first { $0.id == currentAccountID }
    }
}

extension HackerRankMCPAccount {
    var label: String {
        name
    }
}

func remoteWebURL(from value: String) -> URL? {
    guard let url = URL(string: value),
          ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
          url.host?.isEmpty == false, url.user == nil, url.password == nil else { return nil }

    return url
}

extension User {
    var displayName: String {
        let name = [firstName, lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return name.isEmpty ? email : name
    }
}

func parseTimestamp(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions.insert(.withFractionalSeconds)
    return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
}
