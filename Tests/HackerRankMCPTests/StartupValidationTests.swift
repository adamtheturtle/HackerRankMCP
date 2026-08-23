import HackerRankKit
import HackerRankKitMock
@testable import HackerRankMCP
import Testing

struct StartupValidationTests {
    @Test func `startup validation succeeds against mock server`() async throws {
        let account = HackerRankMCPAccount(name: "Work", token: "demo")
        let set = try HackerRankMCPAccountSet(accounts: [account])
        try await validateHackerRankAccountsOnStartup(set) { account in
            let client = HackerRankClient.mock(key: "startup-\(account.name)-\(UUID().uuidString)")
            _ = try await client.usersPage(after: nil)
        }
    }
}
