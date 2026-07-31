import Foundation
@testable import HackerRankMCP
import Testing

struct AccountsTests {
    @Test func `account set resolves its default and named accounts`() throws {
        let first = HackerRankMCPAccount(name: "Work", token: "one")
        let second = HackerRankMCPAccount(name: "EU", token: "two")
        let set = try HackerRankMCPAccountSet(
            accounts: [first, second],
            defaultAccountID: second.id
        )

        #expect(set.resolve(nil)?.id == second.id)
        #expect(set.resolve("work")?.id == first.id)
        #expect(set.resolve(first.id.uuidString)?.id == first.id)
    }

    @Test func `environment configuration requires a token`() {
        #expect(throws: HackerRankMCPConfigError.noAccounts) {
            try loadHackerRankMCPAccounts(environment: [:])
        }
    }

    @Test func `environment configuration rejects unsafe base URLs`() {
        #expect(throws: HackerRankMCPConfigError.invalidBaseURL("http://example.com")) {
            try loadHackerRankMCPAccounts(environment: [
                "HACKERRANK_API_TOKEN": "secret",
                "HACKERRANK_BASE_URL": "http://example.com",
            ])
        }
    }
}
